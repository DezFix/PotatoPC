#Requires -RunAsAdministrator
<#
.SYNOPSIS
    PotatoPC Optimizer - Entry Point
.DESCRIPTION
    Запуск: irm https://raw.githubusercontent.com/DezFix/PotatoPC/main/menu.ps1 | iex
#>

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Требуются права администратора. Перезапуск..." -ForegroundColor Yellow
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
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
    Write-Host "Загрузка PotatoPC Optimizer..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath (Split-Path $zipPath -Parent) -Force
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    $repoFolder = Get-ChildItem -Path (Split-Path $zipPath -Parent) -Filter "*-main" -Directory |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $repoFolder) { throw "Не удалось загрузить репозиторий" }
    $script:ModuleDir = Join-Path $repoFolder.FullName "modules"
}

$loadOrder = @("_config.ps1", "_core.ps1", "_xaml.ps1")
foreach ($module in $loadOrder) {
    . (Join-Path $script:ModuleDir $module)
}

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$script:LogBox         = $window.FindName("LogOutput")
$scriptsPanel          = $window.FindName("ScriptsPanel")
$appsPanel             = $window.FindName("AppsPanel")
$sysPanel              = $window.FindName("SysPanel")
$updatesPanel          = $window.FindName("UpdatesPanel")
$diagPanel             = $window.FindName("DiagPanel")
$headerOsText          = $window.FindName("HeaderOsText")
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
$installAppsBtn        = $window.FindName("InstallAppsBtn")
$selectAllAppsBtn      = $window.FindName("SelectAllAppsBtn")
$deselectAllAppsBtn    = $window.FindName("DeselectAllAppsBtn")
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

$uiModules = @(
    "_scripts.ps1", "_apps.ps1", "_sysdiag.ps1", "_updates.ps1",
    "_startup.ps1", "_users.ps1", "_events.ps1"
)
foreach ($module in $uiModules) {
    . (Join-Path $script:ModuleDir $module)
}
