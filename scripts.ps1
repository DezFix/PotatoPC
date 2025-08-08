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

# Полная функция переноса пользователей с диска C на D с переключением профиля
function Move-UsersToD {
    Write-Host "`n[!] ВНИМАНИЕ: Этот процесс ПОЛНОСТЬЮ перенесёт пользователя на диск D:" -ForegroundColor Yellow
    Write-Host "[!] После переноса пользователь будет работать с папкой на диске D:" -ForegroundColor Yellow
    Write-Host "[!] Папка на диске C: будет УДАЛЕНА после успешного переноса" -ForegroundColor Red
    Write-Host "[!] Рекомендуется создать резервную копию важных данных" -ForegroundColor Yellow

    $confirm = Read-Host "`nВы уверены, что хотите продолжить? (y/n)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "[!] Операция отменена пользователем" -ForegroundColor Yellow
        return
    }

    # Проверка запуска с правами администратора
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "[-] Для выполнения операции требуются права администратора!" -ForegroundColor Red
        Pause
        return
    }

    if (-not (Test-Path "D:\")) {
        Write-Host "[-] Диск D: не найден или недоступен" -ForegroundColor Red
        Pause
        return
    }

    Write-Host "`n[+] Начинаем процесс ПОЛНОГО переноса пользователя..." -ForegroundColor Green

    try {
        # Создание точки восстановления
        $makeRestorePoint = Read-Host "`nСоздать точку восстановления перед переносом? (НАСТОЯТЕЛЬНО РЕКОМЕНДУЕТСЯ) (y/n)"
        if ($makeRestorePoint -eq 'y' -or $makeRestorePoint -eq 'Y') {
            Write-Host "[*] Создание точки восстановления..." -ForegroundColor Cyan
            try {
                Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
                Checkpoint-Computer -Description "Перед полным переносом пользователя на D:" -RestorePointType "MODIFY_SETTINGS"
                Write-Host "[+] Точка восстановления создана" -ForegroundColor Green
            } catch {
                Write-Host "[-] Не удалось создать точку восстановления: $_" -ForegroundColor Red
                $continue = Read-Host "Продолжить без точки восстановления? (НЕБЕЗОПАСНО) (y/n)"
                if ($continue -ne 'y' -and $continue -ne 'Y') {
                    Write-Host "[!] Операция отменена" -ForegroundColor Yellow
                    return
                }
            }
        }

        # Получение списка пользователей
        $users = Get-ChildItem "C:\Users" -Directory | Where-Object {
            $_.Name -notin @('Public', 'All Users', 'Default', 'Default User', 'Administrator', 'Guest') -and
            -not $_.Name.StartsWith('.') -and
            -not $_.Name.StartsWith('TEMP') -and
            -not $_.Name.Contains('$')
        }

        if ($users.Count -eq 0) {
            Write-Host "[!] Пользователи для переноса не найдены" -ForegroundColor Yellow
            Pause
            return
        }

        Write-Host "[*] Найдено пользователей для переноса: $($users.Count)" -ForegroundColor Cyan
        for ($i = 0; $i -lt $users.Count; $i++) {
            try {
                $folderSize = "{0:N2} MB" -f ((Get-ChildItem -Path $users[$i].FullName -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB)
                Write-Host " [$i] $($users[$i].Name) - ($folderSize)" -ForegroundColor White
            } catch {
                Write-Host " [$i] $($users[$i].Name) - (размер не определен)" -ForegroundColor White
            }
        }

        $userIndex = Read-Host "`nВведите номер пользователя для ПОЛНОГО переноса (или оставьте пустым для отмены)"

        if ([string]::IsNullOrWhiteSpace($userIndex)) {
            Write-Host "[!] Операция отменена пользователем" -ForegroundColor Yellow
            return
        }

        if ($userIndex -notmatch '^\d+$' -or [int]$userIndex -lt 0 -or [int]$userIndex -ge $users.Count) {
            Write-Host "[!] Некорректный выбор. Операция отменена." -ForegroundColor Yellow
            return
        }

        $user = $users[[int]$userIndex]
        Write-Host "`n[*] Выбран пользователь для ПОЛНОГО переноса: $($user.Name)" -ForegroundColor Cyan

        $sourceUserPath = $user.FullName
        $targetUsersPath = "D:\Users"
        $targetUserPath = Join-Path $targetUsersPath $user.Name

        # Критическая проверка - нельзя переносить текущего пользователя
        $currentUser = [Environment]::UserName
        if ($user.Name -eq $currentUser) {
            Write-Host "[-] КРИТИЧЕСКАЯ ОШИБКА: Нельзя перенести папку текущего пользователя ($currentUser)" -ForegroundColor Red
            Write-Host "[!] Войдите под другим администратором и повторите операцию" -ForegroundColor Yellow
            Pause
            return
        }

        # Проверка активных сессий пользователя
        Write-Host "[*] Проверка активных сессий пользователя..." -ForegroundColor Cyan
        try {
            $sessions = query user 2>$null | Select-String $user.Name
            if ($sessions) {
                Write-Host "[!] ВНИМАНИЕ: Пользователь $($user.Name) сейчас в системе!" -ForegroundColor Red
                Write-Host "[!] Необходимо завершить его сеанс перед переносом" -ForegroundColor Yellow
                $forceLogoff = Read-Host "Принудительно завершить сеанс пользователя? (y/n)"
                if ($forceLogoff -eq 'y' -or $forceLogoff -eq 'Y') {
                    try {
                        logoff $user.Name /server:localhost 2>$null
                        Start-Sleep -Seconds 5
                        Write-Host "[+] Сеанс пользователя завершен" -ForegroundColor Green
                    } catch {
                        Write-Host "[-] Не удалось завершить сеанс. Операция небезопасна!" -ForegroundColor Red
                        return
                    }
                } else {
                    Write-Host "[!] Операция отменена" -ForegroundColor Yellow
                    return
                }
            }
        } catch {
            Write-Host "[*] Не удалось проверить активные сессии" -ForegroundColor Yellow
        }

        # Получение SID пользователя
        Write-Host "[*] Получение информации о профиле пользователя..." -ForegroundColor Cyan
        $userSid = $null
        $profileListPath = $null
        
        try {
            # Способ 1: Прямое получение SID
            $ntAccount = New-Object System.Security.Principal.NTAccount($user.Name)
            $userSid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
            $profileListPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$userSid"
            Write-Host "[+] SID пользователя: $userSid" -ForegroundColor Green
        } catch {
            Write-Host "[-] Не удалось получить SID напрямую: $_" -ForegroundColor Yellow
            
            # Способ 2: Поиск по пути в реестре
            try {
                $profileEntries = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" | 
                    Where-Object { 
                        $profilePath = (Get-ItemProperty -Path $_.PSPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue).ProfileImagePath
                        $profilePath -eq $sourceUserPath
                    }
                
                if ($profileEntries -and $profileEntries.Count -gt 0) {
                    $userSid = $profileEntries[0].PSChildName
                    $profileListPath = $profileEntries[0].PSPath
                    Write-Host "[+] SID найден в реестре: $userSid" -ForegroundColor Green
                } else {
                    Write-Host "[-] SID не найден в реестре!" -ForegroundColor Red
                    Write-Host "[!] Профиль может быть поврежден или не существовать" -ForegroundColor Yellow
                    return
                }
            } catch {
                Write-Host "[-] Критическая ошибка поиска профиля: $_" -ForegroundColor Red
                return
            }
        }

        # Проверка существования записи в реестре
        if (-not (Test-Path $profileListPath)) {
            Write-Host "[-] Запись профиля в реестре не найдена: $profileListPath" -ForegroundColor Red
            Write-Host "[!] Операция не может быть выполнена безопасно" -ForegroundColor Yellow
            return
        }

        # Создание структуры папок на D:
        if (-not (Test-Path $targetUsersPath)) {
            Write-Host "[*] Создание папки D:\Users..." -ForegroundColor Cyan
            New-Item -Path $targetUsersPath -ItemType Directory -Force | Out-Null
        }

        if (Test-Path $targetUserPath) {
            Write-Host "[!] Папка $targetUserPath уже существует" -ForegroundColor Yellow
            $overwrite = Read-Host "Удалить существующую папку и продолжить? (y/n)"
            if ($overwrite -eq 'y' -or $overwrite -eq 'Y') {
                Write-Host "[*] Удаление существующей папки..." -ForegroundColor Cyan
                Remove-Item -Path $targetUserPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "[+] Существующая папка удалена" -ForegroundColor Green
            } else {
                Write-Host "[!] Операция отменена" -ForegroundColor Yellow
                return
            }
        }

        # Остановка служб, которые могут блокировать файлы
        Write-Host "[*] Остановка служб для безопасного переноса..." -ForegroundColor Cyan
        $servicesToStop = @("WSearch", "Themes", "AudioSrv")
        $stoppedServices = @()
        
        foreach ($serviceName in $servicesToStop) {
            try {
                $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                if ($service -and $service.Status -eq 'Running') {
                    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                    $stoppedServices += $serviceName
                    Write-Host "[+] Служба $serviceName остановлена" -ForegroundColor Green
                }
            } catch {
                Write-Host "[-] Не удалось остановить службу $serviceName" -ForegroundColor Yellow
            }
        }

        # ПОЛНЫЙ ПЕРЕНОС с использованием Robocopy
        Write-Host "`n[*] === НАЧАЛО ПОЛНОГО ПЕРЕНОСА ===" -ForegroundColor Magenta
        Write-Host "[*] Исходная папка: $sourceUserPath" -ForegroundColor Cyan
        Write-Host "[*] Целевая папка: $targetUserPath" -ForegroundColor Cyan
        Write-Host "[*] Это может занять длительное время..." -ForegroundColor Cyan
        
        try {
            # Создаем целевую папку
            New-Item -Path $targetUserPath -ItemType Directory -Force | Out-Null
            
            # Robocopy с полным зеркалированием
            $robocopyArgs = @(
                "`"$sourceUserPath`"",
                "`"$targetUserPath`"",
                "/MIR",              # Зеркальное копирование (удаляет лишние файлы в назначении)
                "/COPYALL",          # Копировать все атрибуты (данные, атрибуты, временные метки, безопасность, владелец, информация аудита)
                "/B",                # Режим резервного копирования (обход безопасности)
                "/R:5",              # 5 повторов при ошибке
                "/W:10",             # Ждать 10 секунд между повторами
                "/MT:4",             # Многопоточность (4 потока)
                "/V",                # Подробный вывод
                "/TS",               # Включить временные метки исходных файлов в вывод
                "/FP",               # Включить полные пути файлов в вывод
                "/XD", "`"AppData\Local\Temp`"", "`"AppData\Local\Microsoft\Windows\Temporary Internet Files`"", # Исключить временные папки
                "/XF", "*.tmp", "*.temp", "thumbs.db", "*.log"  # Исключить временные файлы
            )
            
            $robocopyCmd = "robocopy " + ($robocopyArgs -join " ")
            Write-Host "[*] Выполнение команды переноса..." -ForegroundColor Gray
            
            $result = Invoke-Expression $robocopyCmd
            $exitCode = $LASTEXITCODE
            
            # Анализ результата Robocopy
            Write-Host "[*] Robocopy завершен с кодом: $exitCode" -ForegroundColor Cyan
            
            if ($exitCode -le 7) {
                Write-Host "[+] Копирование файлов завершено успешно!" -ForegroundColor Green
            } elseif ($exitCode -eq 8) {
                Write-Host "[!] Копирование завершено с некоторыми ошибками" -ForegroundColor Yellow
                $continue = Read-Host "Продолжить операцию? (y/n)"
                if ($continue -ne 'y' -and $continue -ne 'Y') {
                    throw "Операция отменена пользователем из-за ошибок копирования"
                }
            } else {
                throw "Robocopy завершился с критической ошибкой (код: $exitCode)"
            }
            
        } catch {
            Write-Host "[-] КРИТИЧЕСКАЯ ОШИБКА при копировании: $_" -ForegroundColor Red
            
            # Очистка частично скопированных данных
            if (Test-Path $targetUserPath) {
                Write-Host "[*] Очистка частично скопированных данных..." -ForegroundColor Yellow
                Remove-Item -Path $targetUserPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            # Восстановление служб
            foreach ($serviceName in $stoppedServices) {
                try {
                    Start-Service -Name $serviceName -ErrorAction SilentlyContinue
                } catch {}
            }
            return
        }

        # ОБНОВЛЕНИЕ РЕЕСТРА - критический этап
        Write-Host "`n[*] === ОБНОВЛЕНИЕ СИСТЕМНОГО РЕЕСТРА ===" -ForegroundColor Magenta
        try {
            # Резервное копирование текущего значения
            $currentPath = (Get-ItemProperty -Path $profileListPath -Name "ProfileImagePath").ProfileImagePath
            Write-Host "[*] Текущий путь профиля: $currentPath" -ForegroundColor Cyan
            
            # Установка нового пути
            Set-ItemProperty -Path $profileListPath -Name "ProfileImagePath" -Value $targetUserPath -Force
            Write-Host "[+] Путь профиля обновлен на: $targetUserPath" -ForegroundColor Green
            
            # Проверка успешности записи
            $newPath = (Get-ItemProperty -Path $profileListPath -Name "ProfileImagePath").ProfileImagePath
            if ($newPath -eq $targetUserPath) {
                Write-Host "[+] Путь профиля успешно обновлен в реестре" -ForegroundColor Green
            } else {
                throw "Не удалось обновить путь профиля в реестре"
            }
            
        } catch {
            Write-Host "[-] КРИТИЧЕСКАЯ ОШИБКА обновления реестра: $_" -ForegroundColor Red
            Write-Host "[!] Попытка восстановления..." -ForegroundColor Yellow
            
            # Попытка восстановить исходное значение
            try {
                Set-ItemProperty -Path $profileListPath -Name "ProfileImagePath" -Value $currentPath -Force
                Write-Host "[+] Исходное значение в реестре восстановлено" -ForegroundColor Green
            } catch {
                Write-Host "[-] Не удалось восстановить реестр!" -ForegroundColor Red
            }
            
            # Очистка скопированных данных
            if (Test-Path $targetUserPath) {
                Remove-Item -Path $targetUserPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            return
        }

        # ОБНОВЛЕНИЕ ПЕРЕМЕННЫХ СРЕДЫ
        Write-Host "[*] Обновление системных переменных среды..." -ForegroundColor Cyan
        try {
            # Обновляем переменную USERPROFILE для новых пользователей
            $currentUserProfile = [Environment]::GetEnvironmentVariable("USERPROFILE", [EnvironmentVariableTarget]::Machine)
            if ($currentUserProfile -like "*C:\Users*") {
                $newUserProfile = $currentUserProfile -replace "C:\\Users", "D:\Users"
                [Environment]::SetEnvironmentVariable("USERPROFILE", $newUserProfile, [EnvironmentVariableTarget]::Machine)
                Write-Host "[+] Системная переменная USERPROFILE обновлена" -ForegroundColor Green
            }
        } catch {
            Write-Host "[-] Предупреждение: Не удалось обновить переменные среды: $_" -ForegroundColor Yellow
        }

        # КРИТИЧЕСКИЙ МОМЕНТ - УДАЛЕНИЕ ИСХОДНОЙ ПАПКИ
        Write-Host "`n[*] === УДАЛЕНИЕ ИСХОДНОЙ ПАПКИ ===" -ForegroundColor Magenta
        Write-Host "[!] ВНИМАНИЕ: Сейчас будет удалена исходная папка на диске C:" -ForegroundColor Red
        Write-Host "[!] Путь: $sourceUserPath" -ForegroundColor Red
        
        $finalConfirm = Read-Host "Подтвердите ОКОНЧАТЕЛЬНОЕ УДАЛЕНИЕ исходной папки (y/n)"
        if ($finalConfirm -eq 'y' -or $finalConfirm -eq 'Y') {
            try {
                Write-Host "[*] Удаление исходной папки $sourceUserPath..." -ForegroundColor Cyan
                Remove-Item -Path $sourceUserPath -Recurse -Force -ErrorAction Stop
                Write-Host "[+] Исходная папка успешно удалена!" -ForegroundColor Green
            } catch {
                Write-Host "[-] Ошибка удаления исходной папки: $_" -ForegroundColor Red
                Write-Host "[!] Возможно, некоторые файлы заблокированы" -ForegroundColor Yellow
                Write-Host "[!] Попробуйте удалить папку вручную после перезагрузки" -ForegroundColor Yellow
            }
        } else {
            Write-Host "[!] Исходная папка НЕ удалена по запросу пользователя" -ForegroundColor Yellow
            Write-Host "[!] У вас две копии папки пользователя!" -ForegroundColor Yellow
        }

        # Запуск остановленных служб
        Write-Host "`n[*] Восстановление служб..." -ForegroundColor Cyan
        foreach ($serviceName in $stoppedServices) {
            try {
                Start-Service -Name $serviceName -ErrorAction SilentlyContinue
                Write-Host "[+] Служба $serviceName запущена" -ForegroundColor Green
            } catch {
                Write-Host "[-] Не удалось запустить службу $serviceName" -ForegroundColor Yellow
            }
        }

        # ФИНАЛЬНАЯ ПРОВЕРКА
        Write-Host "`n[*] === ФИНАЛЬНАЯ ПРОВЕРКА ===" -ForegroundColor Magenta
        $finalCheck = $true
        
        # Проверка существования новой папки
        if (Test-Path $targetUserPath) {
            Write-Host "[+] Новая папка пользователя существует: $targetUserPath" -ForegroundColor Green
        } else {
            Write-Host "[-] ОШИБКА: Новая папка пользователя не найдена!" -ForegroundColor Red
            $finalCheck = $false
        }
        
        # Проверка записи в реестре
        $registryPath = (Get-ItemProperty -Path $profileListPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue).ProfileImagePath
        if ($registryPath -eq $targetUserPath) {
            Write-Host "[+] Запись в реестре корректна: $registryPath" -ForegroundColor Green
        } else {
            Write-Host "[-] ОШИБКА: Неверная запись в реестре: $registryPath" -ForegroundColor Red
            $finalCheck = $false
        }
        
        # Проверка удаления исходной папки
        if (-not (Test-Path $sourceUserPath)) {
            Write-Host "[+] Исходная папка успешно удалена: $sourceUserPath" -ForegroundColor Green
        } else {
            Write-Host "[!] Предупреждение: Исходная папка все еще существует: $sourceUserPath" -ForegroundColor Yellow
        }

        if ($finalCheck) {
            Write-Host "`n[+] ===============================================" -ForegroundColor Green
            Write-Host "[+] ПЕРЕНОС ПОЛЬЗОВАТЕЛЯ ЗАВЕРШЕН УСПЕШНО!" -ForegroundColor Green
            Write-Host "[+] ===============================================" -ForegroundColor Green
            Write-Host "[+] Пользователь: $($user.Name)" -ForegroundColor White
            Write-Host "[+] Новое расположение: $targetUserPath" -ForegroundColor White
            Write-Host "[+] Профиль обновлен в системном реестре" -ForegroundColor White
            Write-Host "[!] ОБЯЗАТЕЛЬНО перезагрузите компьютер для применения всех изменений" -ForegroundColor Yellow
        } else {
            Write-Host "`n[-] ===============================================" -ForegroundColor Red
            Write-Host "[-] ПЕРЕНОС ЗАВЕРШЕН С ОШИБКАМИ!" -ForegroundColor Red
            Write-Host "[-] ===============================================" -ForegroundColor Red
            Write-Host "[!] Рекомендуется проверить систему и при необходимости восстановить из точки восстановления" -ForegroundColor Yellow
        }

        $reboot = Read-Host "`nПерезагрузить компьютер СЕЙЧАС? (НАСТОЯТЕЛЬНО РЕКОМЕНДУЕТСЯ) (y/n)"
        if ($reboot -eq 'y' -or $reboot -eq 'Y') {
            Write-Host "[+] Перезагрузка через 15 секунд... (Ctrl+C для отмены)" -ForegroundColor Yellow
            for ($i = 15; $i -gt 0; $i--) {
                Write-Host "Перезагрузка через $i секунд..." -NoNewline -ForegroundColor Yellow
                Start-Sleep -Seconds 1
                Write-Host "`r" -NoNewline
            }
            Restart-Computer -Force
        }

    } catch {
        Write-Host "`n[-] ===============================================" -ForegroundColor Red
        Write-Host "[-] КРИТИЧЕСКАЯ ОШИБКА ПЕРЕНОСА!" -ForegroundColor Red
        Write-Host "[-] ===============================================" -ForegroundColor Red
        Write-Host "[-] Ошибка: $_" -ForegroundColor Red
        Write-Host "[!] НЕМЕДЛЕННО восстановите систему из точки восстановления!" -ForegroundColor Yellow
        Write-Host "[!] Не перезагружайте компьютер до восстановления системы!" -ForegroundColor Yellow
        
        # Попытка восстановления служб
        foreach ($serviceName in $stoppedServices) {
            try {
                Start-Service -Name $serviceName -ErrorAction SilentlyContinue
            } catch {}
        }
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
    $choice = Read-Host "Выберите опцию (0-5)"
    
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
