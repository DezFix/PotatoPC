#requires -RunAsAdministrator
<#
.SYNOPSIS
    Утилита управления пользователями Windows
.DESCRIPTION
    Создание, удаление, перенос и проверка пользовательских профилей
    с возможностью выбора папки для профиля (например, другой диск).
#>

# ======================== НАСТРОЙКИ ========================
$Global:LogFile = "C:\Logs\UserManager.log"
$Global:ProfileRoot = "D:\Users"   # сюда будут создаваться новые профили
# ===========================================================

# Создание папки логов
if (!(Test-Path (Split-Path $LogFile))) {
    New-Item -ItemType Directory -Force -Path (Split-Path $LogFile) | Out-Null
}

# ======================== ВСПОМОГАТЕЛЬНЫЕ ========================
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $LogFile -Value "$Time [$Level] $Message"
}

# Автозапуск от имени администратора
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Перезапуск от имени администратора..."
    Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ======================== ФУНКЦИИ ========================

# Создание пользователя системным методом
function New-UserOnDrive-SystemMethod {
    param()
    $Username = Read-Host "Введите имя пользователя"
    $Password = Read-Host "Введите пароль" -AsSecureString
    $FullProfilePath = Join-Path $Global:ProfileRoot $Username

    try {
        if (!(Test-Path $FullProfilePath)) {
            New-Item -Path $FullProfilePath -ItemType Directory | Out-Null
        }
        net user $Username $([Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))) /add /y | Out-Null
        net localgroup Administrators $Username /add | Out-Null
        Write-Host "Пользователь $Username создан (системный метод)" -ForegroundColor Green
        Write-Log "Создан пользователь $Username (системный метод)"
    }
    catch {
        Write-Host "Ошибка: $_" -ForegroundColor Red
        Write-Log "Ошибка при создании $Username (системный метод): $_" "ERROR"
    }
}

# Создание пользователя через .NET
function New-UserOnDrive {
    param()
    $Username = Read-Host "Введите имя пользователя"
    $Password = Read-Host "Введите пароль" -AsSecureString
    $FullProfilePath = Join-Path $Global:ProfileRoot $Username

    try {
        if (!(Test-Path $FullProfilePath)) {
            New-Item -Path $FullProfilePath -ItemType Directory | Out-Null
        }
        $plainPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))
        $user = ([ADSI]"WinNT://./$Username,user")
        if ($null -eq $user.Path) {
            $computer = [ADSI]"WinNT://."
            $newUser = $computer.Create("User", $Username)
            $newUser.SetPassword($plainPass)
            $newUser.SetInfo()
            $newUser.Put("HomeDirectory", $FullProfilePath)
            $newUser.SetInfo()

            # Добавляем в группу админов (с поддержкой разных языков)
            $groups = @("Administrators", "Администраторы", "Administrateurs", "Administratoren", "Administradores")
            foreach ($grp in $groups) {
                try { ([ADSI]"WinNT://./$grp,group").Add("WinNT://./$Username,user") } catch {}
            }

            Write-Host "Пользователь $Username создан (.NET метод)" -ForegroundColor Green
            Write-Log "Создан пользователь $Username (.NET метод)"
        }
        else {
            Write-Host "Пользователь $Username уже существует!" -ForegroundColor Yellow
            Write-Log "Попытка создать существующего пользователя $Username" "WARN"
        }
    }
    catch {
        Write-Host "Ошибка: $_" -ForegroundColor Red
        Write-Log "Ошибка при создании $Username (.NET): $_" "ERROR"
    }
}

# Удаление пользователя
function Remove-UserFromSystem {
    param()
    $Username = Read-Host "Введите имя пользователя для удаления"
    try {
        net user $Username /delete | Out-Null
        $FullProfilePath = Join-Path $Global:ProfileRoot $Username
        if (Test-Path $FullProfilePath) {
            Remove-Item -Recurse -Force -Path $FullProfilePath
        }
        Write-Host "Пользователь $Username удален" -ForegroundColor Green
        Write-Log "Удален пользователь $Username"
    }
    catch {
        Write-Host "Ошибка: $_" -ForegroundColor Red
        Write-Log "Ошибка при удалении $Username: $_" "ERROR"
    }
}

# Показ списка пользователей
function Show-UserList {
    param()
    Write-Host "`nСписок локальных пользователей:`n"
    Get-LocalUser | ForEach-Object {
        $name = $_.Name
        $sid = (New-Object System.Security.Principal.NTAccount($name)).Translate([System.Security.Principal.SecurityIdentifier]).Value
        $profilePath = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -ErrorAction SilentlyContinue).ProfileImagePath
        Write-Host ("{0,-20} {1,-50} {2}" -f $name, $profilePath, $_.Enabled)
    }
    Write-Log "Выведен список пользователей"
}

# Проверка профиля
function Test-UserProfile {
    param()
    $Username = Read-Host "Введите имя пользователя для проверки"
    $sid = (New-Object System.Security.Principal.NTAccount($Username)).Translate([System.Security.Principal.SecurityIdentifier]).Value
    $profilePath = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -ErrorAction SilentlyContinue).ProfileImagePath
    if ($profilePath -and (Test-Path $profilePath)) {
        Write-Host "Профиль $Username найден: $profilePath" -ForegroundColor Green
        Write-Log "Проверка профиля $Username: найден $profilePath"
    }
    else {
        Write-Host "Профиль $Username отсутствует или поврежден" -ForegroundColor Red
        Write-Log "Проверка профиля $Username: не найден" "WARN"
    }
}

# Перенос существующих профилей (черновик)
function Move-ExistingProfiles {
    param()
    Write-Host "Функция переноса пока не реализована." -ForegroundColor Yellow
    Write-Log "Вызов Move-ExistingProfiles (не реализовано)" "WARN"
}

# ======================== МЕНЮ ========================
function Show-MainMenu {
    Clear-Host
    Write-Host "==== Управление пользователями ====" -ForegroundColor Cyan
    Write-Host "1. Создать пользователя (системный метод)"
    Write-Host "2. Создать пользователя (.NET метод)"
    Write-Host "3. Удалить пользователя"
    Write-Host "4. Показать список пользователей"
    Write-Host "5. Перенести существующие профили"
    Write-Host "6. Проверить профиль пользователя"
    Write-Host "0. Выход"
    Write-Host "===================================" -ForegroundColor Cyan
}

# ======================== ЗАПУСК ========================
do {
    Show-MainMenu
    $Choice = Read-Host "Выберите действие"
    switch ($Choice) {
        '1' { New-UserOnDrive-SystemMethod }
        '2' { New-UserOnDrive }
        '3' { Remove-UserFromSystem }
        '4' { Show-UserList }
        '5' { Move-ExistingProfiles }
        '6' { Test-UserProfile }
        '0' { break }
        default { Write-Host "Неверный выбор!" -ForegroundColor Red }
    }
    Write-Host "`nНажмите любую клавишу для продолжения..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
} while ($true)
