# NAME: 09 · Чистка реестра: отключение лишней автозагрузки
# DESC: Отключает в реестре (Run/RunOnce + StartupApproved) известный мусор автозагрузки и битые записи. Значения НЕ удаляет — есть откат 09 Откат/09
# TAGS: 2
# ICON: 🔌
# PRESET: potato, office

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

# Одна задача скрипта: почистить реестр автозагрузки. Ничего не удаляем -
# StartupApproved просто помечает запись выключенной (0x03), значение в Run
# остаётся на месте, поэтому 09 Откат/09_undo_autostart.ps1 возвращает всё
# обратно по сохранённой копии.

$script:Unwanted = @(
    '^OneDrive$', 'Updater$', '-updater$', '^Update$', '^Updater\.exe$',
    '^Discord$', '^DiscordUpdate$', '^Spotify$', '^SpotifyMX$', '^Teams$',
    '^TeamsInsights$', '^Skype$', '^Zoom$', '^Slack$', '^Steam$',
    '^EpicGamesLauncher$', '^BattlEye$', '^BEService$', '^GameBar$', '^GameMenu$',
    '^GameOverlayUI$', '^GameBarPresenceWriter$', '^Xbl', '^Xbox', '^GOG', '^Itchio$',
    '^Overwolf', '^LightSail$', '^Gumdrop$', '^iHeartRadio$', '^Evernote$', '^Prynt$',
    '^Widgets$', 'Copilot$', '^YourPhone$', '^CrossDevice$', '^PhoneExperienceHost',
    '^WinStoreAgent$', '^7-Zip$', '^AUMID$', 'Adobe.*Updater', '^Razer', 'Steam Client'
)
# Стоп- список. Совпадение сюда важнее совпадения с мусором: антивирус, звук,
# видеокарта и ввод с клавиатуры нельзя гасить даже по похожему имени.
$script:NeverTouch = @(
    'WindowsDefender|SecurityHealth|WdFilter|wscsvc|MSASCui|Kaspersky|ESET|Avast|AVG',
    'Norton|McAfee|Symantec|Bitdefender|DrWeb|Panda|Avira|Sophos|Malwarebytes|CrowdStrike',
    'Sentinel|CrowdStrike|SentinelOne|Cylance|Sophos|TrendMicro|Kaspersky|Avira',
    'Realtek|NVIDIA|AMD|Intel|Qualcomm|Broadcom|Display|Audio|RTHDVCPL|Sonic|igfx',
    'Synaptics|ELAN|WeTouch|HID|Touch|GALAXY|Lenovo|ThinkPad|ASUS|ACER|MSI|HP|Logi',
    'SteelSeries|Razer|Corsair|ROG|Saitek|Xbox.*Service|OneXPlayer|GameInput|WmiPrvSE'
)

function Get-RunRoots {
    # Все места, откуда Windows запускает программы при входе.
    return @(
        @{ Hive = 'HKCU:'; Path = 'Software\Microsoft\Windows\CurrentVersion\Run';          Approved = 'Run';     Label = 'HKCU\Run' },
        @{ Hive = 'HKCU:'; Path = 'Software\Microsoft\Windows\CurrentVersion\RunOnce';      Approved = 'RunOnce'; Label = 'HKCU\RunOnce' },
        @{ Hive = 'HKLM:'; Path = 'Software\Microsoft\Windows\CurrentVersion\Run';          Approved = 'Run';     Label = 'HKLM\Run' },
        @{ Hive = 'HKLM:'; Path = 'Software\Microsoft\Windows\CurrentVersion\RunOnce';      Approved = 'RunOnce'; Label = 'HKLM\RunOnce' },
        @{ Hive = 'HKLM:'; Path = 'Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = 'Run32'; Label = 'HKLM\Run (x86)' }
    )
}

function Get-ApprovedPath {
    param([string]$Hive, [string]$Approved)
    if ($Hive -like 'HKLM:*') { return "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\$Approved" }
    return "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\$Approved"
}

function Get-ApprovedState {
    # Нет значения в StartupApproved = включено (так по умолчанию).
    param([string]$Path, [string]$Name)
    try {
        $k = Get-Item -LiteralPath $Path -ErrorAction Stop
        try {
            $data = $k.GetValue($Name)
            if ($data -is [byte[]] -and $data.Length -ge 1) { return ($data[0] -ne 0x03 -and $data[0] -ne 0x07) }
        } finally { $k.Close() }
    } catch {}
    return $true
}

function Set-ApprovedState {
    # 0x03 = выключено, 0x02 = включено. Windows читает первый байт, остальное -
    # метка времени, её пишем честно, иначе Проводник может сбросить состояние.
    param([string]$Path, [string]$Name, [bool]$Enable)
    $flag = if ($Enable) { 2 } else { 3 }
    $bytes = New-Object byte[] 12
    $bytes[0] = [byte]$flag
    [System.BitConverter]::GetBytes([int64][DateTime]::UtcNow.ToFileTimeUtc()).CopyTo($bytes, 4)
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
    $k = Get-Item -LiteralPath $Path -ErrorAction Stop
    try { $k.SetValue($Name, $bytes, [Microsoft.Win32.RegistryValueKind]::Binary) } finally { $k.Close() }
}

function Resolve-ExePath {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return '' }
    $cmd = $Command.Trim()
    if ($cmd.StartsWith('"')) {
        $end = $cmd.IndexOf('"', 1)
        $p = if ($end -gt 0) { $cmd.Substring(1, $end - 1) } else { $cmd.Trim('"') }
    } else { $p = ($cmd -split '[\\/]')[0] }
    $p = [System.Environment]::ExpandEnvironmentVariables($p)
    if ([string]::IsNullOrWhiteSpace($p)) { return '' }
    $i = $p.LastIndexOf('.exe', [System.StringComparison]::OrdinalIgnoreCase)
    if ($i -gt 0) { $p = $p.Substring(0, $i + 4) }
    if ([System.IO.File]::Exists($p)) { return $p }
    if (-not $p.Contains('\') -and -not $p.Contains('/')) {
        foreach ($dir in ($env:PATH -split [System.IO.Path]::PathSeparator)) {
            if ([string]::IsNullOrWhiteSpace($dir)) { continue }
            try {
                $full = [System.IO.Path]::Combine($dir, $p)
                if ([System.IO.File]::Exists($full)) { return $full }
            } catch {}
        }
    }
    return ''
}

function Get-Verdict {
    # Вердикт по записи: 'never' / 'broken' / 'junk' / 'keep'.
    param([string]$Name, [string]$Command)
    foreach ($pat in $script:NeverTouch) { if ($Name -match $pat) { return 'never' } }
    $exe = Resolve-ExePath -Command $Command
    if ([string]::IsNullOrWhiteSpace($exe)) { return 'broken' }
    foreach ($pat in $script:Unwanted) { if ($Name -match $pat) { return 'junk' } }
    return 'keep'
}

function Get-StartupFolderItems {
    $out = @()
    foreach ($f in @(
        [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Startup),
        [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonStartup))) {
        if ([string]::IsNullOrWhiteSpace($f) -or -not (Test-Path -LiteralPath $f)) { continue }
        $items = @()
        try { $items = @([System.IO.Directory]::GetFiles($f)) } catch { continue }
        foreach ($file in $items) {
            $fn = [System.IO.Path]::GetFileName($file)
            if ($fn -eq 'desktop.ini') { continue }
            $disabled = $fn.EndsWith('.disabled', [System.StringComparison]::OrdinalIgnoreCase)
            $out += @{
                Kind     = 'Folder'
                Path     = $file
                Name     = $fn
                Command  = $file
                IsEnabled = (-not $disabled)
                Location = $f
            }
        }
    }
    return @($out)
}

try {
    $targets = @()
    foreach ($root in (Get-RunRoots)) {
        $full = "$($root.Hive)\$($root.Path)"
        $names = @()
        try {
            $k = Get-Item -LiteralPath $full -ErrorAction Stop
            try { $names = @($k.GetValueNames()) } finally { $k.Close() }
        } catch { continue }
        if ($names.Count -eq 0) { continue }
        $approved = Get-ApprovedPath -Hive $root.Hive -Approved $root.Approved
        foreach ($name in $names) {
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $cmd = ''
            try {
                $k = Get-Item -LiteralPath $full -ErrorAction Stop
                try { $cmd = [string]$k.GetValue($name) } finally { $k.Close() }
            } catch { continue }
            $targets += @{
                Kind      = 'Reg'
                Hive      = $root.Hive
                RegPath   = $full
                Approved  = $approved
                Name      = $name
                Command   = $cmd
                IsEnabled = (Get-ApprovedState -Path $approved -Name $name)
                Location  = $root.Label
            }
        }
    }
    $targets += Get-StartupFolderItems

    if ($targets.Count -eq 0) {
        Write-Output "[=] Записей автозагрузки не найдено - чистить нечего."
        exit 0
    }

    $disabled = 0; $skipped = 0; $kept = 0
    $changed = @()
    foreach ($t in $targets) {
        $verdict = if ($t.Kind -eq 'Folder') {
            $base = [System.IO.Path]::GetFileNameWithoutExtension(($t.Name -replace '(?i)\.disabled$', ''))
            $v = Get-Verdict -Name $base -Command $t.Command
            if ($v -eq 'junk' -or $v -eq 'broken') { $v } else { 'keep' }
        } else { Get-Verdict -Name $t.Name -Command $t.Command }

        if (-not $t.IsEnabled) { $kept++; continue }
        if ($verdict -eq 'never') {
            Write-Output ("   оставлено (системное): {0}" -f $t.Name)
            $kept++
            continue
        }
        if ($verdict -eq 'keep') {
            Write-Output ("   оставлено: {0}" -f $t.Name)
            $kept++
            continue
        }
        $why = if ($verdict -eq 'broken') { 'битая запись' } else { 'известный мусор' }
        try {
            if ($t.Kind -eq 'Folder') {
                Rename-Item -LiteralPath $t.Path -NewName ($t.Name + '.disabled') -Force -ErrorAction Stop
            } else {
                Set-ApprovedState -Path $t.Approved -Name $t.Name -Enable $false -ErrorAction Stop
            }
            $disabled++
            $changed += [PSCustomObject]@{
                Kind = $t.Kind; Hive = $t.Hive; RegPath = $t.RegPath; Approved = $t.Approved
                Name = $t.Name; Path = $t.Path; Location = $t.Location; Reason = $why
            }
            Write-Output ("   выключено ({0}): {1}" -f $why, $t.Name)
        } catch {
            $skipped++
            Write-Output ("[!] Не смог отключить {0}: {1}" -f $t.Name, $_.Exception.Message)
        }
    }

    if ($changed.Count -gt 0) {
        $backupDir = if ($env:ProgramData) { Join-Path $env:ProgramData 'PotatoPC\backups' } else { Join-Path $env:TEMP 'PotatoPC' }
        try {
            if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction Stop | Out-Null }
            $file = Join-Path $backupDir ('autostart-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
            @{ Time = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); User = $env:USERNAME; Items = @($changed) } |
                ConvertTo-Json -Depth 5 | Out-File -FilePath $file -Encoding UTF8 -Force -ErrorAction Stop
            Write-Output ("[*] Копия для отката: {0}" -f $file)
        } catch {
            Write-Output ("[!] Не смог сохранить копию для отката: " + $_.Exception.Message)
            Write-Output "    Откат 09 Откат/09_undo_autostart.ps1 её не найдёт."
        }
    }

    Write-Output ("[OK] Автозагрузка: отключено {0}, оставлено {1}, ошибок {2} (из {3} записей)" -f $disabled, $kept, $skipped, $targets.Count)
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
