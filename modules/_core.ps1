function Write-Log {
    param([string]$msg, [string]$color = "Default")
    $time = (Get-Date).ToString("HH:mm:ss")
    $line = "[$time] $msg"
    # файл первым: фоновая диагностика сохраняется, даже если UI-поток занят
    if ($script:LogPath) {
        try { "$line`n" | Out-File -FilePath $script:LogPath -Append -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
    }
    try {
        if ($LogBox -and $LogBox.Dispatcher) {
            # неблокирующе: текстбокс догонит, когда UI свободен; фоновый поток не виснет
            $LogBox.Dispatcher.InvokeAsync([System.Action]{ $LogBox.AppendText("$line`n"); $LogBox.ScrollToEnd() }) | Out-Null
        }
    } catch {}
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
                $LogBox.Dispatcher.InvokeAsync([System.Action]{ $LogBox.AppendText("$line`n"); $LogBox.ScrollToEnd() }) | Out-Null
            }
        } catch {}
        $consoleColor = switch ($color) { "Green" {"Green"} "Red" {"Red"} "Yellow" {"Yellow"} default {"White"} }
        Write-Host $line -ForegroundColor $consoleColor
    }
}

function Get-ScriptTimeout {
    param([string]$FilePath)
    if ($FilePath -like '*Winget-install*') { return 600 }
    return 120
}

$global:BgResults = [hashtable]::Synchronized(@{})

function Set-BgResult {
    # Общая шина фон->UI. Работает из любой сессии: в фоне видит живую ссылку
    # $bgResults, в UI — $global:BgResults (один и тот же объект).
    param($Key, $Value)
    try {
        $t = $null
        try { $t = $bgResults } catch {}
        if (-not $t) { try { $t = $global:BgResults } catch {} }
        if ($t) { $t[$Key] = $Value }
    } catch {}
}

function Get-BgResult {
    param($Key)
    try {
        $t = $null
        try { $t = $global:BgResults } catch {}
        if (-not $t) { try { $t = $bgResults } catch {} }
        if ($t -and $t.ContainsKey($Key)) { return $t[$Key] }
    } catch {}
    return $null
}

function Start-BgPoller {
    # Таймер UI-потока: забирает готовые результаты из шины и рисует.
    # Создаётся в UI-сессии — все функции и контролы резолвятся всегда.
    if ($script:BgTimer) { try { $script:BgTimer.Start() } catch {}; return }
    $script:BgTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:BgTimer.Interval = [TimeSpan]::FromMilliseconds(400)
    $script:BgTimer.Add_Tick({
        if ($script:BgTickBusy) { return }
        $script:BgTickBusy = $true
        try { Test-BgQueue } catch { Write-Log "Ошибка очереди фона: $_" -Color "Red" }
        $script:BgTickBusy = $false
    })
    $script:BgTimer.Start()
}

function Stop-BgPoller {
    try { if ($script:BgTimer) { $script:BgTimer.Stop() } } catch {}
}

function Invoke-OnUI {
    # Неблокирующая доставка работы в UI-поток. Никогда не вешает фоновый поток:
    # Dispatcher.InvokeAsync ставит действие в очередь и сразу возвращается.
    # Работает и из основного ранспейса, и из фоновых (туда Invoke-Async
    # вшивает эту функцию и кладёт диспетчер в $bpDispatcher).
    param([scriptblock]$ScriptBlock)
    try {
        $d = $null
        try { if ($window -and $window.Dispatcher) { $d = $window.Dispatcher } } catch {}
        if (-not $d) { try { if ($bpDispatcher) { $d = $bpDispatcher } } catch {} }
        if ($d -and (-not $d.HasShutdownStarted) -and (-not $d.HasShutdownFinished)) {
            $d.InvokeAsync([System.Action]$ScriptBlock) | Out-Null
            return $true
        }
    } catch {}
    try {
        $t = (Get-Date).ToString("HH:mm:ss") + " [Invoke-OnUI] no dispatcher`r`n"
        [System.IO.File]::AppendAllText($script:LogPath, $t)
    } catch {}
    return $false
}

function Test-RequiredCommands {
    param([string[]]$Names)
    return @($Names | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
}

function Invoke-ScriptFileWithRetry {
    param([string]$FilePath, [int]$MaxAttempts = 3, [int]$TimeoutSec = 120)
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Write-Log "[$attempt/$MaxAttempts] Запуск: $(Split-Path $FilePath -Leaf)"
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
        if (-not (Test-Path $psi.FileName)) { $psi.FileName = "powershell" }
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$FilePath`""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $proc = $null
        try {
            $proc = [System.Diagnostics.Process]::Start($psi)
            $outTask = $proc.StandardOutput.ReadToEndAsync()
            $errTask = $proc.StandardError.ReadToEndAsync()
            $exited = $proc.WaitForExit($TimeoutSec * 1000)
            if (-not $exited) {
                Write-Log "ЗАВИС: $(Split-Path $FilePath -Leaf) не отвечает ${TimeoutSec}c, убиваю PID $($proc.Id)..." -Color Yellow
                try { $proc.Kill() } catch {}
                try { $null = $proc.WaitForExit(5000) } catch {}
                if ($attempt -eq $MaxAttempts) {
                    throw "Скрипт `"$FilePath`" завис 3 раза подряд (таймаут ${TimeoutSec}c)"
                }
                Write-Log "Перезапуск $(Split-Path $FilePath -Leaf) (попытка $($attempt+1)/$MaxAttempts)" -Color Yellow
                continue
            }
            $stdout = $outTask.Result
            $stderr = $errTask.Result
            if ($stdout) { $stdout -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | ForEach-Object { Write-Log "   $_" } }
            if ($stderr) { $stderr -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | ForEach-Object { Write-Log "   $_" -Color Yellow } }
            if ($proc.ExitCode -ne 0) {
                Write-Log "Скрипт $(Split-Path $FilePath -Leaf) завершился с кодом $($proc.ExitCode)" -Color Yellow
                return $false
            }
            return $true
        } catch {
            if ($_.Exception.Message -like "*завис 3 раза*") { throw }
            Write-Log "Ошибка запуска $(Split-Path $FilePath -Leaf): $_" -Color Red
            if ($attempt -eq $MaxAttempts) { throw "Скрипт `"$FilePath`" упал 3 раза: $_" }
        } finally {
            if ($proc) { try { $proc.Dispose() } catch {} }
        }
    }
    return $false
}

function Expand-RepoArchive {
    param([string]$ZipPath, [string]$Destination)
    try {
        Expand-Archive -Path $ZipPath -DestinationPath $Destination -Force -ErrorAction Stop
        return
    } catch {
        Write-Log "Expand-Archive недоступен ($($_.Exception.Message)), распаковка через .NET..." -Color "Yellow"
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $Destination)
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
        Expand-RepoArchive -ZipPath $zipPath -Destination $script:WorkFolder
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
    # Пути живут и в UI-сессии: кладём в шину, Test-BgQueue применит до построения панелей
    Set-BgResult -Key 'paths' -Value @{ ScriptsFolder = $script:ScriptsFolder; AppsJsonPath = $script:AppsJsonPath }
}

function Get-WingetPath {
    try {
        $cmd = Get-Command winget -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source -and (Test-Path $cmd.Source)) { return $cmd.Source }
    } catch {}
    $candidates = @(
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
        "$env:USERPROFILE\AppData\Local\Microsoft\WindowsApps\winget.exe",
        "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
    )
    foreach ($p in $candidates) {
        if ($p -like "*`*") {
            try {
                $found = Get-ChildItem -Path $p -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found -and (Test-Path $found.FullName)) { return $found.FullName }
            } catch {}
        } elseif (Test-Path $p) { return $p }
    }
    try {
        $where = (where.exe winget 2>$null | Select-Object -First 1)
        if ($where) { $where = $where.Trim(); if (Test-Path $where) { return $where } }
    } catch {}
    return "winget"
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

$script:BgISS = $null
$script:BgConfigNames = @('WorkFolder','ScriptsFolder','AppsJsonPath','AppsJsonUrl','RepoZipUrl','LogPath','SettingsPath','UIStatePath','WindowsMajorVersion','BcuVersion','BcuNetAsset','BcuPortableAsset')

function Get-BgSessionState {
    # Снимок всех пользовательских функций один раз (после загрузки модулей).
    # Каждый фоновый ранспейс стартует с ним: общий ранспейс UI ни с кем не делится,
    # гонок подгрузки модулей между потоками больше нет.
    if ($script:BgISS) { return $script:BgISS }
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($fn in (Get-Command -CommandType Function)) {
        if ($fn.Source -ne '') { continue }
        if ([string]::IsNullOrWhiteSpace($fn.Name)) { continue }
        try {
            $entry = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry($fn.Name, $fn.ScriptBlock)
            $iss.Commands.Add($entry)
        } catch {}
    }
    $script:BgISS = $iss
    return $iss
}

function Start-Background {
    param([scriptblock]$ScriptBlock, [hashtable]$Variables = @{})
    # Всё тяжёлое предвычисляем здесь, в UI-потоке: объект ISS, init-скрипт,
    # исходник тела, живые ссылки. Пул-поток делает только .NET-обвязку
    # ранспейса (без единого cmdlet) и выполняет тело в полной изоляции.
    $iss = Get-BgSessionState
    $bodySrc = $ScriptBlock.ToString()
    $initLines = @()
    foreach ($n in $script:BgConfigNames) {
        try {
            $v = (Get-Variable -Name $n -Scope Script -ErrorAction Stop).Value
            if ($v -is [string]) { $initLines += ('$script:{0} = ''{1}''' -f $n, ($v -replace "'", "''")) }
            elseif ($v -is [int] -or $v -is [bool]) { $initLines += ('$script:{0} = {1}' -f $n, $v) }
        } catch {}
    }
    $initScript = ($initLines -join "`n")
    $liveVars = @{}
    try { if ($LogBox) { $liveVars['LogBox'] = $LogBox } } catch {}
    try { if ($LogBox -and $LogBox.Dispatcher) { $liveVars['bpDispatcher'] = $LogBox.Dispatcher } } catch {}
    try { if ($global:BgResults) { $liveVars['bgResults'] = $global:BgResults } } catch {}
    foreach ($kv in $Variables.GetEnumerator()) { $liveVars[$kv.Key] = $kv.Value }
    $logPathStr = [string]$script:LogPath
    $runner = {
        try {
            $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
            $rs.ApartmentState = "STA"
            $rs.ThreadOptions = "ReuseThread"
            $rs.Open()
            try {
                foreach ($kv in $liveVars.GetEnumerator()) {
                    try { $rs.SessionStateProxy.SetVariable($kv.Key, $kv.Value) } catch {}
                }
                $ps = [System.Management.Automation.PowerShell]::Create()
                $ps.Runspace = $rs
                try {
                    if (-not [string]::IsNullOrWhiteSpace($initScript)) { [void]$ps.AddScript($initScript) }
                    [void]$ps.AddScript($bodySrc)
                    [void]$ps.Invoke()
                    foreach ($e in @($ps.Streams.Error)) {
                        try {
                            $t = [DateTime]::Now.ToString("HH:mm:ss") + " [BG] " + $e.ToString() + "`r`n"
                            [System.IO.File]::AppendAllText($logPathStr, $t)
                        } catch {}
                    }
                } finally { try { $ps.Dispose() } catch {} }
            } finally { try { $rs.Dispose() } catch {} }
        } catch {
            try {
                $t = [DateTime]::Now.ToString("HH:mm:ss") + " [BG bootstrap] " + $_.Exception.Message + "`r`n"
                [System.IO.File]::AppendAllText($logPathStr, $t)
            } catch {}
        }
    }.GetNewClosure()
    $callerRunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
    $action = [PSAsyncHelper]::MakeRunAction([Action]$runner, $callerRunspace)
    [System.Threading.Tasks.Task]::Run($action) | Out-Null
}

function Invoke-Async {
    param(
        [scriptblock]$ScriptBlock,
        [hashtable]$Variables = @{},
        [scriptblock]$OnComplete = $null
    )
    if (-not $script:LogState) { Set-LogExpanded -Expand $true }
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = "STA"
    $rs.ThreadOptions  = "ReuseThread"
    $rs.Open()
    if ($LogBox) { $rs.SessionStateProxy.SetVariable("LogBox", $LogBox) }
    foreach ($kv in $Variables.GetEnumerator()) {
        $rs.SessionStateProxy.SetVariable($kv.Key, $kv.Value)
    }
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    $ps.AddScript($script:AsyncLogWriter) | Out-Null
    # инжект хелперов чтобы были доступны внутри Invoke-Async
    try {
        $retrySrc = ${function:Invoke-ScriptFileWithRetry}.ToString()
        $ps.AddScript("function Invoke-ScriptFileWithRetry {`n$retrySrc`n}") | Out-Null
        $timeoutSrc = ${function:Get-ScriptTimeout}.ToString()
        $ps.AddScript("function Get-ScriptTimeout {`n$timeoutSrc`n}") | Out-Null
        $wingetSrc = ${function:Get-WingetPath}.ToString()
        $ps.AddScript("function Get-WingetPath {`n$wingetSrc`n}") | Out-Null
        $onUISrc = ${function:Invoke-OnUI}.ToString()
        $ps.AddScript("function Invoke-OnUI {`n$onUISrc`n}") | Out-Null
    } catch {}
    if ($LogBox) { try { $rs.SessionStateProxy.SetVariable("bpDispatcher", $LogBox.Dispatcher) } catch {} }
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

function Get-UIState {
    try {
        if ($script:UIStatePath -and (Test-Path $script:UIStatePath)) {
            return (Get-Content $script:UIStatePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop)
        }
    } catch {}
    return $null
}

function Save-UIState {
    try {
        if (-not $window) { return }
        $dir = Split-Path $script:UIStatePath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        @{
            Left        = $window.Left
            Top         = $window.Top
            Width       = $window.Width
            Height      = $window.Height
            State       = [string]$window.WindowState
            Tab         = $MainTabControl.SelectedIndex
            LogExpanded = $script:LogState
            LogHeight   = $script:LogHeight
        } | ConvertTo-Json -Compress | Out-File -FilePath $script:UIStatePath -Encoding UTF8 -Force
    } catch {}
}

# ── Плавное сворачивание/разворачивание лога ──
if (-not ('PotatoPC.GridLengthAnimation' -as [type])) {
    try {
        Add-Type -ReferencedAssemblies @('PresentationFramework', 'PresentationCore', 'WindowsBase') -TypeDefinition @"
using System;
using System.Windows;
using System.Windows.Media.Animation;

namespace PotatoPC
{
    public class GridLengthAnimation : AnimationTimeline
    {
        public static readonly DependencyProperty FromProperty =
            DependencyProperty.Register("From", typeof(GridLength?), typeof(GridLengthAnimation));
        public static readonly DependencyProperty ToProperty =
            DependencyProperty.Register("To", typeof(GridLength?), typeof(GridLengthAnimation));

        public GridLength? From
        {
            get { return (GridLength?)GetValue(FromProperty); }
            set { SetValue(FromProperty, value); }
        }
        public GridLength? To
        {
            get { return (GridLength?)GetValue(ToProperty); }
            set { SetValue(ToProperty, value); }
        }

        public override Type TargetPropertyType
        {
            get { return typeof(GridLength); }
        }

        protected override Freezable CreateInstanceCore()
        {
            return new GridLengthAnimation();
        }

        public override object GetCurrentValue(object defaultOriginValue, object defaultDestinationValue, AnimationClock animationClock)
        {
            double fromVal = ((GridLength)defaultOriginValue).Value;
            double toVal   = ((GridLength)defaultDestinationValue).Value;
            if (From.HasValue) { fromVal = From.Value.Value; }
            if (To.HasValue)   { toVal   = To.Value.Value; }
            if (animationClock.CurrentProgress.HasValue)
            {
                double p = animationClock.CurrentProgress.Value;
                return new GridLength(fromVal + (toVal - fromVal) * p);
            }
            return new GridLength(toVal);
        }
    }
}
"@
    } catch {}
}

function Set-LogExpanded {
    param([bool]$Expand, [switch]$Instant)
    try {
        if (-not $logRow) { return }
        $script:LogState = $Expand
        if ($Expand) {
            $target = [double]$script:LogHeight
        } else {
            # свёрнутая высота = реальная высота тулбара консоли + запас
            $hdrNeed = 30.0
            try {
                $h = $LogHeaderBorder.ActualHeight
                if ($h -le 0) { $h = $LogHeaderBorder.DesiredSize.Height }
                if ($h -gt 0) { $hdrNeed = [Math]::Ceiling($h) }
            } catch {}
            try { $hdrNeed += $LogOuterBorder.BorderThickness.Top } catch {}
            $target = $hdrNeed + 10
            if ($target -lt 38) { $target = 38 }
        }
        $logSplitter.Visibility = if ($Expand) { "Visible" } else { "Collapsed" }
        $toggleLogBtn.Content   = if ($Expand) { "▾ Свернуть" } else { "▴ Развернуть" }
        $from = $logRow.Height.Value
        if ([Math]::Abs($target - $from) -lt 1) { return }
        $heightProp = [System.Windows.Controls.RowDefinition]::HeightProperty
        if ($Instant) {
            try { $logRow.ApplyAnimationClock($heightProp, $null) } catch {}
            $logRow.SetValue($heightProp, [System.Windows.GridLength]::new($target))
            return
        }
        try {
            # базовое значение сразу = цель: после завершения часов значение останется верным
            $logRow.SetValue($heightProp, [System.Windows.GridLength]::new($target))
            $anim = New-Object PotatoPC.GridLengthAnimation
            $anim.From     = [System.Windows.GridLength]::new($from)
            $anim.To       = [System.Windows.GridLength]::new($target)
            $anim.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(160))
            $clock = $anim.CreateClock()
            $clock.Completed.Add({ $logRow.ApplyAnimationClock($heightProp, $null) }.GetNewClosure())
            $logRow.ApplyAnimationClock($heightProp, $clock)
        } catch {
            $logRow.SetValue($heightProp, [System.Windows.GridLength]::new($target))
        }
    } catch {}
}

# ── Hover-эффект карточек (сдвиг 2px) ──
function Add-CardFx {
    param([System.Windows.Controls.Border]$Card)
    try {
        $Card.RenderTransform = [System.Windows.Media.TranslateTransform]::new()
        $Card.Add_MouseEnter({
            param($s, $e)
            $a = [System.Windows.Media.Animation.DoubleAnimation]::new()
            $a.To = 2; $a.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(110))
            $s.RenderTransform.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $a)
        })
        $Card.Add_MouseLeave({
            param($s, $e)
            $a = [System.Windows.Media.Animation.DoubleAnimation]::new()
            $a.To = 0; $a.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(140))
            $s.RenderTransform.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $a)
        })
    } catch {}
}

function Load-Settings {
    if ($script:SettingsPath -and (Test-Path $script:SettingsPath)) {
        try { return (Get-Content $script:SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop) } catch {}
    }
    return $null
}
