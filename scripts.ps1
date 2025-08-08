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
# Исправленная функция переноса пользователей с диска C на D
function Move-UsersToD {
    Write-Host "`n[!] ВНИМАНИЕ: Этот процесс перенесёт пользовательскую папку" -ForegroundColor Yellow
    Write-Host "[!] Рекомендуется создать резервную копию важных данных" -ForegroundColor Yellow

    $confirm = Read-Host "`nВы уверены, что хотите продолжить? (y/n)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "[!] Операция отменена пользователем" -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path "D:\")) {
        Write-Host "[-] Диск D: не найден или недоступен" -ForegroundColor Red
        Pause
        return
    }

    Write-Host "`n[+] Начинаем процесс переноса пользователя..." -ForegroundColor Green

    try {
        # Создание точки восстановления (по желанию)
        $makeRestorePoint = Read-Host "`nСоздать точку восстановления перед переносом? (y/n)"
        if ($makeRestorePoint -eq 'y' -or $makeRestorePoint -eq 'Y') {
            Write-Host "[*] Создание точки восстановления..." -ForegroundColor Cyan
            try {
                # Включаем службу восстановления системы если отключена
                Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
                Checkpoint-Computer -Description "Перед переносом пользователя на D:" -RestorePointType "MODIFY_SETTINGS"
                Write-Host "[+] Точка восстановления создана" -ForegroundColor Green
            } catch {
                Write-Host "[-] Не удалось создать точку восстановления: $_" -ForegroundColor Yellow
            }
        } else {
            Write-Host "[!] Создание точки восстановления пропущено по запросу пользователя" -ForegroundColor Yellow
        }

        # Получение списка пользователей
        $users = Get-ChildItem "C:\Users" -Directory | Where-Object {
            $_.Name -notin @('Public', 'All Users', 'Default', 'Default User', 'Administrator', 'Guest') -and
            -not $_.Name.StartsWith('.') -and
            -not $_.Name.StartsWith('TEMP')
        }

        if ($users.Count -eq 0) {
            Write-Host "[!] Пользователи для переноса не найдены" -ForegroundColor Yellow
            Pause
            return
        }

        Write-Host "[*] Найдено пользователей: $($users.Count)" -ForegroundColor Cyan
        for ($i = 0; $i -lt $users.Count; $i++) {
            $folderSize = "{0:N2} MB" -f ((Get-ChildItem -Path $users[$i].FullName -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB)
            Write-Host " [$i] $($users[$i].Name) - ($folderSize)" -ForegroundColor White
        }

        $userIndex = Read-Host "`nВведите номер пользователя для переноса (или оставьте пустым для отмены)"

        if ([string]::IsNullOrWhiteSpace($userIndex)) {
            Write-Host "[!] Операция отменена пользователем" -ForegroundColor Yellow
            return
        }

        if ($userIndex -notmatch '^\d+$' -or [int]$userIndex -lt 0 -or [int]$userIndex -ge $users.Count) {
            Write-Host "[!] Некорректный выбор. Операция отменена." -ForegroundColor Yellow
            return
        }

        $user = $users[[int]$userIndex]
        Write-Host "`n[*] Выбран пользователь: $($user.Name)" -ForegroundColor Cyan

        $sourceUserPath = $user.FullName
        $targetUsersPath = "D:\Users"
        $targetUserPath = Join-Path $targetUsersPath $user.Name

        # Проверяем, что пользователь не является текущим
        $currentUser = [Environment]::UserName
        if ($user.Name -eq $currentUser) {
            Write-Host "[!] Нельзя перенести папку текущего пользователя ($currentUser)" -ForegroundColor Red
            Write-Host "[!] Войдите под другим администратором и повторите операцию" -ForegroundColor Yellow
            Pause
            return
        }

        # Проверяем наличие активных процессов пользователя
        $userProcesses = Get-Process | Where-Object { 
            try { 
                $_.StartInfo.UserName -eq $user.Name -or 
                $_.GetOwner().User -eq $user.Name 
            } catch { 
                $false 
            }
        }
        
        if ($userProcesses) {
            Write-Host "[!] Обнаружены активные процессы пользователя $($user.Name)" -ForegroundColor Yellow
            Write-Host "[!] Рекомендуется завершить сеанс пользователя перед переносом" -ForegroundColor Yellow
            $continue = Read-Host "Продолжить несмотря на это? (y/n)"
            if ($continue -ne 'y' -and $continue -ne 'Y') {
                Write-Host "[!] Операция отменена" -ForegroundColor Yellow
                return
            }
        }

        if (-not (Test-Path $targetUsersPath)) {
            Write-Host "[*] Создание папки D:\Users..." -ForegroundColor Cyan
            New-Item -Path $targetUsersPath -ItemType Directory -Force | Out-Null
        }

        if (Test-Path $targetUserPath) {
            Write-Host "[!] Папка $targetUserPath уже существует" -ForegroundColor Yellow
            $overwrite = Read-Host "Перезаписать существующую папку? (y/n)"
            if ($overwrite -eq 'y' -or $overwrite -eq 'Y') {
                Remove-Item -Path $targetUserPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "[*] Существующая папка удалена" -ForegroundColor Cyan
            } else {
                Write-Host "[!] Операция отменена" -ForegroundColor Yellow
                return
            }
        }

        # Получение SID пользователя ДО перемещения
        Write-Host "[*] Получение информации о пользователе..." -ForegroundColor Cyan
        $userSid = $null
        try {
            $ntAccount = New-Object System.Security.Principal.NTAccount($user.Name)
            $userSid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
            Write-Host "[+] SID пользователя: $userSid" -ForegroundColor Green
        } catch {
            Write-Host "[-] Не удалось получить SID пользователя: $_" -ForegroundColor Red
            # Попытаемся найти SID в реестре по пути профиля
            try {
                $profilePaths = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" | 
                                Where-Object { (Get-ItemProperty -Path $_.PSPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue).ProfileImagePath -eq $sourceUserPath }
                if ($profilePaths) {
                    $userSid = $profilePaths[0].PSChildName
                    Write-Host "[+] SID найден в реестре: $userSid" -ForegroundColor Green
                }
            } catch {
                Write-Host "[-] Не удалось найти SID в реестре" -ForegroundColor Red
            }
        }

        # Остановка службы поиска Windows (может блокировать файлы)
        Write-Host "[*] Остановка службы поиска Windows..." -ForegroundColor Cyan
        try {
            Stop-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue
            Write-Host "[+] Служба поиска остановлена" -ForegroundColor Green
        } catch {
            Write-Host "[-] Не удалось остановить службу поиска" -ForegroundColor Yellow
        }

        # Перенос папки с использованием Robocopy для надежности
        Write-Host "[*] Перенос папки $sourceUserPath → $targetUserPath" -ForegroundColor Cyan
        Write-Host "[*] Это может занять несколько минут..." -ForegroundColor Cyan
        
        try {
            # Создаем целевую папку
            New-Item -Path $targetUserPath -ItemType Directory -Force | Out-Null
            
            # Используем robocopy для копирования с сохранением всех атрибутов
            $robocopyArgs = @(
                "`"$sourceUserPath`"",
                "`"$targetUserPath`"",
                "/MIR",           # Зеркальное копирование
                "/COPYALL",       # Копировать все атрибуты
                "/R:3",           # 3 повтора при ошибке
                "/W:5",           # Ждать 5 секунд между повторами
                "/MT:8",          # Многопоточность
                "/XD", "`"AppData\Local\Temp`"", # Исключить временные файлы
                "/XF", "pagefile.sys", "hiberfil.sys", "*.tmp", "*.temp"
            )
            
            $robocopyCmd = "robocopy " + ($robocopyArgs -join " ")
            Write-Host "[*] Выполнение команды: $robocopyCmd" -ForegroundColor Gray
            
            $result = Invoke-Expression $robocopyCmd
            $exitCode = $LASTEXITCODE
            
            # Robocopy коды выхода: 0-7 успех, 8+ ошибка
            if ($exitCode -le 7) {
                Write-Host "[+] Копирование завершено успешно (код: $exitCode)" -ForegroundColor Green
                
                # Удаляем исходную папку только после успешного копирования
                Write-Host "[*] Удаление исходной папки..." -ForegroundColor Cyan
                Remove-Item -Path $sourceUserPath -Recurse -Force -ErrorAction Stop
                Write-Host "[+] Исходная папка удалена" -ForegroundColor Green
            } else {
                throw "Robocopy завершился с ошибкой (код: $exitCode)"
            }
            
        } catch {
            Write-Host "[-] Ошибка при перемещении: $_" -ForegroundColor Red
            Write-Host "[!] Восстанавливаем исходное состояние..." -ForegroundColor Yellow
            
            # Если что-то пошло не так, удаляем частично скопированную папку
            if (Test-Path $targetUserPath) {
                Remove-Item -Path $targetUserPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            return
        }

        # Обновление реестра
        if ($userSid) {
            Write-Host "[*] Обновление реестра..." -ForegroundColor Cyan
            try {
                $profileListPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$userSid"

                if (Test-Path $profileListPath) {
                    Set-ItemProperty -Path $profileListPath -Name "ProfileImagePath" -Value $targetUserPath -Force
                    Write-Host "[+] Путь профиля обновлен в реестре" -ForegroundColor Green
                } else {
                    Write-Host "[-] Не найдена запись профиля в реестре для SID: $userSid" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "[-] Ошибка при обновлении реестра: $_" -ForegroundColor Red
            }
        }

        # Создание символической ссылки (опционально)
        Write-Host "[*] Создание символической ссылки..." -ForegroundColor Cyan
        try {
            $symlinkPath = $sourceUserPath
            if (-not (Test-Path $symlinkPath)) {
                cmd /c "mklink /D `"$symlinkPath`" `"$targetUserPath`"" | Out-Null
                Write-Host "[+] Символическая ссылка создана" -ForegroundColor Green
            }
        } catch {
            Write-Host "[-] Не удалось создать символическую ссылку: $_" -ForegroundColor Yellow
        }

        # Запуск службы поиска
        Write-Host "[*] Запуск службы поиска Windows..." -ForegroundColor Cyan
        try {
            Start-Service -Name "WSearch" -ErrorAction SilentlyContinue
            Write-Host "[+] Служба поиска запущена" -ForegroundColor Green
        } catch {
            Write-Host "[-] Не удалось запустить службу поиска" -ForegroundColor Yellow
        }

        Write-Host "`n[+] Перенос завершён успешно!" -ForegroundColor Green
        Write-Host "[+] Пользователь '$($user.Name)' перенесен с C:\Users на D:\Users" -ForegroundColor Green
        Write-Host "[!] Настоятельно рекомендуется перезагрузить компьютер для применения всех изменений" -ForegroundColor Yellow

        $reboot = Read-Host "`nПерезагрузить компьютер сейчас? (y/n)"
        if ($reboot -eq 'y' -or $reboot -eq 'Y') {
            Write-Host "[+] Перезагрузка через 10 секунд... (Ctrl+C для отмены)" -ForegroundColor Yellow
            Start-Sleep -Seconds 10
            Restart-Computer -Force
        }

    } catch {
        Write-Host "[-] Критическая ошибка при переносе: $_" -ForegroundColor Red
        Write-Host "[!] Рекомендуется восстановить систему из точки восстановления" -ForegroundColor Yellow
        
        # Запуск службы поиска если была остановлена
        try {
            Start-Service -Name "WSearch" -ErrorAction SilentlyContinue
        } catch {}
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
