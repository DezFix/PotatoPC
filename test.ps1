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
    Write-Host "║  1. Создать пользователя (Системный метод) - РЕКОМЕНДУЕТСЯ    ║" -ForegroundColor Green
    Write-Host "║  2. Создать пользователя (Прямой метод)                       ║" -ForegroundColor White
    Write-Host "║  3. Удалить пользователя                                       ║" -ForegroundColor White
    Write-Host "║  4. Показать список пользователей                             ║" -ForegroundColor White
    Write-Host "║  5. Переместить существующие профили на диск D                ║" -ForegroundColor White
    Write-Host "║  6. Проверить пользователя                                     ║" -ForegroundColor White
    Write-Host "║  0. Выход                                                      ║" -ForegroundColor Yellow
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Системный метод (1): Временно меняет настройки Windows, более надежный" -ForegroundColor Gray
    Write-Host "Прямой метод (2): Создает и настраивает профиль напрямую" -ForegroundColor Gray
    Write-Host ""
}

# Функция создания пользователя через временное изменение системных настроек
function New-UserOnDrive-SystemMethod {
    Write-Host "`n--- СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ (СИСТЕМНЫЙ МЕТОД) ---" -ForegroundColor Green
    Write-Host "Этот метод временно изменит системные настройки профилей" -ForegroundColor Yellow
    
    # Проверка существования диска D
    if (-not (Test-Path "D:\")) {
        Write-Host "Ошибка: Диск D:\ не найден!" -ForegroundColor Red
        return
    }
    
    $Username = Read-Host "Введите имя пользователя"
    if ([string]::IsNullOrWhiteSpace($Username) -or $Username -match '[\\/:*?"<>|]' -or $Username.Length -gt 20) {
        Write-Host "Некорректное имя пользователя!" -ForegroundColor Red
        return
    }
    
    # Проверка существования пользователя
    if (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue) {
        Write-Host "Пользователь '$Username' уже существует!" -ForegroundColor Red
        return
    }
    
    $Password = Read-Host "Введите пароль" -AsSecureString
    $PlainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))
    
    if ([string]::IsNullOrWhiteSpace($PlainPassword) -or $PlainPassword.Length -lt 4) {
        Write-Host "Пароль должен содержать минимум 4 символа!" -ForegroundColor Red
        return
    }
    
    $FullName = Read-Host "Введите полное имя (необязательно)"
    $Description = Read-Host "Введите описание (необязательно)"
    if ([string]::IsNullOrWhiteSpace($Description)) {
        $Description = "Пользователь с профилем на диске D"
    }
    
    $IsAdmin = Read-Host "Добавить в группу администраторов? (y/N)"
    $AddToAdministrators = $IsAdmin -eq 'y' -or $IsAdmin -eq 'Y'
    
    # Создание резервной копии настроек реестра
    $RegistryBasePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
    $BackupSettings = @{}
    
    try {
        Write-Host "`n=== РЕЗЕРВНОЕ КОПИРОВАНИЕ НАСТРОЕК ===" -ForegroundColor Cyan
        
        # Сохраняем текущие значения
        $CurrentSettings = Get-ItemProperty -Path $RegistryBasePath -ErrorAction SilentlyContinue
        if ($CurrentSettings) {
            if ($CurrentSettings.PSObject.Properties.Name -contains "ProfilesDirectory") {
                $BackupSettings["ProfilesDirectory"] = $CurrentSettings.ProfilesDirectory
                Write-Host "✓ Сохранено: ProfilesDirectory = $($CurrentSettings.ProfilesDirectory)" -ForegroundColor Green
            }
            if ($CurrentSettings.PSObject.Properties.Name -contains "Default") {
                $BackupSettings["Default"] = $CurrentSettings.Default
                Write-Host "✓ Сохранено: Default = $($CurrentSettings.Default)" -ForegroundColor Green
            }
            if ($CurrentSettings.PSObject.Properties.Name -contains "Public") {
                $BackupSettings["Public"] = $CurrentSettings.Public
                Write-Host "✓ Сохранено: Public = $($CurrentSettings.Public)" -ForegroundColor Green
            }
        }
        
        # Создаем папку D:\Users если не существует
        if (-not (Test-Path "D:\Users")) {
            New-Item -Path "D:\Users" -ItemType Directory -Force | Out-Null
            Write-Host "✓ Создана папка D:\Users" -ForegroundColor Green
        }
        
        Write-Host "`n=== ИЗМЕНЕНИЕ СИСТЕМНЫХ НАСТРОЕК ===" -ForegroundColor Cyan
        
        # Устанавливаем новые значения для создания профилей на диске D
        Set-ItemProperty -Path $RegistryBasePath -Name "ProfilesDirectory" -Value "D:\Users" -Type ExpandString
        Write-Host "✓ Установлено: ProfilesDirectory = D:\Users" -ForegroundColor Green
        
        Set-ItemProperty -Path $RegistryBasePath -Name "Default" -Value "D:\Users\Default" -Type ExpandString
        Write-Host "✓ Установлено: Default = D:\Users\Default" -ForegroundColor Green
        
        Set-ItemProperty -Path $RegistryBasePath -Name "Public" -Value "D:\Users\Public" -Type ExpandString
        Write-Host "✓ Установлено: Public = D:\Users\Public" -ForegroundColor Green
        
        Write-Host "`n=== СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ СИСТЕМНЫМИ СРЕДСТВАМИ ===" -ForegroundColor Cyan
        
        # Создаем пользователя обычным способом - система автоматически использует новые настройки
        $SecurePassword = ConvertTo-SecureString $PlainPassword -AsPlainText -Force
        
        $UserParams = @{
            Name = $Username
            Password = $SecurePassword
            Description = $Description
            PasswordNeverExpires = $true
            UserMayNotChangePassword = $false
        }
        
        if (-not [string]::IsNullOrWhiteSpace($FullName)) {
            $UserParams.FullName = $FullName
        }
        
        New-LocalUser @UserParams
        Write-Host "✓ Пользователь создан системными средствами" -ForegroundColor Green
        
        # Добавление в группу администраторов если нужно
        if ($AddToAdministrators) {
            $AdminGroups = @("Administrators", "Администраторы")
            $GroupAdded = $false
            
            foreach ($GroupName in $AdminGroups) {
                try {
                    Add-LocalGroupMember -Group $GroupName -Member $Username -ErrorAction Stop
                    Write-Host "✓ Добавлен в группу $GroupName" -ForegroundColor Green
                    $GroupAdded = $true
                    break
                } catch {
                    continue
                }
            }
            
            if (-not $GroupAdded) {
                Write-Host "⚠ Не удалось добавить в группу администраторов" -ForegroundColor Yellow
            }
        }
        
        # Проверяем созданного пользователя
        Start-Sleep -Seconds 2
        $CreatedUser = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
        if ($CreatedUser) {
            Write-Host "✓ Пользователь подтвержден в системе" -ForegroundColor Green
            Write-Host "  SID: $($CreatedUser.SID.Value)" -ForegroundColor Gray
        } else {
            throw "Пользователь не найден после создания"
        }
        
        Write-Host "`n=== ВОССТАНОВЛЕНИЕ ИСХОДНЫХ НАСТРОЕК ===" -ForegroundColor Cyan
        
        # Восстанавливаем оригинальные настройки
        foreach ($Setting in $BackupSettings.GetEnumerator()) {
            Set-ItemProperty -Path $RegistryBasePath -Name $Setting.Key -Value $Setting.Value
            Write-Host "✓ Восстановлено: $($Setting.Key) = $($Setting.Value)" -ForegroundColor Green
        }
        
        Write-Host "`n🎉 ПОЛЬЗОВАТЕЛЬ СОЗДАН УСПЕШНО!" -ForegroundColor Green
        Write-Host "Имя: $Username" -ForegroundColor White
        Write-Host "Профиль будет создан в: D:\Users\$Username" -ForegroundColor Cyan
        Write-Host "Системные настройки восстановлены" -ForegroundColor Green
        
        # Финальная проверка
        Write-Host "`n--- Финальная проверка ---" -ForegroundColor Cyan
        Test-UserCreationResult -Username $Username
        
    } catch {
        Write-Host "`nОШИБКА: $($_.Exception.Message)" -ForegroundColor Red
        
        Write-Host "`n=== АВАРИЙНОЕ ВОССТАНОВЛЕНИЕ ===" -ForegroundColor Red
        
        # Восстанавливаем настройки реестра в любом случае
        try {
            foreach ($Setting in $BackupSettings.GetEnumerator()) {
                Set-ItemProperty -Path $RegistryBasePath -Name $Setting.Key -Value $Setting.Value
                Write-Host "✓ Восстановлено: $($Setting.Key)" -ForegroundColor Yellow
            }
            Write-Host "Системные настройки восстановлены" -ForegroundColor Green
        } catch {
            Write-Host "КРИТИЧЕСКАЯ ОШИБКА: Не удалось восстановить настройки реестра!" -ForegroundColor Red
            Write-Host "Требуется ручное восстановление следующих значений:" -ForegroundColor Red
            foreach ($Setting in $BackupSettings.GetEnumerator()) {
                Write-Host "  $($Setting.Key) = $($Setting.Value)" -ForegroundColor Yellow
            }
        }
        
        # Удаляем пользователя если создался
        try {
            if (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue) {
                Remove-LocalUser -Name $Username
                Write-Host "Пользователь удален из-за ошибки" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "Не удалось удалить пользователя: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Функция создания пользователя (оригинальный метод)
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
    
    # Проверка корректности имени пользователя
    if ($Username -match '[\\/:*?"<>|]' -or $Username.Length -gt 20) {
        Write-Host "Некорректное имя пользователя! Избегайте специальных символов и длинных имен." -ForegroundColor Red
        return
    }
    
    # Проверка существования пользователя
    if (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue) {
        Write-Host "Пользователь '$Username' уже существует!" -ForegroundColor Red
        return
    }
    
    $Password = Read-Host "Введите пароль" -AsSecureString
    $PlainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))
    
    if ([string]::IsNullOrWhiteSpace($PlainPassword) -or $PlainPassword.Length -lt 4) {
        Write-Host "Пароль не может быть пустым и должен содержать минимум 4 символа!" -ForegroundColor Red
        return
    }
    
    $FullName = Read-Host "Введите полное имя (необязательно)"
    $Description = Read-Host "Введите описание (необязательно)"
    if ([string]::IsNullOrWhiteSpace($Description)) {
        $Description = "Пользователь с профилем на диске D"
    }
    
    $IsAdmin = Read-Host "Добавить в группу администраторов? (y/N)"
    $AddToAdministrators = $IsAdmin -eq 'y' -or $IsAdmin -eq 'Y'
    
    $ProfilePath = "D:\Users\$Username"
    
    try {
        Write-Host "`n=== НАЧАЛО СОЗДАНИЯ ПОЛЬЗОВАТЕЛЯ ===" -ForegroundColor Yellow
        
        # Шаг 1: Создание пользователя в системе
        Write-Host "Шаг 1: Создание пользователя в системе..." -ForegroundColor Cyan
        $SecurePassword = ConvertTo-SecureString $PlainPassword -AsPlainText -Force
        
        $UserParams = @{
            Name = $Username
            Password = $SecurePassword
            Description = $Description
            PasswordNeverExpires = $true
            UserMayNotChangePassword = $false
        }
        
        if (-not [string]::IsNullOrWhiteSpace($FullName)) {
            $UserParams.FullName = $FullName
        }
        
        New-LocalUser @UserParams
        
        # Проверка создания пользователя
        Start-Sleep -Seconds 2
        $CreatedUser = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
        if (-not $CreatedUser) {
            throw "Не удалось создать пользователя в системе"
        }
        
        Write-Host "✓ Пользователь создан в системе: $($CreatedUser.Name)" -ForegroundColor Green
        Write-Host "  SID: $($CreatedUser.SID.Value)" -ForegroundColor Gray
        Write-Host "  Статус: $($CreatedUser.Enabled)" -ForegroundColor Gray
        
        # Шаг 2: Добавление в группу администраторов
        if ($AddToAdministrators) {
            Write-Host "Шаг 2: Добавление в группу администраторов..." -ForegroundColor Cyan
            try {
                # Попробуем разные варианты названия группы
                $AdminGroups = @("Administrators", "Администраторы")
                $GroupAdded = $false
                
                foreach ($GroupName in $AdminGroups) {
                    try {
                        Add-LocalGroupMember -Group $GroupName -Member $Username -ErrorAction Stop
                        Write-Host "✓ Пользователь добавлен в группу $GroupName" -ForegroundColor Green
                        $GroupAdded = $true
                        break
                    } catch {
                        continue
                    }
                }
                
                if (-not $GroupAdded) {
                    Write-Host "⚠ Не удалось добавить в группу администраторов" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "⚠ Ошибка при добавлении в группу: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        
        # Шаг 3: Создание структуры папок
        Write-Host "Шаг 3: Создание структуры папок..." -ForegroundColor Cyan
        
        if (-not (Test-Path "D:\Users")) {
            New-Item -Path "D:\Users" -ItemType Directory -Force | Out-Null
            Write-Host "✓ Создана папка D:\Users" -ForegroundColor Green
        }
        
        if (-not (Test-Path $ProfilePath)) {
            New-Item -Path $ProfilePath -ItemType Directory -Force | Out-Null
            Write-Host "✓ Создана папка профиля: $ProfilePath" -ForegroundColor Green
        }
        
        # Шаг 4: Настройка реестра
        Write-Host "Шаг 4: Настройка реестра..." -ForegroundColor Cyan
        $SID = $CreatedUser.SID.Value
        $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$SID"
        
        # Создаем ключ реестра если не существует
        if (-not (Test-Path $RegistryPath)) {
            New-Item -Path $RegistryPath -Force | Out-Null
            Write-Host "✓ Создан ключ реестра: $RegistryPath" -ForegroundColor Green
        }
        
        # Устанавливаем путь профиля
        Set-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -Value $ProfilePath -Type String
        
        # Устанавливаем дополнительные параметры
        Set-ItemProperty -Path $RegistryPath -Name "State" -Value 0 -Type DWord
        Set-ItemProperty -Path $RegistryPath -Name "RefCount" -Value 0 -Type DWord
        
        # Проверяем установку
        $CheckValue = Get-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue
        if ($CheckValue -and $CheckValue.ProfileImagePath -eq $ProfilePath) {
            Write-Host "✓ Путь профиля установлен в реестре: $ProfilePath" -ForegroundColor Green
        } else {
            throw "Не удалось установить путь профиля в реестре"
        }
        
        # Шаг 5: Настройка прав доступа
        Write-Host "Шаг 5: Настройка прав доступа..." -ForegroundColor Cyan
        try {
            $Acl = Get-Acl $ProfilePath
            
            # Добавляем права для пользователя
            $UserAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $Username, 
                "FullControl", 
                "ContainerInherit,ObjectInherit", 
                "None", 
                "Allow"
            )
            $Acl.SetAccessRule($UserAccessRule)
            
            # Добавляем права для системы
            $SystemAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "SYSTEM", 
                "FullControl", 
                "ContainerInherit,ObjectInherit", 
                "None", 
                "Allow"
            )
            $Acl.SetAccessRule($SystemAccessRule)
            
            Set-Acl -Path $ProfilePath -AclObject $Acl
            Write-Host "✓ Права доступа настроены" -ForegroundColor Green
            
        } catch {
            Write-Host "⚠ Проблема с настройкой прав доступа: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        
        Write-Host "`n=== ПОЛЬЗОВАТЕЛЬ СОЗДАН УСПЕШНО ===" -ForegroundColor Green
        Write-Host "Имя: $Username" -ForegroundColor White
        Write-Host "Профиль: $ProfilePath" -ForegroundColor Cyan
        Write-Host "SID: $SID" -ForegroundColor Gray
        
        # Финальная проверка
        Write-Host "`n--- Финальная проверка ---" -ForegroundColor Cyan
        Test-UserCreationResult -Username $Username
        
    } catch {
        Write-Host "`nОШИБКА ПРИ СОЗДАНИИ: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Детали ошибки: $($_.Exception.GetType().FullName)" -ForegroundColor Red
        
        # Подробная очистка при ошибке
        Write-Host "`nВыполняется откат изменений..." -ForegroundColor Yellow
        try {
            # Удаляем пользователя если создался
            $UserToCleanup = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
            if ($UserToCleanup) {
                Remove-LocalUser -Name $Username -ErrorAction SilentlyContinue
                Write-Host "- Пользователь удален из системы" -ForegroundColor Yellow
            }
            
            # Удаляем папку профиля
            if (Test-Path $ProfilePath) {
                Remove-Item -Path $ProfilePath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "- Папка профиля удалена" -ForegroundColor Yellow
            }
            
            # Удаляем запись из реестра
            if ($SID -and (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$SID")) {
                Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$SID" -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "- Запись реестра удалена" -ForegroundColor Yellow
            }
            
            Write-Host "Откат завершен" -ForegroundColor Yellow
            
        } catch {
            Write-Host "Внимание: Не удалось выполнить полный откат: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Функция для детальной проверки созданного пользователя
function Test-UserCreationResult {
    param([string]$Username)
    
    $AllGood = $true
    
    # Проверка 1: Пользователь в системе
    $User = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if ($User) {
        Write-Host "✓ Пользователь найден в системе" -ForegroundColor Green
    } else {
        Write-Host "✗ Пользователь НЕ найден в системе" -ForegroundColor Red
        $AllGood = $false
    }
    
    # Проверка 2: Папка профиля
    $ProfilePath = "D:\Users\$Username"
    if (Test-Path $ProfilePath) {
        Write-Host "✓ Папка профиля существует" -ForegroundColor Green
    } else {
        Write-Host "✗ Папка профиля НЕ существует" -ForegroundColor Red
        $AllGood = $false
    }
    
    # Проверка 3: Запись в реестре
    if ($User) {
        $SID = $User.SID.Value
        $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$SID"
        
        if (Test-Path $RegistryPath) {
            $RegValue = Get-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue
            if ($RegValue -and $RegValue.ProfileImagePath -eq $ProfilePath) {
                Write-Host "✓ Запись в реестре корректна" -ForegroundColor Green
            } else {
                Write-Host "✗ Запись в реестре некорректна" -ForegroundColor Red
                $AllGood = $false
            }
        } else {
            Write-Host "✗ Запись в реестре НЕ найдена" -ForegroundColor Red
            $AllGood = $false
        }
    }
    
    if ($AllGood) {
        Write-Host "`n🎉 Все проверки пройдены! Пользователь готов к использованию." -ForegroundColor Green
        Write-Host "При первом входе Windows создаст структуру профиля." -ForegroundColor Cyan
    } else {
        Write-Host "`n⚠ Есть проблемы с созданием пользователя!" -ForegroundColor Red
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
    
    Write-Host "`n--- Подробная информация о пользователе ---" -ForegroundColor Cyan
    
    Write-Host "✓ Пользователь найден в системе" -ForegroundColor Green
    Write-Host "  Имя: $($User.Name)" -ForegroundColor White
    Write-Host "  Полное имя: $($User.FullName)" -ForegroundColor White
    Write-Host "  Описание: $($User.Description)" -ForegroundColor White
    Write-Host "  Активен: $($User.Enabled)" -ForegroundColor White
    Write-Host "  SID: $($User.SID.Value)" -ForegroundColor Gray
    Write-Host "  Последний вход: $($User.LastLogon)" -ForegroundColor White
    
    # Проверка групп пользователя
    try {
        $UserGroups = Get-LocalGroup | Where-Object { 
            (Get-LocalGroupMember -Group $_.Name -ErrorAction SilentlyContinue).Name -contains $User.Name 
        }
        Write-Host "  Группы: $($UserGroups.Name -join ', ')" -ForegroundColor Cyan
    } catch {
        Write-Host "  Группы: Не удалось определить" -ForegroundColor Yellow
    }
    
    # Проверка профиля на диске D
    $ProfilePath = "D:\Users\$Username"
    Write-Host "`n--- Проверка профиля ---" -ForegroundColor Cyan
    
    if (Test-Path $ProfilePath) {
        Write-Host "✓ Папка профиля найдена: $ProfilePath" -ForegroundColor Green
        
        # Проверка содержимого папки
        try {
            $Items = Get-ChildItem -Path $ProfilePath -Force -ErrorAction SilentlyContinue
            Write-Host "  Содержимое: $($Items.Count) элементов" -ForegroundColor Cyan
            
            # Показываем основные папки профиля если они есть
            $ProfileFolders = @("Desktop", "Documents", "Downloads", "Pictures", "Music", "Videos")
            $ExistingFolders = $Items | Where-Object { $_.PSIsContainer -and $ProfileFolders -contains $_.Name }
            if ($ExistingFolders) {
                Write-Host "  Папки профиля: $($ExistingFolders.Name -join ', ')" -ForegroundColor Cyan
            }
            
            # Проверяем права доступа
            $Acl = Get-Acl $ProfilePath
            $UserAccess = $Acl.Access | Where-Object { $_.IdentityReference -like "*$Username*" }
            if ($UserAccess) {
                Write-Host "✓ Права доступа пользователя настроены" -ForegroundColor Green
            } else {
                Write-Host "⚠ Права доступа пользователя не найдены" -ForegroundColor Yellow
            }
            
        } catch {
            Write-Host "  Проблема с доступом к содержимому папки" -ForegroundColor Yellow
        }
    } else {
        Write-Host "✗ Папка профиля НЕ найдена на диске D" -ForegroundColor Red
        
        # Проверка стандартного местоположения
        $StandardPath = "C:\Users\$Username"
        if (Test-Path $StandardPath) {
            Write-Host "! Профиль найден в стандартном месте: $StandardPath" -ForegroundColor Yellow
            $Items = Get-ChildItem -Path $StandardPath -Force -ErrorAction SilentlyContinue
            Write-Host "  Содержимое стандартного профиля: $($Items.Count) элементов" -ForegroundColor Gray
        } else {
            Write-Host "! Профиль не найден ни в одном из стандартных мест" -ForegroundColor Red
        }
    }
    
    # Проверка реестра
    Write-Host "`n--- Проверка реестра ---" -ForegroundColor Cyan
    $SID = $User.SID.Value
    $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$SID"
    
    if (Test-Path $RegistryPath) {
        Write-Host "✓ Ключ реестра найден: $RegistryPath" -ForegroundColor Green
        
        $RegValue = Get-ItemProperty -Path $RegistryPath -ErrorAction SilentlyContinue
        if ($RegValue) {
            Write-Host "  ProfileImagePath: $($RegValue.ProfileImagePath)" -ForegroundColor Cyan
            Write-Host "  State: $($RegValue.State)" -ForegroundColor Gray
            Write-Host "  RefCount: $($RegValue.RefCount)" -ForegroundColor Gray
            
            if ($RegValue.ProfileImagePath -eq $ProfilePath) {
                Write-Host "✓ Путь в реестре соответствует D:\Users\$Username" -ForegroundColor Green
            } else {
                Write-Host "⚠ Путь в реестре: $($RegValue.ProfileImagePath)" -ForegroundColor Yellow
                Write-Host "   Ожидался: $ProfilePath" -ForegroundColor Yellow
            }
        } else {
            Write-Host "✗ Не удалось прочитать данные из реестра" -ForegroundColor Red
        }
    } else {
        Write-Host "✗ Ключ реестра НЕ найден" -ForegroundColor Red
        Write-Host "   Это означает, что пользователь еще не входил в систему" -ForegroundColor Yellow
    }
    
    # Итоговая оценка
    Write-Host "`n--- ЗАКЛЮЧЕНИЕ ---" -ForegroundColor Cyan
    $Issues = 0
    
    if (-not (Test-Path $ProfilePath)) { $Issues++ }
    if (-not (Test-Path $RegistryPath)) { 
        Write-Host "ℹ Пользователь еще не входил в систему - это нормально для нового пользователя" -ForegroundColor Blue
    } else {
        $RegCheck = Get-ItemProperty -Path $RegistryPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue
        if (-not $RegCheck -or $RegCheck.ProfileImagePath -ne $ProfilePath) { $Issues++ }
    }
    
    if ($Issues -eq 0) {
        Write-Host "🎉 Пользователь настроен корректно!" -ForegroundColor Green
    } elseif ($Issues -eq 1) {
        Write-Host "⚠ Найдена 1 проблема - требует внимания" -ForegroundColor Yellow
    } else {
        Write-Host "❌ Найдено $Issues проблем - требуется исправление" -ForegroundColor Red
    }
}

# Главный цикл программы
do {
    Show-MainMenu
    $Choice = Read-Host "Выберите действие (0-6)"
    
    switch ($Choice) {
        "1" { New-UserOnDrive-SystemMethod }
        "2" { New-UserOnDrive }
        "3" { Remove-UserFromSystem }
        "4" { Show-UserList }
        "5" { Move-ExistingProfiles }
        "6" { Test-UserProfile }
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
