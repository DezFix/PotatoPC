function Show-DiagnosticsMenu {
    Clear-Host
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host "       WICKED RAVEN DIAGNOSTICS MODULE       " -ForegroundColor Magenta
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " 1. Проверка системных файлов (SFC)"
    Write-Host " 2. Восстановление компонентов Windows (DISM)"
    Write-Host " 3. Проверка диска (CHKDSK)"
    Write-Host " 4. Проверка оперативной памяти (RAM)"
    Write-Host " 5. Сброс сетевых настроек"
    Write-Host " 6. Быстрый просмотр системных ошибок"
    Write-Host " 0. Назад"
    Write-Host ""
}

function Run-SFC {
    Write-Host "[+] Запуск проверки SFC..." -ForegroundColor Yellow
    sfc /scannow
    Pause
}

function Run-DISM {
    Write-Host "[+] Запуск DISM для восстановления компонентов..." -ForegroundColor Yellow
    DISM /Online /Cleanup-Image /RestoreHealth
    Pause
}

function Run-CHKDSK {
    Write-Host "[+] Выберите параметры проверки диска:" -ForegroundColor Cyan
    Write-Host " 1. Только проверка (только чтение)"
    Write-Host " 2. Проверка и исправление ошибок (/F)"
    Write-Host " 3. Проверка, исправление и восстановление секторов (/F /R)"
    Write-Host " 0. Отмена"
    $option = Read-Host "Введите номер опции"

    switch ($option) {
        '1' {
            Write-Host "[+] Выполняется проверка C: без изменений..." -ForegroundColor Yellow
            chkdsk C:
        }
        '2' {
            Write-Host "[+] Запланирована проверка C: с исправлением ошибок..." -ForegroundColor Yellow
            chkdsk C: /F
            Write-Host "[!] Перезагрузите ПК для выполнения проверки." -ForegroundColor Cyan
        }
        '3' {
            Write-Host "[+] Запланирована проверка C: с восстановлением секторов..." -ForegroundColor Yellow
            chkdsk C: /F /R
            Write-Host "[!] Перезагрузите ПК для выполнения проверки." -ForegroundColor Cyan
        }
        '0' {
            Write-Host "[!] Отменено пользователем." -ForegroundColor DarkYellow
        }
        default {
            Write-Host "Неверный ввод. Возврат в меню." -ForegroundColor Red
        }
    }
    Pause
}

function Run-MemoryTest {
    Write-Host "[+] Планирование проверки оперативной памяти..." -ForegroundColor Yellow
    mdsched.exe
}

function Reset-Network {
    Write-Host "[+] Сброс сетевых настроек..." -ForegroundColor Yellow
    ipconfig /flushdns
    netsh winsock reset
    netsh int ip reset
    Write-Host "[!] Готово. Рекомендуется перезагрузка." -ForegroundColor Cyan
    Pause
}

function Show-SystemErrors {
    Write-Host "[+] Последние 20 системных ошибок..." -ForegroundColor Yellow
    Get-WinEvent -LogName System -MaxEvents 20 | ForEach-Object {
        $entry = $_
        $color = switch ($entry.LevelDisplayName) {
            'Error' { 'Red' }
            'Warning' { 'Yellow' }
            'Information' { 'Gray' }
            default { 'White' }
        }
        Write-Host "[$($entry.TimeCreated)] [$($entry.LevelDisplayName)] $($entry.Message)" -ForegroundColor $color
    }
    Pause
}

$backToMain = $false

while (-not $backToMain) {
    Show-DiagnosticsMenu
    $choice = Read-Host "Выберите опцию (0-6):"
    switch ($choice) {
        '1' { Run-SFC }
        '2' { Run-DISM }
        '3' { Run-CHKDSK }
        '4' { Run-MemoryTest }
        '5' { Reset-Network }
        '6' { Show-SystemErrors }
        '0' {
            Write-Host "Возврат в главное меню..." -ForegroundColor Green
            Start-Sleep -Seconds 1
            iex (irm "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/menu.ps1")
            $backToMain = $true
        }
        default {
            Write-Host "Неверный ввод. Попробуйте снова." -ForegroundColor Red
            Pause
        }
    }
}
