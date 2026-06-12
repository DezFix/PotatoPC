# NAME: Отключение фоновых приложений
# DESC: Отключает работу приложений в фоновом режиме для экономии ресурсов
# TAGS: 2
# ICON: 🚫

# Отключение фоновых приложений
$bgAppsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
if (!(Test-Path $bgAppsPath)) { New-Item -Path $bgAppsPath -Force | Out-Null }
Set-ItemProperty -Path $bgAppsPath -Name "GlobalUserDisabled" -Value 1 -Type DWord -Force

# Отключение фонового поиска
$searchPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"
if (!(Test-Path $searchPath)) { New-Item -Path $searchPath -Force | Out-Null }
Set-ItemProperty -Path $searchPath -Name "BackgroundAppGlobalToggle" -Value 0 -Type DWord -Force

Write-Host "Фоновые приложения отключены"
