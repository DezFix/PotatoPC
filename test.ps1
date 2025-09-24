# ==========================
# Скрипт управления пользователями (C -> D)
# ==========================
# Требует запуск от имени администратора!

# Проверка прав администратора
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Скрипт должен быть запущен от имени администратора!" -ForegroundColor Red
    Pause
    exit
}

# --- Функция: Создание пользователя на диске D ---
function Create-User {
    param(
        [string]$Username,
        [string]$Password,
        [string]$FullName = ""
    )
    try {
        Write-Host "`n[+] Создание пользователя: $Username" -ForegroundColor Yellow

        # === Создание пользователя ===
        if ([string]::IsNullOrWhiteSpace($Password)) {
            if ([string]::IsNullOrWhiteSpace($FullName)) {
                New-LocalUser -Name $Username -NoPassword
            } else {
                New-LocalUser -Name $Username -NoPassword -FullName $FullName
            }
        } else {
            $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
            if ([string]::IsNullOrWhiteSpace($FullName)) {
                New-LocalUser -Name $Username -Password $SecurePassword
            } else {
                New-LocalUser -Name $Username -Password $SecurePassword -FullName $FullName
            }
        }

        # Добавление в группу Users
        try {
            Add-LocalGroupMember -Group "Users" -Member $Username
        } catch {
            Add-LocalGroupMember -Group "Пользователи" -Member $Username -ErrorAction SilentlyContinue
        }

        # === Перенос профиля ===
        $User = Get-LocalUser -Name $Username
        $SID = $User.SID.Value
        $NewProfilePath = "D:\Users\$Username"
        $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$SID"

        # Ждём появления записи в реестре
        $timeout = 30
        while (!(Test-Path $RegistryPath) -and $timeout -gt 0) {
            Start-Sleep -Seconds 1
            $timeout--
        }

        if (Test-Path $RegistryPath) {
            Set-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -Value $NewProfilePath
        }

        # Создаём папку и копируем Default
        if (!(Test-Path "D:\Users")) { New-Item -Path "D:\Users" -ItemType Directory | Out-Null }
        if (!(Test-Path $NewProfilePath)) { New-Item -Path $NewProfilePath -ItemType Directory | Out-Null }

        $DefaultProfile = "C:\Users\Default"
        if (Test-Path $DefaultProfile) {
            robocopy $DefaultProfile $NewProfilePath /E /COPYALL /R:2 /W:1 /NFL /NDL | Out-Null
        }

        # Удаляем C:\Users\Username если создался
        $OldProfile = "C:\Users\$Username"
        if (Test-Path $OldProfile) {
            try {
                Remove-Item -Path $OldProfile -Recurse -Force
                Write-Host "[+] Удалён старый профиль: $OldProfile" -ForegroundColor Green
            } catch {
                Write-Host "[!] Не удалось удалить $OldProfile (возможно, используется)" -ForegroundColor Red
            }
        }

        Write-Host "[+] Пользователь $Username создан и перенесён на диск D" -ForegroundColor Green
    } catch {
        Write-Host "[Ошибка] $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- Функция: Перенос существующего пользователя ---
function Move-User {
    param([string]$Username)

    try {
        $User = Get-LocalUser -Name $Username -ErrorAction Stop
        $SID = $User.SID.Value
        $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$SID"

        if (!(Test-Path $RegistryPath)) {
            Write-Host "Не найдена запись в реестре для $Username" -ForegroundColor Red
            return
        }

        $CurrentPath = (Get-ItemProperty -Path $RegistryPath -Name "ProfileImagePath").ProfileImagePath
        $NewPath = "D:\Users\$Username"

        if ($CurrentPath -like "D:*") {
            Write-Host "[!] Пользователь уже на диске D" -ForegroundColor Yellow
            return
        }

        # Проверяем активность
        $ActiveSessions = quser 2>$null | Where-Object {$_ -match $Username}
        if ($ActiveSessions) {
            Write-Host "[!] Пользователь $Username сейчас активен. Завершите сеанс и повторите." -ForegroundColor Red
            return
        }

        if (!(Test-Path "D:\Users")) { New-Item -Path "D:\Users" -ItemType Directory | Out-Null }

        # Меняем путь в реестре
        Set-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -Value $NewPath

        # Копируем файлы
        robocopy $CurrentPath $NewPath /E /COPYALL /R:2 /W:1 /NFL /NDL
        if ($LASTEXITCODE -le 7) {
            Write-Host "[+] Файлы перенесены" -ForegroundColor Green
            try {
                Remove-Item -Path $CurrentPath -Recurse -Force
                Write-Host "[+] Удалён старый профиль: $CurrentPath" -ForegroundColor Green
            } catch {
                Write-Host "[!] Не удалось удалить $CurrentPath" -ForegroundColor Red
            }
        } else {
            Write-Host "[Ошибка] robocopy завершился с кодом $LASTEXITCODE" -ForegroundColor Red
        }
    } catch {
        Write-Host "[Ошибка] $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- Функция: Удаление пользователя ---
function Remove-User {
    param([string]$Username)

    try {
        $User = Get-LocalUser -Name $Username -ErrorAction Stop
        Remove-LocalUser -Name $Username
        Write-Host "[+] Пользователь $Username удалён" -ForegroundColor Green

        $ProfileC = "C:\Users\$Username"
        $ProfileD = "D:\Users\$Username"

        foreach ($path in @($ProfileC,$ProfileD)) {
            if (Test-Path $path) {
                try {
                    Remove-Item -Path $path -Recurse -Force
                    Write-Host "[+] Папка профиля удалена: $path" -ForegroundColor Green
                } catch {
                    Write-Host "[!] Не удалось удалить $path" -ForegroundColor Red
                }
            }
        }
    } catch {
        Write-Host "[Ошибка] $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- Главное меню ---
function Show-Menu {
    Clear-Host
    Write-Host "====================================" -ForegroundColor Cyan
    Write-Host "   УПРАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯМИ" -ForegroundColor Cyan
    Write-Host "====================================" -ForegroundColor Cyan
    Write-Host "1. Создать пользователя" -ForegroundColor Yellow
    Write-Host "2. Перенести существующего пользователя" -ForegroundColor Yellow
    Write-Host "3. Удалить пользователя" -ForegroundColor Yellow
    Write-Host "0. Выход" -ForegroundColor Red
    Write-Host "====================================" -ForegroundColor Cyan
}

# --- Основной цикл ---
do {
    Show-Menu
    $choice = Read-Host "Выберите действие"

    switch ($choice) {
        "1" {
            $u = Read-Host "Имя пользователя"
            $p = Read-Host "Пароль (можно пусто)"
            $f = Read-Host "Полное имя (можно пусто)"
            Create-User -Username $u -Password $p -FullName $f
            Pause
        }
        "2" {
            $u = Read-Host "Имя пользователя для переноса"
            Move-User -Username $u
            Pause
        }
        "3" {
            $u = Read-Host "Имя пользователя для удаления"
            Remove-User -Username $u
            Pause
        }
        "0" { Write-Host "Выход..." -ForegroundColor Green }
        default { Write-Host "Неверный выбор!" -ForegroundColor Red; Pause }
    }
} while ($choice -ne "0")
