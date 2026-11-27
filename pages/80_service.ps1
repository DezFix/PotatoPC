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
        @{ Id = 'time'; Title = 'Синхронизировать часы'; Desc = 'Когда время уплывает или сайты пишут «сертификат недействителен»: перезапускает службу времени и сверяет часы с сервером'; Icon = 'clock' }
        @{ Id = 'print'; Title = 'Очистить зависшую очередь печати'; Desc = 'Когда документ застрял и принтер ничего не печатает: перезапускает диспетчер печати и удаляет зависшие задания'; Icon = 'file' }
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
        'time' {
            $w32 = Join-Path $sys 'w32tm.exe'
            try {
                $svc = Get-Service -Name w32time -ErrorAction Stop
                if ($svc.StartType -eq 'Disabled') { Set-Service -Name w32time -StartupType Manual; Write-Log 'Служба времени была отключена - включена (вручную)' 'warn' }
                Restart-Service -Name w32time -Force -ErrorAction SilentlyContinue
                if ((Get-Service -Name w32time).Status -ne 'Running') { Start-Service -Name w32time -ErrorAction Stop }
                [void](Invoke-ProcessLive -FilePath $w32 -Arguments '/config /update' -TimeoutSec 60 -Encoding oem)
                $r = Invoke-ProcessLive -FilePath $w32 -Arguments '/resync /force' -TimeoutSec 120 -Encoding oem
                if ($r.Code -ne 0) {
                    Write-Log 'Первая попытка не удалась - сверяю с time.windows.com' 'warn'
                    [void](Invoke-ProcessLive -FilePath $w32 -Arguments '/config /manualpeerlist:time.windows.com,0x9 /syncfromflags:manual /update' -TimeoutSec 60 -Encoding oem)
                    $r = Invoke-ProcessLive -FilePath $w32 -Arguments '/resync /force' -TimeoutSec 120 -Encoding oem
                }
                if ($r.Code -eq 0) { Write-Log ('Часы сверены. Сейчас: ' + (Get-Date -Format 'dd.MM.yyyy HH:mm:ss')) 'ok' }
                else { Write-Log 'Не удалось сверить часы - проверьте интернет' 'warn'; $ok = $false }
            } catch { Write-Log ('Служба времени: ' + $_.Exception.Message) 'warn'; $ok = $false }
        }
        'print' {
            try {
                Stop-Service -Name Spooler -Force -ErrorAction Stop
                $n = 0
                foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $sys 'spool\PRINTERS') -File -Force -ErrorAction SilentlyContinue)) { try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $n++ } catch {} }
                Start-Service -Name Spooler -ErrorAction Stop
                Write-Log ('Очередь печати очищена (заданий удалено: ' + $n + '), диспетчер печати перезапущен') 'ok'
            } catch { Write-Log ('Диспетчер печати: ' + $_.Exception.Message) 'warn'; $ok = $false }
        }
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
    $ui.DataSub = @{}
    $mkOpen = { param($p) $b = New-Button -Text 'Открыть' -Kind Small -Tag $p -OnClick { if (Test-Path -LiteralPath $this.Tag) { Open-Path $this.Tag } else { Show-Info ('Папки пока нет: ' + $this.Tag) } }; return $b }
    $rows = @(
        @{ Key = 'data'; Icon = 'history'; Title = $(if ($PortableMode) { 'Журнал, история, отчёты (на флешке)' } else { 'Журнал, история, отчёты' }); Path = $DataRoot; Right = @((& $mkOpen $DataRoot)) }
        @{ Key = 'backups'; Icon = 'undo'; Title = 'Резервные копии твиков'; Path = $BackupFolder; Right = @((& $mkOpen $BackupFolder)) }
        @{ Key = 'temp'; Icon = 'trash'; Title = 'Временные файлы'; Path = $WorkFolder; Right = @((& $mkOpen $WorkFolder), (New-Button -Text 'Очистить' -Kind Small -OnClick { Clear-PotatoTemp })) }
        @{ Key = 'app'; Icon = 'box'; Title = 'Папка программы (этот запуск)'; Path = $AppRoot; Right = @((& $mkOpen $AppRoot)) }
    )
    foreach ($r in $rows) {
        $tb = New-TitleBlock -Title $r.Title -Sub $r.Path
        $tb.Children[1].TextWrapping = 'Wrap'
        $ui.DataSub[$r.Key] = $tb.Children[1]
        if ($r.Right.Count -gt 1) { $r.Right[0].Margin = New-Thickness 0, 0, 8, 0 }
        [void]$ds.Body.Children.Add((New-Row -Left (New-IconTile -Icon $r.Icon) -Main $tb -Right $r.Right))
    }
    $kill = New-Button -Text 'Уничтожить все следы PotatoPC' -Icon 'trash' -Kind SmallDanger -OnClick { Remove-PotatoTraces }
    $kill.HorizontalAlignment = 'Left'; $kill.Margin = New-Thickness 16, 10, 16, 14
    [void]$ds.Body.Children.Add($kill)
    [void]$L.Body.Children.Add($ds.Root)

    # Портативная версия
    $ps = New-Section -Title 'Портативная версия для флешки'
    $pt = 'Соберёт папку PotatoPC с файлом «Запустить PotatoPC.cmd». Запускается без интернета - для ПК, где сеть не работает и её надо починить. Журнал и история хранятся на флешке, а не на чужом компьютере.'
    [void]$ps.Body.Children.Add((New-Text -Text $pt -Size 13 -Wrap -Margin (16, 0, 16, 6)))
    [void]$ps.Body.Children.Add((New-Text -Text 'Без интернета работает: твики и откаты, очистка, автозагрузка, починка Windows, пользователи, реестр, защита. Не работает: установка программ, драйверы, тест скорости.' -Size 12 -Color 'Muted' -Wrap -Margin (16, 0, 16, 10)))
    $mkp = New-Button -Text 'Создать на флешке…' -Icon 'save' -Kind Small -OnClick { New-PortableCopy }
    $mkp.HorizontalAlignment = 'Left'; $mkp.Margin = New-Thickness 16, 0, 16, 14
    [void]$ps.Body.Children.Add($mkp)
    [void]$L.Body.Children.Add($ps.Root)
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
    Update-PotatoDataSizes
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

# --- Данные PotatoPC: папки, временные файлы, полное удаление ---

function Get-FolderBytes {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return 0 }
    $i = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($i -and -not $i.PSIsContainer) { return [double]$i.Length }
    $sum = 0.0
    foreach ($f in @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue)) { $sum += $f.Length }
    return $sum
}

function Test-ContainsAppRoot {
    # Папка - это папка программы или содержит её (её нельзя удалять, пока программа открыта).
    param([string]$Path)
    $a = ([string]$AppRoot).TrimEnd('\'); $p = $Path.TrimEnd('\')
    return ($a.Equals($p, [System.StringComparison]::OrdinalIgnoreCase) -or $a.StartsWith($p + '\', [System.StringComparison]::OrdinalIgnoreCase))
}

function Get-PotatoTempItems {
    # %TEMP%\PotatoPC и копии, которые оставляет каждый запуск по ссылке (PotatoPC-run-*).
    # Папку текущего запуска без -IncludeCurrent не возвращаем - она занята.
    param([switch]$IncludeCurrent)
    $out = @()
    if (Test-Path -LiteralPath $WorkFolder) { $out += $WorkFolder }
    foreach ($d in @(Get-ChildItem -LiteralPath $env:TEMP -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'PotatoPC-run-*' -or $_.Name -like 'PotatoPC-link-*' -or $_.Name -like 'PotatoPC-cache-*' })) {
        if (-not $IncludeCurrent -and (Test-ContainsAppRoot $d.FullName)) { continue }
        $out += $d.FullName
    }
    return , $out
}

function Update-PotatoDataSizes {
    $ui = $script:SvUi
    if (-not $ui -or -not $ui.DataSub) { return }
    Start-BgTask -Name 'Размер данных PotatoPC' -Silent -Script {
        $tmp = Get-PotatoTempItems
        $tb = 0.0; foreach ($t in $tmp) { $tb += Get-FolderBytes $t }
        $data = Get-FolderBytes $DataRoot
        if (-not $PortableMode) { $data -= Get-FolderBytes $BackupFolder }
        return @{ data = $data; backups = (Get-FolderBytes $BackupFolder); temp = $tb; runs = @($tmp | Where-Object { $_ -ne $WorkFolder }).Count; app = (Get-FolderBytes $AppRoot) }
    } -OnDone {
        param($Result, $Err)
        $ui = $script:SvUi
        if (-not $Result -or -not $ui) { return }
        $sz = { param($b) if ($b -gt 0) { Format-Size $b } else { 'пусто' } }
        $ui.DataSub['data'].Text = $DataRoot + ' · ' + (& $sz $Result.data)
        $ui.DataSub['backups'].Text = $BackupFolder + ' · ' + (& $sz $Result.backups)
        $ui.DataSub['temp'].Text = $WorkFolder + $(if ($Result.runs) { ' и старые копии запуска по ссылке: ' + $Result.runs } else { '' }) + ' · ' + (& $sz $Result.temp)
        $ui.DataSub['app'].Text = $AppRoot + ' · ' + (& $sz $Result.app)
    } | Out-Null
}

function Clear-PotatoTemp {
    Start-BgTask -Name 'Временные файлы PotatoPC' -Script {
        $n = 0; $busy = 0
        foreach ($t in (Get-PotatoTempItems)) {
            if ($t -eq $WorkFolder) {
                foreach ($c in @(Get-ChildItem -LiteralPath $t -Force -ErrorAction SilentlyContinue)) { try { Remove-Item -LiteralPath $c.FullName -Recurse -Force -ErrorAction Stop; $n++ } catch { $busy++ } }
            } else {
                try { Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction Stop; $n++ } catch { $busy++ }
            }
        }
        Write-Log ('Временные файлы PotatoPC: удалено ' + $n + $(if ($busy) { ', занято и пропущено: ' + $busy } else { '' })) 'ok'
    } -OnDone { Update-PotatoDataSizes } | Out-Null
}

function Remove-PotatoTraces {
    $pd = Join-Path $env:ProgramData 'PotatoPC'
    $ps = Get-ProfileState
    $keepProf = (@($ps.Moves).Count -gt 0) -or (Test-Path -LiteralPath (Get-ProfileMoveFolder))
    $tmpRoot = $env:TEMP.TrimEnd('\') + '\'
    $inTemp = ([string]$AppRoot).StartsWith($tmpRoot, [System.StringComparison]::OrdinalIgnoreCase)
    $msg = "Удалить с этого компьютера всё, что оставил PotatoPC:`n  • журнал, историю, отчёты и настройки`n  • кэш и временные файлы, старые копии запуска по ссылке`n  • задачу автообслуживания"
    if ($inTemp) { $msg += "`n  • саму программу (" + $AppRoot + ') - после её закрытия' }
    if ($PortableMode) { $msg += "`n`nДанные на флешке (" + $DataRoot + ') не трогаются.' }
    $msg += "`n`nПрименённые твики и установленные программы останутся как есть."
    if ($keepProf) { $msg += "`n`nЗаписи о переносе профилей на другой диск (profiles.json) сохранятся: без них перенос и возврат файлов после переустановки Windows не сработают." }
    if (-not (Show-Confirm -Message $msg -Title 'Уничтожить следы' -Warning)) { return }
    $withBackups = Show-Confirm -Message ("Удалить и резервные копии твиков (" + $BackupFolder + ")?`n`nБез них откат некоторых твиков (файл подкачки, UAC, гость, PUA) вернёт заводские настройки, а не ваши прежние.") -Title 'Резервные копии' -Warning
    Start-BgTask -Name 'Удаление следов' -Vars @{ Wb = $withBackups; KeepProf = $keepProf; Pd = $pd } -Script {
        Unregister-Maintenance
        $targets = @(Get-PotatoTempItems -IncludeCurrent)
        $targets += (Join-Path $env:LOCALAPPDATA 'PotatoPC')
        if ($PortableMode) { $targets += $BackupFolder }
        foreach ($c in @(Get-ChildItem -LiteralPath $Pd -Force -ErrorAction SilentlyContinue)) {
            if ($KeepProf -and ($c.Name -eq 'profiles.json' -or $c.Name -eq 'profile-move')) { continue }
            $targets += $c.FullName
        }
        if (-not $Wb) { $targets = @($targets | Where-Object { $_ -ne $BackupFolder }) }
        $later = @()
        foreach ($t in $targets) {
            if (-not $t -or -not (Test-Path -LiteralPath $t)) { continue }
            if (Test-ContainsAppRoot $t) { $later += $t; continue }
            try { Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction Stop; Write-Log ('Удалено: ' + $t) } catch { $later += $t }
        }
        # Журнал и настройки окна пишутся до самого закрытия, папка программы занята -
        # их удаляет отдельный скрытый процесс, когда PotatoPC закроется.
        if (-not $PortableMode) { $later += @($LogFolder, $HistoryPath, $SettingsPath, $UIStatePath) }
        $later = @($later | Where-Object { $_ } | Select-Object -Unique)
        $q = { param($s) "'" + ($s -replace "'", "''") + "'" }
        $list = ($later | ForEach-Object { & $q $_ }) -join ','
        $cmd = 'Wait-Process -Id ' + $PID + ' -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2; ' +
               'foreach ($p in @(' + $list + ')) { for ($i = 0; $i -lt 5 -and (Test-Path -LiteralPath $p); $i++) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue; if (Test-Path -LiteralPath $p) { Start-Sleep -Seconds 2 } } }; ' +
               '$r = ' + (& $q $Pd) + '; if ((Test-Path -LiteralPath $r) -and -not (Get-ChildItem -LiteralPath $r -Force -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $r -Force -ErrorAction SilentlyContinue }'
        $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmd))
        Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand ' + $enc) -WindowStyle Hidden
        Write-Log ('Следы PotatoPC удалены. После закрытия программы удалится остальное: ' + $later.Count + ' шт.') 'ok'
        return $true
    } -OnDone {
        param($Result, $Err)
        if ($Result -and (Show-Confirm -Message 'Почти всё удалено. Журнал этого запуска и папка программы удалятся, когда PotatoPC закроется. Закрыть сейчас?' -Title 'Уничтожить следы')) { $script:Window.Close() }
    } | Out-Null
}

# --- Портативная версия для флешки ---

function Export-PortableCopy {
    # Копирует программу в $Dest (файлы из SHA256SUMS + все скрипты, включая плагины
    # пользователя), включает портативный режим и кладёт файл запуска.
    # Папка data на флешке (журнал, история) при обновлении сохраняется.
    param([Parameter(Mandatory)][string]$Dest)
    $src = ([string]$AppRoot).TrimEnd('\')
    $rel = @()
    $man = Join-Path $src 'SHA256SUMS'
    if (Test-Path -LiteralPath $man) {
        $rel += 'SHA256SUMS'
        foreach ($line in [System.IO.File]::ReadAllLines($man)) { if ($line -match '^[0-9A-Fa-f]{64}  (.+)$') { $rel += $Matches[1].Replace('/', '\') } }
    } else {
        foreach ($f in @('menu.ps1', 'apps.json', 'LICENSE', 'README.md')) { $rel += $f }
        foreach ($d in @('core', 'pages', 'assets', 'cleaner')) { foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $src $d) -Recurse -File -Force -ErrorAction SilentlyContinue)) { $rel += $f.FullName.Substring($src.Length + 1) } }
    }
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $src 'scripts') -Recurse -File -Force -ErrorAction SilentlyContinue)) { $rel += $f.FullName.Substring($src.Length + 1) }
    $rel = @($rel | Select-Object -Unique)

    if (-not (Test-Path -LiteralPath $Dest)) { New-Item -ItemType Directory -Path $Dest -Force -ErrorAction Stop | Out-Null }
    # Старая копия программы убирается целиком, чтобы не осталось файлов, удалённых в новой версии.
    foreach ($d in @('core', 'pages', 'scripts', 'assets', 'cleaner', 'docs')) {
        $p = Join-Path $Dest $d
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop }
    }
    $n = 0; $miss = @()
    foreach ($r in $rel) {
        $from = Join-Path $src $r
        if (-not (Test-Path -LiteralPath $from)) { $miss += $r; continue }
        $to = Join-Path $Dest $r
        $dir = Split-Path $to -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
        Copy-Item -LiteralPath $from -Destination $to -Force -ErrorAction Stop
        try { Unblock-File -LiteralPath $to -ErrorAction SilentlyContinue } catch {}
        $n++
        if (Test-JobCancel) { return $null }
    }
    if ($miss.Count) { Write-Log ('Нет в папке программы, пропущено: ' + (($miss | Select-Object -First 5) -join ', ')) 'warn' }
    [System.IO.File]::WriteAllText((Join-Path $Dest 'portable.txt'), "Этот файл включает портативный режим PotatoPC: журнал, история и отчёты хранятся в папке data рядом с программой.`r`n", (New-Object System.Text.UTF8Encoding($true)))
    $cmd = "@echo off`r`n" +
           "rem PotatoPC portable: runs offline, data is kept in the data folder next to this file.`r`n" +
           "start `"`" `"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`" -STA -NoProfile -ExecutionPolicy Bypass -File `"%~dp0menu.ps1`"`r`n"
    [System.IO.File]::WriteAllText((Join-Path $Dest 'Запустить PotatoPC.cmd'), $cmd, (New-Object System.Text.ASCIIEncoding))
    Write-Log ('Портативная версия собрана: ' + $Dest + ' (файлов: ' + $n + ')') 'ok'
    Add-History -Kind 'service' -Name ('Портативная версия: ' + $Dest)
    return $Dest
}

function New-PortableCopy {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Куда сохранить портативный PotatoPC? Выберите флешку или папку - внутри появится папка PotatoPC.'
    $dlg.ShowNewFolderButton = $true
    try { $removable = @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Removable' -and $_.IsReady }); if ($removable.Count) { $dlg.SelectedPath = $removable[0].RootDirectory.FullName } } catch {}
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK -or -not $dlg.SelectedPath) { return }
    $base = $dlg.SelectedPath
    $dest = if ((Split-Path $base -Leaf) -eq 'PotatoPC' -and (Test-Path -LiteralPath (Join-Path $base 'menu.ps1'))) { $base } else { Join-Path $base 'PotatoPC' }
    $a = ([string]$AppRoot).TrimEnd('\'); $d = $dest.TrimEnd('\')
    if ($a.Equals($d, [System.StringComparison]::OrdinalIgnoreCase) -or $d.StartsWith($a + '\', [System.StringComparison]::OrdinalIgnoreCase) -or $a.StartsWith($d + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        Show-Info 'Это папка, из которой сейчас запущен PotatoPC. Выберите другое место.' -Icon 'Warning'; return
    }
    if (Test-Path -LiteralPath $dest) {
        if (Test-Path -LiteralPath (Join-Path $dest 'menu.ps1')) {
            if (-not (Show-Confirm -Message ('В ' + $dest + " уже есть PotatoPC. Обновить его до этой версии?`n`nЖурнал и история на флешке (папка data) сохранятся."))) { return }
        } elseif (@(Get-ChildItem -LiteralPath $dest -Force -ErrorAction SilentlyContinue).Count) {
            if (-not (Show-Confirm -Message ('Папка ' + $dest + ' уже есть и в ней что-то лежит. Положить PotatoPC туда?') -Warning)) { return }
        }
    }
    try {
        $drv = New-Object System.IO.DriveInfo ([System.IO.Path]::GetPathRoot($dest))
        if ($drv.IsReady -and $drv.AvailableFreeSpace -lt 20MB) { Show-Info ('На ' + $drv.Name + ' меньше 20 МБ свободного места.') -Icon 'Warning'; return }
    } catch {}
    Start-BgTask -Name 'Портативная версия' -Vars @{ Dest = $dest } -Script { Export-PortableCopy -Dest $Dest } -OnDone {
        param($Result, $Err)
        if ($Err) { Show-Info ('Не получилось собрать портативную версию: ' + $Err) -Icon 'Warning'; return }
        if ($Result -and (Show-Confirm -Message ("Готово: " + $Result + "`n`nНа другом ПК откройте эту папку и запустите «Запустить PotatoPC.cmd». Интернет не нужен.`n`nОткрыть папку?"))) { Open-Path $Result }
    } | Out-Null
}
