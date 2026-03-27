# Проверка прав администратора в начале скрипта
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║                            ВНИМАНИЕ!                                  ║" -ForegroundColor Red
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    Write-Host "[-] Для работы с этим скриптом требуются права администратора!" -ForegroundColor Red
    Write-Host "[!] Пожалуйста, запустите PowerShell от имени администратора" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Нажмите любую клавишу для выхода..." -ForegroundColor White
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}
function Show-Menu {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║                    WICKED RAVEN SYSTEM TOOLKIT                        ║" -ForegroundColor Yellow
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
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

do {
    Show-Menu
    $userInput = Read-Choice
    Run-Selection $userInput
} while ($true)
