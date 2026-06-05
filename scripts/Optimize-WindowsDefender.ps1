# NAME: Windows Defender отпимизация
# DESC: Оптимизация Windows Defender для снижения нагрузки на CPU (с предупреждением о компромиссах безопасности)
# CATEGORY: Производительность
# ICON: 🛡️

#Requires -RunAsAdministrator

function Optimize-WindowsDefender {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║            ОПТИМИЗАЦИЯ WINDOWS DEFENDER                               ║" -ForegroundColor Yellow
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "[!] ВНИМАНИЕ: Для применения настроек должна быть отключена 'Защита от несанкционированного доступа' (Tamper Protection) в настройках Windows Security." -ForegroundColor Red
    Write-Host "[+] Начинаем настройку баланса производительности и защиты..." -ForegroundColor Green
    Write-Host ""

    try {
        # 1. Снижение нагрузки на CPU (по умолчанию 50, 20-30 - оптимальный компромисс)
        Write-Host "[*] Ограничение нагрузки на CPU при сканировании до 20%..." -ForegroundColor Cyan
        Set-MpPreference -ScanAvgCPULoadFactor 20 -ErrorAction Stop
        Write-Host "[+] Нагрузка на CPU ограничена" -ForegroundColor Green

        # 2. Отключение сканирования архивов (ВНИМАНИЕ: снижает защиту, но сильно экономит ресурсы)
        Write-Host "[*] Отключение сканирования содержимого архивов (ZIP, RAR и др.)..." -ForegroundColor Cyan
        Set-MpPreference -DisableArchiveScanning $true -ErrorAction Stop
        Write-Host "[+] Сканирование архивов отключено (экономит ресурсы, но снижает безопасность)" -ForegroundColor Yellow

        # 3. Отключение сканирования сетевых дисков при полной проверке
        Write-Host "[*] Исключение сетевых дисков из полного сканирования..." -ForegroundColor Cyan
        Set-MpPreference -DisableScanningMappedNetworkDrivesForFullScan $true -ErrorAction Stop
        Write-Host "[+] Сетевые диски исключены из полного сканирования" -ForegroundColor Green

        # 4. Настройка облачной защиты (Basic отправляет минимум метаданных, Advanced - больше)
        Write-Host "[*] Установка базового уровня облачной защиты (MAPS)..." -ForegroundColor Cyan
        Set-MpPreference -MAPSReporting Basic -ErrorAction Stop
        Write-Host "[+] Облачная защита настроена на базовый уровень" -ForegroundColor Green

        # 5. Настройка отправки образцов (1 = Никогда не отправлять, 2 = Только безопасные, 3 = Всегда)
        Write-Host "[*] Запрет автоматической отправки образцов файлов в Microsoft..." -ForegroundColor Cyan
        Set-MpPreference -SubmitSamplesConsent 1 -ErrorAction Stop
        Write-Host "[+] Отправка образцов файлов отключена" -ForegroundColor Green

        # 6. Низкий приоритет для фоновых проверок (не мешает основной работе)
        Write-Host "[*] Установка низкого приоритета для фоновых проверок..." -ForegroundColor Cyan
        Set-MpPreference -EnableLowCpuPriority $true -ErrorAction Stop
        Write-Host "[+] Низкий приоритет фоновых задач установлен" -ForegroundColor Green

        Write-Host ""
        Write-Host "[+] Все настройки Windows Defender успешно применены!" -ForegroundColor Green
        Write-Host "[!] Не забудьте перезагрузить компьютер для вступления изменений в силу." -ForegroundColor Yellow
        
    } catch {
        Write-Host ""
        Write-Host "[-] ОШИБКА: $_" -ForegroundColor Red
        Write-Host "[-] Вероятно, включена 'Защита от несанкционированного доступа' (Tamper Protection)." -ForegroundColor Red
        Write-Host "[-] Отключите её вручную в: Защита от вирусов и угроз -> Параметры защиты от вирусов и угроз." -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "Нажмите любую клавишу для выхода..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Запуск функции
Optimize-WindowsDefender