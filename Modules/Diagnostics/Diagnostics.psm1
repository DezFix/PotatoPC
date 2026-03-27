<#
.SYNOPSIS
    Модуль диагностики системы
.DESCRIPTION
    Проверка системных файлов, диска, памяти, сети и просмотр системной информации
#>

$MODULE_CONFIG = @{
    Name = "Диагностика"
    Version = "1.0.0"
}

# Цвета
$COLOR_ACCENT = "Yellow"
$COLOR_SUCCESS = "Green"
$COLOR_ERROR = "Red"
$COLOR_INFO = "Cyan"
$COLOR_WARNING = "DarkYellow"

# ==============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ==============================================================================

function Write-Status {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Error', 'Warning')]
        [string]$Type = 'Info'
    )
    
    $symbol = switch ($Type) {
        'Info' { '[+]}' }
        'Success' { '[✓]' }
        'Error' { '[✗]' }
        'Warning' { '[!]' }
    }
    
    $color = switch ($Type) {
        'Info' { $COLOR_INFO }
        'Success' { $COLOR_SUCCESS }
        'Error' { $COLOR_ERROR }
        'Warning' { $COLOR_WARNING }
    }
    
    Write-Host "  $symbol $Message" -ForegroundColor $color
}

function Wait-Key {
    param([string]$Message = "Нажмите любую клавишу для продолжения...")
    Write-Host ""
    Write-Host $Message -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ==============================================================================
# ФУНКЦИИ ДИАГНОСТИКИ
# ==============================================================================

function Run-SFC {
    Clear-Host
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $COLOR_ACCENT
    Write-Host "║  ПРОВЕРКА СИСТЕМНЫХ ФАЙЛОВ (SFC)                                      ║" -ForegroundColor $COLOR_ACCENT
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $COLOR_ACCENT
    Write-Host ""
    
    Write-Status -Message "Запуск проверки sfc /scannow..." -Type Info
    Write-Host ""
    
    try {
        sfc /scannow
        Write-Host ""
        Write-Status -Message "Проверка SFC завершена" -Type Success
    }
    catch {
        Write-Status -Message "Ошибка выполнения SFC: $_" -Type Error
    }
    
    Wait-Key
}

function Run-DISM {
    Clear-Host
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $COLOR_ACCENT
    Write-Host "║  ВОССТАНОВЛЕНИЕ КОМПОНЕНТОВ WINDOWS (DISM)                            ║" -ForegroundColor $COLOR_ACCENT
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $COLOR_ACCENT
    Write-Host ""
    
    Write-Status -Message "Шаг 1: Проверка состояния образа..." -Type Info
    DISM /Online /Cleanup-Image /CheckHealth
    
    Write-Host ""
    Write-Status -Message "Шаг 2: Сканирование повреждений..." -Type Info
    DISM /Online /Cleanup-Image /ScanHealth
    
    Write-Host ""
    Write-Status -Message "Шаг 3: Восстановление образа..." -Type Info
    DISM /Online /Cleanup-Image /RestoreHealth
    
    Write-Host ""
    Write-Status -Message "DISM завершен" -Type Success
    
    Wait-Key
}

function Run-CHKDSK {
    Clear-Host
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $COLOR_ACCENT
    Write-Host "║  ПРОВЕРКА ДИСКА (CHKDSK)                                              ║" -ForegroundColor $COLOR_ACCENT
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $COLOR_ACCENT
    Write-Host ""
    
    Write-Host "  1. Только проверка (только чтение)" -ForegroundColor White
    Write-Host "  2. Проверка и исправление ошибок (/F)" -ForegroundColor White
    Write-Host "  3. Проверка, исправление и восстановление секторов (/F /R)" -ForegroundColor White
    Write-Host "  0. Отмена" -ForegroundColor Red
    Write-Host ""
    
    $option = Read-Host "  Введите номер опции"
    
    switch ($option) {
        "1" {
            Write-Host ""
            Write-Status -Message "Выполняется проверка C: без изменений..." -Type Info
            chkdsk C:
        }
        "2" {
            Write-Host ""
            Write-Status -Message "Запланирована проверка C: с исправлением ошибок..." -Type Info
            chkdsk C: /F
            Write-Status -Message "Перезагрузите ПК для выполнения проверки" -Type Warning
        }
        "3" {
            Write-Host ""
            Write-Status -Message "Запланирована проверка C: с восстановлением секторов..." -Type Info
            chkdsk C: /F /R
            Write-Status -Message "Перезагрузите ПК для выполнения проверки" -Type Warning
        }
        "0" {
            Write-Status -Message "Отменено пользователем" -Type Warning
        }
        default {
            Write-Status -Message "Неверный ввод" -Type Error
        }
    }
    
    Wait-Key
}

function Run-MemoryTest {
    Clear-Host
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $COLOR_ACCENT
    Write-Host "║  ПРОВЕРКА ОПЕРАТИВНОЙ ПАМЯТИ                                          ║" -ForegroundColor $COLOR_ACCENT
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $COLOR_ACCENT
    Write-Host ""
    
    Write-Status -Message "Планирование проверки оперативной памяти..." -Type Info
    Write-Status -Message "Проверка начнется после перезагрузки" -Type Warning
    Write-Host ""
    
    try {
        mdsched.exe
        Write-Status -Message "Проверка запланирована. Перезагрузите ПК" -Type Success
    }
    catch {
        Write-Status -Message "Ошибка при проверке памяти: $_" -Type Error
    }
    
    Wait-Key
}

function Reset-Network {
    Clear-Host
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $COLOR_ACCENT
    Write-Host "║  СБРОС СЕТЕВЫХ НАСТРОЕК                                               ║" -ForegroundColor $COLOR_ACCENT
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $COLOR_ACCENT
    Write-Host ""
    
    Write-Status -Message "Сброс сетевых настроек..." -Type Info
    Write-Host ""
    
    try {
        Write-Status -Message "Очистка кэша DNS..." -Type Info
        ipconfig /flushdns | Out-Null
        
        Write-Status -Message "Сброс Winsock..." -Type Info
        netsh winsock reset | Out-Null
        
        Write-Status -Message "Сброс TCP/IP..." -Type Info
        netsh int ip reset | Out-Null
        
        Write-Status -Message "Сброс IPv6..." -Type Info
        netsh int ipv6 reset | Out-Null
        
        Write-Host ""
        Write-Status -Message "Готово. Рекомендуется перезагрузка" -Type Success
    }
    catch {
        Write-Status -Message "Ошибка сброса сетевых настроек: $_" -Type Error
    }
    
    Wait-Key
}

function Show-SystemErrors {
    Clear-Host
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $COLOR_ACCENT
    Write-Host "║  СИСТЕМНЫЕ ОШИБКИ                                                     ║" -ForegroundColor $COLOR_ACCENT
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $COLOR_ACCENT
    Write-Host ""
    
    Write-Status -Message "Анализ последних системных ошибок..." -Type Info
    Write-Host ""
    
    try {
        $eventLogs = Get-WinEvent -LogName System -MaxEvents 50 |
                     Where-Object { $_.LevelDisplayName -in 'Error', 'Critical' }
        
        if ($eventLogs.Count -eq 0) {
            Write-Status -Message "Ошибок не найдено" -Type Success
        }
        else {
            Write-Status -Message "Найдено ошибок: $($eventLogs.Count)" -Type Warning
            Write-Host ""
            Write-Host "  Последние 10 критических ошибок:" -ForegroundColor Cyan
            Write-Host ""
            
            $eventLogs | Select-Object -First 10 | ForEach-Object {
                $entry = $_
                $color = switch ($entry.LevelDisplayName) {
                    'Critical' { 'Red' }
                    'Error' { 'Yellow' }
                }
                $msg = if ($entry.Message.Length -gt 80) {
                    $entry.Message.Substring(0, 80) + "..."
                } else {
                    $entry.Message
                }
                Write-Host "  [$($entry.TimeCreated)] $($entry.ProviderName): $msg" -ForegroundColor $color
            }
        }
    }
    catch {
        Write-Status -Message "Ошибка чтения журнала событий: $_" -Type Error
    }
    
    Wait-Key
}

function Show-SystemInfo {
    Clear-Host
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $COLOR_ACCENT
    Write-Host "║  ИНФОРМАЦИЯ О СИСТЕМЕ                                                 ║" -ForegroundColor $COLOR_ACCENT
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $COLOR_ACCENT
    Write-Host ""
    
    # ОС
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
        Write-Host "  ОПЕРАЦИОННАЯ СИСТЕМА:" -ForegroundColor $COLOR_ACCENT
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
        Write-Host "    • ОС: $($os.Caption) $($os.Version)" -ForegroundColor White
        Write-Host "    • Build: $($os.BuildNumber)" -ForegroundColor White
        Write-Host "    • Разрядность: $($os.OSArchitecture)" -ForegroundColor White
        Write-Host "    • Пользователь: $($os.RegisteredUser)" -ForegroundColor White
        Write-Host "    • Загружена: $([Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime))" -ForegroundColor White
        Write-Host ""
    }
    catch { }
    
    # Процессор
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
        Write-Host "  ПРОЦЕССОР:" -ForegroundColor $COLOR_ACCENT
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
        Write-Host "    • Название: $($cpu.Name)" -ForegroundColor White
        Write-Host "    • Ядер: $($cpu.NumberOfCores)" -ForegroundColor White
        Write-Host "    • Потоков: $($cpu.NumberOfLogicalProcessors)" -ForegroundColor White
        Write-Host "    • Частота: $($cpu.MaxClockSpeed) МГц" -ForegroundColor White
        Write-Host ""
    }
    catch { }
    
    # Графика
    try {
        $gpus = Get-CimInstance -ClassName Win32_VideoController
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
        Write-Host "  ГРАФИКА:" -ForegroundColor $COLOR_ACCENT
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
        foreach ($gpu in $gpus) {
            $gpuMem = if ($gpu.AdapterRAM) {
                [math]::Round($gpu.AdapterRAM / 1GB, 2)
            } else { "N/A" }
            Write-Host "    • $($gpu.Name) ($gpuMem ГБ)" -ForegroundColor White
        }
        Write-Host ""
    }
    catch { }
    
    # ОЗУ
    try {
        $ram = Get-CimInstance -ClassName Win32_PhysicalMemory
        $totalRam = ($ram | Measure-Object -Property Capacity -Sum).Sum / 1GB
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
        Write-Host "  ОПЕРАТИВНАЯ ПАМЯТЬ:" -ForegroundColor $COLOR_ACCENT
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
        Write-Host "    • Общий объем: $([math]::Round($totalRam, 2)) ГБ" -ForegroundColor White
        Write-Host "    • Модулей: $($ram.Count)" -ForegroundColor White
        foreach ($stick in $ram) {
            Write-Host "    • Слот: $($stick.DeviceLocator) - $([math]::Round($stick.Capacity/1GB, 2)) ГБ ($($stick.Speed) МГц)" -ForegroundColor White
        }
        Write-Host ""
    }
    catch { }
    
    # Диски
    try {
        $disks = Get-CimInstance -ClassName Win32_DiskDrive
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
        Write-Host "  ДИСКИ:" -ForegroundColor $COLOR_ACCENT
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
        foreach ($disk in $disks) {
            $size = [math]::Round($disk.Size / 1GB, 2)
            Write-Host "    • $($disk.Model) - $size ГБ" -ForegroundColor White
        }
        Write-Host ""
    }
    catch { }
    
    # Сеть
    try {
        $adapters = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
        Write-Host "  СЕТЕВЫЕ АДАПТЕРЫ:" -ForegroundColor $COLOR_ACCENT
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
        foreach ($adapter in $adapters) {
            Write-Host "    • $($adapter.Description):" -ForegroundColor White
            Write-Host "      IPv4: $($adapter.IPAddress -join ', ')" -ForegroundColor DarkGray
            Write-Host "      MAC: $($adapter.MACAddress)" -ForegroundColor DarkGray
        }
        Write-Host ""
    }
    catch { }
    
    Wait-Key
}

function Show-WiFiPasswords {
    Clear-Host
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $COLOR_ACCENT
    Write-Host "║  ПАРОЛИ WI-FI                                                         ║" -ForegroundColor $COLOR_ACCENT
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $COLOR_ACCENT
    Write-Host ""
    
    try {
        $profiles = netsh wlan show profiles | Select-String "All User Profile" | ForEach-Object {
            $_ -replace ".*: (.*)", '$1'
        }
        
        if (-not $profiles -or $profiles.Count -eq 0) {
            Write-Status -Message "Wi-Fi профили не найдены" -Type Warning
            Wait-Key
            return
        }
        
        Write-Host "  Найдено профилей: $($profiles.Count)" -ForegroundColor Cyan
        Write-Host ""
        
        foreach ($profile in $profiles) {
            $password = netsh wlan show profile name="$profile" key=clear |
                       Select-String "Key Content" |
                       ForEach-Object { $_ -replace ".*: (.*)", '$1' }
            
            Write-Host "  Профиль: $profile" -ForegroundColor White
            Write-Host "  Пароль: $password" -ForegroundColor Green
            Write-Host ""
        }
        
        # Экспорт
        $export = Read-Host "  Экспортировать в файл? (y/n)"
        if ($export -eq "y" -or $export -eq "Y") {
            $outputFile = "$env:USERPROFILE\Desktop\WiFi_Passwords.txt"
            $results = @()
            foreach ($profile in $profiles) {
                $password = netsh wlan show profile name="$profile" key=clear |
                           Select-String "Key Content" |
                           ForEach-Object { $_ -replace ".*: (.*)", '$1' }
                $results += "Профиль: $profile | Пароль: $password"
            }
            $results | Out-File -FilePath $outputFile
            Write-Status -Message "Пароли сохранены в $outputFile" -Type Success
        }
    }
    catch {
        Write-Status -Message "Ошибка: $_" -Type Error
    }
    
    Wait-Key
}

# ==============================================================================
# МЕНЮ МОДУЛЯ
# ==============================================================================

function Show-DiagnosticsMenu {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $COLOR_ACCENT
    Write-Host "║  ДИАГНОСТИКА СИСТЕМЫ                                                  ║" -ForegroundColor $COLOR_ACCENT
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $COLOR_ACCENT
    Write-Host ""
    
    Write-Host "  1. " -ForegroundColor Green -NoNewline
    Write-Host "Проверка системных файлов (SFC)" -ForegroundColor White
    
    Write-Host "  2. " -ForegroundColor Green -NoNewline
    Write-Host "Восстановление компонентов Windows (DISM)" -ForegroundColor White
    
    Write-Host "  3. " -ForegroundColor Green -NoNewline
    Write-Host "Проверка диска (CHKDSK)" -ForegroundColor White
    
    Write-Host "  4. " -ForegroundColor Green -NoNewline
    Write-Host "Проверка оперативной памяти (RAM)" -ForegroundColor White
    
    Write-Host "  5. " -ForegroundColor Green -NoNewline
    Write-Host "Сброс сетевых настроек" -ForegroundColor White
    
    Write-Host "  6. " -ForegroundColor Green -NoNewline
    Write-Host "Просмотр системных ошибок" -ForegroundColor White
    
    Write-Host "  7. " -ForegroundColor Green -NoNewline
    Write-Host "Информация о системе" -ForegroundColor White
    
    Write-Host "  8. " -ForegroundColor Green -NoNewline
    Write-Host "Просмотр паролей Wi-Fi" -ForegroundColor White
    
    Write-Host ""
    Write-Host "  0. " -ForegroundColor Red -NoNewline
    Write-Host "Назад" -ForegroundColor White
    
    Write-Host ""
}

function Invoke-Diagnostics {
    $exit = $false
    
    while (-not $exit) {
        Show-DiagnosticsMenu
        
        $choice = Read-Host "  Выберите опцию"
        
        switch ($choice) {
            "1" { Run-SFC }
            "2" { Run-DISM }
            "3" { Run-CHKDSK }
            "4" { Run-MemoryTest }
            "5" { Reset-Network }
            "6" { Show-SystemErrors }
            "7" { Show-SystemInfo }
            "8" { Show-WiFiPasswords }
            "0" { $exit = $true }
            default {
                Write-Status -Message "Неверный ввод" -Type Warning
                Start-Sleep -Seconds 1
            }
        }
        
        if (-not $exit) {
            Clear-Host
        }
    }
}

# Экспортируем точку входа
Export-ModuleMember -Function Invoke-Diagnostics
