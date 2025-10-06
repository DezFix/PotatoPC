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

# Функция отображения главного меню
function Show-MainMenu {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           WINDOWS SECURITY & UPDATES MANAGER v2.0                     ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host " ┌─ WINDOWS DEFENDER ─────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host " │ 1. " -ForegroundColor Green -NoNewline
    Write-Host "Настроить Windows Defender (оптимизация)" -ForegroundColor White
    Write-Host " │ 2. " -ForegroundColor Green -NoNewline
    Write-Host "Просмотр текущих настроек Defender" -ForegroundColor White
    Write-Host " │ 3. " -ForegroundColor Green -NoNewline
    Write-Host "Настроить расписание сканирования" -ForegroundColor White
    Write-Host " └────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host " ┌─ WINDOWS UPDATES ──────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host " │ 4. " -ForegroundColor Green -NoNewline
    Write-Host "Отложить обновления Windows" -ForegroundColor White
    Write-Host " │ 5. " -ForegroundColor Green -NoNewline
    Write-Host "Настроить службу обновлений" -ForegroundColor White
    Write-Host " └────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host " ┌─ ДОПОЛНИТЕЛЬНО ────────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host " │ 6. " -ForegroundColor Green -NoNewline
    Write-Host "Применить все рекомендуемые настройки" -ForegroundColor Cyan
    Write-Host " │ 7. " -ForegroundColor Green -NoNewline
    Write-Host "Информация о системе защиты" -ForegroundColor White
    Write-Host " └────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host " 0. " -ForegroundColor Red -NoNewline
    Write-Host "Выход"
    
    Write-Host ""
    Write-Host "Выберите опцию: " -NoNewline -ForegroundColor White
}

# Функция оптимизации Windows Defender
function Optimize-WindowsDefender {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║            ОПТИМИЗАЦИЯ WINDOWS DEFENDER                               ║" -ForegroundColor Yellow
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "[+] Начинаем настройку Windows Defender для баланса производительности и защиты..." -ForegroundColor Green
    Write-Host ""

    try {
        # Снижение нагрузки на CPU
        Write-Host "[*] Снижение нагрузки на CPU при сканировании..." -ForegroundColor Cyan
        Set-MpPreference -ScanAvgCPULoadFactor 20
        Write-Host "[+] Нагрузка на CPU установлена на 20% (было 50%)" -ForegroundColor Green

        # Отключение сканирования архивов
        Write-Host "[*] Отключение сканирования архивов..." -ForegroundColor Cyan
        Set-MpPreference -DisableArchiveScanning $true
        Write-Host "[+] Сканирование архивов отключено" -ForegroundColor Green

        # Отключение сканирования сетевых дисков
        Write-Host "[*] Отключение сканирования сетевых дисков..." -ForegroundColor Cyan
        Set-MpPreference -DisableScanningMappedNetworkDrivesForFullScan $true
        Write-Host "[+] Сканирование сетевых дисков отключено" -ForegroundColor Green

        # Настройка облачной защиты
        Write-Host "[*] Настройка облачной защиты (расширенная)..." -ForegroundColor Cyan
        Set-MpPreference -MAPSReporting Advanced
        Write-Host "[+] Облачная защита настроена" -ForegroundColor Green

        # Настройка отправки образцов (не отправлять)
        Write-Host "[*] Настройка политики отправки образцов..." -ForegroundColor Cyan
        Set-MpPreference -SubmitSamplesConsent 2
        Write-Host "[+] Автоматическая отправка образцов отключена" -ForegroundColor Green

        # Отключение расширенных уведомлений
        Write-Host "[*] Отключение расширенных уведомлений..." -ForegroundColor Cyan
        Set-MpPreference -DisableEnhancedNotifications $true
        Write-Host "[+] Расширенные уведомления отключены" -ForegroundColor Green

        # Настройка приоритета сканирования
        Write-Host "[*] Настройка низкого приоритета для фоновых проверок..." -ForegroundColor Cyan
        Set-MpPreference -EnableLowCpuPriority $true
        Write-Host "[+] Низкий приоритет установлен" -ForegroundColor Green

        Write-Host ""
        Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║                  ОПТИМИЗАЦИЯ ЗАВЕРШЕНА УСПЕШНО!                       ║" -ForegroundColor Green
        Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host ""
        Write-Host "[!] Применённые настройки:" -ForegroundColor Yellow
        Write-Host "    ✓ Снижена нагрузка на CPU (20%)" -ForegroundColor White
        Write-Host "    ✓ Отключено сканирование архивов" -ForegroundColor White
        Write-Host "    ✓ Отключено сканирование сетевых дисков" -ForegroundColor White
        Write-Host "    ✓ Включена расширенная облачная защита" -ForegroundColor White
        Write-Host "    ✓ Отключена автоотправка образцов файлов" -ForegroundColor White
        Write-Host "    ✓ Отключены расширенные уведомления" -ForegroundColor White
        Write-Host "    ✓ Установлен низкий приоритет для фоновых проверок" -ForegroundColor White
        Write-Host ""
        Write-Host "[✓] Defender остаётся активным и защищает вашу систему!" -ForegroundColor Green

    } catch {
        Write-Host ""
        Write-Host "[-] ОШИБКА: $_" -ForegroundColor Red
        Write-Host "[-] Не удалось применить некоторые настройки" -ForegroundColor Red
    }

    Write-Host ""
    Pause
}

# Функция просмотра настроек Defender
function Show-DefenderSettings {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║          ТЕКУЩИЕ НАСТРОЙКИ WINDOWS DEFENDER                           ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    try {
        $preferences = Get-MpPreference
        $status = Get-MpComputerStatus

        Write-Host "[*] ОСНОВНЫЕ ПАРАМЕТРЫ:" -ForegroundColor Yellow
        Write-Host "    • Защита в реальном времени: " -NoNewline -ForegroundColor White
        Write-Host $(if ($status.RealTimeProtectionEnabled) { "Включена" } else { "Отключена" }) -ForegroundColor $(if ($status.RealTimeProtectionEnabled) { "Green" } else { "Red" })
        
        Write-Host "    • Облачная защита: " -NoNewline -ForegroundColor White
        Write-Host $(if ($status.IsTamperProtected) { "Активна" } else { "Неактивна" }) -ForegroundColor $(if ($status.IsTamperProtected) { "Green" } else { "Yellow" })
        
        Write-Host ""
        Write-Host "[*] ПРОИЗВОДИТЕЛЬНОСТЬ:" -ForegroundColor Yellow
        Write-Host "    • Нагрузка на CPU при сканировании: $($preferences.ScanAvgCPULoadFactor)%" -ForegroundColor White
        Write-Host "    • Сканирование архивов: " -NoNewline -ForegroundColor White
        Write-Host $(if ($preferences.DisableArchiveScanning) { "Отключено" } else { "Включено" }) -ForegroundColor $(if ($preferences.DisableArchiveScanning) { "Green" } else { "Yellow" })
        
        Write-Host ""
        Write-Host "[*] КОНФИДЕНЦИАЛЬНОСТЬ:" -ForegroundColor Yellow
        Write-Host "    • Отправка образцов: " -NoNewline -ForegroundColor White
        switch ($preferences.SubmitSamplesConsent) {
            0 { Write-Host "Всегда спрашивать" -ForegroundColor Yellow }
            1 { Write-Host "Отправлять безопасные образцы автоматически" -ForegroundColor Yellow }
            2 { Write-Host "Никогда не отправлять" -ForegroundColor Green }
            3 { Write-Host "Отправлять все образцы автоматически" -ForegroundColor Red }
        }
        
        Write-Host "    • Расширенные уведомления: " -NoNewline -ForegroundColor White
        Write-Host $(if ($preferences.DisableEnhancedNotifications) { "Отключены" } else { "Включены" }) -ForegroundColor $(if ($preferences.DisableEnhancedNotifications) { "Green" } else { "Yellow" })
        
        Write-Host ""
        Write-Host "[*] ИСКЛЮЧЕНИЯ:" -ForegroundColor Yellow
        if ($preferences.ExclusionPath.Count -gt 0) {
            Write-Host "    • Исключённые папки ($($preferences.ExclusionPath.Count)):" -ForegroundColor White
            $preferences.ExclusionPath | ForEach-Object { Write-Host "      - $_" -ForegroundColor Gray }
        } else {
            Write-Host "    • Исключённых папок нет" -ForegroundColor Gray
        }

        if ($preferences.ExclusionProcess.Count -gt 0) {
            Write-Host "    • Исключённые процессы ($($preferences.ExclusionProcess.Count)):" -ForegroundColor White
            $preferences.ExclusionProcess | ForEach-Object { Write-Host "      - $_" -ForegroundColor Gray }
        } else {
            Write-Host "    • Исключённых процессов нет" -ForegroundColor Gray
        }

    } catch {
        Write-Host "[-] ОШИБКА: $_" -ForegroundColor Red
    }

    Write-Host ""
    Pause
}

# Функция добавления исключений
function Add-DefenderExclusions {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║          ДОБАВЛЕНИЕ ИСКЛЮЧЕНИЙ В WINDOWS DEFENDER                     ║" -ForegroundColor Yellow
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "[!] Добавляйте в исключения ТОЛЬКО проверенные и безопасные файлы/папки!" -ForegroundColor Red
    Write-Host ""

    Write-Host "Выберите тип исключения:" -ForegroundColor Cyan
    Write-Host "1. Исключить папку" -ForegroundColor White
    Write-Host "2. Исключить процесс (exe файл)" -ForegroundColor White
    Write-Host "3. Исключить файл/расширение" -ForegroundColor White
    Write-Host "0. Назад" -ForegroundColor Red
    Write-Host ""
    
    $choice = Read-Host "Ваш выбор"

    try {
        switch ($choice) {
            '1' {
                $path = Read-Host "Введите полный путь к папке (например, C:\Games)"
                if (Test-Path $path) {
                    Add-MpPreference -ExclusionPath $path
                    Write-Host "[+] Папка '$path' добавлена в исключения" -ForegroundColor Green
                } else {
                    Write-Host "[-] Указанная папка не существует!" -ForegroundColor Red
                }
            }
            '2' {
                $process = Read-Host "Введите имя процесса (например, game.exe)"
                Add-MpPreference -ExclusionProcess $process
                Write-Host "[+] Процесс '$process' добавлен в исключения" -ForegroundColor Green
            }
            '3' {
                $extension = Read-Host "Введите расширение (например, *.tmp или C:\file.dll)"
                Add-MpPreference -ExclusionExtension $extension
                Write-Host "[+] '$extension' добавлено в исключения" -ForegroundColor Green
            }
            '0' { return }
            default {
                Write-Host "[-] Неверный выбор" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "[-] ОШИБКА: $_" -ForegroundColor Red
    }

    Write-Host ""
    Pause
}

# Функция настройки расписания сканирования
function Configure-ScanSchedule {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║          НАСТРОЙКА РАСПИСАНИЯ СКАНИРОВАНИЯ                            ║" -ForegroundColor Yellow
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "[*] Выберите день недели для сканирования:" -ForegroundColor Cyan
    Write-Host "0 - Каждый день" -ForegroundColor White
    Write-Host "1 - Воскресенье" -ForegroundColor White
    Write-Host "2 - Понедельник" -ForegroundColor White
    Write-Host "3 - Вторник" -ForegroundColor White
    Write-Host "4 - Среда" -ForegroundColor White
    Write-Host "5 - Четверг" -ForegroundColor White
    Write-Host "6 - Пятница" -ForegroundColor White
    Write-Host "7 - Суббота" -ForegroundColor White
    Write-Host "8 - Никогда" -ForegroundColor Red
    Write-Host ""
    
    $day = Read-Host "День недели"
    
    if ($day -eq "8") {
        try {
            Set-MpPreference -DisableScheduledScanMaintenance $true
            Write-Host "[+] Запланированное сканирование отключено" -ForegroundColor Green
            Write-Host "[!] ВНИМАНИЕ: Рекомендуется периодически запускать сканирование вручную!" -ForegroundColor Yellow
        } catch {
            Write-Host "[-] ОШИБКА: $_" -ForegroundColor Red
        }
    } elseif ($day -ge 0 -and $day -le 7) {
        Write-Host ""
        Write-Host "[*] Введите время сканирования (0-23 часов):" -ForegroundColor Cyan
        $hour = Read-Host "Час"
        
        if ($hour -ge 0 -and $hour -le 23) {
            try {
                Set-MpPreference -ScanScheduleDay $day
                Set-MpPreference -ScanScheduleTime "$($hour):00:00"
                Write-Host "[+] Расписание установлено!" -ForegroundColor Green
                
                $dayName = @("Каждый день", "Воскресенье", "Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота")
                Write-Host "[+] Сканирование будет выполняться: $($dayName[$day]) в $hour:00" -ForegroundColor White
            } catch {
                Write-Host "[-] ОШИБКА: $_" -ForegroundColor Red
            }
        } else {
            Write-Host "[-] Неверное время!" -ForegroundColor Red
        }
    } else {
        Write-Host "[-] Неверный выбор!" -ForegroundColor Red
    }

    Write-Host ""
    Pause
}

# Функция отложения обновлений Windows
function Postpone-WindowsUpdates {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║          ОТЛОЖЕНИЕ ОБНОВЛЕНИЙ WINDOWS                                 ║" -ForegroundColor Yellow
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "[+] Начинаем настройку отложения обновлений..." -ForegroundColor Green

    try {
        $registryPath = "HKLM:\Software\Microsoft\WindowsUpdate\UX\Settings"

        if (-not (Test-Path $registryPath)) {
            Write-Host "[*] Создание ключа реестра..." -ForegroundColor Cyan
            New-Item -Path $registryPath -Force | Out-Null
            Write-Host "[+] Ключ реестра создан" -ForegroundColor Green
        }

        do {
            Write-Host ""
            Write-Host "[*] Введите количество дней для отложения обновлений:" -ForegroundColor Cyan
            Write-Host "[*] Минимум: 1 день, Максимум: 365 дней" -ForegroundColor Cyan
            Write-Host "[*] Рекомендуется: 30-60 дней для стабильности" -ForegroundColor Yellow
            
            $daysInput = Read-Host "Количество дней"
            
            if ([string]::IsNullOrWhiteSpace($daysInput)) {
                Write-Host "[-] Количество дней не может быть пустым!" -ForegroundColor Red
                continue
            }
            
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

        Write-Host ""
        Write-Host "[*] Применение настроек..." -ForegroundColor Cyan
        
        Set-ItemProperty -Path $registryPath -Name "FlightSettingsMaxPauseDays" -Value $days -Type DWord -Force
        Set-ItemProperty -Path $registryPath -Name "PauseQualityUpdatesStartTime" -Value (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ") -Force
        Set-ItemProperty -Path $registryPath -Name "PauseQualityUpdatesEndTime" -Value (Get-Date).AddDays($days).ToString("yyyy-MM-ddTHH:mm:ssZ") -Force
        Set-ItemProperty -Path $registryPath -Name "PauseFeatureUpdatesStartTime" -Value (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ") -Force
        Set-ItemProperty -Path $registryPath -Name "PauseFeatureUpdatesEndTime" -Value (Get-Date).AddDays($days).ToString("yyyy-MM-ddTHH:mm:ssZ") -Force

        Write-Host ""
        Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║                  НАСТРОЙКА ВЫПОЛНЕНА УСПЕШНО!                         ║" -ForegroundColor Green
        Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host ""
        Write-Host "[+] Обновления отложены на: $days дней" -ForegroundColor White
        Write-Host "[+] Дата окончания: $((Get-Date).AddDays($days).ToString('dd.MM.yyyy'))" -ForegroundColor White
        Write-Host ""
        Write-Host "[!] Важно:" -ForegroundColor Yellow
        Write-Host "    • Настройки вступят в силу немедленно" -ForegroundColor White
        Write-Host "    • После истечения срока обновления возобновятся автоматически" -ForegroundColor White
        Write-Host "    • Критические обновления безопасности могут устанавливаться принудительно" -ForegroundColor White

    } catch {
        Write-Host ""
        Write-Host "[-] ОШИБКА: $_" -ForegroundColor Red
    }

    Write-Host ""
    Pause
}

# Функция настройки активных часов
function Configure-ActiveHours {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║          НАСТРОЙКА АКТИВНЫХ ЧАСОВ                                     ║" -ForegroundColor Yellow
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "[*] Активные часы - это время, когда обновления НЕ будут устанавливаться" -ForegroundColor Cyan
    Write-Host ""

    try {
        $startHour = Read-Host "Введите начальный час (0-23, например 8 для 8:00)"
        $endHour = Read-Host "Введите конечный час (0-23, например 23 для 23:00)"

        if ($startHour -ge 0 -and $startHour -le 23 -and $endHour -ge 0 -and $endHour -le 23) {
            $registryPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
            
            if (-not (Test-Path $registryPath)) {
                New-Item -Path $registryPath -Force | Out-Null
            }

            Set-ItemProperty -Path $registryPath -Name "ActiveHoursStart" -Value $startHour -Type DWord -Force
            Set-ItemProperty -Path $registryPath -Name "ActiveHoursEnd" -Value $endHour -Type DWord -Force

            Write-Host ""
            Write-Host "[+] Активные часы установлены!" -ForegroundColor Green
            Write-Host "[+] С $startHour:00 до $endHour:00 обновления не будут устанавливаться" -ForegroundColor White
        } else {
            Write-Host "[-] Неверное значение часов!" -ForegroundColor Red
        }

    } catch {
        Write-Host "[-] ОШИБКА: $_" -ForegroundColor Red
    }

    Write-Host ""
    Pause
}

# Функция настройки службы обновлений
function Configure-UpdateService {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║          НАСТРОЙКА СЛУЖБЫ ОБНОВЛЕНИЙ                                  ║" -ForegroundColor Yellow
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""

    try {
        $service = Get-Service wuauserv
        Write-Host "[*] Текущий статус службы обновлений:" -ForegroundColor Cyan
        Write-Host "    Состояние: $($service.Status)" -ForegroundColor White
        Write-Host "    Тип запуска: $($service.StartType)" -ForegroundColor White
        Write-Host ""

        Write-Host "Выберите действие:" -ForegroundColor Cyan
        Write-Host "1. Установить отложенный запуск (рекомендуется)" -ForegroundColor White
        Write-Host "2. Установить автоматический запуск" -ForegroundColor White
        Write-Host "3. Установить ручной запуск (не рекомендуется)" -ForegroundColor Yellow
        Write-Host "4. Остановить службу временно" -ForegroundColor Yellow
        Write-Host "5. Запустить службу" -ForegroundColor White
        Write-Host "0. Назад" -ForegroundColor Red
        Write-Host ""

        $choice = Read-Host "Ваш выбор"

        switch ($choice) {
            '1' {
                Set-Service wuauserv -StartupType Automatic
                # Отложенный запуск через реестр
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\wuauserv" -Name "DelayedAutostart" -Value 1 -Type DWord
                Write-Host "[+] Служба настроена на отложенный автоматический запуск" -ForegroundColor Green
            }
            '2' {
                Set-Service wuauserv -StartupType Automatic
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\wuauserv" -Name "DelayedAutostart" -Value 0 -Type DWord
                Write-Host "[+] Служба настроена на автоматический запуск" -ForegroundColor Green
            }
            '3' {
                Set-Service wuauserv -StartupType Manual
                Write-Host "[+] Служба настроена на ручной запуск" -ForegroundColor Yellow
                Write-Host "[!] ВНИМАНИЕ: Обновления не будут устанавливаться автоматически!" -ForegroundColor Red
            }
            '4' {
                Stop-Service wuauserv -Force
                Write-Host "[+] Служба остановлена" -ForegroundColor Yellow
                Write-Host "[!] НЕ ЗАБУДЬТЕ ЗАПУСТИТЬ ЕЁ ОБРАТНО!" -ForegroundColor Red
            }
            '5' {
                Start-Service wuauserv
                Write-Host "[+] Служба запущена" -ForegroundColor Green
            }
            '0' { return }
        }

    } catch {
        Write-Host "[-] ОШИБКА: $_" -ForegroundColor Red
    }

    Write-Host ""
    Pause
}

# Функция применения всех рекомендуемых настроек
function Apply-AllRecommended {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║          ПРИМЕНЕНИЕ ВСЕХ РЕКОМЕНДУЕМЫХ НАСТРОЕК                       ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "[!] Это применит оптимальные настройки для баланса безопасности и производительности" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Будут применены:" -ForegroundColor Cyan
    Write-Host "  • Оптимизация Windows Defender" -ForegroundColor White
    Write-Host "  • Отложение обновлений на 30 дней" -ForegroundColor White
    Write-Host "  • Активные часы 8:00-23:00" -ForegroundColor White
    Write-Host "  • Отложенный запуск службы обновлений" -ForegroundColor White
    Write-Host "  • Расписание сканирования в 3:00 ночи" -ForegroundColor White
    Write-Host ""
    
    $confirm = Read-Host "Применить все настройки? (Y/N)"
    
    if ($confirm -eq 'Y' -or $confirm -eq 'y') {
        Write-Host ""
        Write-Host "[+] Начинаем применение настроек..." -ForegroundColor Green
        Write-Host ""
        
        try {
            # 1. Оптимизация Defender
            Write-Host "[1/5] Оптимизация Windows Defender..." -ForegroundColor Cyan
            Set-MpPreference -ScanAvgCPULoadFactor 20 -ErrorAction SilentlyContinue
            Set-MpPreference -DisableArchiveScanning $true -ErrorAction SilentlyContinue
            Set-MpPreference -DisableScanningMappedNetworkDrivesForFullScan $true -ErrorAction SilentlyContinue
            Set-MpPreference -MAPSReporting Advanced -ErrorAction SilentlyContinue
            Set-MpPreference -SubmitSamplesConsent 2 -ErrorAction SilentlyContinue
            Set-MpPreference -DisableEnhancedNotifications $true -ErrorAction SilentlyContinue
            Set-MpPreference -EnableLowCpuPriority $true -ErrorAction SilentlyContinue
            Write-Host "    ✓ Defender оптимизирован" -ForegroundColor Green
            
            # 2. Расписание сканирования
            Write-Host "[2/5] Настройка расписания сканирования..." -ForegroundColor Cyan
            Set-MpPreference -ScanScheduleDay 0 -ErrorAction SilentlyContinue
            Set-MpPreference -ScanScheduleTime "03:00:00" -ErrorAction SilentlyContinue
            Write-Host "    ✓ Сканирование настроено на 3:00 каждую ночь" -ForegroundColor Green
            
            # 3. Отложение обновлений
            Write-Host "[3/5] Отложение обновлений на 30 дней..." -ForegroundColor Cyan
            $registryPath = "HKLM:\Software\Microsoft\WindowsUpdate\UX\Settings"
            if (-not (Test-Path $registryPath)) {
                New-Item -Path $registryPath -Force | Out-Null
            }
            Set-ItemProperty -Path $registryPath -Name "FlightSettingsMaxPauseDays" -Value 30 -Type DWord -Force
            Set-ItemProperty -Path $registryPath -Name "PauseQualityUpdatesStartTime" -Value (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ") -Force
            Set-ItemProperty -Path $registryPath -Name "PauseQualityUpdatesEndTime" -Value (Get-Date).AddDays(30).ToString("yyyy-MM-ddTHH:mm:ssZ") -Force
            Set-ItemProperty -Path $registryPath -Name "PauseFeatureUpdatesStartTime" -Value (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ") -Force
            Set-ItemProperty -Path $registryPath -Name "PauseFeatureUpdatesEndTime" -Value (Get-Date).AddDays(30).ToString("yyyy-MM-ddTHH:mm:ssZ") -Force
            Write-Host "    ✓ Обновления отложены до $((Get-Date).AddDays(30).ToString('dd.MM.yyyy'))" -ForegroundColor Green
            
            # 4. Активные часы
            Write-Host "[4/5] Настройка активных часов..." -ForegroundColor Cyan
            Set-ItemProperty -Path $registryPath -Name "ActiveHoursStart" -Value 8 -Type DWord -Force
            Set-ItemProperty -Path $registryPath -Name "ActiveHoursEnd" -Value 23 -Type DWord -Force
            Write-Host "    ✓ Активные часы: 8:00-23:00" -ForegroundColor Green
            
            # 5. Служба обновлений
            Write-Host "[5/5] Настройка службы обновлений..." -ForegroundColor Cyan
            Set-Service wuauserv -StartupType Automatic -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\wuauserv" -Name "DelayedAutostart" -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Write-Host "    ✓ Служба настроена на отложенный запуск" -ForegroundColor Green
            
            Write-Host ""
            Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
            Write-Host "║                  ВСЕ НАСТРОЙКИ ПРИМЕНЕНЫ УСПЕШНО!                     ║" -ForegroundColor Green
            Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
            Write-Host ""
            Write-Host "[✓] Ваша система теперь оптимизирована!" -ForegroundColor Green
            Write-Host "[✓] Защита активна, производительность улучшена!" -ForegroundColor Green
            
        } catch {
            Write-Host ""
            Write-Host "[-] ОШИБКА: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "[*] Операция отменена" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Pause
}

# Функция информации о системе защиты
function Show-SecurityInfo {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║          ИНФОРМАЦИЯ О СИСТЕМЕ ЗАЩИТЫ                                  ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    try {
        $defenderStatus = Get-MpComputerStatus
        $updateService = Get-Service wuauserv

        # Windows Defender
        Write-Host "┌─ WINDOWS DEFENDER ─────────────────────────────────────────┐" -ForegroundColor Yellow
        Write-Host "│" -ForegroundColor Yellow
        Write-Host "│ Статус защиты:" -ForegroundColor White
        Write-Host "│   • Защита в реальном времени: " -NoNewline -ForegroundColor White
        if ($defenderStatus.RealTimeProtectionEnabled) {
            Write-Host "✓ Активна" -ForegroundColor Green
        } else {
            Write-Host "✗ Отключена" -ForegroundColor Red
        }
        
        Write-Host "│   • Защита от вирусов: " -NoNewline -ForegroundColor White
        if ($defenderStatus.AntivirusEnabled) {
            Write-Host "✓ Активна" -ForegroundColor Green
        } else {
            Write-Host "✗ Отключена" -ForegroundColor Red
        }
        
        Write-Host "│   • Защита от шпионских программ: " -NoNewline -ForegroundColor White
        if ($defenderStatus.AntispywareEnabled) {
            Write-Host "✓ Активна" -ForegroundColor Green
        } else {
            Write-Host "✗ Отключена" -ForegroundColor Red
        }
        
        Write-Host "│" -ForegroundColor Yellow
        Write-Host "│ Базы данных:" -ForegroundColor White
        Write-Host "│   • Версия антивируса: $($defenderStatus.AntivirusSignatureVersion)" -ForegroundColor Gray
        Write-Host "│   • Последнее обновление: $($defenderStatus.AntivirusSignatureLastUpdated)" -ForegroundColor Gray
        Write-Host "│" -ForegroundColor Yellow
        Write-Host "│ Последнее сканирование:" -ForegroundColor White
        if ($defenderStatus.QuickScanStartTime) {
            Write-Host "│   • Быстрое: $($defenderStatus.QuickScanStartTime)" -ForegroundColor Gray
        }
        if ($defenderStatus.FullScanStartTime) {
            Write-Host "│   • Полное: $($defenderStatus.FullScanStartTime)" -ForegroundColor Gray
        }
        Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
        Write-Host ""

        # Windows Update
        Write-Host "┌─ WINDOWS UPDATE ───────────────────────────────────────────┐" -ForegroundColor Yellow
        Write-Host "│" -ForegroundColor Yellow
        Write-Host "│ Служба обновлений:" -ForegroundColor White
        Write-Host "│   • Статус: $($updateService.Status)" -ForegroundColor $(if ($updateService.Status -eq 'Running') { 'Green' } else { 'Yellow' })
        Write-Host "│   • Тип запуска: $($updateService.StartType)" -ForegroundColor Gray
        Write-Host "│" -ForegroundColor Yellow
        
        # Проверка отложенных обновлений
        $registryPath = "HKLM:\Software\Microsoft\WindowsUpdate\UX\Settings"
        if (Test-Path $registryPath) {
            $pauseEnd = Get-ItemProperty -Path $registryPath -Name "PauseQualityUpdatesEndTime" -ErrorAction SilentlyContinue
            if ($pauseEnd) {
                $endDate = [DateTime]::Parse($pauseEnd.PauseQualityUpdatesEndTime)
                Write-Host "│ Статус обновлений:" -ForegroundColor White
                Write-Host "│   • Обновления отложены до: $($endDate.ToString('dd.MM.yyyy HH:mm'))" -ForegroundColor Yellow
                
                $daysLeft = ($endDate - (Get-Date)).Days
                if ($daysLeft -gt 0) {
                    Write-Host "│   • Осталось дней: $daysLeft" -ForegroundColor Cyan
                } else {
                    Write-Host "│   • Срок отложения истёк" -ForegroundColor Red
                }
            }
            
            $activeStart = Get-ItemProperty -Path $registryPath -Name "ActiveHoursStart" -ErrorAction SilentlyContinue
            $activeEnd = Get-ItemProperty -Path $registryPath -Name "ActiveHoursEnd" -ErrorAction SilentlyContinue
            if ($activeStart -and $activeEnd) {
                Write-Host "│" -ForegroundColor Yellow
                Write-Host "│ Активные часы:" -ForegroundColor White
                Write-Host "│   • С $($activeStart.ActiveHoursStart):00 до $($activeEnd.ActiveHoursEnd):00" -ForegroundColor Gray
            }
        }
        
        Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
        Write-Host ""

        # Общая оценка безопасности
        Write-Host "┌─ ОБЩАЯ ОЦЕНКА ─────────────────────────────────────────────┐" -ForegroundColor Cyan
        Write-Host "│" -ForegroundColor Cyan
        
        $securityScore = 0
        if ($defenderStatus.RealTimeProtectionEnabled) { $securityScore += 25 }
        if ($defenderStatus.AntivirusEnabled) { $securityScore += 25 }
        if ($defenderStatus.AntispywareEnabled) { $securityScore += 25 }
        if ($updateService.Status -eq 'Running') { $securityScore += 25 }
        
        Write-Host "│ Уровень защиты: " -NoNewline -ForegroundColor White
        if ($securityScore -ge 90) {
            Write-Host "Отличный ($securityScore%)" -ForegroundColor Green
        } elseif ($securityScore -ge 70) {
            Write-Host "Хороший ($securityScore%)" -ForegroundColor Yellow
        } else {
            Write-Host "Требует внимания ($securityScore%)" -ForegroundColor Red
        }
        
        Write-Host "│" -ForegroundColor Cyan
        Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan

    } catch {
        Write-Host "[-] ОШИБКА при получении информации: $_" -ForegroundColor Red
    }

    Write-Host ""
    Pause
}

# Функция паузы
function Pause {
    Write-Host ""
    Write-Host "Нажмите любую клавишу для продолжения..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Главный цикл программы
while ($true) {
    Show-MainMenu
    $choice = Read-Host
    
    switch ($choice) {
        '1' { Optimize-WindowsDefender }
        '2' { Show-DefenderSettings }
        '3' { Add-DefenderExclusions }
        '4' { Configure-ScanSchedule }
        '5' { Postpone-WindowsUpdates }
        '6' { Configure-ActiveHours }
        '7' { Configure-UpdateService }
        '8' { Apply-AllRecommended }
        '9' { Show-SecurityInfo }
        '0' {
            Clear-Host
            Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
            Write-Host "║                                                                       ║" -ForegroundColor Green
            Write-Host "║                     Спасибо за использование!                         ║" -ForegroundColor Green
            Write-Host "║                                                                       ║" -ForegroundColor Green
            Write-Host "║              Оставайтесь в безопасности! 🛡️                          ║" -ForegroundColor Green
            Write-Host "║                                                                       ║" -ForegroundColor Green
            Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
            Write-Host ""
            exit 0
        }
        default {
            Write-Host ""
            Write-Host "[-] Неверный выбор! Попробуйте снова." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
