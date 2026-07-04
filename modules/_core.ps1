$script:LogBox = $null
$script:LogPath = $null
function Write-Log($msg, $color = "Default") {
    $time = (Get-Date).ToString("HH:mm:ss")
    $line = "[$time] $msg"
    if ($script:LogBox) {
        $script:LogBox.Dispatcher.Invoke([action]{
            $script:LogBox.AppendText("$line`n")
            $script:LogBox.ScrollToEnd()
        })
    }
    if ($script:LogPath) {
        try { "$line`n" | Out-File -FilePath $script:LogPath -Append -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
    }
    $consoleColor = switch ($color) { "Green" {"Green"} "Red" {"Red"} "Yellow" {"Yellow"} default {"White"} }
    Write-Host $line -ForegroundColor $consoleColor
}

function Download-Repo {
    param([switch]$Force)
    $zipPath = Join-Path $script:WorkFolder "repo.zip"
    try {
        Write-Log "$(if($Force){'Обновление'}else{'Загрузка'}) репозитория с GitHub..."
        if ($Force) {
            $oldFolders = Get-ChildItem -Path $script:WorkFolder -Filter "*-main" -Directory -ErrorAction SilentlyContinue
            foreach ($old in $oldFolders) {
                Write-Log "Удаление старой папки: $($old.Name)"
                Remove-Item -Path $old.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        Invoke-WebRequest -Uri $script:RepoZipUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop
        Expand-Archive -Path $zipPath -DestinationPath $script:WorkFolder -Force
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        $repoFolder = Get-ChildItem -Path $script:WorkFolder -Filter "*-main" -Directory |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($repoFolder) {
            $script:ScriptsFolder = Join-Path $repoFolder.FullName "scripts"
            $script:AppsJsonPath  = Join-Path $repoFolder.FullName "apps.json"
            $n = @(Get-ChildItem -Path $script:ScriptsFolder -Recurse -Filter "*.ps1" -ErrorAction SilentlyContinue).Count
            Write-Log "Готово. Скриптов: $n"
            return $true
        } else {
            Write-Log "Папка репозитория не найдена." -Color "Red"
            return $false
        }
    } catch {
        Write-Log "Ошибка загрузки: $_" -Color "Red"
        return $false
    }
}

function Initialize-PotatoPC {
    Write-Log "Инициализация..."
    if (-not (Test-Path $script:WorkFolder)) {
        New-Item -ItemType Directory -Path $script:WorkFolder -Force | Out-Null
    }
    $repoFolder = Get-ChildItem -Path $script:WorkFolder -Filter "*-main" -Directory |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($repoFolder -and (Test-Path (Join-Path $repoFolder.FullName "scripts"))) {
        $script:ScriptsFolder = Join-Path $repoFolder.FullName "scripts"
        $script:AppsJsonPath  = Join-Path $repoFolder.FullName "apps.json"
        $n = @(Get-ChildItem -Path $script:ScriptsFolder -Recurse -Filter "*.ps1" -ErrorAction SilentlyContinue).Count
        Write-Log "Репозиторий найден локально. Скриптов: $n"
    } else {
        Download-Repo
    }
}

function Get-SystemInfo {
    try {
        $os   = Get-WmiObject Win32_OperatingSystem
        $cpu  = (Get-WmiObject Win32_Processor).Name
        $ramB = (Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory
        $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
        return @{
            OS     = "$($os.Caption) Build $($os.BuildNumber)"
            CPU    = $cpu.Trim()
            RAM    = "$([math]::Round($ramB/1GB,1)) ГБ"
            Disk   = "C: $([math]::Round($disk.FreeSpace/1GB,1)) ГБ своб. / $([math]::Round($disk.Size/1GB,1)) ГБ"
            Uptime = ((Get-Date) - $os.ConvertToDateTime($os.LastBootUpTime)) | ForEach-Object { "$($_.Days)д $($_.Hours)ч $($_.Minutes)м" }
        }
    } catch {
        return @{ OS="Неизвестно"; CPU="Неизвестно"; RAM="Неизвестно"; Disk="Неизвестно"; Uptime="Неизвестно" }
    }
}

function Create-RestorePoint {
    Write-Log "Создание точки восстановления системы..."
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "PotatoPC Optimizer Backup" -RestorePointType "MODIFY_SETTINGS"
        Write-Log "Точка восстановления успешно создана!" -Color "Green"
        return $true
    } catch {
        Write-Log "Ошибка создания точки восстановления: $_" -Color "Red"
        return $false
    }
}

function Set-StartupApprovedState {
    param([string]$RegKey, [string]$ValueName, [bool]$Enable)
    try {
        $isHKCU      = $RegKey -like "HKEY_CURRENT_USER*"
        $isRunOnce   = $RegKey -like "*RunOnce*"
        $approvedSub = if ($isRunOnce) {
            'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApprovedRunOnce'
        } else {
            'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApprovedRun'
        }
        $rootKey = if ($isHKCU) { [Microsoft.Win32.Registry]::CurrentUser }
                   else         { [Microsoft.Win32.Registry]::LocalMachine }
        $approvedKey = $rootKey.OpenSubKey($approvedSub, $true)
        if ($null -eq $approvedKey) {
            $approvedKey = $rootKey.CreateSubKey($approvedSub)
        }
        $existing = $approvedKey.GetValue($ValueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($existing -is [byte[]] -and $existing.Length -ge 4) {
            $data = [byte[]]$existing
        } else {
            $data = [byte[]]@(0x02,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)
        }
        $statusByte = if ($Enable) { [byte]0x02 } else { [byte]0x03 }
        $data[0] = $statusByte
        $byteArray = [byte[]]$data
        $approvedKey.SetValue($ValueName, $byteArray, [Microsoft.Win32.RegistryValueKind]::Binary)
        $approvedKey.Dispose()
        return $true
    } catch {
        Write-Log "StartupApproved для '$ValueName': $_" -Color "Red"
        return $false
    }
}

function Invoke-Async {
    param([scriptblock]$ScriptBlock, [hashtable]$Variables = @{})
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = "STA"; $rs.ThreadOptions = "ReuseThread"; $rs.Open()
    $rs.SessionStateProxy.SetVariable("LogBox", $script:LogBox)
    foreach ($kv in $Variables.GetEnumerator()) {
        $rs.SessionStateProxy.SetVariable($kv.Key, $kv.Value)
    }
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    $ps.AddScript($ScriptBlock) | Out-Null
    $ps.BeginInvoke() | Out-Null
}

$script:SettingsPath = $null
function Save-Settings {
    param([hashtable]$Settings)
    if (-not $script:SettingsPath) { return }
    try {
        $dir = Split-Path $script:SettingsPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $Settings | ConvertTo-Json -Compress | Out-File -FilePath $script:SettingsPath -Encoding UTF8 -Force
    } catch { Write-Log "Не удалось сохранить настройки: $_" -Color "Yellow" }
}

function Load-Settings {
    if ($script:SettingsPath -and (Test-Path $script:SettingsPath)) {
        try { return (Get-Content $script:SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop) } catch {}
    }
    return $null
}
