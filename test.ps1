# Скрипт управления пользователями с профилями на диске D
# Требует запуска от имени администратора

# Проверка запуска от имени администратора
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Этот скрипт должен быть запущен от имени администратора!" -ForegroundColor Red
    Write-Host "Нажмите любую клавишу для выхода..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Функция отображения главного меню
function Show-MainMenu {
    Clear-Host
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              УПРАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯМИ (ДИСК D)               ║" -ForegroundColor Cyan
    Write-Host "╠════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║  1. Создать нового пользователя                                ║" -ForegroundColor White
    Write-Host "║  2. Удалить пользователя                                       ║" -ForegroundColor White
    Write-Host "║  3. Показать список пользователей                             ║" -ForegroundColor White
    Write-Host "║  4. Переместить существующие профили на диск D                ║" -ForegroundColor White
    Write-Host "║  5. Проверить пользователя                                     ║" -ForegroundColor White
    Write-Host "║  0. Выход                                                      ║" -ForegroundColor Yellow
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

# Функция создания пользователя
function New-UserOnDrive {
    Write-Host "`n--- СОЗДАНИЕ НОВОГО ПОЛЬЗОВАТЕЛЯ ---" -ForegroundColor Green
    
    # Проверка существования диска D
    if (-not (Test-Path "D:\")) {
        Write-Host "Ошибка: Диск D:\ не найден!" -ForegroundColor Red
        return
    }
    
    $Username = Read-Host "Введите имя пользователя"
    if ([string]::IsNullOrWhiteSpace($Username)) {
        Write-Host "Имя пользователя не может быть пустым!" -ForegroundColor Red
        return
    }
    
    # Проверка существования пользователя
    if (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue) {
        Write-Host "Пользователь '$Username' уже существует!" -ForegroundColor Red
        return
    }
    
    $Password = Read-Host "Введите пароль" -AsSecureString
    $PlainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))
    
    if ([string]::IsNullOrWhiteSpace($PlainPassword)) {
        Write-Host "Пароль не может быть пустым!" -ForegroundColor Red
        return
    }
    
    $FullName = Read-Host "Введите полное имя (необязательно)"
    $Description = Read-Host "Введите описание (необязательно)"
    if ([string]::IsNullOrWhiteSpace($Description)) {
        $Description = "Пользователь с профилем на диске D"
    }
    
    $IsAdmin = Read-Host "Добавить в группу администраторов? (y/N)"
    $AddToAdministrators = $IsAdmin -eq 'y' -or $IsAdmin -eq 'Y'
    
    try {
        Write-Host "`nСоздание пользователя $Username..." -ForegroundColor Green
        
        # Создание пользователя
        $SecurePassword = ConvertTo-SecureString $PlainPassword -AsPlainText -Force
        New-LocalUser -Name $Username -Password $SecurePassword -FullName $FullName -Description $Description
        
        Write-Host "Пользователь $Username создан успешно!" -ForegroundColor Green
        
        # Добавление в группу администраторов
        if ($AddToAdministrators) {
            Add-LocalGroupMember -Group "Администраторы" -Member $Username
            Write-Host "Пользователь добавлен в группу Администраторов" -ForegroundColor Yellow
        }
        
        # Создание директории профиля на диске D
        $ProfilePath = "D:\Users\$Username"
        Write-Host "Создание директории профиля: $ProfilePath" -ForegroundColor Green
        
        if (-not (Test-Path "D:\Users")) {
            New-Item -Path "D:\Users" -ItemType Directory -Force
        }
        
        New-Item -Path $ProfilePath -ItemType Directory -Force
        
        # Получение SID пользователя
        $User = Get-LocalUser -Name $Username
        $SID = $User.SID.Value
        Write-Host "SID пользователя: $SID" -ForegroundColor Cyan
        
        # Модификация реестра
        $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$SID"
        
        if (-not (Test-Path $RegistryPath)) {
            New-Item -Path $RegistryPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -Value $ProfilePath
        Write-Host "Путь профиля установлен в реестре: $ProfilePath" -ForegroundColor Green
        
        # Установка прав доступа
        $Acl = Get-Acl $ProfilePath
        $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($Username, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $Acl.SetAccessRule($AccessRule)
        Set-Acl -Path $ProfilePath -AclObject $Acl
        
        Write-Host "Права доступа установлены" -ForegroundColor Green
        Write-Host "`nПользователь $Username успешно создан!" -ForegroundColor Green
        Write-Host "Профиль: $ProfilePath" -ForegroundColor Cyan
        
    } catch {
        Write-Host "Ошибка: $($_.Exception.Message)" -ForegroundColor Red
        
        # Очистка при ошибке
        try {
            if (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue) {
                Remove-LocalUser -Name $Username
                Write-Host "Пользователь удален из-за ошибки" -ForegroundColor Yellow
            }
            
            if (Test-Path $ProfilePath) {
                Remove-Item -Path $ProfilePath -Recurse -Force
                Write-Host "Папка профиля удалена" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "Предупреждение: Не удалось выполнить полную очистку" -ForegroundColor Yellow
        }
    }
}

# Функция удаления пользователя
function Remove-UserFromSystem {
    Write-Host "`n--- УДАЛЕНИЕ ПОЛЬЗОВАТЕЛЯ ---" -ForegroundColor Red
    
    # Получение списка пользователей
    $Users = Get-LocalUser | Where-Object { $_.Name -ne "Administrator" -and $_.Name -ne "DefaultAccount" -and $_.Name -ne "Guest" -and $_.Name -ne "WDAGUtilityAccount" }
    
    if ($Users.Count -eq 0) {
        Write-Host "Не найдено пользователей для удаления" -ForegroundColor Yellow
        return
    }
    
    Write-Host "Доступные пользователи:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Users.Count; $i++) {
        $User = $Users[$i]
        Write-Host "  $($i + 1). $($User.Name) - $($User.FullName)" -ForegroundColor White
    }
    
    Write-Host "  0. Отмена" -ForegroundColor Yellow
    
    do {
        $Choice = Read-Host "`nВыберите пользователя для удаления (номер)"
        $ChoiceNum = $null
        $ValidChoice = [int]::TryParse($Choice, [ref]$ChoiceNum)
    } while (-not $ValidChoice -or $ChoiceNum -lt 0 -or $ChoiceNum -gt $Users.Count)
    
    if ($ChoiceNum -eq 0) {
        Write-Host "Операция отменена" -ForegroundColor Yellow
        return
    }
    
    $UserToDelete = $Users[$ChoiceNum - 1]
    $Username = $UserToDelete.Name
    
    Write-Host "`nВы собираетесь удалить пользователя: $Username" -ForegroundColor Red
    Write-Host "Это действие нельзя отменить!" -ForegroundColor Red
    
    $Confirmation = Read-Host "Подтвердите удаление (введите 'DELETE' для подтверждения)"
    
    if ($Confirmation -ne "DELETE") {
        Write-Host "Операция отменена" -ForegroundColor Yellow
        return
    }
    
    try {
        # Получение SID для удаления из реестра
        $SID = $UserToDelete.SID.Value
        
        # Определение пути профиля
        $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$SID"
        $ProfilePath = $null
        
        if (Test-Path $RegistryPath) {
            $RegValue = Get-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue
            if ($RegValue) {
                $ProfilePath = $RegValue.ProfileImagePath
            }
        }
        
        Write-Host "`nУдаление пользователя из системы..." -ForegroundColor Yellow
        Remove-LocalUser -Name $Username
        Write-Host "✓ Пользователь удален из системы" -ForegroundColor Green
        
        # Удаление записи из реестра
        if (Test-Path $RegistryPath) {
            Remove-Item -Path $RegistryPath -Recurse -Force
            Write-Host "✓ Запись удалена из реестра" -ForegroundColor Green
        }
        
        # Удаление папки профиля
        if ($ProfilePath -and (Test-Path $ProfilePath)) {
            Write-Host "Удаление папки профиля: $ProfilePath" -ForegroundColor Yellow
            
            $DeleteProfile = Read-Host "Удалить папку профиля? (Y/n)"
            if ($DeleteProfile -ne 'n' -and $DeleteProfile -ne 'N') {
                try {
                    Remove-Item -Path $ProfilePath -Recurse -Force
                    Write-Host "✓ Папка профиля удалена" -ForegroundColor Green
                } catch {
                    Write-Host "⚠ Не удалось удалить папку профиля: $($_.Exception.Message)" -ForegroundColor Yellow
                    Write-Host "Возможно, папка используется. Удалите вручную: $ProfilePath" -ForegroundColor Yellow
                }
            } else {
                Write-Host "Папка профиля сохранена: $ProfilePath" -ForegroundColor Cyan
            }
        }
        
        Write-Host "`nПользователь $Username успешно удален!" -ForegroundColor Green
        
    } catch {
        Write-Host "Ошибка при удалении: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Функция отображения списка пользователей
function Show-UserList {
    Write-Host "`n--- СПИСОК ПОЛЬЗОВАТЕЛЕЙ ---" -ForegroundColor Cyan
    
    $Users = Get-LocalUser | Sort-Object Name
    
    foreach ($User in $Users) {
        $SID = $User.SID.Value
        $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$SID"
        $ProfilePath = "Не определен"
        
        if (Test-Path $RegistryPath) {
            $RegValue = Get-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue
            if ($RegValue) {
                $ProfilePath = $RegValue.ProfileImagePath
            }
        }
        
        $Status = if ($User.Enabled) { "Активен" } else { "Отключен" }
        $Color = if ($User.Enabled) { "Green" } else { "Red" }
        
        Write-Host "`nИмя: $($User.Name)" -ForegroundColor White
        Write-Host "Полное имя: $($User.FullName)" -ForegroundColor Gray
        Write-Host "Статус: $Status" -ForegroundColor $Color
        Write-Host "Профиль: $ProfilePath" -ForegroundColor Cyan
        Write-Host "Описание: $($User.Description)" -ForegroundColor Gray
        Write-Host "Последний вход: $($User.LastLogon)" -ForegroundColor Gray
        Write-Host "─────────────────────────────────────────────────────" -ForegroundColor DarkGray
    }
}

# Функция перемещения существующих профилей
function Move-ExistingProfiles {
    Write-Host "`n--- ПЕРЕМЕЩЕНИЕ СУЩЕСТВУЮЩИХ ПРОФИЛЕЙ ---" -ForegroundColor Magenta
    Write-Host "Эта функция переместит профили пользователей из C:\Users на D:\Users" -ForegroundColor Yellow
    Write-Host "ВНИМАНИЕ: Это сложная операция. Рекомендуется создать резервную копию!" -ForegroundColor Red
    
    $Confirmation = Read-Host "`nПродолжить? (y/N)"
    if ($Confirmation -ne 'y' -and $Confirmation -ne 'Y') {
        Write-Host "Операция отменена" -ForegroundColor Yellow
        return
    }
    
    # Проверка диска D
    if (-not (Test-Path "D:\")) {
        Write-Host "Диск D:\ не найден!" -ForegroundColor Red
        return
    }
    
    Write-Host "Эта функция требует детальной реализации и тестирования." -ForegroundColor Yellow
    Write-Host "Рекомендуется использовать метод из статьи с временным администратором." -ForegroundColor Yellow
}

# Функция проверки пользователя
function Test-UserProfile {
    Write-Host "`n--- ПРОВЕРКА ПОЛЬЗОВАТЕЛЯ ---" -ForegroundColor Cyan
    
    $Username = Read-Host "Введите имя пользователя для проверки"
    
    if ([string]::IsNullOrWhiteSpace($Username)) {
        Write-Host "Имя пользователя не может быть пустым!" -ForegroundColor Red
        return
    }
    
    $User = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if (-not $User) {
        Write-Host "Пользователь '$Username' не найден!" -ForegroundColor Red
        return
    }
    
    Write-Host "`n--- Результаты проверки ---" -ForegroundColor Cyan
    
    Write-Host "✓ Пользователь найден в системе" -ForegroundColor Green
    Write-Host "  Имя: $($User.Name)" -ForegroundColor White
    Write-Host "  Полное имя: $($User.FullName)" -ForegroundColor White
    Write-Host "  Описание: $($User.Description)" -ForegroundColor White
    Write-Host "  Активен: $($User.Enabled)" -ForegroundColor White
    Write-Host "  Последний вход: $($User.LastLogon)" -ForegroundColor White
    
    # Проверка профиля на диске D
    $ProfilePath = "D:\Users\$Username"
    if (Test-Path $ProfilePath) {
        Write-Host "✓ Папка профиля найдена: $ProfilePath" -ForegroundColor Green
        
        # Проверка содержимого папки
        $Items = Get-ChildItem -Path $ProfilePath -ErrorAction SilentlyContinue
        Write-Host "  Содержимое папки: $($Items.Count) элементов" -ForegroundColor Cyan
    } else {
        Write-Host "✗ Папка профиля не найдена на диске D" -ForegroundColor Red
        
        # Проверка стандартного местоположения
        $StandardPath = "C:\Users\$Username"
        if (Test-Path $StandardPath) {
            Write-Host "! Профиль найден в стандартном месте: $StandardPath" -ForegroundColor Yellow
        }
    }
    
    # Проверка реестра
    $SID = $User.SID.Value
    $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$SID"
    
    if (Test-Path $RegistryPath) {
        $RegValue = Get-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue
        if ($RegValue) {
            $RegProfilePath = $RegValue.ProfileImagePath
            Write-Host "✓ Запись в реестре найдена: $RegProfilePath" -ForegroundColor Green
            
            if ($RegProfilePath -eq $ProfilePath) {
                Write-Host "✓ Путь в реестре соответствует ожидаемому" -ForegroundColor Green
            } else {
                Write-Host "⚠ Путь в реестре не соответствует D:\Users\$Username" -ForegroundColor Yellow
            }
        } else {
            Write-Host "✗ ProfileImagePath не найден в реестре" -ForegroundColor Red
        }
    } else {
        Write-Host "✗ Запись в реестре не найдена" -ForegroundColor Red
    }
}

# Главный цикл программы
do {
    Show-MainMenu
    $Choice = Read-Host "Выберите действие (0-5)"
    
    switch ($Choice) {
        "1" { New-UserOnDrive }
        "2" { Remove-UserFromSystem }
        "3" { Show-UserList }
        "4" { Move-ExistingProfiles }
        "5" { Test-UserProfile }
        "0" { 
            Write-Host "Выход из программы..." -ForegroundColor Yellow
            exit 0 
        }
        default { 
            Write-Host "Неверный выбор! Нажмите любую клавишу для продолжения..." -ForegroundColor Red
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    }
    
    if ($Choice -ne "0") {
        Write-Host "`nНажмите любую клавишу для возврата в меню..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    
} while ($Choice -ne "0")
