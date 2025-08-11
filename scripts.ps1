# Модуль системных скриптов для Wicked Raven Toolkit

# Функция отображения меню скриптов
function Show-ScriptsMenu {
    Clear-Host
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host "        WICKED RAVEN SYSTEM SCRIPTS        " -ForegroundColor Magenta
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " 1. Создание пользователя на диске D:"
    Write-Host ""
    Write-Host " 0. Назад в главное меню"
    Write-Host ""
}

# Функция создания нового пользователя на диске D:
function Create-UserOnD {
    Write-Host "`n[!] ИНФОРМАЦИЯ: Создание нового пользователя на диске D:" -ForegroundColor Yellow
    Write-Host "[!] Профиль пользователя будет создан в D:\Users\" -ForegroundColor Yellow
    Write-Host "[!] Пользователь будет добавлен в группу 'Пользователи'" -ForegroundColor Yellow

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

    Write-Host "`n[+] Начинаем процесс создания нового пользователя..." -ForegroundColor Green

    try {
        # Создание точки восстановления
        $makeRestorePoint = Read-Host "`nСоздать точку восстановления перед созданием пользователя? (рекомендуется) (y/n)"
        if ($makeRestorePoint -eq 'y' -or $makeRestorePoint -eq 'Y') {
            Write-Host "[*] Создание точки восстановления..." -ForegroundColor Cyan
            try {
                Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
                Checkpoint-Computer -Description "Создание пользователя на диске D:" -RestorePointType "MODIFY_SETTINGS"
                Write-Host "[+] Точка восстановления создана" -ForegroundColor Green
            } catch {
                Write-Host "[-] Не удалось создать точку восстановления: $_" -ForegroundColor Red
                $continue = Read-Host "Продолжить без точки восстановления? (y/n)"
                if ($continue -ne 'y' -and $continue -ne 'Y') {
                    Write-Host "[!] Операция отменена" -ForegroundColor Yellow
                    return
                }
            }
        }

        # Ввод данных пользователя
        Write-Host "`n[*] Введите данные нового пользователя:" -ForegroundColor Cyan
        
        do {
            $username = Read-Host "Имя пользователя"
            if ([string]::IsNullOrWhiteSpace($username)) {
                Write-Host "[-] Имя пользователя не может быть пустым!" -ForegroundColor Red
                continue
            }
            if ($username -match '[^\w\-_.]') {
                Write-Host "[-] Имя пользователя содержит недопустимые символы!" -ForegroundColor Red
                Write-Host "[!] Разрешены только буквы, цифры, дефис, подчеркивание и точка" -ForegroundColor Yellow
                continue
            }
            break
        } while ($true)

        # Проверка существования пользователя
        try {
            $existingUser = Get-LocalUser -Name $username -ErrorAction Stop
            Write-Host "[-] Пользователь с именем '$username' уже существует!" -ForegroundColor Red
            Pause
            return
        } catch [Microsoft.PowerShell.Commands.UserNotFoundException] {
            Write-Host "[+] Имя пользователя '$username' доступно" -ForegroundColor Green
        }

        $fullName = Read-Host "Полное имя пользователя (необязательно)"
        if ([string]::IsNullOrWhiteSpace($fullName)) {
            $fullName = $username
        }

        $description = Read-Host "Описание пользователя (необязательно)"

        # Ввод пароля
        do {
            $password1 = Read-Host "Пароль пользователя" -AsSecureString
            $password2 = Read-Host "Подтвердите пароль" -AsSecureString
            
            $pwd1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password1))
            $pwd2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password2))
            
            if ($pwd1 -ne $pwd2) {
                Write-Host "[-] Пароли не совпадают! Попробуйте еще раз." -ForegroundColor Red
                continue
            }
            
            if ($pwd1.Length -lt 4) {
                Write-Host "[-] Пароль слишком короткий! Минимум 4 символа." -ForegroundColor Red
                continue
            }
            
            break
        } while ($true)

        # Создание структуры папок на D:
        $targetUsersPath = "D:\Users"
        $targetUserPath = Join-Path $targetUsersPath $username

        if (-not (Test-Path $targetUsersPath)) {
            Write-Host "[*] Создание папки D:\Users..." -ForegroundColor Cyan
            New-Item -Path $targetUsersPath -ItemType Directory -Force | Out-Null
            Write-Host "[+] Папка D:\Users создана" -ForegroundColor Green
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

        # Создание локального пользователя
        Write-Host "`n[*] === СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ ===" -ForegroundColor Magenta
        Write-Host "[*] Создание локального пользователя '$username'..." -ForegroundColor Cyan
        
        $userParams = @{
            Name = $username
            Password = $password1
            FullName = $fullName
            AccountNeverExpires = $true
            PasswordNeverExpires = $false
            UserMayChangePassword = $true
        }

        if (-not [string]::IsNullOrWhiteSpace($description)) {
            $userParams.Description = $description
        }

        try {
            $newUser = New-LocalUser @userParams -ErrorAction Stop
            Write-Host "[+] Пользователь '$username' создан успешно" -ForegroundColor Green
        } catch {
            Write-Host "[-] Ошибка создания пользователя: $_" -ForegroundColor Red
            return
        }

        # Добавление в группу пользователей
        Write-Host "[*] Добавление в группу 'Пользователи'..." -ForegroundColor Cyan
        try {
            Add-LocalGroupMember -Group "Пользователи" -Member $username -ErrorAction Stop
            Write-Host "[+] Пользователь добавлен в группу 'Пользователи'" -ForegroundColor Green
        } catch {
            try {
                Add-LocalGroupMember -Group "Users" -Member $username -ErrorAction Stop
                Write-Host "[+] Пользователь добавлен в группу 'Users'" -ForegroundColor Green
            } catch {
                Write-Host "[-] Ошибка добавления в группу пользователей: $_" -ForegroundColor Red
            }
        }

        # Получение SID созданного пользователя
        Write-Host "[*] Получение SID пользователя..." -ForegroundColor Cyan
        try {
            $userAccount = Get-LocalUser -Name $username
            $ntAccount = New-Object System.Security.Principal.NTAccount($username)
            $userSid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
            Write-Host "[+] SID пользователя: $userSid" -ForegroundColor Green
        } catch {
            Write-Host "[-] Ошибка получения SID: $_" -ForegroundColor Red
            return
        }

        # Создание структуры профиля пользователя
        Write-Host "`n[*] === СОЗДАНИЕ ПРОФИЛЯ ПОЛЬЗОВАТЕЛЯ ===" -ForegroundColor Magenta
        Write-Host "[*] Создание папки профиля: $targetUserPath" -ForegroundColor Cyan
        
        try {
            # Создание основной папки пользователя
            New-Item -Path $targetUserPath -ItemType Directory -Force | Out-Null
            
            # Создание стандартных папок пользователя
            $standardFolders = @(
                "Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos",
                "AppData", "AppData\Local", "AppData\LocalLow", "AppData\Roaming"
            )
            
            foreach ($folder in $standardFolders) {
                $folderPath = Join-Path $targetUserPath $folder
                New-Item -Path $folderPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
            }
            
            Write-Host "[+] Структура папок профиля создана" -ForegroundColor Green
            
        } catch {
            Write-Host "[-] Ошибка создания структуры профиля: $_" -ForegroundColor Red
            return
        }

        # Установка разрешений для папки пользователя
        Write-Host "[*] Настройка разрешений папки пользователя..." -ForegroundColor Cyan
        try {
            # Даем полные права владельцу
            icacls $targetUserPath /grant "$username:(OI)(CI)F" /t /q 2>$null
            
            # Наследование от родительской папки
            icacls $targetUserPath /inheritance:e /t /q 2>$null
            
            Write-Host "[+] Разрешения настроены успешно" -ForegroundColor Green
        } catch {
            Write-Host "[-] Предупреждение: Не удалось настроить разрешения" -ForegroundColor Yellow
        }

        # Регистрация профиля в реестре
        Write-Host "`n[*] === РЕГИСТРАЦИЯ ПРОФИЛЯ В СИСТЕМЕ ===" -ForegroundColor Magenta
        Write-Host "[*] Создание записи профиля в реестре..." -ForegroundColor Cyan
        
        try {
            $profileListPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$userSid"
            
            # Создание ключа профиля
            if (-not (Test-Path $profileListPath)) {
                New-Item -Path $profileListPath -Force | Out-Null
                Write-Host "[+] Создан ключ реестра профиля" -ForegroundColor Green
            }
            
            # Установка пути профиля
            Set-ItemProperty -Path $profileListPath -Name "ProfileImagePath" -Value $targetUserPath -Force
            Write-Host "[+] Путь профиля установлен: $targetUserPath" -ForegroundColor Green
            
            # Установка дополнительных параметров
            Set-ItemProperty -Path $profileListPath -Name "Flags" -Value 0 -Force
            Set-ItemProperty -Path $profileListPath -Name "State" -Value 0 -Force
            
            Write-Host "[+] Профиль зарегистрирован в системе" -ForegroundColor Green
            
        } catch {
            Write-Host "[-] Ошибка регистрации профиля в реестре: $_" -ForegroundColor Red
            Write-Host "[!] Профиль может не загружаться корректно" -ForegroundColor Yellow
        }

        # Копирование шаблона профиля по умолчанию
        Write-Host "[*] Копирование шаблона профиля по умолчанию..." -ForegroundColor Cyan
        try {
            $defaultProfilePath = "C:\Users\Default"
            if (Test-Path $defaultProfilePath) {
                robocopy "$defaultProfilePath" "$targetUserPath" /E /XJ /R:1 /W:1 /NP /NFL /NDL >$null 2>&1
                Write-Host "[+] Шаблон профиля скопирован" -ForegroundColor Green
            }
        } catch {
            Write-Host "[-] Предупреждение: Не удалось скопировать шаблон профиля" -ForegroundColor Yellow
        }

        # Создание ярлыков на рабочем столе
        Write-Host "[*] Создание базовых ярлыков..." -ForegroundColor Cyan
        try {
            $desktopPath = Join-Path $targetUserPath "Desktop"
            
            # Создание ярлыка "Этот компьютер"
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut("$desktopPath\Этот компьютер.lnk")
            $shortcut.TargetPath = "::{20D04FE0-3AEA-1069-A2D8-08002B30309D}"
            $shortcut.Save()
            
            Write-Host "[+] Базовые ярлыки созданы" -ForegroundColor Green
        } catch {
            Write-Host "[-] Предупреждение: Не удалось создать ярлыки" -ForegroundColor Yellow
        }

        # Финальная проверка
        Write-Host "`n[*] === ФИНАЛЬНАЯ ПРОВЕРКА ===" -ForegroundColor Magenta
        $finalCheck = $true
        
        # Проверка существования пользователя
        try {
            $checkUser = Get-LocalUser -Name $username -ErrorAction Stop
            Write-Host "[+] Пользователь '$username' существует в системе" -ForegroundColor Green
        } catch {
            Write-Host "[-] ОШИБКА: Пользователь не найден в системе!" -ForegroundColor Red
            $finalCheck = $false
        }
        
        # Проверка существования папки профиля
        if (Test-Path $targetUserPath) {
            Write-Host "[+] Папка профиля создана: $targetUserPath" -ForegroundColor Green
        } else {
            Write-Host "[-] ОШИБКА: Папка профиля не найдена!" -ForegroundColor Red
            $finalCheck = $false
        }
        
        # Проверка записи в реестре
        try {
            $registryPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$userSid" -Name "ProfileImagePath" -ErrorAction Stop).ProfileImagePath
            if ($registryPath -eq $targetUserPath) {
                Write-Host "[+] Запись в реестре корректна: $registryPath" -ForegroundColor Green
            } else {
                Write-Host "[-] ОШИБКА: Неверная запись в реестре: $registryPath" -ForegroundColor Red
                $finalCheck = $false
            }
        } catch {
            Write-Host "[-] ОШИБКА: Запись в реестре не найдена!" -ForegroundColor Red
            $finalCheck = $false
        }

        if ($finalCheck) {
            Write-Host "`n[+] ===============================================" -ForegroundColor Green
            Write-Host "[+] ПОЛЬЗОВАТЕЛЬ СОЗДАН УСПЕШНО!" -ForegroundColor Green
            Write-Host "[+] ===============================================" -ForegroundColor Green
            Write-Host "[+] Имя пользователя: $username" -ForegroundColor White
            Write-Host "[+] Полное имя: $fullName" -ForegroundColor White
            Write-Host "[+] Расположение профиля: $targetUserPath" -ForegroundColor White
            Write-Host "[+] SID: $userSid" -ForegroundColor White
            Write-Host "[!] Пользователь готов к использованию" -ForegroundColor Yellow
            Write-Host "[!] При первом входе профиль будет инициализирован" -ForegroundColor Yellow
        } else {
            Write-Host "`n[-] ===============================================" -ForegroundColor Red
            Write-Host "[-] СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ ЗАВЕРШЕНО С ОШИБКАМИ!" -ForegroundColor Red
            Write-Host "[-] ===============================================" -ForegroundColor Red
            Write-Host "[!] Рекомендуется проверить созданного пользователя" -ForegroundColor Yellow
            Write-Host "[!] При необходимости восстановите систему из точки восстановления" -ForegroundColor Yellow
        }

        # Опция добавления в группу администраторов
        $makeAdmin = Read-Host "`nДобавить пользователя в группу 'Администраторы'? (y/n)"
        if ($makeAdmin -eq 'y' -or $makeAdmin -eq 'Y') {
            try {
                Add-LocalGroupMember -Group "Администраторы" -Member $username -ErrorAction Stop
                Write-Host "[+] Пользователь добавлен в группу 'Администраторы'" -ForegroundColor Green
            } catch {
                try {
                    Add-LocalGroupMember -Group "Administrators" -Member $username -ErrorAction Stop
                    Write-Host "[+] Пользователь добавлен в группу 'Administrators'" -ForegroundColor Green
                } catch {
                    Write-Host "[-] Ошибка добавления в группу администраторов: $_" -ForegroundColor Red
                }
            }
        }

    } catch {
        Write-Host "`n[-] ===============================================" -ForegroundColor Red
        Write-Host "[-] КРИТИЧЕСКАЯ ОШИБКА СОЗДАНИЯ ПОЛЬЗОВАТЕЛЯ!" -ForegroundColor Red
        Write-Host "[-] ===============================================" -ForegroundColor Red
        Write-Host "[-] Ошибка: $_" -ForegroundColor Red
        
        # Попытка очистки частично созданных данных
        Write-Host "[*] Попытка очистки частично созданных данных..." -ForegroundColor Yellow
        try {
            if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
                Remove-LocalUser -Name $username -ErrorAction SilentlyContinue
                Write-Host "[+] Пользователь удален из системы" -ForegroundColor Green
            }
            if (Test-Path $targetUserPath) {
                Remove-Item -Path $targetUserPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "[+] Папка профиля удалена" -ForegroundColor Green
            }
        } catch {
            Write-Host "[-] Не удалось полностью очистить созданные данные" -ForegroundColor Red
        }
    }

    Pause
}

# Основной цикл модуля скриптов
$backToMain = $false

while (-not $backToMain) {
    Show-ScriptsMenu
    $choice = Read-Host "Выберите опцию (0-1)"
    
    switch ($choice) {
        '1' { Create-UserOnD }
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
