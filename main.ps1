# ╔═══════════════════════════════════════╗
# ║          МЕНЮ НАСТРОЙКИ WINDOWS       ║
# ╚═══════════════════════════════════════╝

function Show-Menu {
    Clear-Host
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host "     WICKED RAVEN SYSTEM TOOLKIT   " -ForegroundColor Magenta
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " 1. Оптимизация системы"
    Write-Host " 2. Установка софта"
    Write-Host " 3. Настройки приватности"
    Write-Host " 4. Отключить телеметрию"
    Write-Host " 5. Выйти"
    Write-Host ""
}

function Read-Choice {
    param (
        [string]$Prompt = "Выберите опцию (1-5): "
    )
    Write-Host ""
    $choice = Read-Host -Prompt $Prompt
    return $choice
}

function Run-Selection {
    param (
        [string]$selection
    )
    switch ($selection) {
        '1' { Write-Host ">> Запуск оптимизации системы..." -ForegroundColor Yellow; Pause }
        '2' { Write-Host ">> Запуск установки ПО..." -ForegroundColor Yellow; Pause }
        '3' { Write-Host ">> Запуск настроек приватности..." -ForegroundColor Yellow; Pause }
        '4' { Write-Host ">> Отключение телеметрии..." -ForegroundColor Yellow; Pause }
        '5' { Write-Host ">> Выход. До встречи!" -ForegroundColor Green; exit }
        Default { Write-Host ">> Неверный ввод. Попробуйте снова." -ForegroundColor Red; Pause }
    }
}

# Главный цикл
do {
    Show-Menu
    $userInput = Read-Choice
    Run-Selection $userInput
} while ($true)
