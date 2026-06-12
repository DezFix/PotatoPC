# NAME: Отключение истории действий
# DESC: Отключает сбор и синхронизацию истории действий пользователя
# CATEGORY: Конфиденциальность
# ICON: 📜

$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
if (!(Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }

Set-ItemProperty -Path $regPath -Name "PublishUserActivities" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $regPath -Name "EnableActivityFeed" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $regPath -Name "PublishUserActivitiesOnUserConsent" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $regPath -Name "UploadUserActivities" -Value 0 -Type DWord -Force

Write-Host "Activity history disabled successfully"