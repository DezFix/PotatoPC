# Инженерный аудит: быстрые проверки только на чтение (без изменений системы).
# Тяжёлые sfc /scannow и DISM /RestoreHealth остаются отдельными карточками.
# Все функции доступны и в фоновых runspace (снимок функций в Start-Background).

function Test-PendingReboot {
    $reasons = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $reasons += 'CBS' }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $reasons += 'WindowsUpdate' }
    try {
        $v = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop).PendingFileRenameOperations
        if ($v) { $reasons += 'PendingFileRename' }
    } catch {}
    if (Test-Path 'C:\Windows\WinSxS\pending.xml') { $reasons += 'pending.xml' }
    return $reasons
}

function Get-UpdateFailures {
    param([int]$Days = 14)
    try {
        $sess = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop
        $since = (Get-Date).AddDays(-$Days)
        return @($sess.QueryHistory('', 0, 100) | Where-Object { $_.Date -gt $since -and ($_.ResultCode -eq 4 -or $_.ResultCode -eq 5) } |
            Select-Object Date, Title, @{N='Result';E={ if ($_.ResultCode -eq 4) { 'Failed' } else { 'Aborted' } } })
    } catch { return @() }
}

function Get-RecentEventErrors {
    param([int]$Hours = 24, [int]$Max = 100)
    $out = @()
    try {
        $t = (Get-Date).AddHours(-$Hours)
        foreach ($log in @('System', 'Application')) {
            try {
                $ev = @(Get-WinEvent -FilterHashtable @{ LogName=$log; Level=1,2; StartTime=$t } -MaxEvents $Max -ErrorAction Stop)
                $out += $ev | Select-Object @{N='Log';E={$log}}, TimeCreated, Id, LevelDisplayName,
                    @{N='Source';E={$_.ProviderName}},
                    @{N='Msg';E={ $m = [string]$_.Message -replace '\s+',' '; if ($m.Length -gt 160) { $m.Substring(0,160) } else { $m } }}
            } catch {}
        }
    } catch {}
    return $out
}

function Get-MiniDumps {
    param([int]$Max = 5)
    try {
        return @(Get-ChildItem 'C:\Windows\Minidump\*.dmp' -ErrorAction Stop |
            Sort-Object LastWriteTime -Descending | Select-Object -First $Max Name, LastWriteTime,
            @{N='SizeMB';E={[math]::Round($_.Length/1MB,1)}})
    } catch { return @() }
}

function Get-FailedAutoServices {
    try {
        return @(Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State!='Running'" -ErrorAction Stop |
            Select-Object Name, State, StartMode)
    } catch { return @() }
}

function Get-DriverProblems {
    try {
        return @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object { $_.ConfigManagerErrorCode -ne 0 } |
            Select-Object Name, DeviceID, ConfigManagerErrorCode)
    } catch { return @() }
}

function Get-DefenderStatus {
    try {
        $s = Get-MpComputerStatus -ErrorAction Stop
        return @{ Ok=$true; Mode=[string]$s.AMRunningMode; SigAge=$s.AntivirusSignatureAge; QuickAge=$s.QuickScanAge }
    } catch { return @{ Ok=$false } }
}

function Get-DiskSpaceStatus {
    try {
        return @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop |
            Select-Object DeviceID,
            @{N='FreeGB';E={[math]::Round($_.FreeSpace/1GB,1)}},
            @{N='TotalGB';E={[math]::Round($_.Size/1GB,1)}},
            @{N='FreePct';E={ if ($_.Size) { [math]::Round(100*$_.FreeSpace/$_.Size,1) } else { 0 } }})
    } catch { return @() }
}

function Get-SmartAll {
    $out = @()
    try {
        foreach ($pd in (Get-PhysicalDisk -ErrorAction Stop)) {
            try { $rel = $pd | Get-StorageReliabilityCounter -ErrorAction Stop } catch { $rel = $null }
            $out += @{
                Disk   = [string]$pd.FriendlyName
                Health = [string]$pd.HealthStatus
                Media  = [string]$pd.MediaType
                Temp   = $(if ($rel -and $rel.Temperature) { [math]::Round($rel.Temperature) } else { $null })
                Hours  = $(if ($rel) { $rel.PowerOnHours } else { $null })
                Wear   = $(if ($rel) { $rel.Wear } else { $null })
                RErr   = $(if ($rel -and $rel.ReadErrorsTotal) { $rel.ReadErrorsTotal } else { 0 })
                WErr   = $(if ($rel -and $rel.WriteErrorsTotal) { $rel.WriteErrorsTotal } else { 0 })
            }
        }
    } catch {}
    return $out
}

function Test-QuickNetwork {
    $res = @()
    $gw = $null
    try {
        $gw = (Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' -ErrorAction Stop |
            Where-Object { $_.DefaultIPGateway } | Select-Object -First 1).DefaultIPGateway[0]
    } catch {}
    foreach ($t in @(@{ N='Шлюз'; A=$gw }, @{ N='DNS'; A='1.1.1.1' }, @{ N='Интернет'; A='8.8.8.8' })) {
        if (-not $t.A) { $res += @{ Name=$t.N; Ok=$false; Note='нет данных' }; continue }
        try { $ok = Test-Connection -ComputerName $t.A -Count 1 -Quiet -ErrorAction Stop }
        catch { $ok = $false }
        $res += @{ Name=$t.N; Ok=[bool]$ok; Note=[string]$t.A }
    }
    return $res
}

# Экспресс-аудит целиком: выполняется в фоне, пишет в лог и сохраняет отчёт.
function Start-ExpressAudit {
    Write-Log "══ Экспресс-аудит запущен (только чтение, 5-15 мин) ══"
    Start-Background {
        $rep = [System.Collections.Generic.List[string]]::new()
        $script:warnCount = 0; $script:errCount = 0
        function Write-Audit {
            param([string]$Msg, [string]$Color = 'Default', [string]$Sev = 'info')
            $rep.Add($Msg)
            Write-Log $Msg -Color $Color
            if ($Sev -eq 'warn') { $script:warnCount++ }
            if ($Sev -eq 'err')  { $script:errCount++ }
        }
        try {
            $rep.Add("PotatoPC экспресс-аудит: $(Get-Date -Format 'yyyy-MM-dd HH:mm') [$env:COMPUTERNAME]")
            try { $rep.Add("ОС: $((Get-SystemInfo).OS) | CPU: $((Get-SystemInfo).CPU) | RAM: $((Get-SystemInfo).RAM) | Uptime: $((Get-SystemInfo).Uptime)") } catch {}

            # --- Диски: место ---
            Write-Audit '── Место на дисках ──'
            foreach ($d in (Get-DiskSpaceStatus)) {
                if ($d.FreePct -lt 10)      { Write-Audit ("  ✗ {0}: {1} ГБ своб. из {2} ГБ ({3}%)" -f $d.DeviceID,$d.FreeGB,$d.TotalGB,$d.FreePct) -Color 'Red' -Sev 'err' }
                elseif ($d.FreePct -lt 15)  { Write-Audit ("  ⚠ {0}: {1} ГБ своб. из {2} ГБ ({3}%)" -f $d.DeviceID,$d.FreeGB,$d.TotalGB,$d.FreePct) -Color 'Yellow' -Sev 'warn' }
                else                        { Write-Audit ("  ✓ {0}: {1} ГБ своб. из {2} ГБ" -f $d.DeviceID,$d.FreeGB,$d.TotalGB) -Color 'Green' }
            }

            # --- SMART ---
            Write-Audit '── SMART дисков ──'
            $smarts = @(Get-SmartAll)
            if ($smarts.Count -eq 0) { Write-Audit '  ⚠ SMART недоступен (Storage API)' -Color 'Yellow' -Sev 'warn' }
            foreach ($s in $smarts) {
                $line = "  {0} [{1}]: {2}" -f $s.Disk, $s.Media, $s.Health
                if ($s.Temp)  { $line += ", $($s.Temp)°C" }
                if ($s.Hours) { $line += ", наработка $($s.Hours) ч" }
                if ($s.Wear)  { $line += ", износ $($s.Wear)%" }
                if ($s.Health -eq 'Healthy' -and $s.RErr -eq 0 -and $s.WErr -eq 0) { Write-Audit ("  ✓ " + $line) -Color 'Green' }
                elseif ($s.Health -eq 'Healthy') { Write-Audit ("  ⚠ " + $line + " (ошибки R/W: $($s.RErr)/$($s.WErr))") -Color 'Yellow' -Sev 'warn' }
                else { Write-Audit ("  ✗ " + $line) -Color 'Red' -Sev 'err' }
            }

            # --- SFC verifyonly (без изменений) ---
            Write-Audit '── SFC /verifyonly (без изменений) ──'
            try {
                $sfc = sfc /verifyonly 2>&1 | Out-String
                $tail = ($sfc -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -Last 3) -join ' '
                if ($sfc -match 'нарушений целостности не обнаружено|did not find any integrity violations') { Write-Audit '  ✓ Нарушений целостности нет' -Color 'Green' }
                else { Write-Audit ("  ⚠ SFC: " + $tail) -Color 'Yellow' -Sev 'warn' }
            } catch { Write-Audit ("  ⚠ SFC не запустился: " + $_) -Color 'Yellow' -Sev 'warn' }

            # --- DISM CheckHealth (быстро) ---
            Write-Audit '── DISM CheckHealth ──'
            try {
                $dism = DISM /Online /Cleanup-Image /CheckHealth 2>&1 | Out-String
                if ($dism -match 'повреждени|damage|ремонтопригодн|repairable|восстановлению не подлежит|not repairable') {
                    $last = ($dism -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -Last 2) -join ' '
                    Write-Audit ("  ⚠ DISM: " + $last) -Color 'Yellow' -Sev 'warn'
                } else { Write-Audit '  ✓ Образ в порядке' -Color 'Green' }
            } catch { Write-Audit ("  ⚠ DISM не запустился: " + $_) -Color 'Yellow' -Sev 'warn' }

            # --- Pending reboot ---
            Write-Audit '── Ожидание перезагрузки ──'
            $pr = @(Test-PendingReboot)
            if ($pr.Count -eq 0) { Write-Audit '  ✓ Перезагрузка не требуется' -Color 'Green' }
            else { Write-Audit ("  ⚠ Требуется перезагрузка: " + ($pr -join ', ')) -Color 'Yellow' -Sev 'warn' }

            # --- Обновления: сбои 14 дней ---
            Write-Audit '── Сбои обновлений (14 дней) ──'
            $uf = @(Get-UpdateFailures -Days 14)
            if ($uf.Count -eq 0) { Write-Audit '  ✓ Сбоев нет' -Color 'Green' }
            else {
                Write-Audit ("  ✗ Сбоев: " + $uf.Count) -Color 'Red' -Sev 'err'
                $uf | Select-Object -First 5 | ForEach-Object { Write-Audit ("    - {0:dd.MM} [{1}] {2}" -f $_.Date, $_.Result, $_.Title) }
            }

            # --- Журналы: ошибки 24ч ---
            Write-Audit '── Ошибки журналов (24 ч) ──'
            $ee = @(Get-RecentEventErrors -Hours 24 -Max 100)
            if ($ee.Count -eq 0) { Write-Audit '  ✓ Критических ошибок и ошибок нет' -Color 'Green' }
            else {
                $crit = @($ee | Where-Object { $_.LevelDisplayName -match 'Критич|Critical' }).Count
                if ($crit -gt 0) { Write-Audit ("  ✗ Критических: $crit, всего ошибок: " + $ee.Count) -Color 'Red' -Sev 'err' }
                else { Write-Audit ("  ⚠ Ошибок: " + $ee.Count) -Color 'Yellow' -Sev 'warn' }
                $ee | Group-Object Source | Sort-Object Count -Descending | Select-Object -First 5 |
                    ForEach-Object { Write-Audit ("    - {0}: {1}" -f $_.Name, $_.Count) }
            }

            # --- Minidumps ---
            Write-Audit '── Minidumps (BSOD) ──'
            $dumps = @(Get-MiniDumps -Max 5)
            if ($dumps.Count -eq 0) { Write-Audit '  ✓ Дампов нет' -Color 'Green' }
            else {
                Write-Audit ("  ✗ Дампов: " + $dumps.Count + " (последние):") -Color 'Red' -Sev 'err'
                $dumps | ForEach-Object { Write-Audit ("    - {0:dd.MM.yyyy HH:mm} {1} ({2} МБ)" -f $_.LastWriteTime, $_.Name, $_.SizeMB) }
            }

            # --- Службы Auto, которые не запущены ---
            Write-Audit '── Службы автозапуска ──'
            $fs = @(Get-FailedAutoServices)
            if ($fs.Count -eq 0) { Write-Audit '  ✓ Все службы автозапуска работают' -Color 'Green' }
            else {
                Write-Audit ("  ⚠ Не запущено: " + $fs.Count) -Color 'Yellow' -Sev 'warn'
                $fs | Select-Object -First 8 | ForEach-Object { Write-Audit ("    - {0} [{1}]" -f $_.Name, $_.State) }
            }

            # --- Драйверы с ошибками ---
            Write-Audit '── Драйверы ──'
            $dp = @(Get-DriverProblems)
            if ($dp.Count -eq 0) { Write-Audit '  ✓ Устройства без ошибок' -Color 'Green' }
            else {
                Write-Audit ("  ✗ Устройств с ошибками: " + $dp.Count) -Color 'Red' -Sev 'err'
                $dp | Select-Object -First 8 | ForEach-Object { Write-Audit ("    - {0} (код {1})" -f $_.Name, $_.ConfigManagerErrorCode) }
            }

            # --- Defender ---
            Write-Audit '── Defender ──'
            $ds = Get-DefenderStatus
            if (-not $ds.Ok) { Write-Audit '  ⚠ Статус Defender недоступен (сторонний АВ?)' -Color 'Yellow' -Sev 'warn' }
            elseif ($ds.Mode -like '*Normal*') {
                $sigNote = if ($ds.SigAge -gt 7) { " (сигнатуры старше 7 дней!)" } else { "" }
                Write-Audit ("  ✓ Активен, сигнатуры: {0} дн. назад{1}" -f $ds.SigAge, $sigNote) -Color 'Green'
                if ($ds.SigAge -gt 7) { $script:warnCount++ }
            } else { Write-Audit ("  ⚠ Режим: " + $ds.Mode) -Color 'Yellow' -Sev 'warn' }

            # --- Память и CPU ---
            Write-Audit '── Память и CPU ──'
            try {
                $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
                $load = [math]::Round(100 * (1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize))
                if ($load -ge 90) { Write-Audit ("  ⚠ Память загружена на {0}% в простое?" -f $load) -Color 'Yellow' -Sev 'warn' }
                else { Write-Audit ("  ✓ Память: занято {0}%" -f $load) -Color 'Green' }
            } catch {}
            try {
                Get-Process -ErrorAction Stop | Where-Object { $_.CPU } | Sort-Object CPU -Descending |
                    Select-Object -First 5 | ForEach-Object { Write-Audit ("    - {0}: CPU {1:N0} c, RAM {2:N0} МБ" -f $_.ProcessName, $_.CPU, ($_.WorkingSet64/1MB)) }
            } catch {}

            # --- Батарея ---
            Write-Audit '── Батарея ──'
            try {
                $bat = @(Get-CimInstance Win32_Battery -ErrorAction Stop)
                if ($bat.Count -eq 0) { Write-Audit '  - Батареи нет (стационарный ПК)' }
                else { $bat | ForEach-Object { Write-Audit ("  ✓ Заряд: {0}% (статус {1})" -f $_.EstimatedChargeRemaining, $_.BatteryStatus) -Color 'Green' } }
            } catch { Write-Audit '  - Нет данных' }

            # --- Сеть ---
            Write-Audit '── Сеть (ping x1) ──'
            foreach ($n in (Test-QuickNetwork)) {
                if ($n.Ok) { Write-Audit ("  ✓ {0}: {1}" -f $n.Name, $n.Note) -Color 'Green' }
                else { Write-Audit ("  ✗ {0}: {1}" -f $n.Name, $n.Note) -Color 'Red' -Sev 'err' }
            }

            # --- Итог и файл ---
            $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
            $path = Join-Path $script:WorkFolder ("audit-" + $stamp + ".txt")
            try { $rep | Out-File -FilePath $path -Encoding UTF8 -Force } catch { $path = '' }
            Write-Log '══════════════════════════════════════'
            Write-Log ("Аудит завершён: ошибок $($script:errCount), предупреждений $($script:warnCount)") -Color 'Green'
            if ($path) { Write-Log ("Отчёт: " + $path) -Color 'Green' }
            Write-Log '══════════════════════════════════════'
            Set-BgResult -Key 'auditReport' -Value @{ Path=$path; Err=$script:errCount; Warn=$script:warnCount }
        } catch {
            Write-Log ("Аудит прерван: " + $_) -Color 'Red'
            Set-BgResult -Key 'auditReport' -Value @{ Path=''; Err=1; Warn=0 }
        }
    }
}
