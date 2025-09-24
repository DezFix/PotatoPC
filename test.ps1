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

        $password = Read-Host "Введите пароль (можно оставить пустым)"
        $fullname = Read-Host "Введите полное имя (можно оставить пустым)"

        $SecurePassword = if ([string]::IsNullOrWhiteSpace($password)) {
            ConvertTo-SecureString " " -AsPlainText -Force
        } else {
            ConvertTo-SecureString $password -AsPlainText -Force
        }

        if ([string]::IsNullOrWhiteSpace($fullname)) {
            New-LocalUser -Name $username -Password $SecurePassword -Description "Создан через скрипт"
        } else {
            New-LocalUser -Name $username -Password $SecurePassword -FullName $fullname -Description "Создан через скрипт"
        }

        Add-LocalGroupMember -Group "Users" -Member $username -ErrorAction SilentlyContinue

        # Подготовка папки на D:
        $NewProfilePath = "D:\Users\$username"
        if (!(Test-Path "D:\Users")) { New-Item -ItemType Directory -Path "D:\Users" -Force | Out-Null }
        if (!(Test-Path $NewProfilePath)) { New-Item -ItemType Directory -Path $NewProfilePath -Force | Out-Null }

        Write-Host "Пользователь $username создан. При первом входе профиль будет на диске D:\Users\$username" -ForegroundColor Green
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

        Write-Host "`Список пользователей:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $users.Count; $i++) {
            Write-Host "[$($i+1)] $($users[$i].Name)"
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
        $OldProfilePath = "C:\Users\$Username"

        if (!(Test-Path $RegistryPath)) {
            Write-Host "В реестре нет профиля для $Username (нужно войти хотя бы раз)." -ForegroundColor Red
            Pause
            return
        }

        if (!(Test-Path "D:\Users")) { New-Item -ItemType Directory -Path "D:\Users" -Force | Out-Null }
        if (!(Test-Path $NewProfilePath)) { New-Item -ItemType Directory -Path $NewProfilePath -Force | Out-Null }

        if (Test-Path $OldProfilePath) {
            Write-Host "Переносим профиль с $OldProfilePath на $NewProfilePath..." -ForegroundColor Yellow
            robocopy $OldProfilePath $NewProfilePath /E /COPYALL /R:3 /W:1 /NFL /NDL | Out-Null
        }

        Set-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -Value $NewProfilePath

        if (Test-Path $OldProfilePath) {
            Remove-Item -Path $OldProfilePath -Recurse -Force -ErrorAction SilentlyContinue
        }

        Write-Host "Профиль $Username перенесён в $NewProfilePath" -ForegroundColor Green
        Write-Host "Рекомендуется перезагрузить систему перед входом пользователем." -ForegroundColor Cyan
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

        Write-Host "`Список пользователей:" -ForegroundColor Cyan
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

        Remove-LocalUser -Name $Username -ErrorAction Stop

        $Paths = @("C:\Users\$Username", "D:\Users\$Username")
        foreach ($p in $Paths) {
            if (Test-Path $p) {
                Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        Write-Host "Пользователь $Username и его профиль удалены." -ForegroundColor Green
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
            Write-Host "Неверный выбор!" -ForegroundColor Red
            Pause
        }
    }
} while ($choice -ne "0")
