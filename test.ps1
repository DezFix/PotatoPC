# Перенос профилей C -> D (оптимизированная версия)
# Требует запуск от имени администратора

# -----------------------
# Логирование в память
# -----------------------
$global:Log = New-Object System.Collections.Generic.List[String]

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$ts] $Message"
    $global:Log.Add($line)
    Write-Host $line -ForegroundColor $Color
}

function Show-Log {
    if ($global:Log.Count -eq 0) {
        Write-Host "Лог пуст." -ForegroundColor Yellow
        return
    }
    try {
        $tmpFile = Join-Path $env:TEMP ("UserProfileMoveLog_{0}.log" -f ([guid]::NewGuid().ToString()))
        $global:Log | Out-File -FilePath $tmpFile -Encoding UTF8
        Write-Log "Открываю лог в Notepad: $tmpFile"
        Start-Process -FilePath "notepad.exe" -ArgumentList $tmpFile -Wait
        Remove-Item -Path $tmpFile -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Log "Не удалось открыть лог: $($_.Exception.Message)" "Red"
    }
}

# -----------------------
# Проверка прав администратора
# -----------------------
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Host "Скрипт должен быть запущен от имени администратора!" -ForegroundColor Red
    Write-Host "Нажмите любую клавишу для выхода..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

# -----------------------
# Проверка активных сессий пользователя
# -----------------------
function Get-UserSessions {
    param([string]$Username)
    $sessions = @()
    try {
        $quserOutput = quser 2>$null
        if ($quserOutput) {
            foreach ($line in $quserOutput) {
                if ($line -match $Username) {
                    $tokens = $line -split '\s+'
                    $id = ($tokens | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1)
                    if ($id) { $sessions += $id }
                }
            }
        }
    } catch {
        # Игнорируем ошибки
    }
    return $sessions
}

function Try-LogoffUser {
    param([string]$Username)
    $sessions = Get-UserSessions -Username $Username
    if ($sessions.Count -eq 0) {
        return $true
    }

    foreach ($sessionId in $sessions) {
        Write-Log "Завершение сессии $sessionId для пользователя $Username"
        try {
            logoff $sessionId 2>$null
            Start-Sleep -Seconds 2
        } catch {
            Write-Log "Не удалось завершить сессию $($sessionId): $($_.Exception.Message)" "Red"
            return $false
        }
    }
    return $true
}

# -----------------------
# Создание пользователя с размещением на диске D
# -----------------------
function Create-AndMoveUser {
    param(
        [string]$Username,
        [string]$Password = "",
        [string]$FullName = ""
    )

    try {
        Write-Log "Создание пользователя: $Username" "Yellow"

        # Создание пользователя с учётом пустого пароля и полного имени
        if ([string]::IsNullOrWhiteSpace($Password)) {
            if ([string]::IsNullOrWhiteSpace($FullName)) {
                New-LocalUser -Name $Username -NoPassword -ErrorAction Stop
            } else {
                New-LocalUser -Name $Username -NoPassword -FullName $FullName -ErrorAction Stop
            }
        } else {
            $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
            if ([string]::IsNullOrWhiteSpace($FullName)) {
                New-LocalUser -Name $Username -Password $SecurePassword -ErrorAction Stop
            } else {
                New-LocalUser -Name $Username -Password $SecurePassword -FullName $FullName -ErrorAction Stop
            }
        }

        # Добавление в группу пользователей
        try {
            Add-LocalGroupMember -Group "Users" -Member $Username -ErrorAction Stop
            Write-Log "Пользователь добавлен в группу Users" "Green"
        } catch {
            try { 
                Add-LocalGroupMember -Group "Пользователи" -Member $Username -ErrorAction Stop
                Write-Log "Пользователь добавлен в группу Пользователи" "Green"
            } catch {
                Write-Log "Не удалось добавить в группу пользователей (не критично)" "Yellow"
            }
        }

        # Получение SID пользователя
        $User = Get-LocalUser -Name $Username -ErrorAction Stop
        $UserSID = $User.SID.Value
        $NewProfilePath = "D:\Users\$Username"
        $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$UserSID"

        Write-Log "SID пользователя: $UserSID"

        # Создание папки профиля на диске D
        if (!(Test-Path "D:\Users")) {
            New-Item -ItemType Directory -Path "D:\Users" -Force | Out-Null
            Write-Log "Создана папка D:\Users"
        }

        # Ожидание создания записи в реестре и её изменение
        Write-Log "Ожидание создания записи профиля в реестре..."
        $timeout = 30
        $count = 0
        while (!(Test-Path $RegistryPath) -and $count -lt $timeout) {
            Start-Sleep -Seconds 1
            $count++
        }

        if (Test-Path $RegistryPath) {
            Set-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -Value $NewProfilePath -Force
            Write-Log "Путь профиля в реестре установлен: $NewProfilePath" "Green"
        } else {
            # Создаем запись вручную, если система не создала
            New-Item -Path $RegistryPath -Force | Out-Null
            Set-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -Value $NewProfilePath -Force
            Write-Log "Создана и настроена запись в реестре вручную" "Green"
        }

        Write-Log "Пользователь $Username успешно создан и настроен для диска D" "Green"

    } catch {
        Write-Log "Ошибка при создании пользователя: $($_.Exception.Message)" "Red"
    }
}

# -----------------------
# Перенос существующего пользователя
# -----------------------
function Move-ExistingUser {
    param([string]$Username)

    try {
        Write-Log "Перенос пользователя: $Username" "Yellow"

        # Получение информации о пользователе
        $User = Get-LocalUser -Name $Username -ErrorAction Stop
        $UserSID = $User.SID.Value
        $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$UserSID"

        if (!(Test-Path $RegistryPath)) {
            Write-Log "Не найдена запись профиля в реестре для пользователя $Username" "Red"
            return
        }

        # Получение текущего пути профиля
        $CurrentPath = (Get-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue).ProfileImagePath
        if (-not $CurrentPath) {
            Write-Log "Не удалось определить текущий путь профиля" "Red"
            return
        }

        $NewPath = "D:\Users\$Username"
        Write-Log "Текущий путь: $CurrentPath"
        Write-Log "Новый путь: $NewPath"

        # Проверка, не находится ли пользователь уже на диске D
        if ($CurrentPath.StartsWith("D:\")) {
            Write-Log "Пользователь $Username уже находится на диске D" "Yellow"
            return
        }

        # Проверка активных сессий
        $sessions = Get-UserSessions -Username $Username
        if ($sessions.Count -gt 0) {
            Write-Log "Найдены активные сессии для $Username" "Red"
            Write-Host "Завершить сеансы автоматически? (Y/N): " -NoNewline
            $choice = Read-Host
            if ($choice -in @('Y','y')) {
                $success = Try-LogoffUser -Username $Username
                if (-not $success) {
                    Write-Log "Не удалось завершить сеансы. Операция отменена." "Red"
                    return
                }
                Start-Sleep -Seconds 3
            } else {
                Write-Log "Операция отменена пользователем" "Red"
                return
            }
        }

        # Создание папки на диске D
        if (!(Test-Path "D:\Users")) { 
            New-Item -ItemType Directory -Path "D:\Users" -Force | Out-Null 
        }

        # Копирование профиля
        Write-Log "Копирование файлов профиля..."
        robocopy $CurrentPath $NewPath /E /COPYALL /R:3 /W:1 /NFL /NDL | Out-Null
        $exitCode = $LASTEXITCODE

        if ($exitCode -le 7) {
            Write-Log "Файлы успешно скопированы (код: $exitCode)" "Green"
            
            # Изменение пути в реестре
            Set-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -Value $NewPath -Force
            Write-Log "Путь профиля в реестре изменен на: $NewPath" "Green"

            # Предложение удаления исходной папки
            Write-Host "Удалить исходную папку $CurrentPath? (Y/N): " -NoNewline
            $deleteChoice = Read-Host
            if ($deleteChoice -in @('Y','y')) {
                try {
                    Remove-Item -Path $CurrentPath -Recurse -Force
                    Write-Log "Исходная папка удалена" "Green"
                } catch {
                    Write-Log "Не удалось удалить исходную папку: $($_.Exception.Message)" "Yellow"
                }
            }

            Write-Log "Пользователь $Username успешно перенесен на диск D!" "Green"
        } else {
            Write-Log "Ошибка при копировании файлов (код: $exitCode)" "Red"
        }

    } catch {
        Write-Log "Ошибка при переносе пользователя: $($_.Exception.Message)" "Red"
    }
}

# -----------------------
# Удаление пользователя
# -----------------------
function Remove-UserProfile {
    param([string]$Username)

    try {
        Write-Log "Удаление пользователя: $Username" "Yellow"

        # Получение информации о пользователе
        try {
            $User = Get-LocalUser -Name $Username -ErrorAction Stop
            $UserSID = $User.SID.Value
        } catch {
            Write-Log "Пользователь $Username не найден" "Red"
            return
        }

        $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$UserSID"

        # Получение пути профиля из реестра
        $ProfilePath = ""
        if (Test-Path $RegistryPath) {
            $ProfilePath = (Get-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue).ProfileImagePath
        }

        Write-Log "SID пользователя: $UserSID"
        if ($ProfilePath) {
            Write-Log "Путь профиля: $ProfilePath"
        }

        # Проверка активных сессий
        $sessions = Get-UserSessions -Username $Username
        if ($sessions.Count -gt 0) {
            Write-Log "Найдены активные сессии для $Username" "Red"
            Write-Host "Завершить сеансы автоматически? (Y/N): " -NoNewline
            $choice = Read-Host
            if ($choice -in @('Y','y')) {
                $success = Try-LogoffUser -Username $Username
                if (-not $success) {
                    Write-Log "Не удалось завершить сеансы. Операция отменена." "Red"
                    return
                }
                Start-Sleep -Seconds 3
            } else {
                Write-Log "Операция отменена пользователем" "Red"
                return
            }
        }

        # Подтверждение удаления
        Write-Host "`nВНИМАНИЕ! Это действие необратимо!" -ForegroundColor Red
        Write-Host "Будет удалено:" -ForegroundColor Yellow
        Write-Host "- Учетная запись пользователя $Username" -ForegroundColor Yellow
        Write-Host "- Папка профиля: $ProfilePath" -ForegroundColor Yellow
        Write-Host "- Запись в реестре" -ForegroundColor Yellow
        Write-Host "`nВы уверены что хотите удалить пользователя $Username? (Y/N): " -NoNewline -ForegroundColor Red
        
        $confirmChoice = Read-Host
        if ($confirmChoice -notin @('Y','y')) {
            Write-Log "Удаление отменено пользователем" "Yellow"
            return
        }

        # Удаление учетной записи пользователя
        try {
            Remove-LocalUser -Name $Username -ErrorAction Stop
            Write-Log "Учетная запись пользователя удалена" "Green"
        } catch {
            Write-Log "Не удалось удалить учетную запись: $($_.Exception.Message)" "Red"
            return
        }

        # Удаление папки профиля
        if ($ProfilePath -and (Test-Path $ProfilePath)) {
            Write-Log "Удаление папки профиля: $ProfilePath"
            try {
                # Даем системе время на освобождение файлов
                Start-Sleep -Seconds 2
                
                # Попытка обычного удаления
                Remove-Item -Path $ProfilePath -Recurse -Force -ErrorAction Stop
                Write-Log "Папка профиля удалена" "Green"
            } catch {
                Write-Log "Не удалось удалить папку обычным способом, пробуем robocopy..." "Yellow"
                try {
                    # Создаем пустую временную папку и "копируем" её поверх профиля (очищаем)
                    $emptyDir = Join-Path $env:TEMP "EmptyDir_$([guid]::NewGuid().ToString())"
                    New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
                    
                    robocopy $emptyDir $ProfilePath /MIR /R:3 /W:1 | Out-Null
                    Remove-Item -Path $ProfilePath -Recurse -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path $emptyDir -Force -ErrorAction SilentlyContinue
                    
                    if (!(Test-Path $ProfilePath)) {
                        Write-Log "Папка профиля удалена с помощью robocopy" "Green"
                    } else {
                        Write-Log "Не удалось полностью удалить папку профиля" "Yellow"
                    }
                } catch {
                    Write-Log "Ошибка при удалении папки: $($_.Exception.Message)" "Red"
                }
            }
        }

        # Удаление записи из реестра
        if (Test-Path $RegistryPath) {
            try {
                Remove-Item -Path $RegistryPath -Recurse -Force -ErrorAction Stop
                Write-Log "Запись профиля удалена из реестра" "Green"
            } catch {
                Write-Log "Не удалось удалить запись из реестра: $($_.Exception.Message)" "Red"
            }
        }

        Write-Log "Пользователь $Username успешно удален!" "Green"

    } catch {
        Write-Log "Ошибка при удалении пользователя: $($_.Exception.Message)" "Red"
    }
}

# -----------------------
# Показать всех пользователей
# -----------------------
function Show-AllUsers {
    Write-Host "`n=== СПИСОК ПОЛЬЗОВАТЕЛЕЙ ===" -ForegroundColor Cyan
    Write-Host "ID`tИмя пользователя`t`tПуть профиля" -ForegroundColor White
    Write-Host "=" * 80 -ForegroundColor White

    $users = Get-LocalUser | Where-Object { 
        $_.Enabled -eq $true -and 
        $_.Name -notin @("DefaultAccount", "WDAGUtilityAccount", "Guest") 
    }
    
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

# -----------------------
# Главное меню
# -----------------------
function Show-Menu {
    Clear-Host
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host "    ПЕРЕНОС ПРОФИЛЕЙ ПОЛЬЗОВАТЕЛЕЙ C -> D" -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Создать нового пользователя и разместить на диске D" -ForegroundColor Yellow
    Write-Host "2. Перенести существующего пользователя на диск D" -ForegroundColor Yellow
    Write-Host "3. Удалить пользователя (полное удаление)" -ForegroundColor Red
    Write-Host "4. Показать всех пользователей" -ForegroundColor Yellow
    Write-Host "5. Показать лог операций" -ForegroundColor Cyan
    Write-Host "0. Выход" -ForegroundColor Red
    Write-Host ""
    Write-Host "Выберите действие (0-5): " -NoNewline -ForegroundColor White
}

# -----------------------
# Основной цикл программы
# -----------------------
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
                Get-LocalUser -Name $username -ErrorAction Stop | Out-Null
                Write-Host "Пользователь '$username' уже существует!" -ForegroundColor Red
                Write-Host "Нажмите любую клавишу для продолжения..."
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                break
            } catch {
                # Пользователь не найден - продолжаем
            }

            # Ввод пароля (можно оставить пустым)
            Write-Host "Введите пароль (Enter для пустого пароля): " -NoNewline
            $passwordSecure = Read-Host -AsSecureString
            $password = ""
            if ($passwordSecure.Length -gt 0) {
                $password = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwordSecure))
            }

            $fullname = Read-Host "Введите полное имя (необязательно)"

            Create-AndMoveUser -Username $username -Password $password -FullName $fullname

            Write-Host "`nНажмите любую клавишу для продолжения..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }

        "2" {
            Clear-Host
            $userList = Show-AllUsers

            if (-not $userList -or $userList.Count -eq 0) {
                Write-Host "Пользователи не найдены!" -ForegroundColor Red
                Write-Host "Нажмите любую клавишу для продолжения..."
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                break
            }

            Write-Host "`nВведите номер пользователя для переноса (0 - отмена): " -NoNewline
            $userChoice = Read-Host

            if ($userChoice -eq "0") { break }

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

            if (-not $userList -or $userList.Count -eq 0) {
                Write-Host "Пользователи не найдены!" -ForegroundColor Red
                Write-Host "Нажмите любую клавишу для продолжения..."
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                break
            }

            Write-Host "`nВведите номер пользователя для УДАЛЕНИЯ (0 - отмена): " -NoNewline -ForegroundColor Red
            $userChoice = Read-Host

            if ($userChoice -eq "0") { break }

            try {
                $selectedIndex = [int]$userChoice
                $selectedUser = $userList | Where-Object { $_.Index -eq $selectedIndex }

                if ($selectedUser) {
                    # Дополнительная защита от удаления системных пользователей
                    if ($selectedUser.Name -in @("Administrator", "Администратор", $env:USERNAME)) {
                        Write-Host "Нельзя удалить системного пользователя или текущего пользователя!" -ForegroundColor Red
                    } else {
                        Remove-UserProfile -Username $selectedUser.Name
                    }
                } else {
                    Write-Host "Неверный номер пользователя!" -ForegroundColor Red
                }
            } catch {
                Write-Host "Неверный ввод!" -ForegroundColor Red
            }

            Write-Host "`nНажмите любую клавишу для продолжения..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }

        "4" {
            Clear-Host
            $userList = Show-AllUsers

            if (-not $userList -or $userList.Count -eq 0) {
                Write-Host "Пользователи не найдены!" -ForegroundColor Red
            } else {
                Write-Host "`nЛегенда: " -ForegroundColor White
                Write-Host "Красный цвет - профиль на диске C" -ForegroundColor Red
                Write-Host "Зеленый цвет - профиль на диске D" -ForegroundColor Green
            }

            Write-Host "`nНажмите любую клавишу для продолжения..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }

        "4" {
            Clear-Host
            $userList = Show-AllUsers

            if (-not $userList -or $userList.Count -eq 0) {
                Write-Host "Пользователи не найдены!" -ForegroundColor Red
            } else {
                Write-Host "`nЛегенда: " -ForegroundColor White
                Write-Host "Красный цвет - профиль на диске C" -ForegroundColor Red
                Write-Host "Зеленый цвет - профиль на диске D" -ForegroundColor Green
            }

            Write-Host "`nНажмите любую клавишу для продолжения..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }

        "5" {
            Clear-Host
            Show-Log
        }

        "0" {
            Write-Host "Выход из программы..." -ForegroundColor Green
            if ($global:Log.Count -gt 0) {
                Write-Host "Показать финальный лог? (Y/N): " -NoNewline
                $showLog = Read-Host
                if ($showLog -in @('Y','y')) {
                    Show-Log
                }
            }
            break
        }

        default {
            Write-Host "Неверный выбор! Попробуйте еще раз." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
} while ($choice -ne "0")
