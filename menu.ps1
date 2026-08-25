<#
.SYNOPSIS
    PotatoPC Optimizer - Entry Point
.DESCRIPTION
    Run: irm https://raw.githubusercontent.com/DezFix/PotatoPC/main/menu.ps1 | iex
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

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
    $script:ModuleDir = Join-Path (Split-Path $PSCommandPath -Parent) "modules"
} else {
    $zipUrl  = "https://github.com/DezFix/PotatoPC/archive/refs/heads/main.zip"
    $zipPath = Join-Path $env:TEMP "PotatoPC\repo.zip"
    New-Item -ItemType Directory -Path (Split-Path $zipPath -Parent) -Force | Out-Null
    Write-Host "Downloading PotatoPC Optimizer..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath (Split-Path $zipPath -Parent) -Force
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    $repoFolder = Get-ChildItem -Path (Split-Path $zipPath -Parent) -Filter "*-main" -Directory |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $repoFolder) { throw "Failed to download repository" }
    $script:ModuleDir = Join-Path $repoFolder.FullName "modules"
}

$loadOrder = @("_config.ps1", "_core.ps1", "_xaml.ps1")
foreach ($module in $loadOrder) {
    $modulePath = Join-Path $script:ModuleDir $module
    if (-not (Test-Path $modulePath)) { throw "Module not found: $module" }
    . $modulePath
}

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$script:LogBox         = $window.FindName("LogOutput")
$scriptsPanel          = $window.FindName("ScriptsPanel")
$appsPanel             = $window.FindName("AppsPanel")
$sysPanel              = $window.FindName("SysPanel")
$updatesPanel          = $window.FindName("UpdatesPanel")
$diagPanel             = $window.FindName("DiagPanel")
$scriptsFolderText     = $window.FindName("ScriptsFolderText")
$selectedCountText     = $window.FindName("SelectedCountText")
$runScriptsBtn         = $window.FindName("RunScriptsBtn")
$rebootAfterChk        = $window.FindName("RebootAfterScriptsChk")
$selectAllBtn          = $window.FindName("SelectAllBtn")
$deselectAllBtn        = $window.FindName("DeselectAllBtn")
$refreshBtn            = $window.FindName("RefreshBtn")
$openFolderBtn         = $window.FindName("OpenFolderBtn")
$clearLogBtn           = $window.FindName("ClearLogBtn")
$copyLogBtn            = $window.FindName("CopyLogBtn")
$toggleLogBtn          = $window.FindName("ToggleLogBtn")
$logSplitter           = $window.FindName("LogSplitter")
$logRow                = $window.FindName("LogRow")
$installAppsBtn        = $window.FindName("InstallAppsBtn")
$selectAllAppsBtn      = $window.FindName("SelectAllAppsBtn")
$deselectAllAppsBtn    = $window.FindName("DeselectAllAppsBtn")
$appCountText          = $window.FindName("AppCountText")
$restorePointBtn       = $window.FindName("RestorePointBtn")
$presetOfficeBtn       = $window.FindName("PresetOfficeBtn")
$presetGamesBtn        = $window.FindName("PresetGamesBtn")
$selectRecommendedBtn  = $window.FindName("SelectRecommendedBtn")
$checkUpdatesBtn       = $window.FindName("CheckUpdatesBtn")
$selectAllUpdatesBtn   = $window.FindName("SelectAllUpdatesBtn")
$deselectAllUpdatesBtn = $window.FindName("DeselectAllUpdatesBtn")
$installUpdatesBtn     = $window.FindName("InstallUpdatesBtn")
$updateStatusText      = $window.FindName("UpdateStatusText")
$updateCountText       = $window.FindName("UpdateCountText")
$startupAppsPanel      = $window.FindName("StartupAppsPanel")
$refreshStartupBtn     = $window.FindName("RefreshStartupBtn")
$disableStartupBtn     = $window.FindName("DisableStartupBtn")
$enableStartupBtn      = $window.FindName("EnableStartupBtn")
$selectAllStartupBtn   = $window.FindName("SelectAllStartupBtn")
$deselectAllStartupBtn = $window.FindName("DeselectAllStartupBtn")
$startupFilterAllBtn   = $window.FindName("StartupFilterAllBtn")
$startupFilterAppBtn   = $window.FindName("StartupFilterAppBtn")
$startupFilterTaskBtn  = $window.FindName("StartupFilterTaskBtn")
$startupCountText      = $window.FindName("StartupCountText")
$startupSelectedText   = $window.FindName("StartupSelectedText")
$startupSearchBox      = $window.FindName("StartupSearchBox")
$startupSearchHint     = $window.FindName("StartupSearchHint")
$startupSearchClear    = $window.FindName("StartupSearchClear")
$usersPanel            = $window.FindName("UsersPanel")
$refreshUsersBtn       = $window.FindName("RefreshUsersBtn")
$addUserBtn            = $window.FindName("AddUserBtn")
$scriptSearchBox       = $window.FindName("ScriptSearchBox")
$scriptSearchHint      = $window.FindName("ScriptSearchHint")
$scriptSearchClear     = $window.FindName("ScriptSearchClear")
$appSearchBox          = $window.FindName("AppSearchBox")
$appSearchHint         = $window.FindName("AppSearchHint")
$appSearchClear        = $window.FindName("AppSearchClear")
$ToolsBtn              = $window.FindName("ToolsBtn")
$AdminBtn              = $window.FindName("AdminBtn")

# --- Restore saved UI state ---
$script:LogHeight = 150
$script:LogState  = $false
$ui = Get-UIState
if ($ui) {
    try {
        if ($ui.LogHeight -ge 60 -and $ui.LogHeight -le 600) { $script:LogHeight = [double]$ui.LogHeight }
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
        if ($null -ne $ui.Tab -and $ui.Tab -ge 0 -and $ui.Tab -lt $MainTabControl.Items.Count) {
            $MainTabControl.SelectedIndex = [int]$ui.Tab
        }
        $script:LogState = [bool]$ui.LogExpanded
    } catch {}
}
Set-LogExpanded -Expand $script:LogState -Instant
$logSplitter.Add_DragDelta({ if ($logRow.Height.Value -gt 32) { $script:LogHeight = $logRow.Height.Value } })

# --- Window entrance animation ---
$window.Opacity = 0
$contentTf = [System.Windows.Media.TranslateTransform]::new(0, 10)
$window.Content.RenderTransform = $contentTf
$script:FadedIn = $false
$window.Add_ContentRendered({
    if ($script:FadedIn) { return }
    $script:FadedIn = $true
    try {
        $dur = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(220))
        $oa = [System.Windows.Media.Animation.DoubleAnimation]::new(0, 1, $dur)
        $ta = [System.Windows.Media.Animation.DoubleAnimation]::new(10, 0, $dur)
        $window.BeginAnimation([System.Windows.Window]::OpacityProperty, $oa)
        $contentTf.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $ta)
    } catch { $window.Opacity = 1; $contentTf.Y = 0 }
})

$window.Add_Closing({ Save-UIState })

$uiModules = @(
    "_scripts.ps1", "_apps.ps1", "_sysdiag.ps1", "_updates.ps1",
    "_startup.ps1", "_users.ps1", "_events.ps1"
)
foreach ($module in $uiModules) {
    $modulePath = Join-Path $script:ModuleDir $module
    if (-not (Test-Path $modulePath)) { throw "Module not found: $module" }
    . $modulePath
}