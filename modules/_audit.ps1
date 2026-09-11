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

# --- Железо: CPU / RAM / GPU / батарея / скорость диска (только чтение) ---

function Get-CpuInfo {
    try {
        return @(Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1 Name,
            NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, LoadPercentage)
    } catch { return @() }
}

function Get-RamDetails {
    try {
        return @(Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop |
            Select-Object DeviceLocator, Manufacturer,
            @{N='SizeGB';E={[math]::Round($_.Capacity/1GB,1)}},
            @{N='SpeedMHz';E={$_.Speed}})
    } catch { return @() }
}

function Get-GpuInfo {
    try {
        return @(Get-CimInstance Win32_VideoController -ErrorAction Stop | Select-Object Name,
            @{N='VRAM_GB';E={ if ($_.AdapterRAM -and $_.AdapterRAM -gt 0) { [math]::Round($_.AdapterRAM/1GB,1) } else { $null } }},
            DriverVersion, DriverDate, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate, Status)
    } catch { return @() }
}

function Get-BatteryWear {
    try {
        return @(Get-CimInstance Win32_Battery -ErrorAction Stop | Select-Object EstimatedChargeRemaining, BatteryStatus,
            DesignCapacity, FullChargeCapacity,
            @{N='WearPct';E={
                if ($_.DesignCapacity -and $_.FullChargeCapacity -and $_.DesignCapacity -gt 0) {
                    [math]::Max(0, 100 - [math]::Round(100 * $_.FullChargeCapacity / $_.DesignCapacity))
                } else { $null } }})
    } catch { return @() }
}

function Test-DiskSpeed {
    # Быстрый замер во TEMP: запись+чтение 64 МБ, файл удаляется. Безопасно для SSD.
    param([int]$MB = 64)
    $file = Join-Path ([System.IO.Path]::GetTempPath()) ('potato-speed-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $buf = New-Object byte[] (1MB)
        (New-Object Random).NextBytes($buf)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $fs = [System.IO.File]::OpenWrite($file)
        try { for ($i = 0; $i -lt $MB; $i++) { $fs.Write($buf, 0, $buf.Length) } } finally { $fs.Close() }
        $w = $MB / $sw.Elapsed.TotalSeconds
        $sw.Restart()
        $fr = [System.IO.File]::OpenRead($file)
        try { while ($fr.Read($buf, 0, $buf.Length) -gt 0) {} } finally { $fr.Close() }
        $r = $MB / $sw.Elapsed.TotalSeconds
        return @{ WriteMBs = [math]::Round($w, 1); ReadMBs = [math]::Round($r, 1) }
    } catch { return $null }
    finally { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
}

function Get-CpuScore {
    # Решето до 500К: 3-10 сек на нормальном ПК, до полминуты на слабом. Только CPU.
    $N = 500000
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $isP = New-Object bool[] ($N + 1)
    for ($i = 2; $i -le $N; $i++) { $isP[$i] = $true }
    $root = [math]::Sqrt($N)
    for ($i = 2; $i -le $root; $i++) {
        if ($isP[$i]) { for ($j = $i * $i; $j -le $N; $j += $i) { $isP[$j] = $false } }
    }
    $sw.Stop()
    $t = [math]::Max(0.01, $sw.Elapsed.TotalSeconds)
    return @{ Score = [int]($N / $t); Sec = [math]::Round($t, 1) }
}

function Get-RamScore {
    # Копирование 256 МБ: пропускная способность памяти, МБ/с.
    $MB = 256
    $b1 = New-Object byte[] (64MB)
    $b2 = New-Object byte[] (64MB)
    (New-Object Random).NextBytes($b1)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt ($MB / 64); $i++) { [System.Buffer]::BlockCopy($b1, 0, $b2, 0, $b1.Length) }
    $sw.Stop()
    return @{ MBs = [int]($MB / [math]::Max(0.01, $sw.Elapsed.TotalSeconds)) }
}

function Get-Gpu2DScore {
    # 2000 заливок GDI: попугаи 2D-ускорения.
    try { Add-Type -AssemblyName System.Drawing -ErrorAction Stop } catch { return $null }
    $bmp = $null; $gr = $null; $br = $null
    try {
        $bmp = New-Object System.Drawing.Bitmap(800, 600)
        $gr = [System.Drawing.Graphics]::FromImage($bmp)
        $br = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Red)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        for ($i = 0; $i -lt 2000; $i++) { $gr.FillRectangle($br, 0, 0, 200, 200) }
        $sw.Stop()
        return @{ Ops = [int](2000 / [math]::Max(0.01, $sw.Elapsed.TotalSeconds)) }
    } catch { return $null }
    finally { try { $gr.Dispose() } catch {}; try { $bmp.Dispose() } catch {}; try { $br.Dispose() } catch {} }
}

function Get-PotatoVerdict {
    param([int]$Index)
    if ($Index -lt 25) { return 'Картошка: только лёгкие задачи' }
    if ($Index -lt 50) { return 'Офисный: интернет, документы, кино' }
    if ($Index -lt 75) { return 'Игровой: тянет современные игры' }
    return 'Зверь: хватит надолго'
}

# Полный замер в 1 клик: бенчмарки + быстрое здоровье, индекс, сравнение с прошлым.
function Start-FullBenchmark {
    Write-Log "══ Полный тест ПК запущен (3-6 мин) ══"
    Set-Progress
    Start-Background {
        $rep = [System.Collections.Generic.List[string]]::new()
        $warn = 0; $err = 0
        function Write-Bench {
            param([string]$Msg, [string]$Color = 'Default', [string]$Sev = 'info')
            $rep.Add($Msg)
            Write-Log $Msg -Color $Color
            if ($Sev -eq 'warn') { $script:warnCount++ }
            if ($Sev -eq 'err')  { $script:errCount++ }
        }
        $script:warnCount = 0; $script:errCount = 0
        try {
            # Прошлый замер — для дельты (замер до оптимизации vs после).
            $prev = $null
            try {
                $old = @(Get-ChildItem (Join-Path $script:WorkFolder 'bench-*.json') -ErrorAction Stop |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1)
                if ($old.Count -gt 0) {
                    $prev = Get-Content $old[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
                }
            } catch {}
            $rep.Add("PotatoPC замер: $(Get-Date -Format 'yyyy-MM-dd HH:mm') [$env:COMPUTERNAME]")
            try { $rep.Add("ОС: $((Get-SystemInfo).OS) | CPU: $((Get-SystemInfo).CPU) | RAM: $((Get-SystemInfo).RAM)") } catch {}

            # --- Бенчмарки ---
            Write-Bench '── Скорость ──'
            Write-Bench '[*] CPU...'
            $cpu = Get-CpuScore
            Write-Bench ("  CPU: {0} попугаев" -f $cpu.Score) -Color 'Green'
            Write-Bench '[*] Память...'
            $ram = Get-RamScore
            Write-Bench ("  RAM: {0} МБ/с" -f $ram.MBs) -Color 'Green'
            Write-Bench '[*] Диск...'
            $sp = Test-DiskSpeed -MB 64
            if ($sp) { Write-Bench ("  Диск: запись {0}, чтение {1} МБ/с" -f $sp.WriteMBs, $sp.ReadMBs) -Color 'Green' }
            else { Write-Bench '  ⚠ Диск не замерился' -Color 'Yellow' -Sev 'warn' }
            Write-Bench '[*] Видео 2D...'
            $td = Get-Gpu2DScore
            if ($td) { Write-Bench ("  2D: {0} оп/сек" -f $td.Ops) -Color 'Green' }
            $cn = [math]::Min(100, $cpu.Score / 20000)
            $rn = [math]::Min(100, $ram.MBs / 80)
            $dn = 0
            if ($sp) { $dn = [math]::Min(100, (($sp.ReadMBs + $sp.WriteMBs) / 2) / 25) }
            $idx = [int](($cn + $rn + $dn) / 3)
            Write-Bench ("  Индекс: {0}/100 — {1}" -f $idx, (Get-PotatoVerdict -Index $idx)) -Color 'Green'

            # --- Быстрое здоровье (без долгих SFC/DISM — они отдельно) ---
            Write-Bench '── Здоровье ──'
            foreach ($d in (Get-DiskSpaceStatus)) {
                if ($d.FreePct -lt 10)      { Write-Bench ("  ✗ {0}: свободно {1}% — место кончается" -f $d.DeviceID, $d.FreePct) -Color 'Red' -Sev 'err' }
                elseif ($d.FreePct -lt 15)  { Write-Bench ("  ⚠ {0}: свободно {1}%" -f $d.DeviceID, $d.FreePct) -Color 'Yellow' -Sev 'warn' }
            }
            foreach ($s in (Get-SmartAll)) {
                if ($s.Health -ne 'Healthy') { Write-Bench ("  ✗ Диск {0}: {1}" -f $s.Disk, $s.Health) -Color 'Red' -Sev 'err' }
                elseif ($s.RErr -gt 0 -or $s.WErr -gt 0) { Write-Bench ("  ⚠ Диск {0}: ошибки R/W" -f $s.Disk) -Color 'Yellow' -Sev 'warn' }
            }
            $ee = @(Get-RecentEventErrors -Hours 24 -Max 100)
            $crit = @($ee | Where-Object { $_.LevelDisplayName -match 'Критич|Critical' }).Count
            if ($crit -gt 0) { Write-Bench ("  ✗ Критических ошибок за 24ч: $crit" ) -Color 'Red' -Sev 'err' }
            elseif ($ee.Count -gt 20) { Write-Bench ("  ⚠ Ошибок за 24ч: " + $ee.Count) -Color 'Yellow' -Sev 'warn' }
            else { Write-Bench ("  ✓ Журналы чистые ({0})" -f $ee.Count) -Color 'Green' }
            $dumps = @(Get-MiniDumps -Max 5)
            if ($dumps.Count -gt 0) { Write-Bench ("  ✗ BSOD-дампов: " + $dumps.Count) -Color 'Red' -Sev 'err' }
            $fs = @(Get-FailedAutoServices)
            if ($fs.Count -gt 0) { Write-Bench ("  ⚠ Не запущено служб: " + $fs.Count) -Color 'Yellow' -Sev 'warn' }
            $dp = @(Get-DriverProblems)
            if ($dp.Count -gt 0) { Write-Bench ("  ✗ Устройств с ошибками: " + $dp.Count) -Color 'Red' -Sev 'err' }
            $pr = @(Test-PendingReboot)
            if ($pr.Count -gt 0) { Write-Bench ("  ⚠ Нужна перезагрузка: " + ($pr -join ', ')) -Color 'Yellow' -Sev 'warn' }
            foreach ($n in (Test-QuickNetwork)) {
                if (-not $n.Ok) { Write-Bench ("  ✗ Сеть {0}: нет" -f $n.Name) -Color 'Red' -Sev 'err' }
            }
            foreach ($b in (Get-BatteryWear)) {
                if ($null -ne $b.WearPct -and $b.WearPct -ge 40) { Write-Bench ("  ⚠ Батарея изношена: {0}%" -f $b.WearPct) -Color 'Yellow' -Sev 'warn' }
            }

            # --- Дельта с прошлым замером ---
            if ($prev -and $prev.Index) {
                $d = $idx - [int]$prev.Index
                $arrow = if ($d -gt 0) { "▲ +$d" } elseif ($d -lt 0) { "▼ $d" } else { "— без изменений" }
                $dc = if ($d -gt 0) { 'Green' } elseif ($d -lt 0) { 'Red' } else { 'Default' }
                Write-Bench ("  Прошлый замер: {0}/100 ({1})" -f $prev.Index, $prev.Time) -Color 'Default'
                Write-Bench ("  Разница: $arrow") -Color $dc
            } else {
                Write-Bench '  Первый замер сохранён — следующий покажет разницу.' -Color 'Default'
            }

            # --- Сохранение ---
            $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
            $txtPath = Join-Path $script:WorkFolder ("bench-" + $stamp + ".txt")
            $jsPath = Join-Path $script:WorkFolder ("bench-" + $stamp + ".json")
            try { $rep | Out-File -FilePath $txtPath -Encoding UTF8 -Force } catch { $txtPath = '' }
            try {
                @{ Time = (Get-Date -Format 'yyyy-MM-dd HH:mm'); Index = $idx;
                   Cpu = $cpu.Score; Ram = $ram.MBs;
                   DiskR = $(if ($sp) { $sp.ReadMBs } else { 0 }); DiskW = $(if ($sp) { $sp.WriteMBs } else { 0 });
                   Err = $script:errCount; Warn = $script:warnCount } |
                    ConvertTo-Json -Compress | Out-File -FilePath $jsPath -Encoding UTF8 -Force
                Get-ChildItem (Join-Path $script:WorkFolder 'bench-*.json') -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -Skip 20 |
                    Remove-Item -Force -ErrorAction SilentlyContinue
            } catch {}
            Write-Log '══════════════════════════════════════'
            Write-Log ("Замер готов: индекс $idx/100, ошибок $($script:errCount), предупреждений $($script:warnCount)") -Color 'Green'
            if ($txtPath) { Write-Log ("Отчёт: " + $txtPath) -Color 'Green' }
            Write-Log '══════════════════════════════════════'
            Set-BgResult -Key 'benchReport' -Value @{ Path = $txtPath; Index = $idx; Err = $script:errCount; Warn = $script:warnCount }
        } catch {
            Write-Log ("Замер прерван: " + $_) -Color 'Red'
            Set-BgResult -Key 'benchReport' -Value @{ Path = ''; Index = -1; Err = 1; Warn = 0 }
        }
    }
}

# Экспресс-аудит целиком: выполняется в фоне, пишет в лог и сохраняет отчёт.
function Start-ExpressAudit {
    Write-Log "══ Экспресс-аудит запущен (только чтение, 5-15 мин) ══"
    Set-Progress
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

            # --- CPU ---
            Write-Audit '── Процессор ──'
            try {
                $cpu = @(Get-CpuInfo)
                if ($cpu.Count -eq 0) { Write-Audit '  ⚠ Нет данных о CPU' -Color 'Yellow' -Sev 'warn' }
                else {
                    $c = $cpu[0]
                    Write-Audit ("  ✓ {0} ({1} ядер / {2} потоков, до {3} МГц, нагрузка {4}%)" -f $c.Name.Trim(), $c.NumberOfCores, $c.NumberOfLogicalProcessors, $c.MaxClockSpeed, $c.LoadPercentage) -Color 'Green'
                }
            } catch { Write-Audit '  ⚠ Нет данных о CPU' -Color 'Yellow' -Sev 'warn' }

            # --- RAM по слотам ---
            Write-Audit '── Память по слотам ──'
            try {
                $slots = @(Get-RamDetails)
                if ($slots.Count -eq 0) { Write-Audit '  ⚠ Нет данных SPD' -Color 'Yellow' -Sev 'warn' }
                else {
                    $tot = [math]::Round(($slots | Measure-Object SizeGB -Sum).Sum, 1)
                    Write-Audit ("  ✓ Планок: {0}, всего {1} ГБ" -f $slots.Count, $tot) -Color 'Green'
                    $slots | ForEach-Object { Write-Audit ("    - {0}: {1} ГБ, {2} МГц" -f $_.DeviceLocator, $_.SizeGB, $_.SpeedMHz) }
                    if (($slots | Select-Object SpeedMHz -Unique).Count -gt 1) {
                        Write-Audit '  ⚠ Планки с разной частотой — работают на минимальной' -Color 'Yellow' -Sev 'warn'
                    }
                }
            } catch { Write-Audit '  ⚠ Нет данных SPD' -Color 'Yellow' -Sev 'warn' }

            # --- Видео ---
            Write-Audit '── Видео ──'
            try {
                $gpus = @(Get-GpuInfo)
                if ($gpus.Count -eq 0) { Write-Audit '  ⚠ Видеокарта не найдена' -Color 'Yellow' -Sev 'warn' }
                else {
                    foreach ($g in $gpus) {
                        $vram = if ($g.VRAM_GB) { ", VRAM $($g.VRAM_GB) ГБ" } else { "" }
                        $mode = if ($g.CurrentHorizontalResolution) { ", $($g.CurrentHorizontalResolution)x$($g.CurrentVerticalResolution)@$($g.CurrentRefreshRate)Гц" } else { "" }
                        Write-Audit ("  ✓ {0}{1}{2}" -f $g.Name.Trim(), $vram, $mode) -Color 'Green'
                        if ($g.DriverDate) {
                            $dd = [DateTime]$g.DriverDate
                            $age = [int]((Get-Date) - $dd).TotalDays
                            if ($age -gt 365) { Write-Audit ("  ⚠ Драйвер видео старше года ({0:dd.MM.yyyy})" -f $dd) -Color 'Yellow' -Sev 'warn' }
                        }
                    }
                }
            } catch { Write-Audit '  ⚠ Нет данных о видео' -Color 'Yellow' -Sev 'warn' }

            # --- Батарея ---
            Write-Audit '── Батарея ──'
            try {
                $bat = @(Get-BatteryWear)
                if ($bat.Count -eq 0) { Write-Audit '  - Батареи нет (стационарный ПК)' }
                else {
                    foreach ($b in $bat) {
                        $wear = if ($null -ne $b.WearPct) { ", износ $($b.WearPct)%" } else { "" }
                        if ($null -ne $b.WearPct -and $b.WearPct -ge 40) {
                            Write-Audit ("  ⚠ Заряд: {0}%{1} — батарея сильно изношена" -f $b.EstimatedChargeRemaining, $wear) -Color 'Yellow' -Sev 'warn'
                        } else {
                            Write-Audit ("  ✓ Заряд: {0}%{1}" -f $b.EstimatedChargeRemaining, $wear) -Color 'Green'
                        }
                    }
                }
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
