# Модуль системных скриптов для Wicked Raven Toolkit

# Функция отображения меню скриптов
function Show-ScriptsMenu {
    Clear-Host
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host "        WICKED RAVEN SYSTEM SCRIPTS        " -ForegroundColor Magenta
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " 1. Перенос пользователей с C: на D:"
    Write-Host " 2. Очистка логов системы"
    Write-Host " 3. Сброс разрешений файлов"
    Write-Host " 4. Создание точки восстановления"
    Write-Host " 5. Очистка кэша DNS и сети"
    Write-Host ""
    Write-Host " 0. Назад в главное меню"
    Write-Host ""
}

# Функция переноса пользователей с диска C на D
function Move-UsersToD {
    Write-Host "`n[!] ВНИМАНИЕ: Этот процесс изменит расположение пользовательских папок" -ForegroundColor Yellow
    Write-Host "[!] Рекомендуется создать резервную копию важных данных" -ForegroundColor Yellow
    
    $confirm = Read-Host "`nВы уверены, что хотите продолжить? (y/n)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "[!] Операция отменена пользователем" -ForegroundColor Yellow
        return
    }
    
    # Проверка наличия диска D:
    if (-not (Test-Path "D:\")) {
        Write-Host "[-] Диск D: не найден или недоступен" -ForegroundColor Red
        Pause
        return
    }
    
    Write-Host "`n[+] Начинаем процесс переноса пользователей..." -ForegroundColor Green
    
    try {
        # Создание точки восстановления
        Write-Host "[*] Создание точки восстановления..." -ForegroundColor Cyan
        try {
            Checkpoint-Computer -Description "Перед переносом пользователей на D:" -RestorePointType "MODIFY_SETTINGS"
            Write-Host "[+] Точка восстановления создана" -ForegroundColor Green
        } catch {
            Write-Host "[-] Не удалось создать точку восстановления: $_" -ForegroundColor Yellow
        }
        
        # Получение списка пользователей
        $users = Get-ChildItem "C:\Users" -Directory | Where-Object { 
            $_.Name -notin @('Public', 'All Users', 'Default', 'Default User') -and
            -not $_.Name.StartsWith('.')
        }
        
        if ($users.Count -eq 0) {
            Write-Host "[!] Пользователи для переноса не найдены" -ForegroundColor Yellow
            return
        }
        
       Write-Host "[*] Найдено пользователей для переноса: $($users.Count)" -ForegroundColor Cyan
        for ($i = 0; $i -lt $users.Count; $i++) {
        Write-Host " [$i] $($users[$i].Name)" -ForegroundColor White
        }

        $userIndex = Read-Host "`nВведите номер пользователя для переноса (или оставьте пустым для отмены)"
        if (![int]::TryParse($userIndex, [ref]$null) -or $userIndex -lt 0 -or $userIndex -ge $users.Count) {
        Write-Host "[!] Операция отменена или некорректный выбор" -ForegroundColor Yellow
        return
        }

$user = $users[$userIndex]
Write-Host "`n[*] Выбран пользователь: $($user.Name)" -ForegroundColor Cyan

        
        # Создание папки Users на диске D:
        $targetUsersPath = "D:\Users"
        if (-not (Test-Path $targetUsersPath)) {
            Write-Host "[*] Создание папки D:\Users..." -ForegroundColor Cyan
            New-Item -Path $targetUsersPath -ItemType Directory -Force | Out-Null
        }
        
        # Перенос каждого пользователя
        foreach ($user in $users) {
            $sourceUserPath = $user.FullName
            $targetUserPath = Join-Path $targetUsersPath $user.Name
            
            Write-Host "`n[*] Обработка пользователя: $($user.Name)" -ForegroundColor Cyan
            
            # Проверка, не существует ли уже папка на диске D:
            if (Test-Path $targetUserPath) {
                Write-Host "[!] Папка $targetUserPath уже существует. Пропускаем..." -ForegroundColor Yellow
                continue
            }
            
            # Копирование данных пользователя
            Write-Host "[*] Копирование данных на D:..." -ForegroundColor Cyan
            try {
                # Используем robocopy для надежного копирования
                $robocopyArgs = @(
                    "`"$sourceUserPath`"",
                    "`"$targetUserPath`"",
                    "/E",           # Копировать подпапки, включая пустые
                    "/COPYALL",     # Копировать все атрибуты
                    "/R:3",         # Количество попыток при ошибке
                    "/W:5",         # Время ожидания между попытками
                    "/XD", "AppData\Local\Temp", # Исключить временные файлы
                    "/XF", "ntuser.dat*", "NTUSER.DAT*" # Исключить файлы реестра пользователя
                )
                
                $robocopyResult = & robocopy @robocopyArgs
                
                # Robocopy возвращает различные коды выхода
                if ($LASTEXITCODE -le 7) {
                    Write-Host "[+] Данные скопированы успешно" -ForegroundColor Green
                } else {
                    throw "Robocopy завершился с ошибкой. Код: $LASTEXITCODE"
                }
                
                # Изменение реестра для перенаправления папки пользователя
                Write-Host "[*] Обновление реестра..." -ForegroundColor Cyan
                
                # Загрузка куста реестра пользователя
                $userSid = (New-Object System.Security.Principal.NTAccount($user.Name)).Translate([System.Security.Principal.SecurityIdentifier]).Value
                $profileListPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$userSid"
                
                if (Test-Path $profileListPath) {
                    Set-ItemProperty -Path $profileListPath -Name "ProfileImagePath" -Value $targetUserPath -Force
                    Write-Host "[+] Путь профиля обновлен в реестре" -ForegroundColor Green
                } else {
                    Write-Host "[-] Не удалось найти запись профиля в реестре" -ForegroundColor Yellow
                }
                
            } catch {
                Write-Host "[-] Ошибка при копировании пользователя $($user.Name): $_" -ForegroundColor Red
                continue
            }
        }
        
        # Обновление переменных среды
        Write-Host "`n[*] Обновление системных переменных..." -ForegroundColor Cyan
        try {
            [Environment]::SetEnvironmentVariable("USERPROFILE", "D:\Users\%USERNAME%", [EnvironmentVariableTarget]::Machine)
            Write-Host "[+] Переменные среды обновлены" -ForegroundColor Green
        } catch {
            Write-Host "[-] Ошибка обновления переменных среды: $_" -ForegroundColor Yellow
        }
        
        Write-Host "`n[+] Процесс переноса завершен!" -ForegroundColor Green
        Write-Host "[!] ВАЖНО: Необходимо перезагрузить компьютер для применения изменений" -ForegroundColor Yellow
        Write-Host "[!] После перезагрузки проверьте, что все работает корректно" -ForegroundColor Yellow
        Write-Host "[!] Старые папки в C:\Users можно удалить вручную после проверки" -ForegroundColor Yellow
        
        $reboot = Read-Host "`nПерезагрузить компьютер сейчас? (y/n)"
        if ($reboot -eq 'y' -or $reboot -eq 'Y') {
            Write-Host "[+] Перезагрузка через 10 секунд... (Ctrl+C для отмены)" -ForegroundColor Yellow
            Start-Sleep -Seconds 10
            Restart-Computer -Force
        }
        
    } catch {
        Write-Host "[-] Критическая ошибка при переносе: $_" -ForegroundColor Red
        Write-Host "[!] Рекомендуется восстановить систему из точки восстановления" -ForegroundColor Yellow
    }
    
    Pause
}

# Функция очистки системных логов
function Clear-SystemLogs {
    Write-Host "`n[+] Очистка системных логов..." -ForegroundColor Yellow
    
    $logs = @("Application", "Security", "System", "Setup")
    
    foreach ($log in $logs) {
        try {
            Get-WinEvent -ListLog $log -ErrorAction Stop | ForEach-Object {
                if ($_.RecordCount -gt 0) {
                    wevtutil cl $_.LogName
                    Write-Host "[+] Очищен журнал: $($_.LogName)" -ForegroundColor Green
                }
            }
        } catch {
            Write-Host "[-] Ошибка очистки журнала $log : $_" -ForegroundColor Red
        }
    }
    
    Write-Host "[+] Очистка логов завершена" -ForegroundColor Green
    Pause
}

# Функция сброса разрешений файлов
function Reset-FilePermissions {
    Write-Host "`n[+] Сброс разрешений файлов и папок..." -ForegroundColor Yellow
    
    $paths = @("C:\Windows\System32", "C:\Windows\SysWOW64", "C:\Program Files")
    
    foreach ($path in $paths) {
        if (Test-Path $path) {
            Write-Host "[*] Обработка: $path" -ForegroundColor Cyan
            try {
                icacls $path /reset /t /c /q 2>$null
                Write-Host "[+] Разрешения сброшены для: $path" -ForegroundColor Green
            } catch {
                Write-Host "[-] Ошибка сброса разрешений для $path" -ForegroundColor Red
            }
        }
    }
    
    Pause
}

# Функция создания точки восстановления
function Create-RestorePoint {
    Write-Host "`n[+] Создание точки восстановления..." -ForegroundColor Yellow
    
    $description = Read-Host "Введите описание точки восстановления (или Enter для автоматического)"
    if ([string]::IsNullOrWhiteSpace($description)) {
        $description = "Ручная точка восстановления - $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
    }
    
    try {
        Checkpoint-Computer -Description $description -RestorePointType "MODIFY_SETTINGS"
        Write-Host "[+] Точка восстановления '$description' создана успешно" -ForegroundColor Green
    } catch {
        Write-Host "[-] Ошибка создания точки восстановления: $_" -ForegroundColor Red
    }
    
    Pause
}

# Функция очистки сетевого кэша
function Clear-NetworkCache {
    Write-Host "`n[+] Очистка сетевого кэша и DNS..." -ForegroundColor Yellow
    
    try {
        Write-Host "[*] Очистка DNS кэша..." -ForegroundColor Cyan
        ipconfig /flushdns | Out-Null
        
        Write-Host "[*] Сброс Winsock..." -ForegroundColor Cyan
        netsh winsock reset | Out-Null
        
        Write-Host "[*] Сброс TCP/IP стека..." -ForegroundColor Cyan
        netsh int ip reset | Out-Null
        
        Write-Host "[*] Очистка ARP таблицы..." -ForegroundColor Cyan
        arp -d * 2>$null | Out-Null
        
        Write-Host "[*] Сброс сетевых адаптеров..." -ForegroundColor Cyan
        netsh interface ipv4 reset | Out-Null
        netsh interface ipv6 reset | Out-Null
        
        Write-Host "[+] Сетевой кэш очищен успешно" -ForegroundColor Green
        Write-Host "[!] Рекомендуется перезагрузить компьютер" -ForegroundColor Yellow
        
    } catch {
        Write-Host "[-] Ошибка при очистке сетевого кэша: $_" -ForegroundColor Red
    }
    
    Pause
}

# Основной цикл модуля скриптов
$backToMain = $false

while (-not $backToMain) {
    Show-ScriptsMenu
    $choice = Read-Host "Выберите опцию (0-6)"
    
    switch ($choice) {
        '1' { Move-UsersToD }
        '2' { Clear-SystemLogs }
        '3' { Reset-FilePermissions }
        '4' { Create-RestorePoint }
        '5' { Clear-NetworkCache }
        '0' {
            Write-Host "Возврат в главное меню..." -ForegroundColor Green
            Start-Sleep -Seconds 1
            try {
                $menuScript = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/menu.ps1" -UseBasicParsing
                Invoke-Expression $menuScript.Content
            } catch {
                Write-Host "[!] Не удалось загрузить главное меню. Проверьте подключение к интернету." -ForegroundColor Red
            }
            $backToMain = $true
        }
        default {
            Write-Host "Неверный ввод. Попробуйте снова" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
