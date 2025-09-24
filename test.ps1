# Перенос профилей C -> D (исправленная и улучшенная версия)
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
    # Создаёт временный файл, открывает в Notepad, ждёт закрытия и удаляет файл
    if ($global:Log.Count -eq 0) {
        Write-Host "Лог пуст." -ForegroundColor Yellow
        return
    }
    try {
        $tmpFile = Join-Path $env:TEMP ("UserProfileMoveLog_{0}.log" -f ([guid]::NewGuid().ToString()))
        $global:Log | Out-File -FilePath $tmpFile -Encoding UTF8
        Write-Log "Открываю лог в Notepad: $tmpFile"
        Start-Process -FilePath "notepad.exe" -ArgumentList $tmpFile -Wait
    } catch {
        Write-Log "Не удалось открыть лог: $($_.Exception.Message)" "Red"
    } finally {
        # удаляем временный файл
        try { Remove-Item -Path $tmpFile -Force -ErrorAction SilentlyContinue } catch {}
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
# Вспомогательные функции
# -----------------------
function Export-ProfileListBackup {
    try {
        $backupFile = Join-Path $env:TEMP ("ProfileListBackup_{0}.reg" -f ([guid]::NewGuid().ToString()))
        & reg.exe export "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" $backupFile /y > $null 2>&1
        if (Test-Path $backupFile) {
            Write-Log "Экспорт ветки ProfileList в: $backupFile"
            return $backupFile
        } else {
            Write-Log "Не удалось экспортировать ProfileList (reg.exe вернул ошибку)." "Yellow"
            return $null
        }
    } catch {
        Write-Log "Ошибка при экспорте ProfileList: $($_.Exception.Message)" "Red"
        return $null
    }
}

function Get-UserSessions {
    param([string]$Username)
    $sessions = @()

    # Попытка через quser (если доступно)
    try {
        $quserOutput = quser 2>$null
        if ($quserOutput) {
            foreach ($line in $quserOutput) {
                $l = $line.Trim()
                if ($l -eq '') { continue }
                if ($l -match 'USERNAME\s+SESSIONNAME') { continue } # заголовок
                $tokens = $l -split '\s+'
                # обычно username - первый токен
                if ($tokens.Count -ge 1 -and $tokens[0] -eq $Username) {
                    # ищем первый числовой токен (ID)
                    $id = ($tokens | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1)
                    if ($id) { $sessions += $id }
                    else { $sessions += $null } # есть строка, но не нашли ID
                }
            }
        }
    } catch {
        # игнорируем
    }

    # Резервный WMI-подход: проверяем кто вошёл в систему
    if ($sessions.Count -eq 0) {
        try {
            $assoc = Get-CimInstance -ClassName Win32_LoggedOnUser -ErrorAction SilentlyContinue
            foreach ($a in $assoc) {
                $ante = $a.Antecedent -replace '.*Domain="([^"]+)",Name="([^"]+)".*','$1\$2'
                # сравниваем без учёта регистра и домена (берём имя пользователя из строки)
                if ($ante -match "\\$Username$") {
                    $sessions += $null
                }
            }
        } catch {}
    }

    return $sessions
}

function Try-LogoffUser {
    param([string]$Username)
    $sess = Get-UserSessions -Username $Username
    if ($sess.Count -eq 0) {
        return $true  # сессий не найдено
    }

    foreach ($s in $sess) {
        if ($s -and ($s -as [int])) {
            Write-Log "Попытка завершить сессию $s для пользователя $Username"
            try {
                logoff $s 2>$null
                Start-Sleep -Seconds 2
            } catch {
                # ИСПРАВЛЕНО: избегаем "$s:" внутри строки — используем $($s) перед двоеточием
                Write-Log "Не удалось завершить сессию $($s): $($_.Exception.Message)" "Red"
                return $false
            }
        } else {
            # сессия найдена, но ID неизвестен — просим пользователя вручную завершить сеанс
            Write-Log "Пользователь $Username найден в активных сессиях, но ID сеанса определить не удалось. Пожалуйста, завершите сеанс вручную." "Yellow"
            return $false
        }
    }
    return $true
}

# -----------------------
# Create-AndMoveUser
# -----------------------
function Create-AndMoveUser {
    param(
        [string]$Username,
        [string]$Password,
        [string]$FullName = ""
    )

    try {
        Write-Log "Создание пользователя: $Username" "Yellow"

        $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force

        if ([string]::IsNullOrWhiteSpace($FullName)) {
            New-LocalUser -Name $Username -Password $SecurePassword -ErrorAction Stop
        } else {
            New-LocalUser -Name $Username -Password $SecurePassword -FullName $FullName -ErrorAction Stop
        }

        # Добавление в группу Users (пытаемся с разными именами)
        try {
            Add-LocalGroupMember -Group "Users" -Member $Username -ErrorAction Stop
        } catch {
            try { Add-LocalGroupMember -Group "Пользователи" -Member $Username -ErrorAction Stop } catch {
                Write-Log "Не удалось добавить $Username в группу пользователей. Пользователь всё равно создан." "Yellow"
            }
        }

        Write-Log "Пользователь $Username создан." "Green"

        # Получение SID
        $User = Get-LocalUser -Name $Username -ErrorAction Stop
        $UserSID = $User.SID.Value

        $NewProfilePath = "D:\Users\$Username"
        $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$UserSID"

        # Резервная копия реестра
        $backup = Export-ProfileListBackup

        # Создаём папку на D
        if (!(Test-Path "D:\Users")) {
            New-Item -ItemType Directory -Path "D:\Users" -Force | Out-Null
            Write-Log "Создана папка D:\Users"
        }
        if (!(Test-Path $NewProfilePath)) {
            New-Item -ItemType Directory -Path $NewProfilePath -Force | Out-Null
            Write-Log "Создана папка профиля: $NewProfilePath"
        }

        # Попытка изменить/создать запись в реестре (если запись ещё не создана, создаём)
        try {
            if (!(Test-Path $RegistryPath)) {
                New-Item -Path $RegistryPath -Force | Out-Null
                Write-Log "Создана ветка реестра для SID $UserSID"
            }
            Set-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -Value $NewProfilePath -Force
            Write-Log "Путь профиля в реестре установлен: $NewProfilePath" "Green"
        } catch {
            Write-Log "Не удалось изменить реестр: $($_.Exception.Message)" "Red"
        }

        # Установка владельца и прав на папку (если учётная запись ещё не распознана системой, эти команды могут не назначить владельца, но попытка сделана)
        try {
            $owner = "$env:COMPUTERNAME\$Username"
            & icacls $NewProfilePath /setowner $owner /T /C > $null 2>&1
            # ИСПРАВЛЕНО: обёртка для $owner перед двоеточием
            & icacls $NewProfilePath /grant "$($owner):(OI)(CI)F" /T /C > $null 2>&1
            Write-Log "Попытка назначить владельца и права: $owner" "Green"
        } catch {
            Write-Log "Не удалось назначить права (icacls): $($_.Exception.Message)" "Yellow"
        }

    } catch {
        Write-Log "Ошибка при создании пользователя: $($_.Exception.Message)" "Red"
    } finally {
        Show-Log
    }
}

# -----------------------
# Move-ExistingUser
# -----------------------
function Move-ExistingUser {
    param(
        [string]$Username
    )

    try {
        Write-Log "Перенос пользователя: $Username" "Yellow"

        $User = Get-LocalUser -Name $Username -ErrorAction Stop
        $UserSID = $User.SID.Value
        $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$UserSID"

        if (!(Test-Path $RegistryPath)) {
            Write-Log "Не найдена запись профиля в реестре для пользователя $Username" "Red"
            return
        }

        $CurrentPath = (Get-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue).ProfileImagePath
        if (-not $CurrentPath) {
            Write-Log "Не удалось определить текущий путь профиля для $Username" "Red"
            return
        }
        $NewPath = "D:\Users\$Username"

        Write-Log "Текущий путь: $CurrentPath"
        Write-Log "Новый путь: $NewPath"

        if ($CurrentPath.StartsWith("D:\")) {
            Write-Log "Пользователь $Username уже находится на диске D" "Yellow"
            return
        }

        # Проверка активности пользователя
        $sessions = Get-UserSessions -Username $Username
        if ($sessions.Count -gt 0) {
            Write-Log "Найдены активные сессии для $Username. Их нужно завершить перед переносом." "Red"
            Write-Host "Пользователь активен. Завершить сеансы автоматически? (Y/N): " -NoNewline
            $choice = Read-Host
            if ($choice -in @('Y','y')) {
                $ok = Try-LogoffUser -Username $Username
                if (-not $ok) {
                    Write-Log "Не удалось завершить все сеансы автоматически. Операция отменена." "Red"
                    return
                }
                Start-Sleep -Seconds 3
            } else {
                Write-Log "Операция отменена пользователем (сеансы не завершены)." "Red"
                return
            }
        }

        # Проверка места на диске D
        $driveD = Get-PSDrive -Name D -ErrorAction SilentlyContinue
        if (-not $driveD) {
            Write-Log "Диск D не найден. Операция отменена." "Red"
            return
        }

        Write-Log "Вычисление размера текущего профиля (может занять время)..."
        $bytesNeeded = 0
        try {
            $bytesNeeded = (Get-ChildItem -Path $CurrentPath -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum).Sum
            if (-not $bytesNeeded) { $bytesNeeded = 0 }
        } catch {
            Write-Log "Не удалось полностью посчитать размер папки: $($_.Exception.Message)" "Yellow"
            # продолжаем, но предупреждаем
        }

        $free = $driveD.Free
        Write-Log ("Место на D: {0} MB, требуется ~{1} MB" -f ([math]::Round($free/1MB,2)), [math]::Round($bytesNeeded/1MB,2))

        if ($bytesNeeded -gt 0 -and $free -lt $bytesNeeded) {
            Write-Log "Недостаточно свободного места на диске D для копирования профиля." "Red"
            return
        }

        # Создание папки на D
        if (!(Test-Path "D:\Users")) { New-Item -ItemType Directory -Path "D:\Users" -Force | Out-Null }
        if (!(Test-Path $NewPath)) { New-Item -ItemType Directory -Path $NewPath -Force | Out-Null }

        # Копирование профиля на D (копируем ПЕРЕД изменением реестра)
        Write-Log "Копирование файлов профиля с помощью robocopy..."
        robocopy $CurrentPath $NewPath /E /COPYALL /R:3 /W:1 /NFL /NDL | Out-Null
        $rc = $LASTEXITCODE
        Write-Log "Robocopy вернул код: $rc"

        if ($rc -le 7) {
            # Установка владельца и прав
            try {
                $owner = "$env:COMPUTERNAME\$Username"
                & icacls $NewPath /setowner $owner /T /C > $null 2>&1
                # ИСПРАВЛЕНО: обёртка для $owner перед двоеточием
                & icacls $NewPath /grant "$($owner):(OI)(CI)F" /T /C > $null 2>&1
                Write-Log "Установлены права и владелец для $NewPath" "Green"
            } catch {
                Write-Log "Не удалось установить права/владельца: $($_.Exception.Message)" "Yellow"
            }

            # Резервная копия реестра
            $backup = Export-ProfileListBackup

            # Изменение реестра на новый путь
            try {
                Set-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -Value $NewPath -Force
                Write-Log "Путь профиля в реестре изменён на: $NewPath" "Green"
            } catch {
                Write-Log "Ошибка при изменении реестра: $($_.Exception.Message)" "Red"
                # можно откатить - но т.к. мы изменяем реестр после копирования, просто сообщаем
                return
            }

            # Удаление исходной папки по желанию
            Write-Host "Файлы успешно скопированы. Удалить исходную папку $CurrentPath ? (Y/N): " -NoNewline
            $deleteChoice = Read-Host
            if ($deleteChoice -in @('Y','y')) {
                try {
                    Remove-Item -Path $CurrentPath -Recurse -Force -ErrorAction Stop
                    Write-Log "Исходная папка удалена: $CurrentPath" "Green"
                } catch {
                    Write-Log "Не удалось удалить исходную папку: $($_.Exception.Message)" "Yellow"
                }
            } else {
                Write-Log "Исходная папка сохранена по желанию пользователя." "Yellow"
            }

            Write-Log "Пользователь $Username успешно перенесён на диск D." "Green"
        } else {
            Write-Log "Ошибка при копировании (robocopy code $rc). Операция прервана." "Red"
            # при желании можно удалить целевую папку, но оставим как есть для анализа
        }

    } catch {
        Write-Log "Ошибка при переносе пользователя: $($_.Exception.Message)" "Red"
    } finally {
        Show-Log
    }
}

# -----------------------
# Show-AllUsers
# -----------------------
function Show-AllUsers {
    Write-Host "`n=== СПИСОК ПОЛЬЗОВАТЕЛЕЙ ===" -ForegroundColor Cyan
    Write-Host "ID`tИмя пользователя`t`tПуть профиля" -ForegroundColor White
    Write-Host "=" * 80 -ForegroundColor White

    $users = Get-LocalUser | Where-Object { $_.Enabled -eq $true -and $_.Name -ne "DefaultAccount" -and $_.Name -ne "WDAGUtilityAccount" } 2>$null
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
            # игнорируем ошибки системных аккаунтов
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
    Write-Host "3. Показать всех пользователей" -ForegroundColor Yellow
    Write-Host "0. Выход" -ForegroundColor Red
    Write-Host ""
    Write-Host "Выберите действие (0-3): " -NoNewline -ForegroundColor White
}

# -----------------------
# Основной цикл
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

            try {
                $existingUser = Get-LocalUser -Name $username -ErrorAction Stop
                Write-Host "Пользователь с именем '$username' уже существует!" -ForegroundColor Red
                Write-Host "Нажмите любую клавишу для продолжения..."
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                break
            } catch {
                # пользователь не найден - продолжаем
            }

            $password = Read-Host "Введите пароль" -AsSecureString
            $passwordText = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))

            $fullname = Read-Host "Введите полное имя (необязательно)"
            if ([string]::IsNullOrWhiteSpace($fullname)) { $fullname = "" }

            Create-AndMoveUser -Username $username -Password $passwordText -FullName $fullname

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

# По выходу можно показать финальный лог (если остались записи)
Show-Log
