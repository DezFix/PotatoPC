#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Тестовый скрипт для проверки PotatoPS
.DESCRIPTION
    Проверяет наличие всех необходимых файлов и модулей
#>

$ErrorActionPreference = "Stop"
$COLOR_SUCCESS = "Green"
$COLOR_ERROR = "Red"
$COLOR_INFO = "Cyan"
$COLOR_WARNING = "Yellow"

function Write-Test {
    param(
        [string]$Name,
        [bool]$Result
    )
    
    $symbol = if ($Result) { "[✓]" } else { "[✗]" }
    $color = if ($Result) { $COLOR_SUCCESS } else { $COLOR_ERROR }
    
    Write-Host "  $symbol $Name" -ForegroundColor $color
    return $Result
}

Clear-Host
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $COLOR_INFO
Write-Host "║  PotatoPS - ПРОВЕРКА УСТАНОВКИ                                        ║" -ForegroundColor $COLOR_INFO
Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $COLOR_INFO
Write-Host ""

$allPassed = $true
$basePath = $PSScriptRoot

# Проверка PowerShell версии
Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host "  СИСТЕМНЫЕ ТРЕБОВАНИЯ" -ForegroundColor $COLOR_INFO
Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host ""

$psVersionOk = $PSVersionTable.PSVersion.Major -ge 5
$allPassed = $allPassed -and (Write-Test "PowerShell 5.1+ ($($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor))" $psVersionOk)

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
$allPassed = $allPassed -and (Write-Test "Права администратора" $isAdmin)

$osOk = [Environment]::OSVersion.Platform -eq "Win32NT"
$allPassed = $allPassed -and (Write-Test "Windows OS" $osOk)

Write-Host ""

# Проверка файлов
Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host "  ФАЙЛЫ" -ForegroundColor $COLOR_INFO
Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host ""

$launcherOk = Test-Path "$basePath\launcher.ps1"
$allPassed = $allPassed -and (Write-Test "launcher.ps1" $launcherOk)

$readmeOk = Test-Path "$basePath\README.md"
$allPassed = $allPassed -and (Write-Test "README.md" $readmeOk)

$runBatOk = Test-Path "$basePath\Run.bat"
$allPassed = $allPassed -and (Write-Test "Run.bat" $runBatOk)

Write-Host ""

# Проверка конфигов
Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host "  КОНФИГУРАЦИЯ" -ForegroundColor $COLOR_INFO
Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host ""

$appsJsonOk = Test-Path "$basePath\Config\apps.json"
$allPassed = $allPassed -and (Write-Test "Config\apps.json" $appsJsonOk)

$settingsJsonOk = Test-Path "$basePath\Config\settings.json"
$allPassed = $allPassed -and (Write-Test "Config\settings.json" $settingsJsonOk)

Write-Host ""

# Проверка модулей
Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host "  МОДУЛИ" -ForegroundColor $COLOR_INFO
Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host ""

$modules = @(
    @{Name = "SoftwareInstaller"; File = "SoftwareInstaller.psm1"},
    @{Name = "SystemClear"; File = "SystemClear.psm1"},
    @{Name = "Diagnostics"; File = "Diagnostics.psm1"},
    @{Name = "RemoveAI"; File = "RemoveAI.psm1"},
    @{Name = "Debloat"; File = "Debloat.psm1"}
)

foreach ($module in $modules) {
    $moduleOk = Test-Path "$basePath\Modules\$($module.Name)\$($module.File)"
    $allPassed = $allPassed -and (Write-Test "$($module.Name)" $moduleOk)
}

Write-Host ""

# Проверка winget
Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host "  ЗАВИСИМОСТИ" -ForegroundColor $COLOR_INFO
Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host ""

$wingetOk = $false
try {
    $null = Get-Command winget -ErrorAction Stop
    $wingetOk = $true
}
catch {
    $wingetOk = $false
}
$allPassed = $allPassed -and (Write-Test "winget" $wingetOk)

Write-Host ""

# Итог
Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host "  РЕЗУЛЬТАТ" -ForegroundColor $COLOR_INFO
Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host ""

if ($allPassed) {
    Write-Host "  [✓] Все проверки пройдены!" -ForegroundColor $COLOR_SUCCESS
    Write-Host ""
    Write-Host "  PotatoPS готов к использованию." -ForegroundColor $COLOR_INFO
    Write-Host ""
    
    $choice = Read-Host "  Запустить PotatoPS? (y/n)"
    if ($choice -eq "y" -or $choice -eq "Y") {
        & "$basePath\launcher.ps1"
    }
}
else {
    Write-Host "  [✗] Некоторые проверки не пройдены!" -ForegroundColor $COLOR_ERROR
    Write-Host ""
    Write-Host "  Убедитесь, что все файлы присутствуют и права достаточны." -ForegroundColor $COLOR_WARNING
    Write-Host ""
    
    if (-not $wingetOk) {
        Write-Host "  winget не найден. Установите:" -ForegroundColor $COLOR_WARNING
        Write-Host "  https://aka.ms/getwinget" -ForegroundColor $COLOR_INFO
        Write-Host ""
    }
}

Write-Host ""
Write-Host "  Нажмите любую клавишу для выхода..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
