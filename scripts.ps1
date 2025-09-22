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
    Write-Host "Изменить реестр для долгосрочного отложения"
    
    Write-Host ""
    Write-Host " 0. " -ForegroundColor Red -NoNewline
    Write-Host "Назад в главное меню"
    
    Write-Host ""
    Write-Host "Выберите опцию: " -NoNewline -ForegroundColor White
}

# Функция отложения обновлений Windows
function Postpone-WindowsUpdates {
    Write-Host "`n[!] Отложение обновлений Windows" -ForegroundColor Yellow
    Write-Host "[!] Изменение настроек реестра для приостановки обновлений" -ForegroundColor Yellow

    # Проверка прав администратора
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "[-] Требуются права администратора!" -ForegroundColor Red
        Pause
        return
    }

    Write-Host "`n[+] Начинаем настройку отложения обновлений..." -ForegroundColor Green

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
            Write-Host "`n[*] Введите количество дней для отложения обновлений:" -ForegroundColor Cyan
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
        Write-Host "`n[*] Установка параметра FlightSettingsMaxPauseDays = $days..." -ForegroundColor Cyan
        
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
        Write-Host "`n[*] Проверка установленных настроек..." -ForegroundColor Cyan
        
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
        Write-Host "`n[+] ========================================" -ForegroundColor Green
        Write-Host "[+] НАСТРОЙКА ВЫПОЛНЕНА УСПЕШНО!" -ForegroundColor Green
        Write-Host "[+] ========================================" -ForegroundColor Green
        Write-Host "[+] Обновления отложены на: $days дней" -ForegroundColor White
        Write-Host "[+] Дата окончания: $((Get-Date).AddDays($days).ToString('dd.MM.yyyy'))" -ForegroundColor White
        Write-Host "[+] Путь в реестре: $registryPath" -ForegroundColor White
        
        Write-Host "`n[!] Примечание:" -ForegroundColor Yellow
        Write-Host "    - Настройки вступят в силу после перезагрузки" -ForegroundColor Yellow
        Write-Host "    - Для отмены отложения удалите созданные записи из реестра" -ForegroundColor Yellow

    } catch {
        Write-Host "`n[-] ОШИБКА: $_" -ForegroundColor Red
        Write-Host "[-] Не удалось применить настройки отложения обновлений" -ForegroundColor Red
    }

# Функция для изменения реестра для долгосрочного отложения обновлений
function Modify-UpdateRegistryForLongTerm {
    Write-Host "`n[!] Изменение реестра для долгосрочного отложения обновлений" -ForegroundColor Yellow
    Write-Host "[!] Работа с дополнительными ключами реестра Windows Update" -ForegroundColor Yellow

    # Проверка прав администратора
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "[-] Требуются права администратора!" -ForegroundColor Red
        Pause
        return
    }

    Write-Host "`n[+] Начинаем изменение дополнительных настроек реестра..." -ForegroundColor Green

    try {
        # Дополнительные пути реестра для расширенного контроля обновлений
        $additionalPaths = @{
            "WindowsUpdate" = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
            "AU" = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
            "DeliveryOptimization" = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
        }

        # Ввод количества дней для расширенного отложения
        do {
            Write-Host "`n[*] Введите количество дней для расширенного отложения обновлений:" -ForegroundColor Cyan
            Write-Host "[*] Для долгосрочного отложения рекомендуется: 90-730 дней" -ForegroundColor Cyan
            Write-Host "[*] Максимум: 730 дней (2 года)" -ForegroundColor Cyan
            
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
            
            if ($days -lt 1 -or $days -gt 730) {
                Write-Host "[-] Количество дней должно быть от 1 до 730!" -ForegroundColor Red
                continue
            }
            
            break
        } while ($true)

        # Создание и настройка ключей реестра
        foreach ($pathName in $additionalPaths.Keys) {
            $path = $additionalPaths[$pathName]
            
            Write-Host "`n[*] Обработка ключа: $pathName..." -ForegroundColor Cyan
            
            # Проверка существования ключа
            if (-not (Test-Path $path)) {
                Write-Host "[*] Создание ключа реестра: $path" -ForegroundColor Yellow
                New-Item -Path $path -Force | Out-Null
                Write-Host "[+] Ключ создан" -ForegroundColor Green
            } else {
                Write-Host "[+] Ключ уже существует: $path" -ForegroundColor Green
            }
        }

        # Настройка параметров Windows Update
        $windowsUpdatePath = $additionalPaths["WindowsUpdate"]
        Write-Host "`n[*] Настройка основных параметров Windows Update..." -ForegroundColor Cyan
        
        # Отключение автоматических обновлений драйверов
        Set-ItemProperty -Path $windowsUpdatePath -Name "ExcludeWUDriversInQualityUpdate" -Value 1 -Type DWord -Force
        
        # Установка периода отсрочки для качественных обновлений
        Set-ItemProperty -Path $windowsUpdatePath -Name "DeferQualityUpdatesPeriodInDays" -Value $days -Type DWord -Force
        
        # Установка периода отсрочки для функциональных обновлений  
        Set-ItemProperty -Path $windowsUpdatePath -Name "DeferFeatureUpdatesPeriodInDays" -Value $days -Type DWord -Force
        
        # Отключение автоматического перезапуска
        Set-ItemProperty -Path $windowsUpdatePath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord -Force

        Write-Host "[+] Основные параметры настроены" -ForegroundColor Green

        # Настройка параметров AU (Automatic Updates)
        $auPath = $additionalPaths["AU"]
        Write-Host "`n[*] Настройка параметров автоматических обновлений..." -ForegroundColor Cyan
        
        # Уведомлять перед загрузкой и установкой
        Set-ItemProperty -Path $auPath -Name "AUOptions" -Value 2 -Type DWord -Force
        
        # Отключение автоматического перезапуска
        Set-ItemProperty -Path $auPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord -Force
        
        # Настройка времени активных часов
        Set-ItemProperty -Path $auPath -Name "ActiveHoursStart" -Value 8 -Type DWord -Force
        Set-ItemProperty -Path $auPath -Name "ActiveHoursEnd" -Value 22 -Type DWord -Force

        Write-Host "[+] Параметры автоматических обновлений настроены" -ForegroundColor Green

        # Настройка Delivery Optimization
        $deliveryPath = $additionalPaths["DeliveryOptimization"]
        Write-Host "`n[*] Настройка оптимизации доставки..." -ForegroundColor Cyan
        
        # Отключение загрузки обновлений с других компьютеров
        Set-ItemProperty -Path $deliveryPath -Name "DODownloadMode" -Value 0 -Type DWord -Force

        Write-Host "[+] Оптимизация доставки настроена" -ForegroundColor Green

        # Дополнительные настройки в основном ключе UX Settings
        $uxSettingsPath = "HKLM:\Software\Microsoft\WindowsUpdate\UX\Settings"
        if (Test-Path $uxSettingsPath) {
            Write-Host "`n[*] Обновление настроек UX..." -ForegroundColor Cyan
            
            # Проверка и обновление существующего значения FlightSettingsMaxPauseDays
            try {
                $currentValue = Get-ItemProperty -Path $uxSettingsPath -Name "FlightSettingsMaxPauseDays" -ErrorAction SilentlyContinue
                if ($currentValue) {
                    Write-Host "[+] Найден существующий параметр FlightSettingsMaxPauseDays = $($currentValue.FlightSettingsMaxPauseDays)" -ForegroundColor Yellow
                    Write-Host "[*] Обновление значения на $days дней..." -ForegroundColor Cyan
                } else {
                    Write-Host "[*] Создание нового параметра FlightSettingsMaxPauseDays..." -ForegroundColor Cyan
                }
                
                Set-ItemProperty -Path $uxSettingsPath -Name "FlightSettingsMaxPauseDays" -Value $days -Type DWord -Force
                Write-Host "[+] Параметр FlightSettingsMaxPauseDays обновлен" -ForegroundColor Green
                
            } catch {
                Write-Host "[-] Ошибка при работе с FlightSettingsMaxPauseDays: $_" -ForegroundColor Red
            }
        }

        # Проверка всех установленных значений
        Write-Host "`n[*] Проверка установленных параметров..." -ForegroundColor Cyan
        
        $verificationResults = @()
        
        # Проверка основных параметров
        try {
            $deferQuality = (Get-ItemProperty -Path $windowsUpdatePath -Name "DeferQualityUpdatesPeriodInDays" -ErrorAction SilentlyContinue).DeferQualityUpdatesPeriodInDays
            $deferFeature = (Get-ItemProperty -Path $windowsUpdatePath -Name "DeferFeatureUpdatesPeriodInDays" -ErrorAction SilentlyContinue).DeferFeatureUpdatesPeriodInDays
            $flightSettings = (Get-ItemProperty -Path $uxSettingsPath -Name "FlightSettingsMaxPauseDays" -ErrorAction SilentlyContinue).FlightSettingsMaxPauseDays
            
            $verificationResults += "[+] DeferQualityUpdatesPeriodInDays: $deferQuality"
            $verificationResults += "[+] DeferFeatureUpdatesPeriodInDays: $deferFeature"  
            $verificationResults += "[+] FlightSettingsMaxPauseDays: $flightSettings"
            
        } catch {
            $verificationResults += "[-] Ошибка при проверке некоторых параметров"
        }

        # Вывод результатов
        Write-Host "`n[+] ========================================" -ForegroundColor Green
        Write-Host "[+] РАСШИРЕННАЯ НАСТРОЙКА ВЫПОЛНЕНА!" -ForegroundColor Green  
        Write-Host "[+] ========================================" -ForegroundColor Green
        Write-Host "[+] Обновления отложены на: $days дней" -ForegroundColor White
        Write-Host "[+] Дата окончания отсрочки: $((Get-Date).AddDays($days).ToString('dd.MM.yyyy'))" -ForegroundColor White
        
        Write-Host "`n[+] Установленные параметры:" -ForegroundColor Cyan
        foreach ($result in $verificationResults) {
            Write-Host $result -ForegroundColor White
        }
        
        Write-Host "`n[!] Примечания:" -ForegroundColor Yellow
        Write-Host "    - Изменения вступят в силу после перезагрузки системы" -ForegroundColor Yellow
        Write-Host "    - Обновления безопасности могут устанавливаться принудительно" -ForegroundColor Yellow
        Write-Host "    - Для полной отмены удалите созданные ключи из реестра" -ForegroundColor Yellow
        Write-Host "    - Рекомендуется периодически проверять критические обновления" -ForegroundColor Yellow

    } catch {
        Write-Host "`n[-] ОШИБКА: $_" -ForegroundColor Red
        Write-Host "[-] Не удалось применить расширенные настройки реестра" -ForegroundColor Red
    }

    Pause
}

# Основной цикл
while ($true) {
    Show-ScriptsMenu
    $choice = Read-Host
    
    switch ($choice) {
        '1' { Postpone-WindowsUpdates }
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
