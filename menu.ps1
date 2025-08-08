# Проверка прав администратора
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Скрипт не запущен от имени администратора!" -ForegroundColor Red
    $answer = Read-Host "Запустить PowerShell от имени администратора? (Y/N)"
    if ($answer -eq 'Y' -or $answer -eq 'y') {
        Start-Process powershell "-Command irm 'https://kutt.it/potatopc' | iex" -Verb RunAs
    }
    exit
}

# Функция отображения меню с улучшенным дизайном
function Show-Menu {
    Clear-Host
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host "       WICKED RAVEN TOOLKIT        " -ForegroundColor Magenta
    Write-Host "         v2.1 - Улучшенная         " -ForegroundColor DarkGray
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " 1. Оптимизация системы" 
    Write-Host " 2. Установка программ" 
    Write-Host " 3. Диагностика и тесты" 
    Write-Host " 4. Системные скрипты" 
    Write-Host ""
    Write-Host " 0. Выйти" -ForegroundColor Red
    Write-Host ""
    
}

# Функция для загрузки и выполнения скриптов с обработкой ошибок
function Execute-RemoteScript {
    param (
        [string]$Url,
        [string]$Description
    )
    
    Write-Host ">> $Description..." -ForegroundColor Yellow
    
    # Проверка интернет-соединения перед загрузкой
    if (-not (Test-InternetConnection)) {
        Write-Host "[!] Нет подключения к интернету. Проверьте соединение." -ForegroundColor Red
        Pause
        return
    }
    
    try {
        Write-Host "[*] Загрузка скрипта..." -ForegroundColor Cyan
        $scriptContent = Invoke-RestMethod -Uri $Url -UseBasicParsing -TimeoutSec 30
        Write-Host "[+] Скрипт загружен успешно" -ForegroundColor Green
        
        # Выполнение скрипта
        Invoke-Expression $scriptContent
        
    } catch {
        Write-Host "[-] Ошибка при загрузке или выполнении скрипта:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host "[!] Проверьте подключение к интернету или попробуйте позже." -ForegroundColor Yellow
        Pause
    }
}

# Функция выполнения выбора пользователя
function Run-Selection {
    param (
        [string]$selection
    )
    
    switch ($selection) {
        '1' {
            Execute-RemoteScript -Url "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/clear.ps1" -Description "Запуск модуля оптимизации системы"
        }
        '2' {
            Execute-RemoteScript -Url "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/install.ps1" -Description "Запуск модуля установки программ"
        }
        '3' {
            Execute-RemoteScript -Url "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/Diagnostics.ps1" -Description "Запуск модуля диагностики и тестов"
        }
        '4' {
            Execute-RemoteScript -Url "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/scripts.ps1" -Description "Запуск модуля системных скриптов"
        }
        '0' {
            Write-Host ">> Спасибо за использование Wicked Raven Toolkit!" -ForegroundColor Green
            Write-Host ">> Нажмите любую клавишу для выхода..." -ForegroundColor Gray
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            exit
        }
        default {
            Write-Host ">> Неверный ввод. Выберите опцию от 0 до 4." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
}

# Функция чтения пользовательского ввода
function Read-Choice {
    param (
        [string]$Prompt = "Выберите опцию (0-4)"
    )
    $choice = Read-Host -Prompt $Prompt
    return $choice.Trim()
}

# Главный цикл программы
Write-Host "Добро пожаловать в Wicked Raven Toolkit!" -ForegroundColor Green
Start-Sleep -Seconds 1

do {
    Show-Menu
    $userInput = Read-Choice
    Run-Selection $userInput
} while ($true)
