# Онлайн-загрузчик PotatoPS
# Запуск: & ([scriptblock]::Create((irm "https://raw.githubusercontent.com/DezFix/PotatoPC/main/install.ps1")))

$ErrorActionPreference = "Stop"

# Проверка прав администратора
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║  ТРЕБУЮТСЯ ПРАВА АДМИНИСТРАТОРА                                       ║" -ForegroundColor Red
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    Write-Host "Перезапуск с правами администратора..." -ForegroundColor Yellow
    Write-Host ""
    
    $arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/DezFix/PotatoPC/main/install.ps1')))`""
    Start-Process PowerShell -Verb RunAs -ArgumentList $arguments
    exit
}

# Проверка версии PowerShell
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "[ОШИБКА] Требуется PowerShell 5.1 или выше!" -ForegroundColor Red
    Write-Host "Ваша версия: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    Start-Sleep -Seconds 3
    exit 1
}

# Загрузка и выполнение PotatoPS
try {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  PotatoPS - Загрузка...                                               ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    $launcherUrl = "https://raw.githubusercontent.com/DezFix/PotatoPC/main/launcher.ps1"
    
    Write-Host "[i] Загрузка launcher.ps1..." -ForegroundColor Cyan
    $launcherScript = Invoke-RestMethod -Uri $launcherUrl -UseBasicParsing
    
    Write-Host "[i] Запуск PotatoPS..." -ForegroundColor Cyan
    Write-Host ""
    
    # Выполняем загруженный скрипт
    Invoke-Expression $launcherScript
}
catch {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║  ОШИБКА ЗАГРУЗКИ                                                      ║" -ForegroundColor Red
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    Write-Host "Ошибка: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Возможные причины:" -ForegroundColor Yellow
    Write-Host "  - Нет подключения к интернету" -ForegroundColor DarkGray
    Write-Host "  - GitHub недоступен" -ForegroundColor DarkGray
    Write-Host "  - Блокировка антивирусом/файрволом" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Попробуйте:" -ForegroundColor Yellow
    Write-Host "  1. Проверить подключение к интернету" -ForegroundColor DarkGray
    Write-Host "  2. Запустить от имени администратора" -ForegroundColor DarkGray
    Write-Host "  3. Скачать файлы вручную с GitHub" -ForegroundColor DarkGray
    Write-Host ""
    
    $choice = Read-Host "Открыть GitHub в браузере? (y/n)"
    if ($choice -eq "y" -or $choice -eq "Y") {
        Start-Process "https://github.com/DezFix/PotatoPC"
    }
    
    Write-Host ""
    Write-Host "Нажмите любую клавишу для выхода..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
