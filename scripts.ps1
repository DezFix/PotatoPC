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
    Write-Host "`n[!] Создание нового пользователя на диске D:" -ForegroundColor Yellow
    Write-Host "[!] Профиль пользователя будет создан в D:\Users\" -ForegroundColor Yellow

    # Проверка прав администратора
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "[-] Требуются права администратора!" -ForegroundColor Red
        Pause
        return
    }

    # Проверка существования диска D:
    if (-not (Test-Path "D:\")) {
        Write-Host "[-] Диск D: не найден или недоступен" -ForegroundColor Red
        Pause
        return
    }

    Write-Host "`n[+] Начинаем создание нового пользователя..." -ForegroundColor Green

    try {
        # Ввод данных пользователя
        Write-Host "`n[*] Введите данные нового пользователя:" -ForegroundColor Cyan
        
        do {
            $username = Read-Host "Имя пользователя"
            if ([string]::IsNullOrWhiteSpace($username)) {
                Write-Host "[-] Имя пользователя не может быть пустым!" -ForegroundColor Red
                continue
            }
            if ($username -match '[^\w\-_.]') {
                Write-Host "[-] Недопустимые символы! Используйте только буквы, цифры, дефис, подчеркивание" -ForegroundColor Red
                continue
            }
            break
        } while ($true)

        # Проверка существования пользователя
        try {
            Get-LocalUser -Name $username -ErrorAction Stop | Out-Null
            Write-Host "[-] Пользователь '$username' уже существует!" -ForegroundColor Red
            Pause
            return
        } catch [Microsoft.PowerShell.Commands.UserNotFoundException] {
            Write-Host "[+] Имя пользователя '$username' доступно" -ForegroundColor Green
        }

        $fullName = Read-Host "Полное имя (необязательно)"
        if ([string]::IsNullOrWhiteSpace($fullName)) {
            $fullName = $username
        }

        # Ввод пароля с проверкой
        do {
            $password1 = Read-Host "Пароль пользователя" -AsSecureString
            $password2 = Read-Host "Подтвердите пароль" -AsSecureString
            
            $pwd1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password1))
            $pwd2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password2))
            
            if ($pwd1 -ne $pwd2) {
                Write-Host "[-] Пароли не совпадают!" -ForegroundColor Red
                continue
            }
            if ($pwd1.Length -lt 4) {
                Write-Host "[-] Пароль слишком короткий! Минимум 4 символа." -ForegroundColor Red
                continue
            }
            break
        } while ($true)

        # Определение путей
        $targetUsersPath = "D:\Users"
        $targetUserPath = Join-Path $targetUsersPath $username

        # Создание структуры папок
        if (-not (Test-Path $targetUsersPath)) {
            New-Item -Path $targetUsersPath -ItemType Directory -Force | Out-Null
            Write-Host "[+] Создана папка D:\Users" -ForegroundColor Green
        }

        if (Test-Path $targetUserPath) {
            Write-Host "[!] Папка $targetUserPath уже существует" -ForegroundColor Yellow
            $overwrite = Read-Host "Удалить и продолжить? (y/n)"
            if ($overwrite -eq 'y' -or $overwrite -eq 'Y') {
                Remove-Item -Path $targetUserPath -Recurse -Force -ErrorAction SilentlyContinue
            } else {
                Write-Host "[!] Операция отменена" -ForegroundColor Yellow
                return
            }
        }

        # Создание пользователя
        Write-Host "`n[*] Создание пользователя '$username'..." -ForegroundColor Cyan
        
        $userParams = @{
            Name = $username
            Password = $password1
            FullName = $fullName
            AccountNeverExpires = $true
            UserMayChangePassword = $true
        }

        $newUser = New-LocalUser @userParams
        Write-Host "[+] Пользователь '$username' создан" -ForegroundColor Green

        # Добавление в группу пользователей
        try {
            Add-LocalGroupMember -Group "Users" -Member $username
            Write-Host "[+] Добавлен в группу Users" -ForegroundColor Green
        } catch {
            Add-LocalGroupMember -Group "Пользователи" -Member $username -ErrorAction SilentlyContinue
        }

        # Получение SID пользователя
        $ntAccount = New-Object System.Security.Principal.NTAccount($username)
        $userSid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
        Write-Host "[+] SID пользователя: $userSid" -ForegroundColor Green

        # Создание профиля
        Write-Host "[*] Создание профиля пользователя..." -ForegroundColor Cyan
        
        # Создание основной папки
        New-Item -Path $targetUserPath -ItemType Directory -Force | Out-Null
        
        # Создание стандартных папок
        $standardFolders = @("Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos", "AppData\Local", "AppData\Roaming")
        foreach ($folder in $standardFolders) {
            $folderPath = Join-Path $targetUserPath $folder
            New-Item -Path $folderPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Write-Host "[+] Структура папок создана" -ForegroundColor Green

        # Установка разрешений
        icacls $targetUserPath /grant "$username`:F" /t /q 2>$null
        Write-Host "[+] Разрешения настроены" -ForegroundColor Green

        # Регистрация в реестре
        Write-Host "[*] Регистрация профиля в системе..." -ForegroundColor Cyan
        $profileListPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$userSid"
        
        New-Item -Path $profileListPath -Force | Out-Null
        Set-ItemProperty -Path $profileListPath -Name "ProfileImagePath" -Value $targetUserPath -Force
        Set-ItemProperty -Path $profileListPath -Name "Flags" -Value 0 -Force
        Set-ItemProperty -Path $profileListPath -Name "State" -Value 0 -Force
        Write-Host "[+] Профиль зарегистрирован в системе" -ForegroundColor Green

        # Копирование шаблона профиля
        $defaultProfilePath = "C:\Users\Default"
        if (Test-Path $defaultProfilePath) {
            Write-Host "[*] Копирование шаблона профиля..." -ForegroundColor Cyan
            robocopy "$defaultProfilePath" "$targetUserPath" /E /XJ /R:1 /W:1 /NFL /NDL /NP >$null 2>&1
            Write-Host "[+] Шаблон профиля скопирован" -ForegroundColor Green
        }

        # Финальная проверка
        $success = $true
        
        if (-not (Get-LocalUser -Name $username -ErrorAction SilentlyContinue)) {
            Write-Host "[-] Пользователь не найден в системе!" -ForegroundColor Red
            $success = $false
        }
        
        if (-not (Test-Path $targetUserPath)) {
            Write-Host "[-] Папка профиля не найдена!" -ForegroundColor Red
            $success = $false
        }
        
        try {
            $registryPath = (Get-ItemProperty -Path $profileListPath -Name "ProfileImagePath").ProfileImagePath
            if ($registryPath -ne $targetUserPath) {
                Write-Host "[-] Неверная запись в реестре!" -ForegroundColor Red
                $success = $false
            }
        } catch {
            Write-Host "[-] Запись в реестре не найдена!" -ForegroundColor Red
            $success = $false
        }

        if ($success) {
            Write-Host "`n[+] ========================================" -ForegroundColor Green
            Write-Host "[+] ПОЛЬЗОВАТЕЛЬ СОЗДАН УСПЕШНО!" -ForegroundColor Green
            Write-Host "[+] ========================================" -ForegroundColor Green
            Write-Host "[+] Имя: $username" -ForegroundColor White
            Write-Host "[+] Профиль: $targetUserPath" -ForegroundColor White
            Write-Host "[+] SID: $userSid" -ForegroundColor White
        } else {
            Write-Host "`n[-] Создание завершено с ошибками!" -ForegroundColor Red
        }

        # Добавление в администраторы (опционально)
        $makeAdmin = Read-Host "`nДобавить в группу Администраторы? (y/n)"
        if ($makeAdmin -eq 'y' -or $makeAdmin -eq 'Y') {
            try {
                Add-LocalGroupMember -Group "Administrators" -Member $username
                Write-Host "[+] Добавлен в группу Administrators" -ForegroundColor Green
            } catch {
                Add-LocalGroupMember -Group "Администраторы" -Member $username -ErrorAction SilentlyContinue
            }
        }

    } catch {
        Write-Host "`n[-] ОШИБКА: $_" -ForegroundColor Red
        
        # Очистка при ошибке
        if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
            Remove-LocalUser -Name $username -ErrorAction SilentlyContinue
        }
        if (Test-Path $targetUserPath) {
            Remove-Item -Path $targetUserPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Pause
}

# Основной цикл
while ($true) {
    Show-ScriptsMenu
    $choice = Read-Host "Выберите опцию"
    
    switch ($choice) {
        '1' { Create-UserOnD }
        '0' {
            Write-Host "Возврат в главное меню..." -ForegroundColor Green
            try {
                $menuScript = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/menu.ps1" -UseBasicParsing
                Invoke-Expression $menuScript.Content
            } catch {
                Write-Host "[!] Не удалось загрузить главное меню" -ForegroundColor Red
            }
            return
        }
        default {
            Write-Host "Неверный выбор" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
