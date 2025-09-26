# Скрипт создания пользователя с профилем на диске D

function Create-UserOnDrive {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Username,
        
        [Parameter(Mandatory=$true)]
        [string]$Password,
        
        [string]$Drive = "D:"
    )

    # Проверка наличия диска D
    if (!(Test-Path $Drive)) {
        Write-Host "<b>Ошибка: Диск $Drive не существует!</b>"
        return
    }

    # Путь к профилю пользователя на диске D
    $UserProfilePath = "$Drive\Users\$Username"

    # Создание пользователя
    try {
        # Создаем локальную учетную запись
        New-LocalUser -Name $Username -Password (ConvertTo-SecureString $Password -AsPlainText -Force) -FullName $Username -Description "Пользователь с профилем на диске D"
        
        # Добавляем пользователя в группу пользователей
        Add-LocalGroupMember -Group "Users" -Member $Username
    }
    catch {
        Write-Host "<b>Ошибка при создании пользователя: $($_.Exception.Message)</b>"
        return
    }

    # Создаем директорию профиля на диске D
    try {
        # Создаем основную папку пользователя
        New-Item -Path $UserProfilePath -ItemType Directory -Force | Out-Null
        
        # Настраиваем разрешения для папки
        $Acl = Get-Acl $UserProfilePath
        $UserSid = (Get-LocalUser -Name $Username).SID
        $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($UserSid, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $Acl.SetAccessRule($AccessRule)
        Set-Acl $UserProfilePath $Acl
    }
    catch {
        Write-Host "<b>Ошибка при создании папки профиля: $($_.Exception.Message)</b>"
        return
    }

    # Настройка профиля пользователя
    try {
        # Регистрация нового пути профиля в реестре
        $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
        $ProfileImagePath = "$UserProfilePath\NTUSER.DAT"
        
        New-ItemProperty -Path "$RegPath\$UserSid" -Name "ProfileImagePath" -Value $ProfileImagePath -PropertyType "String" -Force | Out-Null
    }
    catch {
        Write-Host "<b>Ошибка при настройке профиля в реестре: $($_.Exception.Message)</b>"
    }

    Write-Host "<b>Пользователь $Username успешно создан с профилем на диске $Drive</b>"
}

# Пример вызова функции
# Замените 'NovogoPolzovatelya' и 'StrongPassword123!' на желаемые значения
Create-UserOnDrive -Username "NovogoPolzovatelya" -Password "StrongPassword123!" -Drive "D:"
