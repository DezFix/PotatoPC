<#
.SYNOPSIS
  Простая утилита: создать пользователя (системный метод с профилем на D:\Users) и удалить пользователя.
.NOTES
  Сохраняет/восстанавливает ключи:
  HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfilesDirectory
  HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Default
  HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Public
#>

# --- Конфигурация ---
$LogFile = "C:\Logs\UserManager.log"
$TargetProfileRoot = "D:\Users"

# Создать папку логов если нет
$logDir = Split-Path $LogFile
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param([string]$msg, [string]$level = "INFO")
    $t = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $LogFile -Value "$t [$level] $msg"
}

# --- Повышение прав если нужно ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Перезапуск с правами администратора..." -ForegroundColor Yellow
    $script = $MyInvocation.MyCommand.Path
    if (-not $script) {
        Write-Host "Ошибка: скрипт должен быть запущен из файла (не из интерактивной консоли)." -ForegroundColor Red
        exit 1
    }
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$script`"" -Verb RunAs
    exit
}

# --- Вспомогательная функция: безопасная установка/создание свойства реестра ---
function Set-OrNew-ItemProperty {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Value,
        [ValidateSet("String","ExpandString","DWord","QWord","MultiString","Binary","Unknown")] [string]$Type = "ExpandString"
    )
    try {
        $exists = $false
        try { $pv = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop; $exists = $true } catch {}
        if ($exists) {
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -ErrorAction Stop
        } else {
            New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        }
        return $true
    } catch {
        Write-Log "Не удалось установить/создать реестровое свойство $Name в $Path: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# --- Создание пользователя (системный метод: временно меняем ProfilesDirectory -> D:\Users) ---
function New-User-SystemMethod {
    Clear-Host
    Write-Host "=== Создание пользователя (СИСТЕМНЫЙ МЕТОД, профиль на $TargetProfileRoot) ===" -ForegroundColor Cyan

    if (-not (Test-Path $TargetProfileRoot.Split("\")[0] + "\")) {
        Write-Host "Ошибка: диск для $TargetProfileRoot не найден." -ForegroundColor Red
        Write-Log "Ошибка: диск для $TargetProfileRoot не найден." "ERROR"
        return
    }

    $Username = Read-Host "Введите имя пользователя (без пробелов и спецсимволов)"
    if ([string]::IsNullOrWhiteSpace($Username) -or $Username -match '[\\/:*?"<>|]' -or $Username.Length -gt 20) {
        Write-Host "Некорректное имя пользователя." -ForegroundColor Red
        return
    }

    # Проверка существования
    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction SilentlyContinue
    if (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue) {
        Write-Host "Пользователь '$Username' уже существует." -ForegroundColor Yellow
        return
    }

    $SecurePass = Read-Host "Введите пароль" -AsSecureString
    $plainPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
    )
    if ([string]::IsNullOrWhiteSpace($plainPass) -or $plainPass.Length -lt 4) {
        Write-Host "Пароль должен быть минимум 4 символа." -ForegroundColor Red
        return
    }

    $FullName = Read-Host "Полное имя (необязательно)"
    $Description = Read-Host "Описание (необязательно)"
    if ([string]::IsNullOrWhiteSpace($Description)) { $Description = "Пользователь с профилем на D" }
    $IsAdminAnswer = Read-Host "Добавить в администраторы? (y/N)"
    $AddToAdministrators = ($IsAdminAnswer -eq 'y' -or $IsAdminAnswer -eq 'Y')

    $regBase = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $keysToSave = @("ProfilesDirectory","Default","Public")
    $backup = @{}

    try {
        Write-Host "`nСохраняю текущие значения реестра..." -ForegroundColor Cyan
        $current = Get-ItemProperty -Path $regBase -ErrorAction Stop
        foreach ($k in $keysToSave) {
            if ($current.PSObject.Properties.Name -contains $k) {
                $backup[$k] = $current.$k
                Write-Host "  Сохранено $k = $($current.$k)" -ForegroundColor Green
            } else {
                $backup[$k] = $null
                Write-Host "  $k не найден (будет создан временно)." -ForegroundColor Gray
            }
        }

        # Создаем целевой корень профилей
        if (-not (Test-Path $TargetProfileRoot)) {
            New-Item -Path $TargetProfileRoot -ItemType Directory -Force | Out-Null
            Write-Host "Создана папка: $TargetProfileRoot" -ForegroundColor Green
        }

        # Если есть C:\Users\Default — копируем в D:\Users\Default чтобы новые профили корректно формировались
        $cDefault = "C:\Users\Default"
        $dDefault = Join-Path $TargetProfileRoot "Default"
        if (Test-Path $cDefault) {
            Write-Host "Копирование Default профиля (может занять время)..." -ForegroundColor Cyan
            # robocopy используется — обычно присутствует в Windows
            robocopy $cDefault $dDefault /MIR /COPYALL /B /R:2 /W:2 | Out-Null
            Write-Host "Default скопирован в $dDefault" -ForegroundColor Green
        } else {
            if (-not (Test-Path $dDefault)) {
                New-Item -Path $dDefault -ItemType Directory -Force | Out-Null
                Write-Host "Создана пустая папка Default: $dDefault" -ForegroundColor Yellow
            }
        }

        # Устанавливаем временные значения реестра
        Write-Host "Устанавливаю временные значения реестра на $TargetProfileRoot..." -ForegroundColor Cyan
        Set-OrNew-ItemProperty -Path $regBase -Name "ProfilesDirectory" -Value $TargetProfileRoot -Type "ExpandString" | Out-Null
        Set-OrNew-ItemProperty -Path $regBase -Name "Default" -Value (Join-Path $TargetProfileRoot "Default") -Type "ExpandString" | Out-Null
        Set-OrNew-ItemProperty -Path $regBase -Name "Public" -Value (Join-Path $TargetProfileRoot "Public") -Type "ExpandString" | Out-Null

        Start-Sleep -Seconds 1

        # Создаём пользователя штатно — система будет использовать временные значения для формирования профиля при первом логине
        Write-Host "`nСоздаю локального пользователя..." -ForegroundColor Cyan
        $securePwdForNew = ConvertTo-SecureString $plainPass -AsPlainText -Force
        New-LocalUser -Name $Username -Password $securePwdForNew -FullName $FullName -Description $Description -PasswordNeverExpires:$true -UserMayNotChangePassword:$false -ErrorAction Stop
        Write-Host "Пользователь $Username создан." -ForegroundColor Green
        Write-Log "Создан пользователь $Username (системный метод, профиль на $TargetProfileRoot)"

        if ($AddToAdministrators) {
            $adminGroups = @("Administrators","Администраторы","Administrateurs","Administratoren","Administradores")
            $added = $false
            foreach ($g in $adminGroups) {
                try {
                    Add-LocalGroupMember -Group $g -Member $Username -ErrorAction Stop
                    Write-Host "Добавлен в группу: $g" -ForegroundColor Green
                    $added = $true
                    break
                } catch {}
            }
            if (-not $added) { Write-Host "Не удалось добавить в группу администраторов автоматически." -ForegroundColor Yellow }
        }

        Write-Host "`nОперация создания завершена. Восстанавливаю реестр..." -ForegroundColor Cyan

    } catch {
        Write-Host "Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Ошибка при создании пользователя $Username: $($_.Exception.Message)" "ERROR"
    } finally {
        # Восстановление реестра в любом случае
        try {
            foreach ($k in $keysToSave) {
                if ($backup.ContainsKey($k) -and $backup[$k] -ne $null) {
                    Set-OrNew-ItemProperty -Path $regBase -Name $k -Value $backup[$k] -Type "ExpandString" | Out-Null
                    Write-Host "Восстановлено: $k = $($backup[$k])" -ForegroundColor Green
                } else {
                    # если изначально не было — удаляем временное свойство
                    try {
                        Remove-ItemProperty -Path $regBase -Name $k -ErrorAction Stop
                        Write-Host "Удалено временное свойство реестра: $k" -ForegroundColor Yellow
                    } catch {
                        # возможно свойство отсутствует — игнорируем
                    }
                }
            }
            Write-Log "Реестр восстановлен после создания пользователя $Username"
        } catch {
            Write-Host "Ошибка при восстановлении реестра: $($_.Exception.Message)" -ForegroundColor Red
            Write-Log "Ошибка при восстановлении реестра: $($_.Exception.Message)" "ERROR"
        }
    }

    Write-Host "`nГотово. Важно: профиль фактически создаётся системой при первом входе пользователя." -ForegroundColor Cyan
    Write-Host "Если нужно — выполните вход под новым пользователем или вручную создайте/проверьте папку $($TargetProfileRoot)\$Username" -ForegroundColor Cyan
}

# --- Удаление пользователя (и опционально профиль) ---
function Remove-User {
    Clear-Host
    Write-Host "=== Удаление пользователя ===" -ForegroundColor Cyan

    $Username = Read-Host "Введите имя пользователя для удаления"
    if ([string]::IsNullOrWhiteSpace($Username)) { Write-Host "Имя не задано." -ForegroundColor Red; return }

    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction SilentlyContinue
    $user = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if (-not $user) {
        Write-Host "Пользователь '$Username' не найден." -ForegroundColor Yellow
        return
    }

    Write-Host "Будет удалён пользователь: $Username" -ForegroundColor Yellow
    $confirm = Read-Host "Подтвердите удаление (введите DELETE)"
    if ($confirm -ne "DELETE") { Write-Host "Отмена." -ForegroundColor Yellow; return }

    try {
        # Получаем путь профиля из реестра по SID (если есть)
        $sid = $user.SID.Value
        $profileReg = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"
        $profilePath = $null
        if (Test-Path $profileReg) {
            $p = Get-ItemProperty -Path $profileReg -ErrorAction SilentlyContinue
            if ($p -and $p.ProfileImagePath) { $profilePath = $p.ProfileImagePath }
        }

        # Удаляем пользователя
        Remove-LocalUser -Name $Username -ErrorAction Stop
        Write-Host "Пользователь удалён из системы." -ForegroundColor Green
        Write-Log "Пользователь $Username удалён."

        # Удаляем запись реестра (ProfileList\<SID>)
        if (Test-Path $profileReg) {
            Remove-Item -Path $profileReg -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Запись реестра профиля удалена." -ForegroundColor Green
            Write-Log "Реестровая запись профиля для $Username удалена."
        }

        # Удаление папки профиля (если найдена)
        if ($profilePath -and (Test-Path $profilePath)) {
            $del = Read-Host "Удалить папку профиля $profilePath ? (Y/n)"
            if ($del -ne 'n' -and $del -ne 'N') {
                try {
                    Remove-Item -Path $profilePath -Recurse -Force -ErrorAction Stop
                    Write-Host "Папка профиля удалена." -ForegroundColor Green
                    Write-Log "Папка профиля $profilePath удалена."
                } catch {
                    Write-Host "Не удалось удалить папку профиля: $($_.Exception.Message)" -ForegroundColor Yellow
                    Write-Log "Ошибка удаления папки профиля $profilePath: $($_.Exception.Message)" "ERROR"
                }
            } else {
                Write-Host "Папка профиля сохранена: $profilePath" -ForegroundColor Cyan
            }
        } else {
            Write-Host "Путь профиля не найден или папка отсутствует." -ForegroundColor Gray
        }

    } catch {
        Write-Host "Ошибка при удалении: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Ошибка при удалении $Username: $($_.Exception.Message)" "ERROR"
    }
}

# --- Меню: только создать / удалить / выйти ---
function Show-Menu {
    Clear-Host
    Write-Host "==========================" -ForegroundColor Cyan
    Write-Host "  УПРАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯМИ (профили на D:\Users)" -ForegroundColor Cyan
    Write-Host "1. Создать пользователя (системный метод, профиль на D:\Users)" -ForegroundColor Green
    Write-Host "2. Удалить пользователя" -ForegroundColor Red
    Write-Host "0. Выход" -ForegroundColor Yellow
    Write-Host "==========================" -ForegroundColor Cyan
}

# --- Главный цикл ---
do {
    Show-Menu
    $choice = Read-Host "Выберите действие (0-2)"
    switch ($choice) {
        "1" { New-User-SystemMethod; Pause }
        "2" { Remove-User; Pause }
        "0" { Write-Host "Выход..." -ForegroundColor Yellow; break }
        default { Write-Host "Неверный выбор." -ForegroundColor Red; Pause }
    }
} while ($true)

# --- Конец скрипта ---
