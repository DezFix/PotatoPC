# Скрипт для переноса профилей пользователей с диска C на D
# Требует запуск от имени администратора

# Проверка прав администратора
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Host "Скрипт должен быть запущен от имени администратора!" -ForegroundColor Red
    Write-Host "Нажмите любую клавишу для выхода..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

# Функция для создания пользователя и переноса на диск D
function Create-AndMoveUser {
    param(
        [string]$Username,
        [string]$Password,
        [string]$FullName = ""
    )
    
    try {
        Write-Host "`nСоздание пользователя: $Username" -ForegroundColor Yellow
        
        # Создание пользователя
        $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        New-LocalUser -Name $Username -Password $SecurePassword -FullName $FullName -PasswordNeverExpires
        
        # Добавление в группу пользователей
        Add-LocalGroupMember -Group "Пользователи" -Member $Username
        
        Write-Host "Пользователь $Username успешно создан" -ForegroundColor Green
        
        # Получение SID нового пользователя
        $User = Get-LocalUser -Name $Username
        $UserSID = $User.SID.Value
        
        # Путь к новому профилю на диске D
        $NewProfilePath = "D:\Users\$Username"
        
        # Изменение реестра ПЕРЕД созданием профиля
        Write-Host "Изменение пути в реестре..." -ForegroundColor Yellow
        $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$UserSID"
        
        # Ожидание создания записи в реестре (иногда требуется время)
        $timeout = 30
        $count = 0
        while (!(Test-Path $RegistryPath) -and $count -lt $timeout) {
            Start-Sleep -Seconds 1
            $count++
        }
        
        if (Test-Path $RegistryPath) {
            Set-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -Value $NewProfilePath
            Write-Host "Путь профиля в реестре изменен на: $NewProfilePath" -ForegroundColor Green
        } else {
            Write-Host "Не удалось найти запись в реестре для пользователя" -ForegroundColor Red
            return
        }
        
        # Создание директории на диске D
        if (!(Test-Path "D:\Users")) {
            New-Item -ItemType Directory -Path "D:\Users" -Force
        }
        
        Write-Host "Пользователь $Username успешно создан и настроен для диска D" -ForegroundColor Green
        
    } catch {
        Write-Host "Ошибка при создании пользователя: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Функция для переноса существующего пользователя
function Move-ExistingUser {
    param(
        [string]$Username
    )
    
    try {
        Write-Host "`nПеренос пользователя: $Username" -ForegroundColor Yellow
        
        # Получение информации о пользователе
        $User = Get-LocalUser -Name $Username -ErrorAction Stop
        $UserSID = $User.SID.Value
        
        # Путь в реестре
        $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$UserSID"
        
        if (!(Test-Path $RegistryPath)) {
            Write-Host "Не найдена запись профиля в реестре для пользователя $Username" -ForegroundColor Red
            return
        }
        
        # Получение текущего пути профиля
        $CurrentPath = (Get-ItemProperty -Path $RegistryPath -Name "ProfileImagePath").ProfileImagePath
        $NewPath = "D:\Users\$Username"
        
        Write-Host "Текущий путь: $CurrentPath"
        Write-Host "Новый путь: $NewPath"
        
        # Проверка, не находится ли пользователь уже на диске D
        if ($CurrentPath.StartsWith("D:\")) {
            Write-Host "Пользователь $Username уже находится на диске D" -ForegroundColor Yellow
            return
        }
        
        # Проверка активности пользователя
        $ActiveSessions = quser 2>$null | Where-Object { $_ -match $Username }
        if ($ActiveSessions) {
            Write-Host "Пользователь $Username активен. Необходимо завершить все сеансы!" -ForegroundColor Red
            Write-Host "Хотите принудительно завершить сеанс? (Y/N): " -NoNewline
            $choice = Read-Host
            if ($choice -eq 'Y' -or $choice -eq 'y') {
                logoff (($ActiveSessions -split '\s+')[2])
                Start-Sleep -Seconds 5
            } else {
                return
            }
        }
        
        # Создание папки на диске D
        if (!(Test-Path "D:\Users")) {
            New-Item -ItemType Directory -Path "D:\Users" -Force
        }
        
        # Изменение реестра ПЕРЕД переносом
        Write-Host "Изменение пути в реестре..." -ForegroundColor Yellow
        Set-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -Value $NewPath
        
        # Перенос папки профиля
        if (Test-Path $CurrentPath) {
            Write-Host "Копирование файлов профиля..." -ForegroundColor Yellow
            robocopy $CurrentPath $NewPath /E /COPYALL /R:3 /W:1 /NFL /NDL
            
            if ($LASTEXITCODE -le 7) {  # robocopy коды завершения 0-7 считаются успешными
                Write-Host "Файлы успешно скопированы" -ForegroundColor Green
                
                # Подтверждение удаления старой папки
                Write-Host "Удалить исходную папку? (Y/N): " -NoNewline
                $deleteChoice = Read-Host
                if ($deleteChoice -eq 'Y' -or $deleteChoice -eq 'y') {
                    Remove-Item -Path $CurrentPath -Recurse -Force
                    Write-Host "Исходная папка удалена" -ForegroundColor Green
                }
            } else {
                Write-Host "Ошибка при копировании файлов. Возвращаю изменения в реестре..." -ForegroundColor Red
                Set-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -Value $CurrentPath
                return
            }
        }
        
        Write-Host "Пользователь $Username успешно перенесен на диск D!" -ForegroundColor Green
        
    } catch {
        Write-Host "Ошибка при переносе пользователя: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Функция для показа всех пользователей
function Show-AllUsers {
    Write-Host "`n=== СПИСОК ПОЛЬЗОВАТЕЛЕЙ ===" -ForegroundColor Cyan
    Write-Host "ID`tИмя пользователя`t`tПуть профиля" -ForegroundColor White
    Write-Host "=" * 80 -ForegroundColor White
    
    $users = Get-LocalUser | Where-Object { $_.Enabled -eq $true -and $_.Name -ne "DefaultAccount" -and $_.Name -ne "WDAGUtilityAccount" }
    $userList = @()
    
    $index = 1
    foreach ($user in $users) {
        try {
            $userSID = $user.SID.Value
            $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$userSID"
            
            if (Test-Path $registryPath) {
                $profilePath = (Get-ItemProperty -Path $registryPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue).ProfileImagePath
                if ($profilePath) {
                    $diskLetter = $profilePath.Substring(0,1)
                    $colorDisk = if ($diskLetter -eq "C") { "Red" } else { "Green" }
                    
                    Write-Host "$index`t$($user.Name)`t`t`t" -NoNewline
                    Write-Host "$profilePath" -ForegroundColor $colorDisk
                    
                    $userList += [PSCustomObject]@{
                        Index = $index
                        Name = $user.Name
                        SID = $userSID
                        ProfilePath = $profilePath
                    }
                    $index++
                }
            }
        } catch {
            # Игнорируем ошибки для системных аккаунтов
        }
    }
    
    return $userList
}

# Главное меню
function Show-Menu {
    Clear-Host
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host "    ПЕРЕНОС ПРОФИЛЕЙ ПОЛЬЗОВАТЕЛЕЙ C -> D" -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Создать нового пользователя и разместить на диске D" -ForegroundColor Yellow
    Write-Host "2. Перенести существующего пользователя на диск D" -ForegroundColor Yellow
    Write-Host "3. Показать всех пользователей" -ForegroundColor Yellow
    Write-Host "0. Выход" -ForegroundColor Red
    Write-Host ""
    Write-Host "Выберите действие (0-3): " -NoNewline -ForegroundColor White
}

# Основной цикл программы
do {
    Show-Menu
    $choice = Read-Host
    
    switch ($choice) {
        "1" {
            Clear-Host
            Write-Host "=== СОЗДАНИЕ НОВОГО ПОЛЬЗОВАТЕЛЯ ===" -ForegroundColor Cyan
            
            $username = Read-Host "Введите имя пользователя"
            if ([string]::IsNullOrWhiteSpace($username)) {
                Write-Host "Имя пользователя не может быть пустым!" -ForegroundColor Red
                Write-Host "Нажмите любую клавишу для продолжения..."
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                break
            }
            
            # Проверка существования пользователя
            try {
                $existingUser = Get-LocalUser -Name $username -ErrorAction Stop
                Write-Host "Пользователь с именем '$username' уже существует!" -ForegroundColor Red
                Write-Host "Нажмите любую клавишу для продолжения..."
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                break
            } catch {
                # Пользователь не существует - это хорошо
            }
            
            $password = Read-Host "Введите пароль" -AsSecureString
            $passwordText = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
            
            $fullname = Read-Host "Введите полное имя (необязательно)"
            
            Create-AndMoveUser -Username $username -Password $passwordText -FullName $fullname
            
            Write-Host "`nНажмите любую клавишу для продолжения..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        
        "2" {
            Clear-Host
            $userList = Show-AllUsers
            
            if ($userList.Count -eq 0) {
                Write-Host "Пользователи не найдены!" -ForegroundColor Red
                Write-Host "Нажмите любую клавишу для продолжения..."
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                break
            }
            
            Write-Host "`nВведите номер пользователя для переноса (0 - отмена): " -NoNewline
            $userChoice = Read-Host
            
            if ($userChoice -eq "0") {
                break
            }
            
            try {
                $selectedIndex = [int]$userChoice
                $selectedUser = $userList | Where-Object { $_.Index -eq $selectedIndex }
                
                if ($selectedUser) {
                    Move-ExistingUser -Username $selectedUser.Name
                } else {
                    Write-Host "Неверный номер пользователя!" -ForegroundColor Red
                }
            } catch {
                Write-Host "Неверный ввод!" -ForegroundColor Red
            }
            
            Write-Host "`nНажмите любую клавишу для продолжения..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        
        "3" {
            Clear-Host
            $userList = Show-AllUsers
            
            if ($userList.Count -eq 0) {
                Write-Host "Пользователи не найдены!" -ForegroundColor Red
            } else {
                Write-Host "`nЛегенда: " -ForegroundColor White
                Write-Host "Красный цвет - профиль на диске C" -ForegroundColor Red
                Write-Host "Зеленый цвет - профиль на диске D" -ForegroundColor Green
            }
            
            Write-Host "`nНажмите любую клавишу для продолжения..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        
        "0" {
            Write-Host "Выход из программы..." -ForegroundColor Green
            break
        }
        
        default {
            Write-Host "Неверный выбор! Попробуйте еще раз." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
} while ($choice -ne "0")
