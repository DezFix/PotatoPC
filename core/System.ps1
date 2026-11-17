# PotatoPC v7 - сведения о системе, проверки, оценка, замеры «до/после».
# Все функции здесь рассчитаны на фоновый поток (CIM/реестр/диск).

function Get-SystemDriveInfo {
    $r = @{ Letter = ($env:SystemDrive).TrimEnd(':'); Total = 0.0; Free = 0.0; Media = 'Неизвестно'; Bus = ''; Model = '' }
    try {
        $ld = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $env:SystemDrive + "'") -ErrorAction Stop
        $r.Total = [double]$ld.Size; $r.Free = [double]$ld.FreeSpace
    } catch {}
    try {
        $part = Get-Partition -DriveLetter $r.Letter -ErrorAction Stop | Select-Object -First 1
        $pd = Get-PhysicalDisk -ErrorAction Stop | Where-Object { [string]$_.DeviceId -eq [string]$part.DiskNumber } | Select-Object -First 1
        if ($pd) {
            $r.Model = [string]$pd.FriendlyName
            $r.Bus = [string]$pd.BusType
            $m = [string]$pd.MediaType
            $r.Media = switch ($m) { 'SSD' { 'SSD' } 'HDD' { 'HDD' } default { if ($r.Bus -eq 'NVMe') { 'SSD' } else { 'Неизвестно' } } }
            if ($r.Bus -eq 'NVMe') { $r.Media = 'SSD NVMe' }
        }
    } catch {}
    return $r
}

function Get-SystemSummary {
    $s = @{
        Cpu = ''; Cores = 0; Threads = 0; CpuLoad = 0; RamTotal = 0.0; RamFree = 0.0
        Uptime = 0.0; Manufacturer = ''; Model = ''; Serial = ''; Os = $WinInfo.Name; Build = $WinInfo.Build
        Gpus = @(); HasBattery = $false; Disk = (Get-SystemDriveInfo); IsLaptop = $false
    }
    try {
        $cpu = @(Get-CimInstance Win32_Processor -ErrorAction Stop)
        $s.Cpu = (([string]$cpu[0].Name) -replace '\(R\)|\(TM\)|\(tm\)', '' -replace '\s+CPU\s+@.*$', '' -replace '\s+', ' ').Trim()
        $s.Cores = [int](($cpu | Measure-Object NumberOfCores -Sum).Sum)
        $s.Threads = [int](($cpu | Measure-Object NumberOfLogicalProcessors -Sum).Sum)
        $s.CpuLoad = [int](($cpu | Measure-Object LoadPercentage -Average).Average)
    } catch {}
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $s.RamTotal = [double]$os.TotalVisibleMemorySize * 1KB
        $s.RamFree = [double]$os.FreePhysicalMemory * 1KB
        $s.Uptime = ((Get-Date) - $os.LastBootUpTime).TotalSeconds
    } catch {}
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $s.Manufacturer = ([string]$cs.Manufacturer).Trim()
        $s.Model = ([string]$cs.Model).Trim()
        if ($cs.TotalPhysicalMemory) { $s.RamTotal = [double]$cs.TotalPhysicalMemory }
        $s.IsLaptop = ([int]$cs.PCSystemType -eq 2)
    } catch {}
    try { $s.Serial = ([string](Get-CimInstance Win32_BIOS -ErrorAction Stop).SerialNumber).Trim() } catch {}
    try {
        $s.Gpus = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.Name -notmatch '(?i)basic display|remote|virtual|mirage|parsec' } | ForEach-Object {
            @{ Name = [string]$_.Name; Driver = [string]$_.DriverVersion; Date = $(try { [datetime]$_.DriverDate } catch { $null })
               Discrete = ([string]$_.Name -match '(?i)nvidia|geforce|quadro|radeon\s*(rx|pro|r[5-9]|hd\s*[5-9]\d{3})|arc\s*a\d') -and ([string]$_.Name -notmatch '(?i)radeon\(tm\)\s*graphics$|vega\s*\d+\s*graphics') }
        })
    } catch {}
    try { $s.HasBattery = @(Get-CimInstance Win32_Battery -ErrorAction Stop).Count -gt 0 } catch {}
    if ($s.HasBattery) { $s.IsLaptop = $true }
    return $s
}

function Get-BootTimeSec {
    # Время последней загрузки из журнала Diagnostics-Performance (событие 100).
    try {
        $e = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } -MaxEvents 1 -ErrorAction Stop
        $x = [xml]$e.ToXml()
        $bt = ($x.Event.EventData.Data | Where-Object { $_.Name -eq 'BootTime' }).'#text'
        if ($bt) { return [Math]::Round([double]$bt / 1000, 1) }
    } catch {}
    return -1
}

# --- Автозагрузка (используется Главной, страницей «Автозагрузка» и отчётом) ---

function Get-StartupLists {
    # Списки внутри функции: фоновые потоки получают только функции, не переменные.
    return @{
        Heavy = @('steam','discord','onedrive','teams','skype','zoom','epicgames','spotify','adobe creative','creative cloud','ccxprocess','acrotray','origin','eadesktop','battle.net','ubisoft','goggalaxy','dropbox','yandex.disk','yandexdisk','utorrent','bittorrent','opera','browser_assistant','razer synapse','icloud','lghub','overwolf','wallpaper')
        Recommend = @('steam','discord','onedrive','teams','skype','zoom','epicgames','spotify','ccxprocess','adobe gc','adobe arm','acrotray','origin','eadesktop','battle.net','ubisoft','goggalaxy','utorrent','bittorrent','browser_assistant','opera browser assistant','java update','jusched','itunes helper','ituneshelper','quicktime','cortana','microsoft edge update','edgeupdate','yandex','mail.ru','amigo','cisco webex','anydesk','teamviewer','ccleaner','avast secure browser','wallpaper','overwolf','icloud','dropbox','viber','telegram','whatsapp')
        Never = @('securityhealth','windows defender','windowsdefender','realtek','rthdvcpl','rtkngui','nvidia','nvcontainer','amd','radeon','igfx','intel','synaptics','elan','etd','alps','touchpad','bluetooth','audio','sound','hd audio','waves','dolby','nahimic','asus','lenovo','vantage','hp ','hpq','dell','acer','msi','logitech','kaspersky','eset','avast','avg','norton','mcafee','bitdefender','drweb','dr.web','avira','malwarebytes','sophos','360','comodo','ctfmon','onscreenkeyboard','keyboard','punto','lang')
    }
}

function Resolve-StartupTarget {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return $null }
    $cmd = [Environment]::ExpandEnvironmentVariables($Command.Trim())
    $path = $null
    if ($cmd.StartsWith('"')) {
        $end = $cmd.IndexOf('"', 1)
        if ($end -gt 1) { $path = $cmd.Substring(1, $end - 1) }
    } else {
        $m = [regex]::Match($cmd, '^(.+?\.(exe|com|bat|cmd|lnk))(\s|$)', 'IgnoreCase')
        $path = if ($m.Success) { $m.Groups[1].Value } else { ($cmd -split '\s+')[0] }
    }
    if (-not $path) { return $null }
    if ([System.IO.File]::Exists($path)) { return $path }
    if (-not $path.Contains('\')) {
        foreach ($d in @("$env:WINDIR\System32", $env:WINDIR)) { $c = Join-Path $d $path; if ([System.IO.File]::Exists($c)) { return $c } }
    }
    return $null
}

function Get-StartupApprovedEnabled {
    param([Microsoft.Win32.RegistryKey]$Root, [string]$Sub, [string]$Name)
    try {
        $k = $Root.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\' + $Sub)
        if ($null -eq $k) { return $true }
        try {
            $d = $k.GetValue($Name)
            if ($d -is [byte[]] -and $d.Length -ge 1) { return -not (($d[0] -band 1) -eq 1) }
        } finally { $k.Dispose() }
    } catch {}
    return $true
}

function Get-StartupItems {
    # Возвращает список элементов автозагрузки. -WithIcons: PNG-байты значков.
    param([switch]$WithIcons, [switch]$IncludeServices)
    $items = New-Object System.Collections.ArrayList
    $hkcu = [Microsoft.Win32.Registry]::CurrentUser
    $hklm = [Microsoft.Win32.Registry]::LocalMachine
    $sources = @(
        @{ Root = $hkcu; Hive = 'HKCU'; Key = 'Software\Microsoft\Windows\CurrentVersion\Run'; Approved = 'Run'; Label = 'Реестр (пользователь)' },
        @{ Root = $hklm; Hive = 'HKLM'; Key = 'Software\Microsoft\Windows\CurrentVersion\Run'; Approved = 'Run'; Label = 'Реестр (все пользователи)' },
        @{ Root = $hklm; Hive = 'HKLM'; Key = 'Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = 'Run32'; Label = 'Реестр (все, 32-бит)' }
    )
    foreach ($src in $sources) {
        $k = $null
        try {
            $k = $src.Root.OpenSubKey($src.Key)
            if ($null -eq $k) { continue }
            foreach ($n in $k.GetValueNames()) {
                if ([string]::IsNullOrEmpty($n)) { continue }
                $cmd = [string]$k.GetValue($n)
                [void]$items.Add(@{
                    Kind = 'reg'; Name = $n; Command = $cmd; Source = $src.Label; Hive = $src.Hive; Key = $src.Key; Approved = $src.Approved
                    Enabled = (Get-StartupApprovedEnabled -Root $src.Root -Sub $src.Approved -Name $n)
                })
            }
        } catch {} finally { if ($k) { $k.Dispose() } }
    }
    foreach ($f in @(@{ Dir = [Environment]::GetFolderPath('Startup'); Root = $hkcu; Label = 'Папка «Автозагрузка»' },
                     @{ Dir = [Environment]::GetFolderPath('CommonStartup'); Root = $hklm; Label = 'Папка «Автозагрузка» (все)' })) {
        if (-not $f.Dir -or -not (Test-Path -LiteralPath $f.Dir)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $f.Dir -File -Force -ErrorAction SilentlyContinue)) {
            if ($file.Name -ieq 'desktop.ini') { continue }
            $disabledByName = $file.Name.EndsWith('.disabled', [StringComparison]::OrdinalIgnoreCase)
            $orig = if ($disabledByName) { $file.Name.Substring(0, $file.Name.Length - 9) } else { $file.Name }
            $target = $file.FullName
            if ($orig -like '*.lnk') {
                try { $sh = New-Object -ComObject WScript.Shell; $t = $sh.CreateShortcut($file.FullName).TargetPath; if ($t) { $target = $t } } catch {}
            }
            [void]$items.Add(@{
                Kind = 'folder'; Name = [System.IO.Path]::GetFileNameWithoutExtension($orig); Command = $target; File = $file.FullName
                FileName = $orig; Source = $f.Label; Hive = $(if ($f.Root -eq $hklm) { 'HKLM' } else { 'HKCU' })
                Enabled = (-not $disabledByName) -and (Get-StartupApprovedEnabled -Root $f.Root -Sub 'StartupFolder' -Name $orig)
            })
        }
    }
    try {
        foreach ($t in @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notlike '\Microsoft\*' })) {
            $trig = @($t.Triggers | ForEach-Object { $_.CimClass.CimClassName })
            if (-not ($trig -match 'Logon|Boot')) { continue }
            $exe = ''
            try { $exe = [string]@($t.Actions)[0].Execute } catch {}
            [void]$items.Add(@{
                Kind = 'task'; Name = $t.TaskName; Command = $exe; TaskPath = $t.TaskPath; Source = 'Планировщик задач'
                Enabled = ($t.State -ne 'Disabled')
            })
        }
    } catch {}
    if ($IncludeServices) {
        try {
            foreach ($svc in @(Get-CimInstance Win32_Service -Filter "StartMode='Auto'" -ErrorAction Stop)) {
                $p = [string]$svc.PathName
                if ($p -match '(?i)\\windows\\(system32|syswow64)\\' -or $p -match '(?i)\\windows\\') { continue }
                if ($p -match '(?i)\\Microsoft\\|Windows Defender|\\Program Files\\Windows ') { continue }
                [void]$items.Add(@{ Kind = 'service'; Name = [string]$svc.DisplayName; ServiceName = [string]$svc.Name; Command = $p; Source = 'Служба'; Enabled = $true })
            }
        } catch {}
    }
    $L = Get-StartupLists
    foreach ($it in $items) {
        $path = Resolve-StartupTarget -Command $it.Command
        $it.Target = $path
        $pub = ''
        if ($path) { try { $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path); $pub = [string]$vi.CompanyName; if ($vi.FileDescription -and $it.Kind -eq 'reg' -and $it.Name -match '^[\{\w-]{20,}') { $it.Name = [string]$vi.FileDescription } } catch {} }
        $it.Publisher = $pub
        $hay = (($it.Name + ' ' + $it.Command + ' ' + $pub).ToLowerInvariant())
        $never = $false; foreach ($w in $L.Never) { if ($hay.Contains($w)) { $never = $true; break } }
        $rec = $false; if (-not $never) { foreach ($w in $L.Recommend) { if ($hay.Contains($w)) { $rec = $true; break } } }
        $heavy = $false; foreach ($w in $L.Heavy) { if ($hay.Contains($w)) { $heavy = $true; break } }
        $impact = 1
        if ($heavy) { $impact = 3 } elseif ($it.Kind -eq 'reg' -or $it.Kind -eq 'folder') {
            $size = 0; try { if ($path) { $size = (Get-Item -LiteralPath $path -ErrorAction Stop).Length } } catch {}
            $impact = if ($size -gt 20MB) { 2 } else { 1 }
        } elseif ($it.Kind -eq 'service') { $impact = 2 }
        $it.Never = $never; $it.Recommend = $rec; $it.Impact = $impact
        $it.Id = ($it.Kind + '|' + $it.Hive + '|' + $it.Key + '|' + $it.TaskPath + '|' + $it.Name + '|' + $it.File + '|' + $it.ServiceName)
        $it.Icon = $null
        if ($WithIcons -and $path) {
            try {
                Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
                $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
                if ($ico) {
                    $bmp = $ico.ToBitmap(); $ms = New-Object System.IO.MemoryStream
                    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
                    $it.Icon = $ms.ToArray(); $ms.Dispose(); $bmp.Dispose(); $ico.Dispose()
                }
            } catch {}
        }
    }
    return @($items)
}

function Set-StartupItemEnabled {
    # Включает/выключает элемент автозагрузки так же, как это делает Диспетчер задач.
    param($Item, [bool]$Enable)
    switch ($Item.Kind) {
        'reg' {
            $root = if ($Item.Hive -eq 'HKCU') { [Microsoft.Win32.Registry]::CurrentUser } else { [Microsoft.Win32.Registry]::LocalMachine }
            $sub = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\' + $Item.Approved
            $k = $root.CreateSubKey($sub)
            try {
                $data = [byte[]](0x02,0,0,0,0,0,0,0,0,0,0,0)
                if (-not $Enable) { $data[0] = 0x03; $ft = [BitConverter]::GetBytes((Get-Date).ToFileTime()); [Array]::Copy($ft, 0, $data, 4, 8) }
                $k.SetValue($Item.Name, $data, [Microsoft.Win32.RegistryValueKind]::Binary)
            } finally { $k.Dispose() }
        }
        'folder' {
            $root = if ($Item.Hive -eq 'HKCU') { [Microsoft.Win32.Registry]::CurrentUser } else { [Microsoft.Win32.Registry]::LocalMachine }
            # Возвращаем старый способ (.disabled), если элемент был так выключен.
            if ($Enable -and $Item.File -like '*.disabled') {
                Rename-Item -LiteralPath $Item.File -NewName $Item.FileName -Force -ErrorAction Stop
            }
            $k = $root.CreateSubKey('Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder')
            try {
                $data = [byte[]](0x02,0,0,0,0,0,0,0,0,0,0,0)
                if (-not $Enable) { $data[0] = 0x03; $ft = [BitConverter]::GetBytes((Get-Date).ToFileTime()); [Array]::Copy($ft, 0, $data, 4, 8) }
                $k.SetValue($Item.FileName, $data, [Microsoft.Win32.RegistryValueKind]::Binary)
            } finally { $k.Dispose() }
        }
        'task' {
            if ($Enable) { Enable-ScheduledTask -TaskName $Item.Name -TaskPath $Item.TaskPath -ErrorAction Stop | Out-Null }
            else { Disable-ScheduledTask -TaskName $Item.Name -TaskPath $Item.TaskPath -ErrorAction Stop | Out-Null }
        }
        'service' {
            # Службы не выключаем совсем: «Вручную» - запустятся, когда понадобятся.
            $mode = if ($Enable) { 'Automatic' } else { 'Manual' }
            Set-Service -Name $Item.ServiceName -StartupType $mode -ErrorAction Stop
        }
    }
    Add-History -Kind 'startup' -Name ($(if ($Enable) { 'Включено в автозагрузке: ' } else { 'Выключено из автозагрузки: ' }) + $Item.Name)
}

# --- Проверки и оценка ---

function Get-QuickJunkBytes {
    # Быстрая оценка мусора: Temp, кэш обновлений, отчёты об ошибках. Не дольше ~6 с.
    $sum = 0L
    $deadline = (Get-Date).AddSeconds(6)
    foreach ($d in @($env:TEMP, (Join-Path $env:WINDIR 'Temp'), (Join-Path $env:WINDIR 'SoftwareDistribution\Download'), (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER'), (Join-Path $env:ProgramData 'Microsoft\Windows\WER'), (Join-Path $env:LOCALAPPDATA 'CrashDumps'))) {
        if (-not $d -or -not [System.IO.Directory]::Exists($d)) { continue }
        try {
            $stack = New-Object System.Collections.Stack; $stack.Push($d)
            while ($stack.Count -gt 0 -and (Get-Date) -lt $deadline) {
                $di = New-Object System.IO.DirectoryInfo -ArgumentList ([string]$stack.Pop())
                try {
                    foreach ($e in $di.EnumerateFileSystemInfos()) {
                        if (($e.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                        if ($e -is [System.IO.DirectoryInfo]) { $stack.Push($e.FullName) } else { $sum += $e.Length }
                    }
                } catch {}
            }
        } catch {}
    }
    return $sum
}

function Get-HealthChecks {
    param($Summary, $StartupItems = $null)
    $c = New-Object System.Collections.ArrayList
    function Add-Check($Area, $Level, $Title, $Detail, $Fix, $Weight = 10) {
        [void]$c.Add(@{ Area = $Area; Level = $Level; Title = $Title; Detail = $Detail; Fix = $Fix; Weight = $Weight })
    }
    # Безопасность
    try {
        $off = @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { -not $_.Enabled })
        if ($off.Count -eq 0) { Add-Check 'security' 'ok' 'Брандмауэр включён' 'Все сети' '' 25 }
        else { Add-Check 'security' 'bad' 'Брандмауэр выключен' (($off | ForEach-Object { $_.Name }) -join ', ') 'protect' 25 }
    } catch {}
    $av = Get-AntivirusState
    if ($av.Ok) { Add-Check 'security' 'ok' ($av.Title) ($av.Detail) '' 30 }
    else { Add-Check 'security' 'bad' ($av.Title) ($av.Detail) 'protect' 30 }
    try {
        $lua = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -ErrorAction Stop).EnableLUA
        if ([int]$lua -ne 1) { Add-Check 'security' 'bad' 'Контроль учётных записей (UAC) выключен' 'Любая программа получает права администратора молча' 'tweaks:08' 20 }
    } catch {}
    if (-not (Test-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun' 255)) {
        Add-Check 'security' 'warn' 'Автозапуск с флешек включён' 'Так распространяются вирусы с USB' 'tweaks:08' 10
    }
    try {
        if ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction Stop).fDenyTSConnections -eq 0) {
            Add-Check 'security' 'warn' 'Удалённый рабочий стол открыт' 'Если вы им не пользуетесь - закройте' 'protect' 10
        }
    } catch {}
    # Приватность
    $tel = $null
    try { $tel = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name AllowTelemetry -ErrorAction Stop).AllowTelemetry } catch {}
    if ($null -eq $tel -or $tel -ge 2) { Add-Check 'privacy' 'warn' 'Телеметрия на полном уровне' 'Твик «Диагностические данные на минимум»' 'tweaks:03' 40 }
    else { Add-Check 'privacy' 'ok' 'Телеметрия на минимуме' '' '' 40 }
    if (-not (Test-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0)) {
        Add-Check 'privacy' 'warn' 'Реклама и «рекомендации» Windows включены' 'Твик «Без рекламы Windows»' 'tweaks:01' 30
    }
    if (-not (Test-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0)) {
        Add-Check 'privacy' 'warn' 'История действий собирается' 'Твик «Выкл. историю действий»' 'tweaks:03' 30
    }
    # Скорость
    if ($null -eq $StartupItems) { $StartupItems = Get-StartupItems }
    $en = @($StartupItems | Where-Object { $_.Enabled })
    $recEn = @($en | Where-Object { $_.Recommend })
    if ($recEn.Count -ge 3 -or $en.Count -gt 15) { Add-Check 'speed' 'warn' ($en.Count.ToString() + ' программ в автозагрузке') ('Лишних: ' + $recEn.Count + '. Отключите - вход станет быстрее') 'startup' 35 }
    else { Add-Check 'speed' 'ok' ('Автозагрузка в порядке (' + $en.Count + ')') '' '' 35 }
    if ($Summary.RamTotal -gt 0) {
        $used = 1 - ($Summary.RamFree / $Summary.RamTotal)
        if ($used -gt 0.85) { Add-Check 'speed' 'bad' ('Память занята на ' + [int]($used * 100) + '%') 'Закройте лишние программы или отключите фоновые' 'startup' 25 }
    }
    if (-not (Test-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2) -and ($Summary.RamTotal -le 8GB -or $Summary.Disk.Media -eq 'HDD')) {
        Add-Check 'speed' 'warn' 'Включены визуальные эффекты' 'На слабом ПК их лучше выключить' 'tweaks:01' 20
    }
    if ($Summary.Uptime -gt 5 * 86400) { Add-Check 'speed' 'warn' ('Без перезагрузки ' + (Format-Duration $Summary.Uptime)) 'Перезагрузка освободит память' '' 10 }
    if (Test-PendingReboot) { Add-Check 'speed' 'warn' 'Ожидается перезагрузка' 'Windows ждёт перезагрузки, чтобы закончить обновление' '' 10 }
    # Чистота
    $junk = Get-QuickJunkBytes
    $level = if ($junk -gt 3GB) { 'bad' } elseif ($junk -gt 500MB) { 'warn' } else { 'ok' }
    Add-Check 'clean' $level ('Мусор: ' + (Format-Size $junk)) 'Temp, кэш обновлений, отчёты об ошибках' $(if ($level -ne 'ok') { 'clean' } else { '' }) 50
    if ($Summary.Disk.Total -gt 0) {
        $freePct = $Summary.Disk.Free / $Summary.Disk.Total
        if ($freePct -lt 0.10) { Add-Check 'clean' 'bad' ('Мало места на ' + $env:SystemDrive + ' ' + (Format-Size $Summary.Disk.Free)) 'Меньше 10% - Windows начинает тормозить' 'clean' 50 }
        elseif ($freePct -lt 0.2) { Add-Check 'clean' 'warn' ('Свободно ' + [int]($freePct * 100) + '% на ' + $env:SystemDrive) '' 'clean' 30 }
    }
    return @($c)
}

function Get-HealthScore {
    param($Checks)
    $areas = @{}
    foreach ($a in @('speed','clean','privacy','security')) {
        $list = @($Checks | Where-Object { $_.Area -eq $a })
        if ($list.Count -eq 0) { $areas[$a] = 100; continue }
        $total = 0.0; $got = 0.0
        foreach ($x in $list) {
            $total += $x.Weight
            $got += switch ($x.Level) { 'ok' { $x.Weight } 'warn' { $x.Weight * 0.45 } default { 0 } }
        }
        # Проверки «только при проблеме» (без ok-записи) должны снижать, а не задавать оценку целиком.
        $areas[$a] = [int][Math]::Round(100 * $got / [Math]::Max(1, $total))
    }
    $areas.total = [int][Math]::Round(($areas.speed * 0.3) + ($areas.clean * 0.2) + ($areas.privacy * 0.15) + ($areas.security * 0.35))
    return $areas
}

function Get-AntivirusState {
    $r = @{ Ok = $false; Title = 'Антивирус не найден'; Detail = 'Включите Защитник Windows'; Defender = $false; Products = @() }
    try {
        $r.Products = @(Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | ForEach-Object {
            # productState: бит 0x1000 = включён, 0x10 = базы устарели.
            $st = [int]$_.productState
            @{ Name = [string]$_.displayName; On = (($st -band 0x1000) -ne 0); Outdated = (($st -band 0x10) -ne 0) }
        })
    } catch {}
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        if ($mp.AntivirusEnabled -and $mp.RealTimeProtectionEnabled) {
            $r.Defender = $true
            $age = [int]$mp.AntivirusSignatureAge
            $r.Ok = ($age -le 7)
            $r.Title = if ($r.Ok) { 'Защитник Windows активен' } else { 'Базы Защитника устарели' }
            $r.Detail = 'Базы от ' + ([datetime]$mp.AntivirusSignatureLastUpdated).ToString('dd.MM')
            return $r
        }
    } catch {}
    $on = @($r.Products | Where-Object { $_.On -and $_.Name -notmatch '(?i)defender' })
    if ($on.Count -gt 0) {
        $r.Ok = -not $on[0].Outdated
        $r.Title = $on[0].Name + $(if ($r.Ok) { ' активен' } else { ': базы устарели' })
        $r.Detail = 'Сторонний антивирус'
    } else {
        $r.Title = 'Защита в реальном времени выключена'
    }
    return $r
}

function Test-PendingReboot {
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { return $true }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { return $true }
    return $false
}

function Get-RecommendedPreset {
    param($Summary)
    if ($Summary.RamTotal -le 4.5GB -or $Summary.Disk.Media -eq 'HDD' -or $Summary.Cores -le 2) { return 'potato' }
    if (@($Summary.Gpus | Where-Object { $_.Discrete }).Count -gt 0 -and $Summary.RamTotal -ge 7.5GB) { return 'game' }
    return 'office'
}

# --- Замеры «до/после» ---

function Get-MetricSnapshot {
    param([string]$Label = 'manual', $StartupItems = $null)
    $s = [ordered]@{ Time = (Get-Date).ToString('s'); Label = $Label; BootSec = (Get-BootTimeSec); RamUsed = 0.0; RamTotal = 0.0; Processes = 0; Startup = 0; FreeSys = 0.0; Uptime = 0.0 }
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $s.RamTotal = [double]$os.TotalVisibleMemorySize * 1KB
        $s.RamUsed = ([double]$os.TotalVisibleMemorySize - [double]$os.FreePhysicalMemory) * 1KB
        $s.Uptime = ((Get-Date) - $os.LastBootUpTime).TotalSeconds
    } catch {}
    try { $s.Processes = @(Get-Process -ErrorAction Stop).Count } catch {}
    if ($null -eq $StartupItems) { $StartupItems = Get-StartupItems }
    $s.Startup = @($StartupItems | Where-Object { $_.Enabled }).Count
    try { $s.FreeSys = [double](Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $env:SystemDrive + "'") -ErrorAction Stop).FreeSpace } catch {}
    return $s
}

function Save-MetricSnapshot {
    param($Snapshot)
    try {
        $file = Join-Path $SnapshotFolder ('snap-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $Snapshot.Label + '.json')
        ($Snapshot | ConvertTo-Json -Depth 3) | Set-Content -LiteralPath $file -Encoding UTF8 -ErrorAction Stop
    } catch {}
}

function Get-BaselineSnapshot {
    # Последний замер «до оптимизации».
    try {
        $f = Get-ChildItem -LiteralPath $SnapshotFolder -Filter 'snap-*-before.json' -ErrorAction Stop | Sort-Object Name -Descending | Select-Object -First 1
        if ($f) { return (Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop) }
    } catch {}
    return $null
}
