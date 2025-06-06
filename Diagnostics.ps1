# Функция отображения основного меню
function Show-DiagnosticsMenu {
    Clear-Host
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host "           WICKED RAVEN DIAGNOSTICS        " -ForegroundColor Magenta
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " 1. Проверка системных файлов (SFC)"
    Write-Host " 2. Восстановление компонентов Windows (DISM)"
    Write-Host " 3. Проверка диска (CHKDSK)"
    Write-Host " 4. Проверка оперативной памяти (RAM)"
    Write-Host " 5. Сброс сетевых настроек"
    Write-Host " 6. Быстрый просмотр системных ошибок"
    Write-Host " 7. Информация о системе"
    Write-Host " 0. Назад"
    Write-Host ""
}

# Функция отображения системной информации
function Show-SystemInfo {
    Clear-Host
    Write-Host "[+] Получение информации о системе..." -ForegroundColor Yellow
    
    # ОС
    $os = Get-WmiObject -Class Win32_OperatingSystem
    $osVersion = [System.Environment]::OSVersion.Version
    Write-Host "ОС: $($os.Caption) $($os.Version)" -ForegroundColor Cyan
    Write-Host "Build: $($os.BuildNumber)"
    Write-Host "Разрядность: $($os.OSArchitecture)"
    Write-Host "Загружена: $($os.LastBootUpTime)" -ForegroundColor Cyan

    # Процессор
    $cpu = Get-WmiObject -Class Win32_Processor
    Write-Host "`nПроцессор: $($cpu.Name)" -ForegroundColor Cyan
    Write-Host "Количество ядер: $($cpu.NumberOfCores)"
    Write-Host "Максимальная скорость: $($cpu.MaxClockSpeed) МГц"

    # ОЗУ
    $memory = Get-WmiObject -Class Win32_ComputerSystem
    $totalRam = [math]::Round($memory.TotalPhysicalMemory / 1GB, 2)
    $freeRam = [math]::Round((Get-WmiObject -Class Win32_OperatingSystem).FreePhysicalMemory / 1MB, 2)
    Write-Host "`nПамять: $totalRam ГБ" -ForegroundColor Cyan
    Write-Host "Свободно: $freeRam ГБ"
    Write-Host "Использовано: $($totalRam - $freeRam) ГБ"

    # Диски
    $disks = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType=3"
    Write-Host "`nДиски:" -ForegroundColor Cyan
    foreach ($disk in $disks) {
        $size = [math]::Round($disk.Size / 1GB, 2)
        $free = [math]::Round($disk.FreeSpace / 1GB, 2)
        Write-Host "$($disk.DeviceID) $size ГБ (Свободно: $free ГБ)"
    }

    # Графика
    $gpu = Get-WmiObject -Class Win32_VideoController
    Write-Host "`nГрафика: $($gpu.Name)" -ForegroundColor Cyan
    Write-Host "Память: $([math]::Round($gpu.AdapterRAM / 1GB, 2)) ГБ"

    Pause
}

# Функция проверки SFC
function Run-SFC {
    Write-Host "[+] Запуск проверки SFC..." -ForegroundColor Yellow
    try {
        sfc /scannow
        Write-Host "[+] Проверка SFC завершена" -ForegroundColor Green
    } catch {
        Write-Host "[-] Ошибка выполнения SFC: $_" -ForegroundColor Red
    }
    Pause
}

# Функция проверки DISM
function Run-DISM {
    Write-Host "[+] Запуск DISM для восстановления компонентов..." -ForegroundColor Yellow
    try {
        Write-Host "[*] Шаг 1: Проверка состояния образа..." -ForegroundColor Cyan
        DISM /Online /Cleanup-Image /CheckHealth
        
        Write-Host "[*] Шаг 2: Сканирование повреждений..." -ForegroundColor Cyan
        DISM /Online /Cleanup-Image /ScanHealth
        
        Write-Host "[*] Шаг 3: Восстановление образа..." -ForegroundColor Cyan
        DISM /Online /Cleanup-Image /RestoreHealth
        
        Write-Host "[+] DISM завершен" -ForegroundColor Green
    } catch {
        Write-Host "[-] Ошибка выполнения DISM: $_" -ForegroundColor Red
    }
    Pause
}

# Функция проверки диска
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

# Функция проверки оперативной памяти
function Run-MemoryTest {
    Write-Host "[+] Планирование проверки оперативной памяти..." -ForegroundColor Yellow
    Write-Host "[!] Проверка начнется после перезагрузки" -ForegroundColor Cyan
    
    # Проверка поддержки Windows Memory Diagnostic
    try {
        $memDiag = Get-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsMemoryDiagnostic
        if (-not $memDiag.State -eq 'Enabled') {
            Write-Host "[*] Включение Windows Memory Diagnostic..." -ForegroundColor Cyan
            Enable-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsMemoryDiagnostic -All
        }
        
        mdsched.exe
        Write-Host "[!] Проверка запланирована. Перезагрузите ПК для выполнения" -ForegroundColor Cyan
    } catch {
        Write-Host "[-] Ошибка при проверке памяти: $_" -ForegroundColor Red
    }
    Pause
}

# Функция сброса сетевых настроек
function Reset-Network {
    Write-Host "[+] Сброс сетевых настроек..." -ForegroundColor Yellow
    try {
        Write-Host "[*] Очистка кэша DNS..." -ForegroundColor Cyan
        ipconfig /flushdns
        
        Write-Host "[*] Сброс Winsock..." -ForegroundColor Cyan
        netsh winsock reset
        
        Write-Host "[*] Сброс TCP/IP..." -ForegroundColor Cyan
        netsh int ip reset
        
        Write-Host "[*] Сброс IPv6..." -ForegroundColor Cyan
        netsh int ipv6 reset
        
        Write-Host "[!] Готово. Рекомендуется перезагрузка" -ForegroundColor Cyan
    } catch {
        Write-Host "[-] Ошибка сброса сетевых настроек: $_" -ForegroundColor Red
    }
    Pause
}

# Функция просмотра системных ошибок
function Show-SystemErrors {
    Write-Host "[+] Анализ последних системных ошибок..." -ForegroundColor Yellow
    
    # Фильтрация по уровням серьезности
    $eventLogs = Get-WinEvent -LogName System -MaxEvents 50 | 
                 Where-Object { $_.LevelDisplayName -in 'Error', 'Critical' }
    
    if ($eventLogs.Count -eq 0) {
        Write-Host "[+] Ошибок не найдено" -ForegroundColor Green
    } else {
        Write-Host "Найдено ошибок: $($eventLogs.Count)" -ForegroundColor Cyan
        Write-Host "Последние 10 критических ошибок:" -ForegroundColor Cyan
        
        $eventLogs | Select-Object -First 10 | ForEach-Object {
            $entry = $_
            $color = switch ($entry.LevelDisplayName) {
                'Critical' { 'Red' }
                'Error' { 'Yellow' }
            }
            Write-Host "[$($entry.TimeCreated)] [$($entry.LevelDisplayName)] $($entry.ProviderName): $($entry.Message.Substring(0, [math]::Min(100, $entry.Message.Length)))" -ForegroundColor $color
        }
    }
    
    # Проверка системных журналов
    Write-Host "`n[+] Проверка системных журналов..." -ForegroundColor Cyan
    $criticalEvents = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2} -MaxEvents 5
    if ($criticalEvents) {
        Write-Host "Найдены критические события:" -ForegroundColor Red
        $criticalEvents | ForEach-Object {
            Write-Host "[$($_.TimeCreated)] $($_.ProviderName): $($_.Message.Substring(0, [math]::Min(80, $_.Message.Length)))" -ForegroundColor Red
        }
    } else {
        Write-Host "Критических событий нет" -ForegroundColor Green
    }
    
    Pause
}

# Основной цикл
$backToMain = $false

while (-not $backToMain) {
    Show-DiagnosticsMenu
    $choice = Read-Host "Выберите опцию (0-7)"
    switch ($choice) {
        '1' { Run-SFC }
        '2' { Run-DISM }
        '3' { Run-CHKDSK }
        '4' { Run-MemoryTest }
        '5' { Reset-Network }
        '6' { Show-SystemErrors }
        '7' { Show-SystemInfo }
        '0' {
            Write-Host "Возврат в главное меню..." -ForegroundColor Green
            Start-Sleep -Seconds 1
            try {
                $menuScript = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/menu.ps1" -UseBasicParsing
                Invoke-Expression $menuScript.Content
            } catch {
                Write-Host "[!] Не удалось загрузить меню. Проверьте подключение к интернету." -ForegroundColor Red
            }
            $backToMain = $true
        }
        default {
            Write-Host "Неверный ввод. Попробуйте снова" -ForegroundColor Red
            Pause
        }
    }
}
