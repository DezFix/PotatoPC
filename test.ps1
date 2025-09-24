# Скрипт управления локальными пользователями Windows
# Требует запуск от имени администратора

# Проверка прав администратора
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Запустите скрипт от имени администратора!" -ForegroundColor Red
    pause
    exit
}

# === Утилиты ===
function Pause {
    Write-Host "`nНажмите любую клавишу для продолжения..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Get-UserList {
    Get-LocalUser |
        Where-Object {
            $_.Enabled -eq $true -and
            $_.Name -notin @("Administrator", "DefaultAccount", "WDAGUtilityAccount")
        }
}

# === 1. Создание пользователя ===
function Create-User {
    try {
        $username = Read-Host "Введите имя пользователя"
        if ([string]::IsNullOrWhiteSpace($username)) {
            Write-Host "Имя пользователя не может быть пустым." -ForegroundColor Red
            Pause
            return
        }

        if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
            Write-Host "Пользователь $username уже существует." -ForegroundColor Red
            Pause
            return
        }

        $password = Read-Host "Введите пароль (Enter для пустого пароля)"
        $fullname = Read-Host "Введите полное имя (можно оставить пустым)"

        Write-Host "Создание пользователя $username..." -ForegroundColor Yellow

        # Создание пользователя с учетом пустого пароля
        if ([string]::IsNullOrWhiteSpace($password)) {
            if ([string]::IsNullOrWhiteSpace($fullname)) {
                New-LocalUser -Name $username -NoPassword -Description "Создан через скрипт"
            } else {
                New-LocalUser -Name $username -NoPassword -FullName $fullname -Description "Создан через скрипт"
            }
        } else {
            $SecurePassword = ConvertTo-SecureString $password -AsPlainText -Force
            if ([string]::IsNullOrWhiteSpace($fullname)) {
                New-LocalUser -Name $username -Password $SecurePassword -Description "Создан через скрипт"
            } else {
                New-LocalUser -Name $username -Password $SecurePassword -FullName $fullname -Description "Создан через скрипт"
            }
        }

        # Добавление в группу пользователей
        try {
            Add-LocalGroupMember -Group "Users" -Member $username -ErrorAction Stop
        } catch {
            try {
                Add-LocalGroupMember -Group "Пользователи" -Member $username -ErrorAction Stop
            } catch {
                Write-Host "Не удалось добавить в группу пользователей" -ForegroundColor Yellow
            }
        }

        # Получение SID пользователя
        $User = Get-LocalUser -Name $username
        $UserSID = $User.SID.Value
        $NewProfilePath = "D:\Users\$username"
        $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$UserSID"

        Write-Host "🔧 Настройка профиля на диске D..." -ForegroundColor Yellow
        Write-Host "   SID: $UserSID" -ForegroundColor Gray

        # Создание папки на диске D
        if (!(Test-Path "D:\Users")) { 
            New-Item -ItemType Directory -Path "D:\Users" -Force | Out-Null 
            Write-Host "   Создана папка D:\Users" -ForegroundColor Gray
        }
        if (!(Test-Path $NewProfilePath)) { 
            New-Item -ItemType Directory -Path $NewProfilePath -Force | Out-Null 
            Write-Host "   Создана папка $NewProfilePath" -ForegroundColor Gray
        }

        # Ожидание создания записи в реестре или создание вручную
        Write-Host "Настройка реестра..." -ForegroundColor Yellow
        $timeout = 30
        $count = 0
        
        # Ждем появления записи в реестре
        while (!(Test-Path $RegistryPath) -and $count -lt $timeout) {
            Start-Sleep -Seconds 1
            $count++
            if ($count % 5 -eq 0) {
                Write-Host "   Ожидание записи в реестре... ($count/$timeout)" -ForegroundColor Gray
            }
        }

        # Если запись не появилась - создаем вручную
        if (!(Test-Path $RegistryPath)) {
            Write-Host "   Создание записи в реестре вручную..." -ForegroundColor Gray
            try {
                New-Item -Path $RegistryPath -Force | Out-Null
                Set-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -Value $NewProfilePath -Type String
                Set-ItemProperty -Path $RegistryPath -Name "Flags" -Value 0 -Type DWord
                Set-ItemProperty -Path $RegistryPath -Name "State" -Value 0 -Type DWord
                Write-Host "   Запись в реестре создана" -ForegroundColor Green
            } catch {
                Write-Host "   Не удалось создать запись в реестре: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            # Если запись есть - изменяем путь
            try {
                Set-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -Value $NewProfilePath
                Write-Host "Путь профиля изменен в реестре" -ForegroundColor Green
            } catch {
                Write-Host "Не удалось изменить путь в реестре: $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        Write-Host "`Пользователь $username создан и настроен для диска D!" -ForegroundColor Green
        Write-Host "Путь профиля: $NewProfilePath" -ForegroundColor Cyan
        Write-Host "При первом входе профиль будет создан на диске D" -ForegroundColor Cyan

    }
    catch {
        Write-Host "Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    }
    Pause
}

# === 2. Перенос существующего пользователя ===
function Move-UserProfile {
    try {
        $users = Get-UserList
        if ($users.Count -eq 0) {
            Write-Host "Нет доступных пользователей для переноса." -ForegroundColor Red
            Pause
            return
        }

        Write-Host "Список пользователей:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $users.Count; $i++) {
            $user = $users[$i]
            $userSID = $user.SID.Value
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$userSID"
            $currentPath = "Профиль не создан"
            $color = "Gray"
            
            if (Test-Path $regPath) {
                $profilePath = (Get-ItemProperty -Path $regPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue).ProfileImagePath
                if ($profilePath) {
                    $currentPath = $profilePath
                    $color = if ($profilePath.StartsWith("C:\")) { "Red" } else { "Green" }
                }
            }
            
            Write-Host "[$($i+1)] " -NoNewline
            Write-Host "$($user.Name)" -NoNewline -ForegroundColor White
            Write-Host " - $currentPath" -ForegroundColor $color
        }

        $choice = Read-Host "`nВведите номер пользователя для переноса"
        if ($choice -notmatch '^\d+$' -or $choice -lt 1 -or $choice -gt $users.Count) {
            Write-Host "Неверный выбор." -ForegroundColor Red
            Pause
            return
        }

        $Username = $users[$choice-1].Name
        $User = Get-LocalUser -Name $Username
        $SID = $User.SID.Value
        $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$SID"
        $NewProfilePath = "D:\Users\$Username"

        if (!(Test-Path $RegistryPath)) {
            Write-Host "В реестре нет профиля для $Username (пользователь не входил в систему)." -ForegroundColor Red
            Pause
            return
        }

        # Получаем текущий путь профиля
        $CurrentPath = (Get-ItemProperty -Path $RegistryPath -Name "ProfileImagePath").ProfileImagePath
        
        if ($CurrentPath.StartsWith("D:\")) {
            Write-Host "Пользователь $Username уже находится на диске D" -ForegroundColor Yellow
            Pause
            return
        }

        Write-Host "Текущий путь: $CurrentPath" -ForegroundColor Yellow
        Write-Host "Новый путь: $NewProfilePath" -ForegroundColor Green

        # Проверка активности пользователя
        $sessions = quser 2>$null | Where-Object { $_ -match $Username }
        if ($sessions) {
            Write-Host "Пользователь $Username активен! Завершите сеанс перед переносом." -ForegroundColor Red
            Pause
            return
        }

        # Создание папки на диске D
        if (!(Test-Path "D:\Users")) { 
            New-Item -ItemType Directory -Path "D:\Users" -Force | Out-Null 
        }

        # Копирование профиля
        if (Test-Path $CurrentPath) {
            Write-Host "Копирование файлов профиля..." -ForegroundColor Yellow
            robocopy $CurrentPath $NewProfilePath /E /COPYALL /R:3 /W:1 /NFL /NDL | Out-Null
            
            if ($LASTEXITCODE -le 7) {
                Write-Host "Файлы скопированы успешно" -ForegroundColor Green
            } else {
                Write-Host "Ошибка при копировании файлов (код: $LASTEXITCODE)" -ForegroundColor Red
                Pause
                return
            }
        }

        # Изменение пути в реестре
        Set-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -Value $NewProfilePath
        Write-Host "Путь в реестре изменен" -ForegroundColor Green

        # Предложение удаления старой папки
        if (Test-Path $CurrentPath) {
            $deleteChoice = Read-Host "Удалить исходную папку $CurrentPath? (Y/N)"
            if ($deleteChoice -in @('Y','y')) {
                Remove-Item -Path $CurrentPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "Исходная папка удалена" -ForegroundColor Green
            }
        }

        Write-Host "Профиль $Username успешно перенесён на диск D!" -ForegroundColor Green
        Write-Host "Рекомендуется перезагрузить систему." -ForegroundColor Cyan
    }
    catch {
        Write-Host "Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    }
    Pause
}

# === 3. Удаление пользователя ===
function Remove-User {
    try {
        $users = Get-UserList
        if ($users.Count -eq 0) {
            Write-Host "Нет доступных пользователей для удаления." -ForegroundColor Red
            Pause
            return
        }

        Write-Host "Список пользователей:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $users.Count; $i++) {
            Write-Host "[$($i+1)] $($users[$i].Name)"
        }

        $choice = Read-Host "`nВведите номер пользователя для удаления"
        if ($choice -notmatch '^\d+$' -or $choice -lt 1 -or $choice -gt $users.Count) {
            Write-Host "Неверный выбор." -ForegroundColor Red
            Pause
            return
        }

        $Username = $users[$choice-1].Name

        # Получение SID и пути профиля
        $User = Get-LocalUser -Name $Username
        $SID = $User.SID.Value
        $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$SID"
        
        $ProfilePath = ""
        if (Test-Path $RegistryPath) {
            $ProfilePath = (Get-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue).ProfileImagePath
        }

        # Подтверждение удаления
        Write-Host "ВНИМАНИЕ! Это действие необратимо!" -ForegroundColor Red
        Write-Host "Будет удалено:" -ForegroundColor Yellow
        Write-Host "- Учетная запись: $Username" -ForegroundColor Yellow
        if ($ProfilePath) {
            Write-Host "- Папка профиля: $ProfilePath" -ForegroundColor Yellow
        }
        Write-Host "- Папки C:\Users\$Username и D:\Users\$Username (если существуют)" -ForegroundColor Yellow
        Write-Host "- Запись в реестре" -ForegroundColor Yellow
        
        $confirm = Read-Host "`nВы уверены? Введите 'YES' для подтверждения"
        if ($confirm -ne "YES") {
            Write-Host "Удаление отменено." -ForegroundColor Yellow
            Pause
            return
        }

        # Проверка активности пользователя
        $sessions = quser 2>$null | Where-Object { $_ -match $Username }
        if ($sessions) {
            Write-Host "Пользователь $Username активен! Завершите сеанс перед удалением." -ForegroundColor Red
            Pause
            return
        }

        # Удаление учетной записи
        Remove-LocalUser -Name $Username -ErrorAction Stop
        Write-Host "Учетная запись удалена" -ForegroundColor Green

        # Удаление папок профиля
        $PathsToDelete = @("C:\Users\$Username", "D:\Users\$Username")
        if ($ProfilePath -and $ProfilePath -notin $PathsToDelete) {
            $PathsToDelete += $ProfilePath
        }

        foreach ($path in $PathsToDelete) {
            if (Test-Path $path) {
                Write-Host "Удаление $path..." -ForegroundColor Yellow
                try {
                    Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                    Write-Host "Удалено" -ForegroundColor Green
                } catch {
                    Write-Host "Не удалось удалить: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }

        # Удаление записи из реестра
        if (Test-Path $RegistryPath) {
            try {
                Remove-Item -Path $RegistryPath -Recurse -Force
                Write-Host "Запись в реестре удалена" -ForegroundColor Green
            } catch {
                Write-Host "Не удалось удалить запись из реестра: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        Write-Host "Пользователь $Username полностью удален!" -ForegroundColor Green
    }
    catch {
        Write-Host "Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    }
    Pause
}

# === Главное меню ===
function Show-Menu {
    Clear-Host
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "   МЕНЮ УПРАВЛЕНИЯ ПОЛЬЗОВАТЕЛЯМИ Windows" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "1. Создать нового пользователя (с размещением на D:)" -ForegroundColor Yellow
    Write-Host "2. Перенести существующего пользователя на диск D" -ForegroundColor Yellow
    Write-Host "3. Удалить пользователя (полное удаление)" -ForegroundColor Yellow
    Write-Host "0. Выход" -ForegroundColor Red
    Write-Host ""
}

# === Основной цикл ===
do {
    Show-Menu
    $choice = Read-Host "Выберите действие"

    switch ($choice) {
        "1" { Create-User }
        "2" { Move-UserProfile }
        "3" { Remove-User }
        "0" { Write-Host "Выход..." -ForegroundColor Green }
        default {
            Write-Host "Неверный выбор!" -ForegroundColor Red
            Pause
        }
    }
} while ($choice -ne "0")
