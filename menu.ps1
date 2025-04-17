function Show-Menu {
    Clear-Host
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host "     WICKED RAVEN SYSTEM TOOLKIT   " -ForegroundColor Magenta
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " 1. Оптимизация системы"
    Write-Host " 2. Установка софта"
    Write-Host " 3. В разработке..."
    Write-Host " 4. В разработке..."
    Write-Host " 0. Выйти"
    Write-Host ""
}

function Read-Choice {
    param (
        [string]$Prompt = "Выберите опцию (0-4)"
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
        '1' {
            Write-Host ">> Запуск оптимизации системы..." -ForegroundColor Yellow
            iex (irm "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/clear.ps1")
        }
        '2' {
            Write-Host ">> Запуск оптимизации системы..." -ForegroundColor Yellow
            iex (irm "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/install.ps1")
        }
        '3' {
            Write-Host ">> В разработке..." -ForegroundColor DarkGray
            Pause
        }
        '4' {
            Write-Host ">> В разработке..." -ForegroundColor DarkGray
            Pause
        }
        '0' {
            Write-Host ">> Выход. До встречи!" -ForegroundColor Green
            exit
        }
        default {
            Write-Host ">> Неверный ввод. Попробуйте снова." -ForegroundColor Red
            Pause
        }
    }
}

# Главный цикл
do {
    Show-Menu
    $userInput = Read-Choice
    Run-Selection $userInput
} while ($true)
