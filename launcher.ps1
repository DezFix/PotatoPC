#Requires -RunAsAdministrator
<#
.SYNOPSIS
    PotatoPS - Универсальный менеджер настройки Windows
.DESCRIPTION
    Модульное приложение для установки ПО, оптимизации системы, удаления AI-компонентов и деблотинга Windows
.NOTES
    Версия: 1.0.0
    Автор: PotatoPS Team
    GitHub: https://github.com/USER/PotatoPS_reborn
#>

[CmdletBinding()]
param(
    [switch]$Debug,
    [switch]$NoLogo,
    [string]$Module
)

# ==============================================================================
# КОНФИГУРАЦИЯ
# ==============================================================================
$SCRIPT_VERSION = "1.0.0"
$SCRIPT_NAME = "PotatoPS"
$GITHUB_REPO = "https://raw.githubusercontent.com/DezFix/PotatoPC/main"
$GITHUB_PROJECT = "https://github.com/DezFix/PotatoPC"
$MODULES_PATH = "$PSScriptRoot\Modules"
$CONFIG_PATH = "$PSScriptRoot\Config"

# Цветовая схема
$COLOR_PRIMARY = "Cyan"
$COLOR_ACCENT = "Yellow"
$COLOR_SUCCESS = "Green"
$COLOR_ERROR = "Red"
$COLOR_WARNING = "DarkYellow"

# ==============================================================================
# ПРОВЕРКА ВЕРСИИ POWERSHELL
# ==============================================================================
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "[ОШИБКА] Требуется PowerShell 5.1 или выше!" -ForegroundColor Red
    Write-Host "Ваша версия: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    Start-Sleep -Seconds 3
    exit 1
}

# ==============================================================================
# ФУНКЦИИ ЯДРА
# ==============================================================================

function Write-Logo {
    Clear-Host
    $logo = @"
    
    ╔═══════════════════════════════════════════════════════════════╗
    ║                                                               ║
    ║      ██████╗  ██████╗  ██████╗ ██╗  ██╗███████╗███████╗       ║
    ║      ██╔══██╗██╔═══██╗██╔════╝ ██║  ██║██╔════╝██╔════╝       ║
    ║      ██████╔╝██║   ██║██║  ███╗███████║█████╗  ███████╗       ║
    ║      ██╔══██╗██║   ██║██║   ██║╚════██║██╔══╝  ╚════██║       ║
    ║      ██████╔╝╚██████╔╝╚██████╔╝     ██║███████╗███████║       ║
    ║      ╚═════╝  ╚═════╝  ╚═════╝      ╚═╝╚══════╝╚══════╝       ║
    ║                                                               ║
    ║                  СИСТЕМНЫЙ МЕНЕДЖЕР WINDOWS                   ║
    ║                                                               ║
    ╚═══════════════════════════════════════════════════════════════╝
    
"@
    Write-Host $logo -ForegroundColor $COLOR_PRIMARY
    
    $versionInfo = "Версия: $SCRIPT_VERSION | PowerShell: $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor) | Build: $(Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' CurrentBuild)"
    Write-Host $versionInfo -ForegroundColor Gray
    Write-Host "" -ForegroundColor Gray
}

function Write-MenuHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $COLOR_ACCENT
    Write-Host "║  $Title" -ForegroundColor $COLOR_ACCENT -NoNewline
    $padding = 68 - $Title.Length
    Write-Host (" " * $padding) + "║" -ForegroundColor $COLOR_ACCENT
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $COLOR_ACCENT
    Write-Host ""
}

function Wait-Key {
    param([string]$Message = "Нажмите любую клавишу для продолжения...")
    Write-Host ""
    Write-Host $Message -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Test-InternetConnection {
    try {
        $connection = Test-Connection -ComputerName www.microsoft.com -Count 1 -Quiet -ErrorAction Stop
        return $connection
    }
    catch {
        return $false
    }
}

function Get-ModuleList {
    return @(
        @{Name = "Установка ПО"; Id = "installer"; Description = "Установка программ через winget"; Icon = "📦"},
        @{Name = "Очистка системы"; Id = "clear"; Description = "Оптимизация и очистка Windows"; Icon = "🧹"},
        @{Name = "Диагностика"; Id = "diagnostics"; Description = "Проверка системных компонентов"; Icon = "🔍"},
        @{Name = "Удаление AI"; Id = "removeai"; Description = "Удаление Copilot и AI-компонентов"; Icon = "🤖"},
        @{Name = "Деблотер"; Id = "debloat"; Description = "Удаление встроенного мусора"; Icon = "🗑️"},
        @{Name = "Настройки"; Id = "settings"; Description = "Конфигурация приложения"; Icon = "⚙️"}
    )
}

function Show-MainMenu {
    $modules = Get-ModuleList
    
    Write-MenuHeader "ГЛАВНОЕ МЕНЮ"
    
    $index = 1
    foreach ($module in $modules) {
        $color = switch ($index) {
            1 { "Green" }
            2 { "Green" }
            3 { "Green" }
            4 { "DarkMagenta" }
            5 { "DarkYellow" }
            6 { "Cyan" }
            default { "White" }
        }
        
        Write-Host "  $index. " -ForegroundColor $color -NoNewline
        Write-Host "$($module.Icon) $($module.Name)" -ForegroundColor White
        Write-Host "      $($module.Description)" -ForegroundColor DarkGray
        $index++
    }
    
    Write-Host ""
    Write-Host "  0. " -ForegroundColor Red -NoNewline
    Write-Host "Выход" -ForegroundColor White
    Write-Host ""
}

function Load-Module {
    param([string]$ModuleId)
    
    $modulePath = "$MODULES_PATH\$ModuleId\$ModuleId.psm1"
    
    if (Test-Path $modulePath) {
        try {
            Import-Module $modulePath -Force -ErrorAction Stop
            Write-Host "[ЗАГРУЗКА] Модуль '$ModuleId' загружен..." -ForegroundColor Cyan
            
            # Ищем функцию Run-Module или Main в модуле
            if (Get-Command "Invoke-$ModuleId" -ErrorAction SilentlyContinue) {
                & "Invoke-$ModuleId"
            }
            elseif (Get-Command "Main-$ModuleId" -ErrorAction SilentlyContinue) {
                & "Main-$ModuleId"
            }
            else {
                Write-Host "[ОШИБКА] Точка входа модуля не найдена!" -ForegroundColor Red
                Wait-Key
            }
            
            Remove-Module $ModuleId -ErrorAction SilentlyContinue
        }
        catch {
            Write-Host "[ОШИБКА] Не удалось загрузить модуль: $_" -ForegroundColor Red
            Wait-Key
        }
    }
    else {
        Write-Host "[ОШИБКА] Модуль не найден: $modulePath" -ForegroundColor Red
        Wait-Key
    }
}

# ==============================================================================
# ТОЧКА ВХОДА
# ==============================================================================

function Main {
    # Показываем логотип
    if (-not $NoLogo) {
        Write-Logo
    }
    
    # Проверяем подключение к интернету
    if (-not (Test-InternetConnection)) {
        Write-Host "[ВНИМАНИЕ] Нет подключения к интернету. Некоторые функции могут быть недоступны." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
    
    # Основной цикл меню
    $exit = $false
    
    while (-not $exit) {
        Show-MainMenu
        
        $choice = Read-Host "  Выберите опцию"
        
        switch ($choice) {
            "1" { Load-Module "SoftwareInstaller" }
            "2" { Load-Module "SystemClear" }
            "3" { Load-Module "Diagnostics" }
            "4" { Load-Module "RemoveAI" }
            "5" { Load-Module "Debloat" }
            "6" { 
                Write-Host ""
                Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
                Write-Host "║  НАСТРОЙКИ                                                            ║" -ForegroundColor Cyan
                Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "  1. Проверить обновления" -ForegroundColor White
                Write-Host "  2. О программе" -ForegroundColor White
                Write-Host "  0. Назад" -ForegroundColor White
                Write-Host ""
                
                $settingsChoice = Read-Host "  Выберите опцию"
                switch ($settingsChoice) {
                    "1" {
                        Write-Host ""
                        Write-Host "[ПРОВЕРКА] Проверка обновлений..." -ForegroundColor Cyan
                        Write-Host "[ИНФО] Функция обновлений будет добавлена в следующей версии" -ForegroundColor Yellow
                        Wait-Key
                    }
                    "2" {
                        Write-Host ""
                        Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
                        Write-Host "║  О ПРОГРАММЕ                                                          ║" -ForegroundColor Cyan
                        Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
                        Write-Host ""
                        Write-Host "  Название:     $SCRIPT_NAME" -ForegroundColor White
                        Write-Host "  Версия:       $SCRIPT_VERSION" -ForegroundColor White
                        Write-Host "  PowerShell:   $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)" -ForegroundColor White
                        Write-Host "  Windows:      $((Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' ProductName))" -ForegroundColor White
                        Write-Host "  Build:        $(Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' CurrentBuild)" -ForegroundColor White
                        Write-Host ""
                        Write-Host "  GitHub:       $GITHUB_PROJECT" -ForegroundColor Cyan
                        Write-Host ""
                        Wait-Key
                    }
                }
            }
            "0" { 
                Write-Host ""
                Write-Host "До свидания! Возвращайтесь ещё!" -ForegroundColor Green
                Write-Host ""
                $exit = $true 
            }
            default { 
                Write-Host ""
                Write-Host "[ОШИБКА] Неверный ввод! Попробуйте снова." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
        
        if (-not $exit) {
            Clear-Host
            Write-Logo
        }
    }
}

# Запускаем приложение
Main
