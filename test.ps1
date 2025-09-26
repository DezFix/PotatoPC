# Менеджер двойных профилей пользователей
# Управление и переключение между системным (C:\Users) и домашним (D:\Home) профилями
# Запускать от имени администратора

param(
    [Parameter(Mandatory=$false)]
    [string]$Username,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("List", "Switch", "Create", "Info", "Remove")]
    [string]$Action = "List",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("System", "Home")]
    [string]$ProfileType = "System"
)

function Show-Header {
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                    МЕНЕДЖЕР ДВОЙНЫХ ПРОФИЛЕЙ                 ║" -ForegroundColor Cyan
    Write-Host "║                  System (C:\Users) + Home (D:\Home)          ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Get-UserProfiles {
    $UserProfilesKey = "HKLM:\SOFTWARE\UserProfiles"
    $profiles = @()
    
    if (Test-Path $UserProfilesKey) {
        $userKeys = Get-ChildItem -Path $UserProfilesKey
        foreach ($key in $userKeys) {
            $keyPath = $key.PSPath
            $username = $key.PSChildName
            
            if (Test-Path $keyPath) {
                $profile = @{
                    Username = $username
                    SystemProfile = (Get-ItemProperty -Path $keyPath -Name "SystemProfile" -ErrorAction SilentlyContinue).SystemProfile
                    HomeProfile = (Get-ItemProperty -Path $keyPath -Name "HomeProfile" -ErrorAction SilentlyContinue).HomeProfile
                    ActiveProfile = (Get-ItemProperty -Path $keyPath -Name "ActiveProfile" -ErrorAction SilentlyContinue).ActiveProfile
                    Created = (Get-ItemProperty -Path $keyPath -Name "Created" -ErrorAction SilentlyContinue).Created
                    UserSID = (Get-ItemProperty -Path $keyPath -Name "UserSID" -ErrorAction SilentlyContinue).UserSID
                }
                $profiles += $profile
            }
        }
    }
    
    return $profiles
}

function Show-UserProfiles {
    $profiles = Get-UserProfiles
    
    if ($profiles.Count -eq 0) {
        Write-Host "Пользователи с двойными профилями не найдены." -ForegroundColor Yellow
        return
    }
    
    Write-Host "Список пользователей с двойными профилями:" -ForegroundColor Green
    Write-Host ("═" * 80) -ForegroundColor Gray
    
    foreach ($profile in $profiles) {
        $activeColor = if ($profile.ActiveProfile -eq "Home") { "Yellow" } else { "White" }
        
        Write-Host "Пользователь: " -NoNewline -ForegroundColor Cyan
        Write-Host $profile.Username -ForegroundColor White
        Write-Host "  Системный:  " -NoNewline -ForegroundColor Gray
        Write-Host $profile.SystemProfile -ForegroundColor White
        Write-Host "  Домашний:   " -NoNewline -ForegroundColor Gray
        Write-Host $profile.HomeProfile -ForegroundColor White
        Write-Host "  Активный:   " -NoNewline -ForegroundColor Gray
        Write-Host $profile.ActiveProfile -ForegroundColor $activeColor
        Write-Host "  Создан:     " -NoNewline -ForegroundColor Gray
        Write-Host $profile.Created -ForegroundColor White
        Write-Host ("─" * 80) -ForegroundColor DarkGray
    }
}

function Switch-UserProfile {
    param($Username, $ProfileType)
    
    if (-not $Username) {
        Write-Error "Не указано имя пользователя для переключения профиля!"
        return
    }
    
    # Проверка существования пользователя
    $user = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if (-not $user) {
        Write-Error "Пользователь $Username не найден!"
        return
    }
    
    $UserSID = $user.SID.Value
    $UserKey = "HKLM:\SOFTWARE\UserProfiles\$Username"
    
    if (!(Test-Path $UserKey)) {
        Write-Error "Двойной профиль для пользователя $Username не настроен!"
        Write-Host "Используйте действие 'Create' для создания двойного профиля." -ForegroundColor Yellow
        return
    }
    
    $SystemPath = (Get-ItemProperty -Path $UserKey -Name "SystemProfile").SystemProfile
    $HomePath = (Get-ItemProperty -Path $UserKey -Name "HomeProfile").HomeProfile
    
    # Проверка существования путей
    if ($ProfileType -eq "Home" -and !(Test-Path $HomePath)) {
        Write-Error "Домашняя папка не существует: $HomePath"
        return
    }
    
    if ($ProfileType -eq "System" -and !(Test-Path $SystemPath)) {
        Write-Warning "Системная папка не существует: $SystemPath"
    }
    
    # Завершение сеанса пользователя
    Write-Host "Завершение активных сеансов пользователя $Username..." -ForegroundColor Yellow
    $sessions = query user 2>$null | Where-Object { $_ -match $Username }
    foreach ($session in $sessions) {
        $sessionId = ($session -split '\s+')[2]
        if ($sessionId -match '^\d+$') {
            logoff $sessionId 2>$null
            Write-Host "Сеанс $sessionId завершен." -ForegroundColor Gray
        }
    }
    
    # Ожидание завершения процессов
    Start-Sleep -Seconds 2
    
    # Переключение профиля в реестре
    $ProfileListPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$UserSID"
    
    switch ($ProfileType) {
        "System" {
            Set-ItemProperty -Path $ProfileListPath -Name "ProfileImagePath" -Value $SystemPath
            Set-ItemProperty -Path $UserKey -Name "ActiveProfile" -Value "System"
            Write-Host "✓ Переключено на системный профиль: $SystemPath" -ForegroundColor Green
        }
        "Home" {
            Set-ItemProperty -Path $ProfileListPath -Name "ProfileImagePath" -Value $HomePath
            Set-ItemProperty -Path $UserKey -Name "ActiveProfile" -Value "Home"
            Write-Host "✓ Переключено на домашний профиль: $HomePath" -ForegroundColor Green
        }
    }
    
    Write-Host "⚠  Перезагрузите систему для применения изменений!" -ForegroundColor Yellow
}

function Show-UserInfo {
    param($Username)
    
    if (-not $Username) {
        Write-Error "Не указано имя пользователя!"
        return
    }
    
    $UserKey = "HKLM:\SOFTWARE\UserProfiles\$Username"
    
    if (!(Test-Path $UserKey)) {
        Write-Host "Двойной профиль для пользователя $Username не настроен." -ForegroundColor Yellow
        return
    }
    
    $profile = Get-ItemProperty -Path $UserKey
    $user = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                    ИНФОРМАЦИЯ О ПРОФИЛЕ                      ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    
    Write-Host "Пользователь:      " -NoNewline -ForegroundColor Cyan
    Write-Host $Username -ForegroundColor White
    Write-Host "SID:               " -NoNewline -ForegroundColor Cyan
    Write-Host $profile.UserSID -ForegroundColor White
    Write-Host "Создан:            " -NoNewline -ForegroundColor Cyan
    Write-Host $profile.Created -ForegroundColor White
    Write-Host ""
    Write-Host "Системный профиль: " -NoNewline -ForegroundColor Cyan
    Write-Host $profile.SystemProfile -ForegroundColor White
    Write-Host "  Существует:      " -NoNewline -ForegroundColor Gray
    $systemExists = Test-Path $profile.SystemProfile
    Write-Host $systemExists -ForegroundColor $(if($systemExists){"Green"}else{"Red"})
    
    Write-Host "Домашний профиль:  " -NoNewline -ForegroundColor Cyan
    Write-Host $profile.HomeProfile -ForegroundColor White
    Write-Host "  Существует:      " -NoNewline -ForegroundColor Gray
    $homeExists = Test-Path $profile.HomeProfile
    Write-Host $homeExists -ForegroundColor $(if($homeExists){"Green"}else{"Red"})
    
    Write-Host ""
    Write-Host "Активный профиль:  " -NoNewline -ForegroundColor Cyan
    $activeColor = if ($profile.ActiveProfile -eq "Home") { "Yellow" } else { "White" }
    Write-Host $profile.ActiveProfile -ForegroundColor $activeColor
    
    # Проверка текущего профиля в реестре Windows
    if ($user) {
        $ProfileListPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($user.SID.Value)"
        if (Test-Path $ProfileListPath) {
            $currentPath = (Get-ItemProperty -Path $ProfileListPath -Name "ProfileImagePath").ProfileImagePath
            Write-Host "Windows профиль:   " -NoNewline -ForegroundColor Cyan
            Write-Host $currentPath -ForegroundColor White
        }
    }
    
    Write-Host ""
    Write-Host "Переменные окружения:" -ForegroundColor Yellow
    Write-Host "  %MYHOME% = $($profile.HomeProfile)" -ForegroundColor Gray
    Write-Host "  %USER_HOME_$Username% = $($profile.HomeProfile)" -ForegroundColor Gray
}

function Create-DualProfile {
    param($Username)
    
    if (-not $Username) {
        Write-Error "Не указано имя пользователя!"
        return
    }
    
    Write-Host "Создание двойного профиля для существующего пользователя $Username..." -ForegroundColor Yellow
    
    # Проверка существования пользователя
    $user = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if (-not $user) {
        Write-Error "Пользователь $Username не найден!"
        return
    }
    
    $UserSID = $user.SID.Value
    $SystemPath = "C:\Users\$Username"
    $HomePath = "D:\Home\$Username"
    
    # Создание домашней папки
    if (!(Test-Path "D:\Home")) {
        New-Item -ItemType Directory -Path "D:\Home" -Force | Out-Null
    }
    
    if (!(Test-Path $HomePath)) {
        New-Item -ItemType Directory -Path $HomePath -Force | Out-Null
        Write-Host "✓ Создана домашняя папка: $HomePath" -ForegroundColor Green
    }
    
    # Создание структуры папок
    $folders = @("Documents", "Desktop", "Downloads", "Pictures", "Music", "Videos", "Projects", "Work")
    foreach ($folder in $folders) {
        $folderPath = Join-Path $HomePath $folder
        if (!(Test-Path $folderPath)) {
            New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
        }
    }
    
    # Настройка прав доступа
    $Acl = Get-Acl $HomePath
    $Acl.SetAccessRuleProtection($true, $false)
    
    $UserRule = New-Object System.Security.AccessControl.FileSystemAccessRule($Username, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $AdminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $SystemRule = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    
    $Acl.SetAccessRule($UserRule)
    $Acl.SetAccessRule($AdminRule)
    $Acl.SetAccessRule($SystemRule)
    $Acl.SetOwner([System.Security.Principal.NTAccount]$Username)
    
    Set-Acl -Path $HomePath -AclObject $Acl
    
    # Создание записей в реестре
    $UserProfilesKey = "HKLM:\SOFTWARE\UserProfiles"
    if (!(Test-Path $UserProfilesKey)) {
        New-Item -Path $UserProfilesKey -Force | Out-Null
    }
    
    $UserKey = "$UserProfilesKey\$Username"
    if (!(Test-Path $UserKey)) {
        New-Item -Path $UserKey -Force | Out-Null
    }
    
    Set-ItemProperty -Path $UserKey -Name "SystemProfile" -Value $SystemPath -Type String
    Set-ItemProperty -Path $UserKey -Name "HomeProfile" -Value $HomePath -Type String
    Set-ItemProperty -Path $UserKey -Name "UserSID" -Value $UserSID -Type String
    Set-ItemProperty -Path $UserKey -Name "Created" -Value (Get-Date).ToString() -Type String
    Set-ItemProperty -Path $UserKey -Name "ActiveProfile" -Value "System" -Type String
    
    Write-Host "✓ Двойной профиль создан для пользователя $Username" -ForegroundColor Green
    Write-Host "  Системный: $SystemPath" -ForegroundColor Gray
    Write-Host "  Домашний:  $HomePath" -ForegroundColor Gray
}

function Remove-DualProfile {
    param($Username)
    
    if (-not $Username) {
        Write-Error "Не указано имя пользователя!"
        return
    }
    
    $UserKey = "HKLM:\SOFTWARE\UserProfiles\$Username"
    
    if (!(Test-Path $UserKey)) {
        Write-Host "Двойной профиль для пользователя $Username не найден." -ForegroundColor Yellow
        return
    }
    
    $confirm = Read-Host "Удалить двойной профиль для пользователя $Username? (y/N)"
    
    if ($confirm -eq 'y' -or $confirm -eq 'Y') {
        # Получение информации о профиле
        $profile = Get-ItemProperty -Path $UserKey
        $HomePath = $profile.HomeProfile
        
        # Переключение обратно на системный профиль
        Write-Host "Переключение на системный профиль..." -ForegroundColor Yellow
        Switch-UserProfile -Username $Username -ProfileType "System"
        
        # Удаление записи из реестра
        Remove-Item -Path $UserKey -Recurse -Force
        Write-Host "✓ Запись реестра удалена." -ForegroundColor Green
        
        # Опционально удалить домашнюю папку
        if (Test-Path $HomePath) {
            $deleteFolder = Read-Host "Удалить домашнюю папку $HomePath? (y/N)"
            if ($deleteFolder -eq 'y' -or $deleteFolder -eq 'Y') {
                Remove-Item -Path $HomePath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "✓ Домашняя папка удалена." -ForegroundColor Green
            }
        }
        
        Write-Host "✓ Двойной профиль для пользователя $Username удален." -ForegroundColor Green
    } else {
        Write-Host "Операция отменена." -ForegroundColor Yellow
    }
}

function Show-Help {
    Write-Host "Использование:" -ForegroundColor Yellow
    Write-Host "  .\ProfileManager.ps1 -Action List                              # Показать все двойные профили" -ForegroundColor Gray
    Write-Host "  .\ProfileManager.ps1 -Action Info -Username UserName           # Информация о профиле" -ForegroundColor Gray
    Write-Host "  .\ProfileManager.ps1 -Action Create -Username UserName         # Создать двойной профиль" -ForegroundColor Gray
    Write-Host "  .\ProfileManager.ps1 -Action Switch -Username UserName -ProfileType System  # Переключить на C:\" -ForegroundColor Gray
    Write-Host "  .\ProfileManager.ps1 -Action Switch -Username UserName -ProfileType Home    # Переключить на D:\" -ForegroundColor Gray
    Write-Host "  .\ProfileManager.ps1 -Action Remove -Username UserName         # Удалить двойной профиль" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Параметры:" -ForegroundColor Yellow
    Write-Host "  -Action: List, Info, Create, Switch, Remove" -ForegroundColor Gray
    Write-Host "  -Username: Имя пользователя" -ForegroundColor Gray
    Write-Host "  -ProfileType: System (C:\Users) или Home (D:\Home)" -ForegroundColor Gray
}

# Основная логика
Show-Header

switch ($Action) {
    "List" {
        Show-UserProfiles
    }
    "Info" {
        Show-UserInfo -Username $Username
    }
    "Create" {
        Create-DualProfile -Username $Username
    }
    "Switch" {
        Switch-UserProfile -Username $Username -ProfileType $ProfileType
    }
    "Remove" {
        Remove-DualProfile -Username $Username
    }
    default {
        Show-Help
    }
}

Write-Host ""
Write-Host "Для получения справки: .\ProfileManager.ps1" -ForegroundColor DarkGray

# Примеры использования:
# .\ProfileManager.ps1 -Action List
# .\ProfileManager.ps1 -Action Create -Username "TestUser"
# .\ProfileManager.ps1 -Action Switch -Username "TestUser" -ProfileType Home
# .\ProfileManager.ps1 -Action Info -Username "TestUser"
