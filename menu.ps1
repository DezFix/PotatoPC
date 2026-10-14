<#
.SYNOPSIS
    PotatoPC Optimizer v6 - Entry Point
.DESCRIPTION
    Local:  powershell -STA -NoProfile -ExecutionPolicy Bypass -File menu.ps1
    Remote: irm https://raw.githubusercontent.com/DezFix/PotatoPC/main/menu.ps1 | iex
#>

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Administrator rights required. Relaunching..." -ForegroundColor Yellow
    try {
        if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
            Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        } else {
            Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -Command', 'irm https://raw.githubusercontent.com/DezFix/PotatoPC/main/menu.ps1 | iex'
        }
    } catch {
        Write-Host "Failed to relaunch as administrator. Run the console manually as administrator." -ForegroundColor Red
        Read-Host "Press Enter to exit"
    }
    exit
}

# Обычно скрипт стартует с -ExecutionPolicy Bypass, и Set-ExecutionPolicy
# тут просто тратит время на загрузку движка политик. Проверяем текущую
# политику и дёргаем движок только когда это реально нужно.
try {
    $curPolicy = Get-ExecutionPolicy -Scope Process -ErrorAction SilentlyContinue
    if ($curPolicy -eq 'Restricted') { Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue }
} catch {}

# Menu build tag (ASCII-only file!): printed to the log at startup next to the
# modules build tag, so a version mix (old menu + new modules) is visible.
$script:MenuTag = '2026-10-14-r7'

# Тяжёлые модули (CimCmdlets, ScheduledTasks, LocalAccounts, Archive,
# PrintManagement) намеренно НЕ импортируются: Windows PowerShell 5.1
# подгружает их автозагрузкой при первом реальном вызове, то есть лениво и
# в фоновом ранспейсе. На слабом ПК предварительный импорт семи модулей
# стоил ~0.5 с до появления окна.
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
    $script:ModuleDir = Join-Path (Split-Path $PSCommandPath -Parent) "modules"
} else {
    # Link launch: fetch a fresh ZIP. Any network/extract trouble ends here
    # with a readable message + pause instead of a silent flash-and-gone.
    $zipUrl  = "https://codeload.github.com/DezFix/PotatoPC/zip/refs/heads/main?cachebust=$([Guid]::NewGuid().ToString('N'))"
    $downloadRoot = Join-Path $env:TEMP ('PotatoPC-link-' + [Guid]::NewGuid().ToString('N'))
    $zipPath = Join-Path $downloadRoot 'repo.zip'
    $needBase = @("_config.ps1","_core.ps1","_theme.ps1","_icons.ps1","_ui.ps1","_xaml.ps1")
    $repoFolder = $null
    $dlError = $null
    for ($dlAttempt = 1; $dlAttempt -le 2 -and -not $repoFolder; $dlAttempt++) {
        try {
            New-Item -ItemType Directory -Path (Split-Path $zipPath -Parent) -Force | Out-Null
            if ($dlAttempt -eq 1) { Write-Host "Downloading PotatoPC Optimizer..." -ForegroundColor Cyan }
            else { Write-Host "Re-downloading PotatoPC Optimizer (attempt 2)..." -ForegroundColor Yellow }
            Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
            try {
                Expand-Archive -Path $zipPath -DestinationPath (Split-Path $zipPath -Parent) -Force -ErrorAction Stop
            } catch {
                Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
                [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, (Split-Path $zipPath -Parent))
            }
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
            try {
                Get-ChildItem -Path (Split-Path $zipPath -Parent) -Filter '*.ps1' -Recurse -Force -ErrorAction SilentlyContinue |
                    Unblock-File -ErrorAction SilentlyContinue
            } catch {}
            $cand = Get-ChildItem -Path (Split-Path $zipPath -Parent) -Filter "*-main" -Directory |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if (-not $cand) { throw "Failed to download repository" }
            $miss = @($needBase | Where-Object { -not (Test-Path (Join-Path (Join-Path $cand.FullName "modules") $_)) })
            if ($miss.Count -gt 0) { throw ("Archive incomplete, missing: " + ($miss -join ", ")) }
            $repoFolder = $cand
        } catch {
            $dlError = $_
            $repoFolder = $null
            if ($dlAttempt -eq 1) { try { Start-Sleep 2 } catch {} }
        }
    }
    if (-not $repoFolder) {
        Write-Host ""
        Write-Host ("FAILED to download PotatoPC: " + $dlError.Exception.Message) -ForegroundColor Red
        Write-Host "Check internet / VPN / antivirus and run the link again." -ForegroundColor Yellow
        try { Read-Host "Enter - exit" | Out-Null } catch {}
        exit 1
    }
    $script:ModuleDir = Join-Path $repoFolder.FullName "modules"
}

$loadOrder = @("_config.ps1", "_core.ps1", "_theme.ps1", "_icons.ps1", "_ui.ps1", "_xaml.ps1")
foreach ($module in $loadOrder) {
    $modulePath = Join-Path $script:ModuleDir $module
    if (-not (Test-Path $modulePath)) { throw "Module not found: $module" }
    . $modulePath
}
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

Initialize-Controls $window

# XAML/modules mismatch gate: fail fast with a readable message
# instead of a cryptic $null crash deep inside _events.ps1.
$needNames = @("LogOutput","TaskProgressBar","ScriptsPanel","AppsPanel","SysPanel","UpdatesPanel","DiagPanel",
    "ScriptsFolderText","SelectedCountText","RunScriptsBtn","RebootAfterScriptsChk","SelectAllBtn","DeselectAllBtn",
    "RefreshBtn","OpenFolderBtn","ClearLogBtn","CopyLogBtn","SaveLogBtn","ToggleLogBtn","LogSplitter","LogRow",
    "LogOuterBorder","LogHeaderBorder","MainTabControl","InstallAppsBtn","SelectAllAppsBtn","DeselectAllAppsBtn",
    "AppCountText","RestorePointBtn","PresetPotatoBtn","PresetOfficeBtn","PresetGamesBtn",
    "ScriptPresetPotatoBtn","ScriptPresetOfficeBtn","ScriptPresetGameBtn","CheckUpdatesBtn","SelectAllUpdatesBtn",
    "DeselectAllUpdatesBtn","InstallUpdatesBtn","UpdateAllBtn","HiddenUpdatesBtn","UpdateStatusText","UpdateCountText",
    "StartupAppsPanel","RefreshStartupBtn","DisableStartupBtn","EnableStartupBtn","SelectAllStartupBtn","DeselectAllStartupBtn",
    "StartupFilterAllBtn","StartupFilterAppBtn","StartupFilterTaskBtn","StartupCountText","StartupSelectedText",
    "StartupSearchBox","CleanPanel","CleanFilterRow","CleanScanBtn","SelectAllCleanBtn","DeselectAllCleanBtn","CleanBtn",
    "CleanStatusText","CleanCountText","PageProt","ProtectPanel","ProtectStatusText","ScanProgressText","ScanProgressBar","ScanBtn","DefenderScanBtn","RefreshProtectBtn","SelectAllScanBtn","DeselectAllScanBtn",
    "QuarantineBtn","RestoreQuarantineBtn","RollbackPanel","RollbackCountText","RollbackFolderText","SelectAllRollbackBtn","DeselectAllRollbackBtn","RunRollbackBtn",
    "UsersPanel","RefreshUsersBtn","AddUserBtn","ScriptSearchBox","AppSearchBox",
    "ToolsBtn","AdminBtn","NavModulesBtn","NavStartupBtn","NavUsersBtn","NavAppsBtn","NavUpdatesBtn","NavCleanBtn",
    "NavProtectBtn","NavDiagBtn","NavSysBtn","NavRollbackBtn","NavRollbackIcon","NavDashBtn","HeaderTitleText","HeaderSubtitleText","SideStatusText")
$missNames = @($needNames | Where-Object { -not $window.FindName($_) })
if ($missNames.Count -gt 0) {
    throw ("XAML outdated, missing controls: " + ($missNames -join ", ") + ". Delete $env:TEMP\PotatoPC and relaunch.")
}

# Last-chance UI-thread handler: an unhandled error goes to the log and expands
# the console, but does NOT close the window (used to kill the whole app).
try {
    $window.Dispatcher.add_UnhandledException({
        param($s, $e)
        try {
            $msg = "UI ERROR (caught, window stays): " + $e.Exception.Message
            try { Write-Log $msg -Color "Red" } catch {}
            try {
                $lp = $null; try { $lp = $script:LogPath } catch {}
                if ($lp) { ("[" + (Get-Date).ToString("HH:mm:ss") + "] " + $msg + "`r`n") | Out-File -FilePath $lp -Append -Encoding UTF8 -ErrorAction SilentlyContinue }
            } catch {}
            try { if (-not $script:LogState) { Set-LogExpanded -Expand $true } } catch {}
            $e.Handled = $true
        } catch { try { $e.Handled = $true } catch {} }
    })
} catch {}

# v6 bindings: chrome, pages, search, dashboard (shared modules untouched)
. (Join-Path $script:ModuleDir "_ui_v6.ps1")

# --- Restore saved UI state (tabs 0-10; console state restored when saved) ---
$script:LogHeight = 150
$script:LogState  = $false
$ui = Get-UIState
if ($ui) {
    try {
        if ($ui.LogHeight -ge 60 -and $ui.LogHeight -le 600) { $script:LogHeight = [double]$ui.LogHeight }
        if ($null -ne $ui.LogExpanded) { $script:LogState = [bool]$ui.LogExpanded }
        if ($null -ne $ui.Width  -and $ui.Width  -ge 500) { $window.Width  = [double]$ui.Width }
        if ($null -ne $ui.Height -and $ui.Height -ge 400) { $window.Height = [double]$ui.Height }
        if ($null -ne $ui.Left -and $null -ne $ui.Top) {
            $vsL = [System.Windows.SystemParameters]::VirtualScreenLeft
            $vsT = [System.Windows.SystemParameters]::VirtualScreenTop
            $vsW = [System.Windows.SystemParameters]::VirtualScreenWidth
            $vsH = [System.Windows.SystemParameters]::VirtualScreenHeight
            $l  = [Math]::Max($vsL - $window.Width + 120, [Math]::Min([double]$ui.Left, $vsL + $vsW - 120))
            $tp = [Math]::Max($vsT - 20, [Math]::Min([double]$ui.Top, $vsT + $vsH - 80))
            if ($ui.State -ne "Maximized") { $window.Left = $l; $window.Top = $tp }
        }
        if ($ui.State -eq "Maximized") { $window.WindowState = "Maximized" }
        $tab = if ($null -ne $ui.Tab) { [int]$ui.Tab } else { -1 }
        if ($null -eq $ui.UiVersion -and $tab -eq 9) { $tab = 10 }
        if ($tab -ge 0 -and $tab -le 10) {
            try { Set-ActiveNav -Index $tab } catch {}
        } else {
            try { Set-ActiveNav -Index 10 } catch {}
        }
    } catch {}
} else {
    try { Set-ActiveNav -Index 10 } catch {}
}
Set-LogExpanded -Expand $script:LogState -Instant
try { if ($logSplitter) { $logSplitter.Add_DragDelta({ if ($logRow.Height.Value -gt 32) { $script:LogHeight = $logRow.Height.Value } }) } } catch {}

# --- Window entrance animation ---
$window.Opacity = 1
try { $contentTf = [System.Windows.Media.TranslateTransform]::new(0, 0) } catch { $contentTf = $null }
if ($contentTf) { try { $window.Content.RenderTransform = $contentTf } catch {} }
$script:FadedIn = $true

$window.Add_Closing({ Save-UIState })

# Только модули, нужные ДО первого клика. Остальные 8 (~375 КБ) догружает
# Ensure-ModuleLoaded при первом открытии своей вкладки.
$uiModules = @("_scripts.ps1", "_search.ps1", "_events.ps1")
foreach ($module in $uiModules) {
    $modulePath = Join-Path $script:ModuleDir $module
    if (-not (Test-Path $modulePath)) { throw "Module not found: $module" }
    . $modulePath
}
# Базовые модули загружены - фон может работать, первый снимок полный.
$script:V6ModulesReady = $true
try { Update-DashStats } catch { }

# Гейт проверяет только то, что реально загружено сейчас. Остальные функции
# проверяются по факту догрузки своего модуля: если модуль не поднялся,
# Ensure-PanelBuilt напишет «Вкладка N не построилась» с причиной.
$requiredCommands = @(
    "Run-SelectedScripts", "Stop-SelectedScripts", "Reset-RunButton", "Select-ScriptPreset",
    "Build-ScriptsPanel", "Build-RollbackPanel",
    "Run-SelectedRollbackScripts",
    "New-Card", "New-CategoryHeader", "Set-LogExpanded", "Update-HeaderCount",
    "Get-IconImage", "Get-IconSource", "Initialize-WindowIcons", "New-SectionHeader",
    "Invoke-Async", "Invoke-OnUI", "Set-BgResult", "Get-BgResult",
    "Start-BgPoller", "Stop-BgPoller", "Test-BgQueue", "Complete-BgPipelines",
    "Start-Background", "Invoke-ScriptFileWithRetry", "Get-ScriptTimeout",
    "Set-Progress", "Clear-Progress", "Update-ProgressUI", "Get-LogAutoColor", "Get-LogHexColor",
    "Sync-V6Page", "Update-DashStats", "Ensure-PanelBuilt", "Ensure-TabReady", "Ensure-ModuleLoaded"
)
$missingCommands = @(Test-RequiredCommands -Names $requiredCommands)
if ($missingCommands.Count -gt 0) {
    throw "Modules incomplete, missing functions: $($missingCommands -join ', '). Delete $env:TEMP\PotatoPC and relaunch."
}
