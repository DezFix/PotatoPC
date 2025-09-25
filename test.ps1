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
            $_.Name -notin @("Administrator", "DefaultAccount", "WDAGUtilityAccount", "Guest")
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

        Write-Host "Пользователь $username создан успешно!" -ForegroundColor Green

        # Настройка автоматического переноса на D:
        $choice = Read-Host "Настроить автоматический перенос профиля на диск D при первом входе? (Y/N)"
        if ($choice -in @('Y','y')) {
            Setup-ProfileRedirect -Username $username
        }

    }
    catch {
        Write-Host "Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    }
    Pause
}

# === Настройка перенаправления профиля через символическую ссылку ===
function Setup-ProfileRedirect {
    param([string]$Username)
    
    try {
        $StandardProfilePath = "C:\Users\$Username"
        $NewProfilePath = "D:\Users\$Username"
        
        Write-Host "Настройка перенаправления профиля..." -ForegroundColor Yellow
        
        # Проверяем, не существует ли уже папка на C:
        if (Test-Path $StandardProfilePath) {
            Write-Host "Папка $StandardProfilePath уже существует" -ForegroundColor Yellow
            return
        }

        # Создание папки на диске D
        if (!(Test-Path "D:\Users")) { 
            New-Item -ItemType Directory -Path "D:\Users" -Force | Out-Null 
        }
        if (!(Test-Path $NewProfilePath)) { 
            New-Item -ItemType Directory -Path $NewProfilePath -Force | Out-Null 
        }

        # Создаем символическую ссылку
        Write-Host "Создание символической ссылки..." -ForegroundColor Yellow
        $result = cmd /c "mklink /D `"$StandardProfilePath`" `"$NewProfilePath`"" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Символическая ссылка создана!" -ForegroundColor Green
            Write-Host "$StandardProfilePath -> $NewProfilePath" -ForegroundColor Cyan
        } else {
            Write-Host "Не удалось создать символическую ссылку: $result" -ForegroundColor Red
        }
        
    } catch {
        Write-Host "Ошибка при настройке перенаправления: $($_.Exception.Message)" -ForegroundColor Red
    }
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

        Write-Host "`nСписок пользователей:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $users.Count; $i++) {
            $user = $users[$i]
            $userSID = $user.SID.Value
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$userSID"
            $currentPath = "Профиль не создан"
            $color = "Gray"
            
            # Проверяем символическую ссылку
            $standardPath = "C:\Users\$($user.Name)"
            if (Test-Path $standardPath) {
                $item = Get-Item $standardPath -Force
                if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                    $currentPath = "Символическая ссылка -> D:\Users\$($user.Name)"
                    $color = "Green"
                }
            }
            
            # Проверяем реестр
            if (Test-Path $regPath -and $currentPath -eq "Профиль не создан") {
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
        $StandardProfilePath = "C:\Users\$Username"
        $NewProfilePath = "D:\Users\$Username"

        # Проверка активности пользователя
        $sessions = quser 2>$null | Where-Object { $_ -match $Username }
        if ($sessions) {
            Write-Host "Пользователь $Username активен! Завершите сеанс перед переносом." -ForegroundColor Red
            Pause
            return
        }

        # Проверяем символическую ссылку
        if (Test-Path $StandardProfilePath) {
            $item = Get-Item $StandardProfilePath -Force
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                Write-Host "У пользователя $Username уже настроена символическая ссылка на диск D" -ForegroundColor Yellow
                Pause
                return
            }
        }

        # Если профиль еще не создан - создаем символическую ссылку
        if (!(Test-Path $RegistryPath)) {
            Write-Host "Пользователь еще не входил в систему. Создаем символическую ссылку для автоматического переноса." -ForegroundColor Yellow
            Setup-ProfileRedirect -Username $Username
            Pause
            return
        }

        # Получаем текущий путь профиля
        $CurrentPath = (Get-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue).ProfileImagePath
        
        if (!$CurrentPath) {
            Write-Host "Не удалось определить путь профиля" -ForegroundColor Red
            Pause
            return
        }
        
        if ($CurrentPath.StartsWith("D:\")) {
            Write-Host "Пользователь $Username уже находится на диске D" -ForegroundColor Yellow
            Pause
            return
        }

        Write-Host "Текущий путь: $CurrentPath" -ForegroundColor Yellow
        Write-Host "Новый путь: $NewProfilePath" -ForegroundColor Green

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

        Write-Host "`nПрофиль $Username успешно перенесён на диск D!" -ForegroundColor Green
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

        Write-Host "`nСписок пользователей:" -ForegroundColor Cyan
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

        # Защита от удаления текущего пользователя и Administrator
        if ($Username -in @("Administrator", "Администратор", $env:USERNAME)) {
            Write-Host "Нельзя удалить системного пользователя или текущего пользователя!" -ForegroundColor Red
            Pause
            return
        }

        # Получение SID и пути профиля
        $User = Get-LocalUser -Name $Username
        $SID = $User.SID.Value
        $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$SID"
        $StandardProfilePath = "C:\Users\$Username"
        
        $ProfilePath = ""
        if (Test-Path $RegistryPath) {
            $ProfilePath = (Get-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue).ProfileImagePath
        }

        # Подтверждение удаления
        Write-Host "`nВНИМАНИЕ! Это действие необратимо!" -ForegroundColor Red
        Write-Host "Будет удалено:" -ForegroundColor Yellow
        Write-Host "- Учетная запись: $Username" -ForegroundColor Yellow
        if ($ProfilePath) {
            Write-Host "- Папка профиля: $ProfilePath" -ForegroundColor Yellow
        }
        Write-Host "- Папки C:\Users\$Username и D:\Users\$Username (если существуют)" -ForegroundColor Yellow
        Write-Host "- Символические ссылки (если есть)" -ForegroundColor Yellow
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

        # Удаление символической ссылки если есть
        if (Test-Path $StandardProfilePath) {
            $item = Get-Item $StandardProfilePath -Force -ErrorAction SilentlyContinue
            if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                Write-Host "Удаление символической ссылки..." -ForegroundColor Yellow
                try {
                    cmd /c "rmdir /Q `"$StandardProfilePath`"" | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "Символическая ссылка удалена" -ForegroundColor Green
                    } else {
                        Remove-Item -Path $StandardProfilePath -Force -ErrorAction SilentlyContinue
                        Write-Host "Символическая ссылка удалена (альтернативным методом)" -ForegroundColor Green
                    }
                } catch {
                    Write-Host "Не удалось удалить символическую ссылку: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }

        # Удаление учетной записи
        try {
            Remove-LocalUser -Name $Username -ErrorAction Stop
            Write-Host "Учетная запись удалена" -ForegroundColor Green
        } catch {
            Write-Host "Ошибка при удалении учетной записи: $($_.Exception.Message)" -ForegroundColor Red
            Pause
            return
        }

        # Удаление папок профиля
        $PathsToDelete = @("C:\Users\$Username", "D:\Users\$Username")
        if ($ProfilePath -and $ProfilePath -notin $PathsToDelete) {
            $PathsToDelete += $ProfilePath
        }

        foreach ($path in $PathsToDelete) {
            if (Test-Path $path) {
                Write-Host "Удаление $path..." -ForegroundColor Yellow
                try {
                    # Попытка удаления через robocopy (для заблокированных файлов)
                    $emptyDir = Join-Path $env:TEMP "EmptyDir_$([guid]::NewGuid().ToString())"
                    New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
                    
                    robocopy $emptyDir $path /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
                    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path $emptyDir -Force -ErrorAction SilentlyContinue
                    
                    if (!(Test-Path $path)) {
                        Write-Host "Удалено" -ForegroundColor Green
                    } else {
                        Write-Host "Частично удалено (некоторые файлы могут остаться)" -ForegroundColor Yellow
                    }
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

        Write-Host "`nПользователь $Username полностью удален!" -ForegroundColor Green
    }
    catch {
        Write-Host "Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    }
    Pause
}

# === 4. Показать информацию о профилях ===
function Show-ProfileInfo {
    try {
        $users = Get-UserList
        if ($users.Count -eq 0) {
            Write-Host "Пользователи не найдены." -ForegroundColor Red
            Pause
            return
        }

        Write-Host "`nИНФОРМАЦИЯ О ПРОФИЛЯХ ПОЛЬЗОВАТЕЛЕЙ" -ForegroundColor Cyan
        Write-Host "=" * 60 -ForegroundColor Cyan

        foreach ($user in $users) {
            Write-Host "`nПользователь: $($user.Name)" -ForegroundColor Yellow
            Write-Host "SID: $($user.SID.Value)" -ForegroundColor Gray
            
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($user.SID.Value)"
            $standardPath = "C:\Users\$($user.Name)"
            
            # Проверка символической ссылки
            if (Test-Path $standardPath) {
                $item = Get-Item $standardPath -Force -ErrorAction SilentlyContinue
                if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                    $target = $item.Target
                    Write-Host "Символическая ссылка: $standardPath -> $target" -ForegroundColor Green
                } else {
                    Write-Host "Обычная папка: $standardPath" -ForegroundColor White
                }
            }
            
            # Проверка реестра
            if (Test-Path $regPath) {
                $profilePath = (Get-ItemProperty -Path $regPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue).ProfileImagePath
                if ($profilePath) {
                    $color = if ($profilePath.StartsWith("C:\")) { "Red" } else { "Green" }
                    Write-Host "Путь в реестре: $profilePath" -ForegroundColor $color
                    
                    if (Test-Path $profilePath) {
                        $size = (Get-ChildItem -Path $profilePath -Recurse -Force -ErrorAction SilentlyContinue | 
                                Measure-Object -Property Length -Sum).Sum
                        $sizeMB = [math]::Round($size / 1MB, 2)
                        Write-Host "Размер профиля: $sizeMB MB" -ForegroundColor Gray
                    }
                }
            } else {
                Write-Host "Пользователь еще не входил в систему" -ForegroundColor Gray
            }
            
            Write-Host "-" * 50 -ForegroundColor Gray
        }

        Write-Host "`nЛегенда:" -ForegroundColor White
        Write-Host "Зеленый - профиль на диске D или символическая ссылка" -ForegroundColor Green
        Write-Host "Красный - профиль на диске C" -ForegroundColor Red
        Write-Host "Серый - профиль не создан" -ForegroundColor Gray
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
    Write-Host "3. Удалить пользователя (полное удаление)" -ForegroundColor Yellow
    Write-Host "4. Показать информацию о профилях" -ForegroundColor Cyan
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
        "4" { Show-ProfileInfo }
        "0" { Write-Host "Выход..." -ForegroundColor Green }
        default {
            Write-Host "Неверный выбор!" -ForegroundColor Red
            Pause
        }
    }
} while ($choice -ne "0")
