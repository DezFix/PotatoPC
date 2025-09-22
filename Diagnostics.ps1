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
# Функция отображения основного меню
function Show-DiagnosticsMenu {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║                       WICKED RAVEN DIAGNOSTICS                        ║" -ForegroundColor Yellow
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host " 1. " -ForegroundColor Green -NoNewline
    Write-Host "Проверка системных файлов (SFC)"
    
    Write-Host " 2. " -ForegroundColor Green -NoNewline
    Write-Host "Восстановление компонентов Windows (DISM)"
    
    Write-Host " 3. " -ForegroundColor Green -NoNewline
    Write-Host "Проверка диска (CHKDSK)"
    
    Write-Host " 4. " -ForegroundColor Green -NoNewline
    Write-Host "Проверка оперативной памяти (RAM)"
    
    Write-Host ""
    Write-Host " 5. " -ForegroundColor Green -NoNewline
    Write-Host "Сброс сетевых настроек"
    
    Write-Host " 6. " -ForegroundColor Green -NoNewline
    Write-Host "Быстрый просмотр системных ошибок"
    
    Write-Host " 7. " -ForegroundColor Green -NoNewline
    Write-Host "Информация о системе"
    
    Write-Host " 8. " -ForegroundColor Green -NoNewline
    Write-Host "Просмотр паролей Wi-Fi"
    
    Write-Host ""
    Write-Host " 0. " -ForegroundColor Red -NoNewline
    Write-Host "Выход"
    
    Write-Host ""
    Write-Host "Выберите опцию: " -NoNewline -ForegroundColor White
}




# Функция отображения системной информации
function Show-SystemInfo {
    Clear-Host
    Write-Host "[+] Получение информации о системе..." -ForegroundColor Yellow

    # ОС
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        Write-Host "ОС: $($os.Caption) $($os.Version)" -ForegroundColor Cyan
        Write-Host "Build: $($os.BuildNumber)"
        Write-Host "Разрядность: $($os.OSArchitecture)"
        Write-Host "Пользователь: $($os.RegisteredUser)"
        Write-Host "Загружена: $([Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime))" -ForegroundColor Cyan
    } catch {
        Write-Host "Ошибка получения информации об ОС: $_" -ForegroundColor Red
    }

    # Процессор
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor
        Write-Host "`nПроцессор: $($cpu.Name)" -ForegroundColor Cyan
        Write-Host "Количество ядер: $($cpu.NumberOfCores)"
        Write-Host "Потоков: $($cpu.NumberOfLogicalProcessors)"
        Write-Host "Максимальная скорость: $($cpu.MaxClockSpeed) МГц"
    } catch {
        Write-Host "Ошибка получения информации о процессоре: $_" -ForegroundColor Red
    }

    # Графика
    try {
        $gpus = Get-CimInstance -ClassName Win32_VideoController
        Write-Host "`nГрафика:" -ForegroundColor Cyan
        foreach ($gpu in $gpus) {
            $gpuMem = if ($gpu.AdapterRAM) { [math]::Round($gpu.AdapterRAM / 1GB, 2) } else { "N/A" }
            Write-Host "$($gpu.Name) ($gpuMem ГБ)"
        }
    } catch {
        Write-Host "Ошибка получения информации о графике: $_" -ForegroundColor Red
    }

    # Сеть
    try {
        $adapters = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }
        Write-Host "`nСетевые адаптеры:" -ForegroundColor Cyan
        foreach ($adapter in $adapters) {
            Write-Host "$($adapter.Description):"
            Write-Host "  IPv4: $($adapter.IPAddress -join ', ')"
            Write-Host "  MAC: $($adapter.MACAddress)"
        }
    } catch {
        Write-Host "Ошибка получения информации о сети: $_" -ForegroundColor Red
    }

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
function Show-WiFiMenu {
    Clear-Host
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host "         WICKED RAVEN WI-FI PASSWORDS      " -ForegroundColor Magenta
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " 1. Показать все Wi-Fi профили"
    Write-Host " 2. Показать пароль конкретного Wi-Fi профиля"
    Write-Host " 3. Экспортировать все пароли в файл"
    Write-Host " 4. Назад"
    Write-Host ""
}

function Get-WiFiProfiles {
    try {
        $profiles = netsh wlan show profiles | Select-String "All User Profile" | ForEach-Object { $_ -replace ".*: (.*)", '$1' }
        return $profiles
    }
    catch {
        Write-Host "Ошибка при получении списка профилей: $_" -ForegroundColor Red
        return $null
    }
}

function Get-WiFiPassword {
    param($profileName)
    try {
        $output = netsh wlan show profile name="$profileName" key=clear
        $keyContent = $output | Select-String "Key Content" | ForEach-Object { $_ -replace ".*: (.*)", '$1' }
        return $keyContent
    }
    catch {
        Write-Host "Ошибка при получении пароля для $profileName : $_" -ForegroundColor Red
        return $null
    }
}

function WiFi-Passwords-Menu {
    while ($true) {
        Show-WiFiMenu
        $choice = Read-Host "Выберите опцию (1-4)"

        switch ($choice) {
            '1' {
                $profiles = Get-WiFiProfiles
                if ($profiles) {
                    Write-Host "`nСписок Wi-Fi профилей:" -ForegroundColor Green
                    $profiles | ForEach-Object { Write-Host $_ }
                } else {
                    Write-Host "Wi-Fi профили не найдены." -ForegroundColor Yellow
                }
                Read-Host "`nНажмите Enter для продолжения..."
            }
            '2' {
                $profiles = Get-WiFiProfiles
                if ($profiles) {
                    Write-Host "`nДоступные Wi-Fi профили:" -ForegroundColor Green
                    $profiles | ForEach-Object { Write-Host $_ }
                    $profileName = Read-Host "`nВведите имя Wi-Fi профиля"
                    $password = Get-WiFiPassword -profileName $profileName
                    if ($password) {
                        Write-Host "`nПароль для $profileName : $password" -ForegroundColor Green
                    } else {
                        Write-Host "Пароль не найден или профиль не существует." -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "Wi-Fi профили не найдены." -ForegroundColor Yellow
                }
                Read-Host "`nНажмите Enter для продолжения..."
            }
            '3' {
                $profiles = Get-WiFiProfiles
                if ($profiles) {
                    $outputFile = "$env:USERPROFILE\Desktop\WiFi_Passwords.txt"
                    $results = @()
                    foreach ($profile in $profiles) {
                        $password = Get-WiFiPassword -profileName $profile
                        $results += "Профиль: $profile | Пароль: $password"
                    }
                    $results | Out-File -FilePath $outputFile
                    Write-Host "`nПароли сохранены в $outputFile" -ForegroundColor Green
                } else {
                    Write-Host "Wi-Fi профили не найдены." -ForegroundColor Yellow
                }
                Read-Host "`nНажмите Enter для продолжения..."
            }
            '4' {
                Write-Host "Возврат в меню диагностики..." -ForegroundColor Green
                Start-Sleep -Seconds 1
                return
            }
            default {
                Write-Host "Неверный выбор. Пожалуйста, выберите 1-4." -ForegroundColor Red
                Read-Host "`nНажмите Enter для продолжения..."
            }
        }
    }
}
# Основной цикл
$backToMain = $false

while (-not $backToMain) {
    Show-DiagnosticsMenu
    $choice = Read-Host
    switch ($choice) {
        '1' { Run-SFC }
        '2' { Run-DISM }
        '3' { Run-CHKDSK }
        '4' { Run-MemoryTest }
        '5' { Reset-Network }
        '6' { Show-SystemErrors }
        '7' { Show-SystemInfo }
        '8' { WiFi-Passwords-Menu }
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
            Read-Host "Нажмите Enter для продолжения..."
        }
    }
}
