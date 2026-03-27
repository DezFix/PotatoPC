# PotatoPS - Онлайн установщик и загрузчик
# Запуск: & ([scriptblock]::Create((irm "https://raw.githubusercontent.com/DezFix/PotatoPC/main/install.ps1")))

$ErrorActionPreference = "Stop"

# Цвета
$COLOR_ACCENT = "Cyan"
$COLOR_ERROR = "Red"
$COLOR_SUCCESS = "Green"

function Write-Status {
    param([string]$Message, [string]$Type = "Info")
    $color = switch ($Type) {
        "Info" { $COLOR_ACCENT }
        "Success" { $COLOR_SUCCESS }
        "Error" { $COLOR_ERROR }
    }
    Write-Host "[$Type] $Message" -ForegroundColor $color
}

# Проверка прав администратора
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Status "Требуется запуск от имени администратора!" "Error"
    Start-Sleep -Seconds 2
    
    $arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/DezFix/PotatoPC/main/install.ps1')))`""
    Start-Process PowerShell -Verb RunAs -ArgumentList $arguments
    exit
}

# Проверка PowerShell
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Status "Требуется PowerShell 5.1 или выше!" "Error"
    Start-Sleep -Seconds 3
    exit 1
}

# Проверка интернета
Write-Status "Проверка подключения..." "Info"
try {
    $connection = Test-Connection -ComputerName www.github.com -Count 1 -Quiet -ErrorAction Stop
    if (-not $connection) {
        throw "Нет подключения"
    }
}
catch {
    Write-Status "Нет подключения к интернету!" "Error"
    Start-Sleep -Seconds 2
    exit 1
}

# Создание временной папки
$tempPath = Join-Path $env:TEMP "PotatoPS-$(Get-Random)"
Write-Status "Создание временной папки: $tempPath" "Info"
New-Item -Path $tempPath -ItemType Directory -Force | Out-Null

# Файлы для загрузки
$files = @(
    "launcher.ps1",
    "Config/apps.json",
    "Config/settings.json",
    "Modules/SoftwareInstaller/SoftwareInstaller.psm1",
    "Modules/SystemClear/SystemClear.psm1",
    "Modules/Diagnostics/Diagnostics.psm1",
    "Modules/RemoveAI/RemoveAI.psm1",
    "Modules/Debloat/Debloat.psm1"
)

$baseUrl = "https://raw.githubusercontent.com/DezFix/PotatoPC/main/"

# Загрузка файлов
Write-Status "Загрузка файлов PotatoPS..." "Info"
foreach ($file in $files) {
    $url = $baseUrl + $file
    $localPath = Join-Path $tempPath $file
    
    $dir = Split-Path $localPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    
    try {
        Invoke-WebRequest -Uri $url -OutFile $localPath -UseBasicParsing
        Write-Status "  ✓ $file" "Success"
    }
    catch {
        Write-Status "  ✗ Ошибка загрузки: $file" "Error"
    }
}

# Запуск launcher
Write-Status "Запуск PotatoPS..." "Info"
Write-Host ""

try {
    & "$tempPath\launcher.ps1"
}
catch {
    Write-Status "Ошибка запуска: $_" "Error"
    Start-Sleep -Seconds 3
}
finally {
    # Очистка
    Write-Status "Очистка временных файлов..." "Info"
    Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Нажмите любую клавишу для выхода..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
