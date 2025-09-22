$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Скрипт не запущен от имени администратора!" -ForegroundColor Red
    $answer = Read-Host "Запустить PowerShell от имени администратора? (Y/N)"
    if ($answer -eq 'Y' -or $answer -eq 'y') {
        Start-Process powershell "-File `"$PSCommandPath`"" -Verb RunAs
    }
    exit
}
function Show-Menu {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                    WICKED RAVEN SYSTEM TOOLKIT                        ║" -ForegroundColor Magenta
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host " 1. " -ForegroundColor Green -NoNewline
    Write-Host "Оптимизация системы"
    
    Write-Host " 2. " -ForegroundColor Green -NoNewline
    Write-Host "Установка софта"
    
    Write-Host " 3. " -ForegroundColor Green -NoNewline
    Write-Host "Тесты и проверки"
    
    Write-Host " 4. " -ForegroundColor Green -NoNewline
    Write-Host "Системные скрипты"
    
    Write-Host ""
    Write-Host " 0. " -ForegroundColor Red -NoNewline
    Write-Host "Выход"

    Write-Host ""
    Write-Host "Выберите опцию: " -NoNewline -ForegroundColor White

}





function Read-Choice {
    $choice = Read-Host -Prompt $Prompt
    return $choice
}

function Run-Selection {
    param (
        [string]$selection
    )
    switch ($selection) {
        '1' {
            Write-Host ">> Запуск оптимизации системы..." -ForegroundColor Yellow
            iex (irm "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/clear.ps1")
        }
        '2' {
            Write-Host ">> Запуск установки софта..." -ForegroundColor Yellow
            iex (irm "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/install.ps1")
        }
        '3' {
            Write-Host ">> Запуск тестов и проверок..." -ForegroundColor Yellow
            iex (irm "https://github.com/DezFix/PotatoPC/raw/refs/heads/main/Diagnostics.ps1")  
        }
        '4' {
            Write-Host ">> Запуск модуля системных скриптов..." -ForegroundColor Yellow
            iex (irm "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/scripts.ps1")
        }    
        '0' {
            Write-Host ">> Выход. До встречи!" -ForegroundColor Green
            exit
        }
        default {
            Write-Host ">> Неверный ввод. Попробуйте снова." -ForegroundColor Red
            Read-Host "Нажмите Enter для продолжения..."
        }
    }
}

# Главный цикл
do {
    Show-Menu
    $userInput = Read-Choice
    Run-Selection $userInput
} while ($true)
