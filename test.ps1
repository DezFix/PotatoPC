# Скрипт управления локальными пользователями и их профилями
# Требует запуск от имени администратора

# Проверка прав администратора
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "⚠️ Запустите скрипт от имени администратора!" -ForegroundColor Red
    pause
    exit
}

# === Утилиты ===
function Pause {
    Write-Host "`nНажмите любую клавишу для продолжения..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# === 1. Создание нового пользователя на диске D ===
function Create-User {
    try {
        $username = Read-Host "Введите имя пользователя"
        if ([string]::IsNullOrWhiteSpace($username)) {
            Write-Host "❌ Имя пользователя не может быть пустым." -ForegroundColor Red
            Pause
            return
        }

        # Проверка, существует ли уже
        if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
            Write-Host "❌ Пользователь $username уже существует." -ForegroundColor Red
            Pause
            return
        }

        $password = Read-Host "Введите пароль (можно оставить пустым)"
        $fullname = Read-Host "Введите полное имя (можно оставить пустым)"

        $SecurePassword = if ([string]::IsNullOrWhiteSpace($password)) {
            (ConvertTo-SecureString " " -AsPlainText -Force)  # заглушка
        } else {
            (ConvertTo-SecureString $password -AsPlainText -Force)
        }

        if ([string]::IsNullOrWhiteSpace($fullname)) {
            New-LocalUser -Name $username -Password $SecurePassword
        } else {
            New-LocalUser -Name $username -Password $SecurePassword -FullName $fullname
        }

        Add-LocalGroupMember -Group "Users" -Member $username -ErrorAction SilentlyContinue

        $User = Get-LocalUser -Name $username
        $SID = $User.SID.Value
        $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$SID"
        $NewProfilePath = "D:\Users\$username"

        if (!(Test-Path "D:\Users")) { New-Item -ItemType Directory -Path "D:\Users" -Force | Out-Null }
        if (!(Test-Path $NewProfilePath)) { New-Item -ItemType Directory -Path $NewProfilePath -Force | Out-Null }

        # Ждём, пока Windows создаст запись в реестре
        $timeout = 30
        $count = 0
        while (!(Test-Path $RegistryPath) -and $count -lt $timeout) {
            Start-Sleep -Seconds 1
            $count++
        }

        if (Test-Path $RegistryPath) {
            Set-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -Value $NewProfilePath
        }

        Write-Host "✅ Пользователь $username создан. Профиль будет размещён в $NewProfilePath" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    }
    Pause
}

# === 2. Перенос профиля пользователя на диск D ===
function Move-UserProfile {
    try {
        $users = Get-LocalUser | Where-Object { -not $_.Disabled }
        if ($users.Count -eq 0) {
            Write-Host "❌ Нет доступных пользователей для переноса." -ForegroundColor Red
            Pause
            return
        }

        Write-Host "`n📋 Список локальных пользователей:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $users.Count; $i++) {
            Write-Host "[$($i+1)] $($users[$i].Name)"
        }

        $choice = Read-Host "`nВведите номер пользователя для переноса"
        if ($choice -match '^\d+$' -and $choice -ge 1 -and $choice -le $users.Count) {
            $Username = $users[$choice-1].Name
        } else {
            Write-Host "❌ Неверный выбор." -ForegroundColor Red
            Pause
            return
        }

        $User = Get-LocalUser -Name $Username -ErrorAction Stop
        $SID = $User.SID.Value
        $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$SID"
        $NewProfilePath = "D:\Users\$Username"

        if (!(Test-Path $RegistryPath)) {
            Write-Host "❌ Запись профиля для $Username не найдена. Нужно хотя бы раз войти под пользователем." -ForegroundColor Red
            Pause
            return
        }

        if (!(Test-Path "D:\Users")) { New-Item -ItemType Directory -Path "D:\Users" -Force | Out-Null }
        if (!(Test-Path $NewProfilePath)) { New-Item -ItemType Directory -Path $NewProfilePath -Force | Out-Null }

        $OldProfilePath = "C:\Users\$Username"

        if (Test-Path $OldProfilePath) {
            Write-Host "➡️ Копирование профиля..." -ForegroundColor Yellow
            robocopy $OldProfilePath $NewProfilePath /E /COPYALL /R:3 /W:1 /NFL /NDL | Out-Null
        }

        Set-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -Value $NewProfilePath

        if (Test-Path $OldProfilePath) {
            Remove-Item -Path $OldProfilePath -Recurse -Force -ErrorAction SilentlyContinue
        }

        Write-Host "✅ Профиль $Username перенесён в $NewProfilePath" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    }
    Pause
}

# === 3. Удаление пользователя и его профиля ===
function Remove-User {
    try {
        $users = Get-LocalUser
        if ($users.Count -eq 0) {
            Write-Host "❌ Нет доступных пользователей для удаления." -ForegroundColor Red
            Pause
            return
        }

        Write-Host "`n📋 Список локальных пользователей:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $users.Count; $i++) {
            Write-Host "[$($i+1)] $($users[$i].Name)"
        }

        $choice = Read-Host "`nВведите номер пользователя для удаления"
        if ($choice -match '^\d+$' -and $choice -ge 1 -and $choice -le $users.Count) {
            $Username = $users[$choice-1].Name
        } else {
            Write-Host "❌ Неверный выбор." -ForegroundColor Red
            Pause
            return
        }

        Remove-LocalUser -Name $Username -ErrorAction Stop

        $Paths = @("C:\Users\$Username", "D:\Users\$Username")
        foreach ($p in $Paths) {
            if (Test-Path $p) {
                Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        Write-Host "✅ Пользователь $Username и его профиль удалены." -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    }
    Pause
}

# === Главное меню ===
function Show-Menu {
    Clear-Host
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "   МЕНЮ УПРАВЛЕНИЯ ПОЛЬЗОВАТЕЛЯМИ Windows" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "1. Создать нового пользователя" -ForegroundColor Yellow
    Write-Host "2. Перенести существующего пользователя на диск D" -ForegroundColor Yellow
    Write-Host "3. Удалить пользователя" -ForegroundColor Yellow
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
            Write-Host "❌ Неверный выбор!" -ForegroundColor Red
            Pause
        }
    }
} while ($choice -ne "0")
