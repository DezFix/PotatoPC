function Write-Log {
    param([string]$msg, [string]$color = "Default")
    $time = (Get-Date).ToString("HH:mm:ss")
    $line = "[$time] $msg"
    try {
        if ($script:LogBox -and $script:LogBox.Dispatcher) {
            $script:LogBox.Dispatcher.Invoke([action]{ $script:LogBox.AppendText("$line`n"); $script:LogBox.ScrollToEnd() })
        }
    } catch {}
    if ($script:LogPath) {
        try { "$line`n" | Out-File -FilePath $script:LogPath -Append -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
    }
    $consoleColor = switch ($color) { "Green" {"Green"} "Red" {"Red"} "Yellow" {"Yellow"} default {"White"} }
    Write-Host $line -ForegroundColor $consoleColor
}

# Определение Write-Log для runspace (Invoke-Async). Использует переменную $LogBox из runspace.
$script:AsyncLogWriter = {
    function Write-Log {
        param([string]$msg, [string]$color = "Default")
        $time = (Get-Date).ToString("HH:mm:ss")
        $line = "[$time] $msg"
        try {
            if ($LogBox -and $LogBox.Dispatcher) {
                $LogBox.Dispatcher.Invoke([action]{ $LogBox.AppendText("$line`n"); $LogBox.ScrollToEnd() })
            }
        } catch {}
        $consoleColor = switch ($color) { "Green" {"Green"} "Red" {"Red"} "Yellow" {"Yellow"} default {"White"} }
        Write-Host $line -ForegroundColor $consoleColor
    }
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
        if (-not (Test-Path $script:WorkFolder)) {
            New-Item -ItemType Directory -Path $script:WorkFolder -Force | Out-Null
        }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
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
        $os    = Get-CimInstance Win32_OperatingSystem
        $cpu   = (Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).Name
        $ramB  = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory
        $disk  = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
        $boot  = $os.LastBootUpTime
        $upMin = [int]((Get-Date) - $boot).TotalMinutes
        $upStr = if ($upMin -ge 1440) { "$([int]($upMin/1440))д $([int](($upMin%1440)/60))ч $(($upMin%60))м" }
                 elseif ($upMin -ge 60) { "$([int]($upMin/60))ч $(($upMin%60))м" }
                 else { "$upMin мин" }
        return @{
            OS     = "$($os.Caption) Build $($os.BuildNumber)"
            CPU    = $cpu.Trim()
            RAM    = "$([math]::Round($ramB/1GB,1)) ГБ"
            Disk   = "C: $([math]::Round($disk.FreeSpace/1GB,1)) ГБ своб. / $([math]::Round($disk.Size/1GB,1)) ГБ"
            Uptime = $upStr
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
    param([string]$RegKey, [string]$ValueName, [bool]$Enable, [string]$ApprovedSubOverride = "")
    try {
        $isHKCU      = $RegKey -like "HKEY_CURRENT_USER*"
        $isRunOnce   = $RegKey -like "*RunOnce*"
        $approvedSub = if ($ApprovedSubOverride) { $ApprovedSubOverride }
                       elseif ($isRunOnce) {
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
        $data[0] = if ($Enable) { [byte]0x02 } else { [byte]0x03 }
        $approvedKey.SetValue($ValueName, [byte[]]$data, [Microsoft.Win32.RegistryValueKind]::Binary)
        $approvedKey.Dispose()
        return $true
    } catch {
        Write-Log "StartupApproved для '$ValueName': $_" -Color "Red"
        return $false
    }
}

if (-not ("PSAsyncHelper" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
public static class PSAsyncHelper {
    public static Action MakeCompletion(PowerShell ps, IAsyncResult iar, Action completion, Runspace bgRunspace, Runspace callerRunspace) {
        return () => {
            Exception err = null;
            try { ps.EndInvoke(iar); }
            catch (Exception e) { err = e; }
            try { ps.Dispose(); } catch {}
            try { if (bgRunspace != null) bgRunspace.Dispose(); } catch {}
            try { if (callerRunspace != null) { callerRunspace.SessionStateProxy.SetVariable("AsyncLastError", err == null ? null : err.Message); } } catch {}
            try { if (callerRunspace != null) { Runspace.DefaultRunspace = callerRunspace; } } catch {}
            if (completion != null) { try { completion(); } catch {} }
        };
    }
    public static Action MakeRunAction(Action body, Runspace callerRunspace) {
        return () => {
            try { if (callerRunspace != null) Runspace.DefaultRunspace = callerRunspace; } catch {}
            if (body != null) { try { body(); } catch {} }
        };
    }
}
"@
}

function Start-Background {
    param([scriptblock]$ScriptBlock)
    $callerRunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
    $body = [Action]$ScriptBlock
    $action = [PSAsyncHelper]::MakeRunAction($body, $callerRunspace)
    [System.Threading.Tasks.Task]::Run($action) | Out-Null
}

function Invoke-Async {
    param(
        [scriptblock]$ScriptBlock,
        [hashtable]$Variables = @{},
        [scriptblock]$OnComplete = $null
    )
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = "STA"
    $rs.ThreadOptions  = "ReuseThread"
    $rs.Open()
    if ($script:LogBox) { $rs.SessionStateProxy.SetVariable("LogBox", $script:LogBox) }
    foreach ($kv in $Variables.GetEnumerator()) {
        $rs.SessionStateProxy.SetVariable($kv.Key, $kv.Value)
    }
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    $ps.AddScript($script:AsyncLogWriter) | Out-Null
    $ps.AddScript($ScriptBlock) | Out-Null
    $iar = $ps.BeginInvoke()
    $callerRunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
    $completion = [Action]$OnComplete
    $action = [PSAsyncHelper]::MakeCompletion($ps, $iar, $completion, $rs, $callerRunspace)
    [System.Threading.Tasks.Task]::Run($action) | Out-Null
}

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
