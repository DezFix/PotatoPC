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

# Предзагрузка системных модулей в основном потоке: фоновые ранспейсы больше
# не дерутся за автозагрузку ("module could not be loaded" на Join-Path и т.п.)
foreach ($m in @('Microsoft.PowerShell.Management','Microsoft.PowerShell.Utility','Microsoft.PowerShell.Archive','CimCmdlets','ScheduledTasks','Microsoft.PowerShell.LocalAccounts','PrintManagement')) {
    try { Import-Module $m -ErrorAction SilentlyContinue } catch {}
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
    $script:ModuleDir = Join-Path (Split-Path $PSCommandPath -Parent) "modules"
} else {
    # fallback constants until _config.ps1 loads (irm|iex without local file)
    $zipUrl  = "https://github.com/DezFix/PotatoPC/archive/refs/heads/main.zip"
    $zipPath = Join-Path $env:TEMP "PotatoPC\repo.zip"
    New-Item -ItemType Directory -Path (Split-Path $zipPath -Parent) -Force | Out-Null
    Write-Host "Downloading PotatoPC Optimizer..." -ForegroundColor Cyan
    # remove stale extracted repos so we never load cached buggy modules
    Get-ChildItem -Path (Split-Path $zipPath -Parent) -Filter "*-main" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        try { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
    try {
        Expand-Archive -Path $zipPath -DestinationPath (Split-Path $zipPath -Parent) -Force -ErrorAction Stop
    } catch {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, (Split-Path $zipPath -Parent))
    }
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    $repoFolder = Get-ChildItem -Path (Split-Path $zipPath -Parent) -Filter "*-main" -Directory |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $repoFolder) { throw "Failed to download repository" }
    $script:ModuleDir = Join-Path $repoFolder.FullName "modules"
}

$loadOrder = @("_config.ps1", "_core.ps1", "_theme.ps1", "_ui.ps1", "_xaml.ps1")
foreach ($module in $loadOrder) {
    $modulePath = Join-Path $script:ModuleDir $module
    if (-not (Test-Path $modulePath)) { throw "Module not found: $module" }
    . $modulePath
}

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

Initialize-Controls $window

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
    "_startup.ps1", "_users.ps1", "_search.ps1", "_events.ps1"
)
foreach ($module in $uiModules) {
    $modulePath = Join-Path $script:ModuleDir $module
    if (-not (Test-Path $modulePath)) { throw "Module not found: $module" }
    . $modulePath
}

$requiredCommands = @(
    "Run-SelectedScripts", "Select-RecommendedScripts",
    "Build-ScriptsPanel", "Build-AppsPanel", "Build-SysPanel", "Build-DiagPanel",
    "Build-UpdatesPanel", "Build-StartupPanel", "Build-UsersPanel",
    "New-Card", "New-CategoryHeader", "Set-LogExpanded",
    "Invoke-Async", "Invoke-OnUI", "Set-BgResult", "Get-BgResult",
    "Start-BgPoller", "Stop-BgPoller", "Test-BgQueue",
    "Start-Background", "Invoke-ScriptFileWithRetry", "Get-ScriptTimeout", "Get-WingetPath"
)
$missingCommands = @(Test-RequiredCommands -Names $requiredCommands)
if ($missingCommands.Count -gt 0) {
    throw "Modules incomplete, missing functions: $($missingCommands -join ', '). Delete $env:TEMP\PotatoPC and relaunch."
}