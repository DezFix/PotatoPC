# Простой скрипт для создания пользователя с домашней папкой на диске D
# Запускать от имени администратора

# Параметры (измените по необходимости)
$Username = "NewUser"
$Password = "YourPassword123"
$HomePath = "D:\Users\$Username"

# Создание пользователя
$SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
New-LocalUser -Name $Username -Password $SecurePassword -PasswordNeverExpires:$true

# Добавление в группу пользователей
Add-LocalGroupMember -Group "Users" -Member $Username

# Создание домашней папки
New-Item -ItemType Directory -Path $HomePath -Force

# Назначение прав доступа
$Acl = Get-Acl $HomePath
$Acl.SetAccessRuleProtection($true, $false)

# Полный доступ для пользователя
$UserRule = New-Object System.Security.AccessControl.FileSystemAccessRule($Username, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$Acl.SetAccessRule($UserRule)

# Полный доступ для администраторов
$AdminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$Acl.SetAccessRule($AdminRule)

# Применение прав
Set-Acl -Path $HomePath -AclObject $Acl

Write-Host "Пользователь $Username создан с домашней папкой $HomePath" -ForegroundColor Green
