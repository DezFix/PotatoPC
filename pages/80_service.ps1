# PAGE: service
# TITLE: Обслуживание
# ICON: wrench
# ORDER: 80

$script:SvUi = $null

function Get-RepairTools {
    return @(
        @{ Id = 'sfcdism'; Title = 'Проверить и починить системные файлы'; Desc = 'DISM восстанавливает хранилище компонентов, затем SFC чинит файлы Windows. 15-40 минут'; Icon = 'shield' }
        @{ Id = 'chkdsk'; Title = 'Проверить диск ' + $env:SystemDrive; Desc = 'Поиск ошибок файловой системы без перезагрузки (chkdsk /scan)'; Icon = 'disk' }
        @{ Id = 'chkdskboot'; Title = 'Исправить диск при перезагрузке'; Desc = 'Если проверка нашла ошибки: исправление выполнится при следующем включении'; Icon = 'power' }
        @{ Id = 'net'; Title = 'Сбросить настройки сети'; Desc = 'Winsock, TCP/IP и кэш DNS - когда интернет «есть, но не работает». Нужна перезагрузка'; Icon = 'network' }
        @{ Id = 'wu'; Title = 'Починить Центр обновления'; Desc = 'Останавливает службы обновления и пересоздаёт их кэш (SoftwareDistribution, catroot2)'; Icon = 'refresh' }
        @{ Id = 'icons'; Title = 'Пересоздать кэш значков'; Desc = 'Когда у ярлыков пустые или чужие значки. Проводник перезапустится'; Icon = 'folder' }
        @{ Id = 'store'; Title = 'Сбросить кэш Microsoft Store'; Desc = 'Когда Магазин не открывается или не скачивает'; Icon = 'box' }
    )
}

function Invoke-RepairTool {
    param([string]$Id)
    $sys = Join-Path $env:WINDIR 'System32'
    $ok = $true
    switch ($Id) {
        'sfcdism' {
            Write-Log 'DISM /RestoreHealth (может долго стоять на 20% и 62% - это нормально)...'
            $r = Invoke-ProcessLive -FilePath (Join-Path $sys 'dism.exe') -Arguments '/Online /Cleanup-Image /RestoreHealth' -TimeoutSec 5400 -Encoding oem
            if ($r.Code -ne 0) { Write-Log ('DISM завершился с кодом ' + $r.Code) 'warn'; $ok = $false }
            if (Test-JobCancel) { return $false }
            Write-Log 'SFC /scannow...'
            $r = Invoke-ProcessLive -FilePath (Join-Path $sys 'sfc.exe') -Arguments '/scannow' -TimeoutSec 5400 -Encoding unicode
            if ($r.Output -match '(?i)did not find any integrity|не обнаружила нарушений') { Write-Log 'Системные файлы в порядке' 'ok' }
            elseif ($r.Output -match '(?i)successfully repaired|успешно их восстановила') { Write-Log 'Повреждённые файлы восстановлены. Перезагрузите компьютер.' 'ok' }
            elseif ($r.Output -match '(?i)unable to fix|не может восстановить') { Write-Log 'SFC нашла файлы, которые не смогла восстановить. Подробности: C:\Windows\Logs\CBS\CBS.log' 'warn'; $ok = $false }
        }
        'chkdsk' {
            $r = Invoke-ProcessLive -FilePath (Join-Path $sys 'chkdsk.exe') -Arguments ($env:SystemDrive + ' /scan') -TimeoutSec 3600 -Encoding oem
            $ok = ($r.Code -eq 0)
            if ($r.Code -eq 0) { Write-Log 'Ошибок файловой системы не найдено' 'ok' } else { Write-Log 'Найдены ошибки. Нажмите «Исправить диск при перезагрузке».' 'warn' }
        }
        'chkdskboot' {
            $r = Invoke-ProcessLive -FilePath (Join-Path $sys 'fsutil.exe') -Arguments ('dirty set ' + $env:SystemDrive) -TimeoutSec 60 -Encoding oem
            $ok = ($r.Code -eq 0)
            if ($ok) { Write-Log 'Проверка с исправлением запланирована на следующую загрузку' 'ok' }
        }
        'net' {
            foreach ($a in @('winsock reset', 'int ip reset', 'int ipv6 reset')) { [void](Invoke-ProcessLive -FilePath (Join-Path $sys 'netsh.exe') -Arguments $a -TimeoutSec 120 -Encoding oem) }
            [void](Invoke-ProcessLive -FilePath (Join-Path $sys 'ipconfig.exe') -Arguments '/flushdns' -TimeoutSec 60 -Encoding oem)
            Write-Log 'Сеть сброшена. Перезагрузите компьютер.' 'ok'
        }
        'wu' {
            $svcs = @('wuauserv', 'bits', 'cryptsvc', 'msiserver')
            foreach ($s in $svcs) { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue }
            $stamp = Get-Date -Format 'yyyyMMddHHmmss'
            foreach ($d in @((Join-Path $env:WINDIR 'SoftwareDistribution'), (Join-Path $sys 'catroot2'))) {
                if (Test-Path -LiteralPath $d) {
                    try { Rename-Item -LiteralPath $d -NewName ((Split-Path $d -Leaf) + '.old-' + $stamp) -ErrorAction Stop; Write-Log ('Переименовано: ' + $d) }
                    catch { Write-Log ('Не удалось переименовать ' + $d + ': ' + $_.Exception.Message) 'warn'; $ok = $false }
                }
            }
            foreach ($s in $svcs) { Start-Service -Name $s -ErrorAction SilentlyContinue }
            Write-Log 'Центр обновления сброшен. Старые папки с суффиксом .old можно удалить позже.' 'ok'
        }
        'icons' {
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            foreach ($f in @((Join-Path $env:LOCALAPPDATA 'IconCache.db')) + @(Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer') -Filter 'iconcache*' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })) {
                try { Remove-Item -LiteralPath $f -Force -ErrorAction Stop } catch {}
            }
            Start-Process explorer.exe
            Write-Log 'Кэш значков пересоздан' 'ok'
        }
        'store' { Start-Process (Join-Path $sys 'wsreset.exe'); Write-Log 'Кэш Магазина сбрасывается - откроется окно Microsoft Store' 'ok' }
    }
    Add-History -Kind 'service' -Name ('Обслуживание: ' + $Id) -Result $(if ($ok) { 'ok' } else { 'fail' })
    return $ok
}

# --- Автообслуживание по расписанию ---

function Get-MaintenanceScript {
    return @'
# PotatoPC: еженедельное обслуживание (запускается планировщиком от SYSTEM).
$ErrorActionPreference = 'Continue'
$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Join-Path $env:ProgramData 'PotatoPC'
$log = Join-Path $root 'logs\maintenance.log'
New-Item -ItemType Directory -Path (Split-Path $log) -Force -ErrorAction SilentlyContinue | Out-Null
function L($m) { Add-Content -LiteralPath $log -Value ((Get-Date -Format 's') + ' ' + $m) -Encoding UTF8 }
L 'Старт обслуживания'
$cfg = Get-Content -LiteralPath (Join-Path $base 'maintenance.json') -Raw -Encoding UTF8 | ConvertFrom-Json
. (Join-Path $base 'CleanGuard.ps1')
$paths = @()
if ($cfg.Temp) {
    $paths += (Join-Path $env:WINDIR 'Temp')
    $paths += (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive')
}
foreach ($p in @(Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special -and $_.LocalPath -and (Test-Path -LiteralPath $_.LocalPath) })) {
    $lp = $p.LocalPath
    if ($cfg.Temp) { $paths += @((Join-Path $lp 'AppData\Local\Temp'), (Join-Path $lp 'AppData\Local\Microsoft\Windows\WER'), (Join-Path $lp 'AppData\Local\CrashDumps')) }
    if ($cfg.Browsers) {
        foreach ($b in @('Google\Chrome\User Data\Default\Cache\Cache_Data', 'Microsoft\Edge\User Data\Default\Cache\Cache_Data', 'BraveSoftware\Brave-Browser\User Data\Default\Cache\Cache_Data', 'Yandex\YandexBrowser\User Data\Default\Cache\Cache_Data')) {
            $paths += (Join-Path $lp ('AppData\Local\' + $b))
        }
    }
}
$paths = @($paths | Where-Object { Test-Path -LiteralPath $_ })
if ($paths.Count) {
    Reset-CleanRemovedReport
    [void](Clear-CleanPaths -Resolved $paths -MinAgeDays 2)
    $rep = Get-CleanRemovedReport
    L ('Очистка: удалено ' + $rep.Count + ' файлов, ' + [math]::Round($rep.Bytes / 1MB) + ' МБ')
}
if ($cfg.Defender) { try { Update-MpSignature -ErrorAction Stop; L 'Базы Защитника обновлены' } catch { L ('Базы Защитника: ' + $_.Exception.Message) } }
if ($cfg.RestorePoint) {
    try {
        Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description 'PotatoPC: еженедельная точка' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; L 'Точка восстановления создана'
    } catch { L ('Точка восстановления: ' + $_.Exception.Message) }
}
try {
    $h = @{ Time = (Get-Date).ToString('s'); Kind = 'maintenance'; Name = 'Автообслуживание по расписанию'; Result = 'ok'; Detail = ''; Ref = ''; Pc = $env:COMPUTERNAME } | ConvertTo-Json -Compress
    Add-Content -LiteralPath (Join-Path $root 'history.jsonl') -Value $h -Encoding UTF8
} catch {}
L 'Готово'
'@
}

function Get-MaintenanceState {
    $r = @{ On = $false; Config = $null; Last = $null; Result = $null; Next = $null }
    try {
        $t = Get-ScheduledTask -TaskName 'PotatoPC Maintenance' -TaskPath '\PotatoPC\' -ErrorAction Stop
        $r.On = ($t.State -ne 'Disabled')
        $i = Get-ScheduledTaskInfo -TaskName 'PotatoPC Maintenance' -TaskPath '\PotatoPC\' -ErrorAction SilentlyContinue
        if ($i) { $r.Last = $i.LastRunTime; $r.Result = $i.LastTaskResult; $r.Next = $i.NextRunTime }
    } catch {}
    try { $r.Config = Get-Content -LiteralPath (Join-Path $env:ProgramData 'PotatoPC\maintenance\maintenance.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch {}
    return $r
}

function Register-Maintenance {
    param($Config)
    $dir = Join-Path $env:ProgramData 'PotatoPC\maintenance'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    # Задача выполняется от SYSTEM, поэтому писать в папку могут только администраторы,
    # иначе обычный пользователь подменил бы скрипт и получил права системы.
    & icacls.exe $dir /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
    Copy-Item -LiteralPath $CleanGuardPath -Destination (Join-Path $dir 'CleanGuard.ps1') -Force
    $utf8 = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText((Join-Path $dir 'maintenance.ps1'), (Get-MaintenanceScript), $utf8)
    [System.IO.File]::WriteAllText((Join-Path $dir 'maintenance.json'), ($Config | ConvertTo-Json), $utf8)
    $days = @($Config.Days | ForEach-Object { [System.DayOfWeek]$_ })
    $at = [datetime]::ParseExact($Config.Time, 'HH:mm', $null)
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $days -At $at
    $action = New-ScheduledTaskAction -Execute (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $dir 'maintenance.ps1') + '"')
    $principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2) -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries
    Register-ScheduledTask -TaskName 'PotatoPC Maintenance' -TaskPath '\PotatoPC\' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'PotatoPC: еженедельная чистка и обслуживание' -Force | Out-Null
    Add-History -Kind 'service' -Name 'Автообслуживание включено'
}

function Unregister-Maintenance {
    try { Unregister-ScheduledTask -TaskName 'PotatoPC Maintenance' -TaskPath '\PotatoPC\' -Confirm:$false -ErrorAction Stop } catch {}
    Add-History -Kind 'service' -Name 'Автообслуживание выключено'
}

function Build-Page_service {
    $ui = @{ Days = @{}; DayBtns = @() }
    $L = New-PageLayout -Title 'Обслуживание' -Subtitle 'Починка Windows, обслуживание по расписанию и данные PotatoPC'
    $all = New-Button -Text 'Починить Windows' -Icon 'shield' -Kind Primary -OnClick { Start-Repair -Id 'sfcdism' }
    $refresh = New-Button -Text 'Обновить' -Icon 'refresh' -Kind Ghost -OnClick { Show-Page_service }
    $refresh.Margin = New-Thickness 10, 0, 0, 0
    $all.Margin = New-Thickness 10, 0, 0, 0
    [void]$L.HeaderRight.Children.Add($refresh)
    [void]$L.HeaderRight.Children.Add($all)
    $sec = New-Section -Title 'Починка Windows'
    foreach ($t in (Get-RepairTools)) {
        $b = New-Button -Text 'Запустить' -Kind Small -Tag $t.Id -OnClick { Start-Repair -Id $this.Tag }
        [void]$sec.Body.Children.Add((New-Row -Left (New-IconTile -Icon $t.Icon) -Main (New-TitleBlock -Title $t.Title -Sub $t.Desc) -Right @($b)))
    }
    [void]$L.Body.Children.Add($sec.Root)

    # Расписание
    $ui.MaintToggle = New-Toggle -OnClick { Switch-Maintenance -On ([bool]$this.IsChecked) }
    $ms = New-Section -Title 'Автообслуживание' -Right @($ui.MaintToggle)
    $ui.MaintState = New-Text -Text '' -Size 13 -Color 'Muted' -Wrap -Margin (16, 0, 16, 10)
    [void]$ms.Body.Children.Add($ui.MaintState)
    $opts = New-Stack -Margin (16, 4, 16, 14)
    $dw = New-Object System.Windows.Controls.WrapPanel
    [void]$dw.Children.Add((New-Text -Text 'Дни:' -Size 13 -Color 'Muted' -Margin (0, 0, 10, 8)))
    $names = @('Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'); $vals = @(1, 2, 3, 4, 5, 6, 0)
    for ($i = 0; $i -lt 7; $i++) {
        $b = New-Button -Text $names[$i] -Kind Chip -Tag $vals[$i] -OnClick { $script:SvUi.Days[[int]$this.Tag] = -not $script:SvUi.Days[[int]$this.Tag]; Set-ChipActive -Button $this -Active $script:SvUi.Days[[int]$this.Tag] }
        $ui.Days[$vals[$i]] = $false
        $ui.DayBtns += , $b
        [void]$dw.Children.Add($b)
    }
    [void]$dw.Children.Add((New-Text -Text 'Время:' -Size 13 -Color 'Muted' -Margin (12, 0, 10, 8)))
    $ui.Time = New-TextInput -Text '12:00' -Width 80
    $ui.Time.Margin = New-Thickness 0, 0, 0, 8
    [void]$dw.Children.Add($ui.Time)
    [void]$opts.Children.Add($dw)
    $ui.OptTemp = New-CheckBox -Text 'Временные файлы и отчёты об ошибках (старше 2 дней)' -Checked $true
    $ui.OptBr = New-CheckBox -Text 'Кэши браузеров'
    $ui.OptDef = New-CheckBox -Text 'Обновить базы Защитника' -Checked $true
    $ui.OptRp = New-CheckBox -Text 'Точка восстановления раз в неделю' -Checked $true
    foreach ($c in @($ui.OptTemp, $ui.OptBr, $ui.OptDef, $ui.OptRp)) { $c.Margin = New-Thickness 0, 4, 0, 4; [void]$opts.Children.Add($c) }
    $save = New-Button -Text 'Сохранить расписание' -Kind Small -OnClick { Switch-Maintenance -On $true }
    $save.HorizontalAlignment = 'Left'; $save.Margin = New-Thickness 0, 8, 0, 0
    [void]$opts.Children.Add($save)
    [void]$ms.Body.Children.Add($opts)
    [void]$L.Body.Children.Add($ms.Root)

    # Данные PotatoPC
    $ds = New-Section -Title 'Данные PotatoPC на этом компьютере'
    $mode = if ($PortableMode) { 'Портативный режим: журнал, история и отчёты лежат рядом с программой - ' + $DataRoot } else { 'Журнал, история и отчёты: ' + $DataRoot + '. Резервные копии твиков: ' + $BackupFolder }
    [void]$ds.Body.Children.Add((New-Text -Text $mode -Size 13 -Color 'Muted' -Wrap -Margin (16, 0, 16, 10)))
    $w = New-Object System.Windows.Controls.WrapPanel
    $w.Margin = New-Thickness 16, 0, 16, 14
    $b1 = New-Button -Text 'Открыть папку данных' -Kind Small -OnClick { Open-Path $DataRoot }
    $b2 = New-Button -Text $(if ($PortableMode) { 'Выключить портативный режим' } else { 'Портативный режим (для флешки)' }) -Kind Small -OnClick { Switch-PortableMode }
    $b3 = New-Button -Text 'Удалить следы PotatoPC' -Kind SmallDanger -OnClick { Remove-PotatoTraces }
    foreach ($b in @($b1, $b2, $b3)) { $b.Margin = New-Thickness 0, 0, 10, 8; [void]$w.Children.Add($b) }
    [void]$ds.Body.Children.Add($w)
    [void]$L.Body.Children.Add($ds.Root)
    $script:SvUi = $ui
    return $L.Root
}

function Show-Page_service {
    param($Arg)
    $s = Get-MaintenanceState
    $ui = $script:SvUi
    $ui.MaintToggle.IsChecked = $s.On
    if ($s.Config) {
        foreach ($k in @($ui.Days.Keys)) { $ui.Days[$k] = (@($s.Config.Days) -contains $k) }
        $ui.Time.Text = [string]$s.Config.Time
        $ui.OptTemp.IsChecked = [bool]$s.Config.Temp; $ui.OptBr.IsChecked = [bool]$s.Config.Browsers
        $ui.OptDef.IsChecked = [bool]$s.Config.Defender; $ui.OptRp.IsChecked = [bool]$s.Config.RestorePoint
    } elseif (-not ($ui.Days.Values -contains $true)) { $ui.Days[0] = $true }
    foreach ($b in $ui.DayBtns) { Set-ChipActive -Button $b -Active $ui.Days[[int]$b.Tag] }
    $t = if ($s.On) { 'Включено.' } else { 'Выключено. Раз в неделю PotatoPC может сам чистить мусор, обновлять базы Защитника и делать точку восстановления - даже если программу не запускать.' }
    if ($s.Last -and $s.Last.Year -gt 2000) { $t += ' Последний запуск: ' + $s.Last.ToString('dd.MM.yyyy HH:mm') + $(if ($s.Result -eq 0) { ' (успешно)' } else { ' (код ' + $s.Result + ')' }) + '.' }
    if ($s.On -and $s.Next) { $t += ' Следующий: ' + $s.Next.ToString('dd.MM.yyyy HH:mm') + '.' }
    $ui.MaintState.Text = $t
}

function Start-Repair {
    param([string]$Id)
    $t = @(Get-RepairTools | Where-Object { $_.Id -eq $Id })[0]
    if ($Id -eq 'net' -and -not (Show-Confirm -Message 'Сбросить сетевые настройки? Пропадут ручные настройки IP, VPN-адаптеры может понадобиться переустановить. После сброса нужна перезагрузка.' -Warning)) { return }
    if ($Id -eq 'icons' -and -not (Show-Confirm -Message 'Проводник и панель задач перезапустятся на пару секунд. Продолжить?')) { return }
    Start-BgTask -Name $t.Title -Vars @{ Id = $Id } -Script { Invoke-RepairTool -Id $Id } | Out-Null
}

function Switch-Maintenance {
    param([bool]$On)
    $ui = $script:SvUi
    if (-not $On) {
        Start-BgTask -Name 'Автообслуживание' -Script { Unregister-Maintenance; Write-Log 'Автообслуживание выключено' 'ok' } -OnDone { Show-Page_service } | Out-Null
        return
    }
    $days = @($ui.Days.Keys | Where-Object { $ui.Days[$_] })
    if ($days.Count -eq 0) { Show-Info 'Выберите хотя бы один день.'; $ui.MaintToggle.IsChecked = $false; return }
    $time = ([string]$ui.Time.Text).Trim()
    if ($time -notmatch '^([01]?\d|2[0-3]):[0-5]\d$') { Show-Info 'Время в формате ЧЧ:ММ, например 12:00'; $ui.MaintToggle.IsChecked = $false; return }
    if ($time.Length -eq 4) { $time = '0' + $time }
    $cfg = [ordered]@{ Days = $days; Time = $time; Temp = [bool]$ui.OptTemp.IsChecked; Browsers = [bool]$ui.OptBr.IsChecked; Defender = [bool]$ui.OptDef.IsChecked; RestorePoint = [bool]$ui.OptRp.IsChecked }
    Start-BgTask -Name 'Автообслуживание' -Vars @{ Cfg = $cfg } -Script { Register-Maintenance -Config $Cfg; Write-Log 'Автообслуживание включено' 'ok' } -OnDone { Show-Page_service } | Out-Null
}

function Switch-PortableMode {
    $flag = Join-Path $AppRoot 'portable.txt'
    try {
        if ($PortableMode) { Remove-Item -LiteralPath $flag -Force -ErrorAction Stop; Show-Info 'Портативный режим выключен. Перезапустите PotatoPC.' }
        else {
            Set-Content -LiteralPath $flag -Value 'Этот файл включает портативный режим PotatoPC: данные хранятся в папке data рядом с программой.' -Encoding UTF8 -ErrorAction Stop
            Show-Info 'Портативный режим включён. Перезапустите PotatoPC - журнал, история и отчёты будут храниться в папке data рядом с программой.'
        }
    } catch { Show-Info ('Не получилось: ' + $_.Exception.Message + "`nВозможно, папка программы защищена от записи.") -Icon 'Warning' }
}

function Remove-PotatoTraces {
    $msg = "Удалить с этого компьютера:`n  • журнал, историю и отчёты`n  • временные файлы PotatoPC`n  • задачу автообслуживания`n`nСама программа (папка " + $AppRoot + ') не удаляется.'
    if (-not (Show-Confirm -Message $msg -Title 'Удалить следы' -Warning)) { return }
    $withBackups = Show-Confirm -Message ("Удалить и резервные копии (" + $BackupFolder + ")?`n`nБез них откат некоторых твиков (файл подкачки, UAC, гость, PUA) вернёт заводские настройки, а не ваши прежние.") -Title 'Резервные копии' -Warning
    Start-BgTask -Name 'Удаление следов' -Vars @{ Wb = $withBackups } -Script {
        Unregister-Maintenance
        $targets = @($WorkFolder, (Join-Path $env:LOCALAPPDATA 'PotatoPC'), (Join-Path $env:ProgramData 'PotatoPC\maintenance'), (Join-Path $env:ProgramData 'PotatoPC\cache'))
        if (-not $PortableMode) { $targets += @($LogFolder, $ReportFolder, $HistoryPath, $SettingsPath, $UIStatePath) }
        if ($Wb) { $targets += $BackupFolder }
        foreach ($t in $targets) {
            if (-not $t -or -not (Test-Path -LiteralPath $t)) { continue }
            try { Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction Stop; Write-Log ('Удалено: ' + $t) } catch { Write-Log ('Не удалено (занято): ' + $t) 'warn' }
        }
        Write-Log 'Следы PotatoPC удалены. Журнал этого запуска удалится после закрытия программы.' 'ok'
    } | Out-Null
}
