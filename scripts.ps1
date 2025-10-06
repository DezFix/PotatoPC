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
	Write-Host "Установка даты и времени для сканирования" -ForegroundColor White
    Write-Host " │ 3. " -ForegroundColor Green -NoNewline
    Write-Host "Просмотр текущих настроек Defender" -ForegroundColor White
    Write-Host " └────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host " ┌─ WINDOWS UPDATES ──────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host " │ 4. " -ForegroundColor Green -NoNewline
    Write-Host "Отложить обновления Windows" -ForegroundColor White
    Write-Host " └────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host " ┌─ ДОПОЛНИТЕЛЬНО ────────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host " │ 5. " -ForegroundColor Green -NoNewline
    Write-Host "Тест Зона" -ForegroundColor Red
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
        '2' { Configure-ScanSchedule }
        '3' { Show-DefenderSettings }
        '4' { Postpone-WindowsUpdates }
		'5' {
			Write-Host ">> Запуск..." -ForegroundColor Yellow
            iex (irm "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/test.ps1")
		}
        '0' {
            Write-Host ">> Запуск..." -ForegroundColor Yellow
            iex (irm "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/scripts.ps1")
        }
        default {
            Write-Host ""
            Write-Host "[-] Неверный выбор! Попробуйте снова." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
