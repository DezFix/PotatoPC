function Create-UserOnDrive {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Username,

        [Parameter(Mandatory=$true)]
        [string]$Password,

        [string]$Drive = "D:"
    )

    # Проверка прав администратора
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "Ошибка: Для выполнения этого скрипта требуются права администратора!" -ForegroundColor Red
        return
    }

    # Проверка наличия диска с использованием Test-Path
    if (!(Test-Path -Path $Drive)) {
        Write-Host "Ошибка: Диск $Drive не существует или недоступен!" -ForegroundColor Red
        return
    }

    # Проверка существования пользователя
    try {
        $ExistingUser = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
        if ($ExistingUser) {
            Write-Host "Ошибка: Пользователь '$Username' уже существует!" -ForegroundColor Red
            return
        }
    }
    catch {
        # Пользователь не существует, продолжаем
    }

    # Путь к профилю пользователя на указанном диске
    $UserProfilePath = "$Drive\Users\$Username"

    # Создание пользователя
    try {
        # Создаем локальную учетную запись
        $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        New-LocalUser -Name $Username -Password $SecurePassword -FullName $Username -Description "Пользователь с профилем на диске $Drive" -PasswordNeverExpires

        Write-Host "Пользователь '$Username' успешно создан." -ForegroundColor Green

        # Добавляем пользователя в группу пользователей
        Add-LocalGroupMember -Group "Users" -Member $Username
        Write-Host "Пользователь добавлен в группу 'Users'." -ForegroundColor Green
    }
    catch {
        Write-Host "Ошибка при создании пользователя: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # Создаем директорию профиля на указанном диске
    try {
        # Создаем основную папку пользователя, если она не существует
        if (!(Test-Path -Path $UserProfilePath)) {
            New-Item -Path $UserProfilePath -ItemType Directory -Force | Out-Null
            Write-Host "Папка профиля создана: $UserProfilePath" -ForegroundColor Green
        }

        # Получаем SID пользователя
        $User = Get-LocalUser -Name $Username
        $UserSid = $User.SID

        # Настраиваем разрешения для папки
        $Acl = Get-Acl $UserProfilePath
        
        # Удаляем унаследованные разрешения для безопасности
        $Acl.SetAccessRuleProtection($true, $false)
        
        # Даем полный доступ пользователю
        $UserAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $UserSid, 
            "FullControl", 
            "ContainerInherit,ObjectInherit", 
            "None", 
            "Allow"
        )
        $Acl.SetAccessRule($UserAccessRule)
        
        # Даем полный доступ системе
        $SystemAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "SYSTEM", 
            "FullControl", 
            "ContainerInherit,ObjectInherit", 
            "None", 
            "Allow"
        )
        $Acl.SetAccessRule($SystemAccessRule)
        
        # Даем полный доступ администраторам
        $AdminAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "Administrators", 
            "FullControl", 
            "ContainerInherit,ObjectInherit", 
            "None", 
            "Allow"
        )
        $Acl.SetAccessRule($AdminAccessRule)

        # Применяем разрешения
        Set-Acl $UserProfilePath $Acl
        Write-Host "Разрешения для папки настроены." -ForegroundColor Green

    }
    catch {
        Write-Host "Ошибка при создании папки профиля: $($_.Exception.Message)" -ForegroundColor Red
        
        # Если не удалось создать папку, удаляем созданного пользователя
        try {
            Remove-LocalUser -Name $Username
            Write-Host "Пользователь '$Username' удален из-за ошибки создания профиля." -ForegroundColor Yellow
        }
        catch {
            Write-Host "Не удалось удалить пользователя '$Username'. Удалите его вручную." -ForegroundColor Red
        }
        return
    }

    # Создание профиля пользователя в реестре (опционально)
    try {
        $ProfileListPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
        $UserProfileKey = "$ProfileListPath\$UserSid"
        
        # Создаем ключ профиля в реестре
        if (!(Test-Path $UserProfileKey)) {
            New-Item -Path $UserProfileKey -Force | Out-Null
            Set-ItemProperty -Path $UserProfileKey -Name "ProfileImagePath" -Value $UserProfilePath
            Write-Host "Профиль пользователя зарегистрирован в реестре." -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Предупреждение: Не удалось создать запись профиля в реестре: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Профиль все равно должен работать." -ForegroundColor Yellow
    }

    Write-Host "`nПользователь '$Username' успешно создан с профилем на диске $Drive" -ForegroundColor Green
    Write-Host "Путь к профилю: $UserProfilePath" -ForegroundColor Cyan
}

# Пример использования функции
# Убедитесь, что запускаете PowerShell от имени администратора
# Create-UserOnDrive -Username "TestUser" -Password "StrongPassword123!" -Drive "D:"
