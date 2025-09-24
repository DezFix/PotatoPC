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

# Функция отображения меню скриптов
function Show-ScriptsMenu {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║                        WICKED RAVEN SYSTEM SCRIPTS                    ║" -ForegroundColor Yellow
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host " 1. " -ForegroundColor Green -NoNewline
    Write-Host "Отложить обновления Windows"

    Write-Host " 2. " -ForegroundColor Green -NoNewline
    Write-Host "Тестовая Зона ОПАСНО" -ForegroundColor Red
    
    Write-Host ""
    Write-Host " 0. " -ForegroundColor Red -NoNewline
    Write-Host "Назад в главное меню"
    
    Write-Host ""
    Write-Host "Выберите опцию: " -NoNewline -ForegroundColor White
}

# Функция отложения обновлений Windows
function Postpone-WindowsUpdates {
    Write-Host "[!] Отложение обновлений Windows" -ForegroundColor Yellow
    Write-Host "[!] Изменение настроек реестра для приостановки обновлений" -ForegroundColor Yellow
    Write-Host "[+] Начинаем настройку отложения обновлений..." -ForegroundColor Green

    try {
        # Путь к реестру для настроек Windows Update
        $registryPath = "HKLM:\Software\Microsoft\WindowsUpdate\UX\Settings"

        # Проверка существования ключа реестра
        if (-not (Test-Path $registryPath)) {
            Write-Host "[*] Создание ключа реестра..." -ForegroundColor Cyan
            New-Item -Path $registryPath -Force | Out-Null
            Write-Host "[+] Ключ реестра создан" -ForegroundColor Green
        }

        # Ввод количества дней для отложения
        do {
            Write-Host "[*] Введите количество дней для отложения обновлений:" -ForegroundColor Cyan
            Write-Host "[*] Минимум: 1 день, Максимум: 365 дней" -ForegroundColor Cyan
            
            $daysInput = Read-Host "Количество дней"
            
            if ([string]::IsNullOrWhiteSpace($daysInput)) {
                Write-Host "[-] Количество дней не может быть пустым!" -ForegroundColor Red
                continue
            }
            
            # Проверка на число
            if (-not [int]::TryParse($daysInput, [ref]$null)) {
                Write-Host "[-] Введите корректное число!" -ForegroundColor Red
                continue
            }
            
            $days = [int]$daysInput
            
            if ($days -lt 1 -or $days -gt 365) {
                Write-Host "[-] Количество дней должно быть от 1 до 365!" -ForegroundColor Red
                continue
            }
            
            break
        } while ($true)

        # Установка параметра в реестре
        Write-Host "[*] Установка параметра FlightSettingsMaxPauseDays = $days..." -ForegroundColor Cyan
        
        Set-ItemProperty -Path $registryPath -Name "FlightSettingsMaxPauseDays" -Value $days -Type DWord -Force
        Write-Host "[+] Параметр успешно установлен" -ForegroundColor Green

        # Дополнительные настройки для лучшего контроля обновлений
        Write-Host "[*] Применение дополнительных настроек..." -ForegroundColor Cyan
        
        # Установка периода отложения для качественных обновлений
        Set-ItemProperty -Path $registryPath -Name "PauseQualityUpdatesStartTime" -Value (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ") -Force
        Set-ItemProperty -Path $registryPath -Name "PauseQualityUpdatesEndTime" -Value (Get-Date).AddDays($days).ToString("yyyy-MM-ddTHH:mm:ssZ") -Force
        
        # Установка периода отложения для функциональных обновлений
        Set-ItemProperty -Path $registryPath -Name "PauseFeatureUpdatesStartTime" -Value (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ") -Force
        Set-ItemProperty -Path $registryPath -Name "PauseFeatureUpdatesEndTime" -Value (Get-Date).AddDays($days).ToString("yyyy-MM-ddTHH:mm:ssZ") -Force

        Write-Host "[+] Дополнительные настройки применены" -ForegroundColor Green

        # Проверка установленных значений
        Write-Host "[*] Проверка установленных настроек..." -ForegroundColor Cyan
        
        try {
            $maxPauseDays = Get-ItemProperty -Path $registryPath -Name "FlightSettingsMaxPauseDays" -ErrorAction Stop
            if ($maxPauseDays.FlightSettingsMaxPauseDays -eq $days) {
                Write-Host "[+] Проверка успешна: FlightSettingsMaxPauseDays = $($maxPauseDays.FlightSettingsMaxPauseDays)" -ForegroundColor Green
            } else {
                Write-Host "[-] Ошибка: значение не соответствует заданному" -ForegroundColor Red
            }
        } catch {
            Write-Host "[-] Ошибка при проверке настроек" -ForegroundColor Red
        }

        # Информация о результате
        Write-Host "[+] ========================================" -ForegroundColor Green
        Write-Host "[+]       НАСТРОЙКА ВЫПОЛНЕНА УСПЕШНО!"       -ForegroundColor Green
        Write-Host "[+] ========================================" -ForegroundColor Green
        Write-Host "[+] Обновления отложены на: $days дней" -ForegroundColor White
        Write-Host "[+] Дата окончания: $((Get-Date).AddDays($days).ToString('dd.MM.yyyy'))" -ForegroundColor White
        Write-Host "[+] Путь в реестре: $registryPath" -ForegroundColor White
        
        Write-Host "[!] Примечание:" -ForegroundColor Yellow
        Write-Host "    - Настройки вступят в силу после перезагрузки" -ForegroundColor Yellow
        Write-Host "    - Для отмены отложения удалите созданные записи из реестра" -ForegroundColor Yellow

    } catch {
        Write-Host "[-] ОШИБКА: $_" -ForegroundColor Red
        Write-Host "[-] Не удалось применить настройки отложения обновлений" -ForegroundColor Red
    }

    Pause
}

# Основной цикл
while ($true) {
    Show-ScriptsMenu
    $choice = Read-Host
    
    switch ($choice) {
        '1' { Postpone-WindowsUpdates }
        '2' {
            Write-Host ">> Запуск..." -ForegroundColor Yellow
            iex (irm "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/test.ps1")
        }
        '0' {
            Write-Host "Возврат в главное меню..." -ForegroundColor Green
            try {
                $menuScript = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/menu.ps1" -UseBasicParsing
                Invoke-Expression $menuScript.Content
            } catch {
                Write-Host "[!] Не удалось загрузить главное меню" -ForegroundColor Red
            }
            return
        }
        default {
            Write-Host "Неверный выбор" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
