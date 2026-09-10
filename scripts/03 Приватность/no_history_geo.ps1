# NAME: Без истории и мест
# DESC: Не пишет историю действий и не следит где ты
# TAGS: 1
# ICON: 📍
# PRESET: potato, office
# RECOMMENDED: true

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $s = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    if (-not (Test-Path $s)) { New-Item -Path $s -Force | Out-Null }
    foreach ($n in @("PublishUserActivities","EnableActivityFeed","UploadUserActivities")) {
        Set-ItemProperty -Path $s -Name $n -Value 0 -Type DWord -Force
    }
    $l = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"
    if (-not (Test-Path $l)) { New-Item -Path $l -Force | Out-Null }
    Set-ItemProperty -Path $l -Name "DisableLocation" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $l -Name "DisableSensors" -Value 1 -Type DWord -Force

    Disable-ScheduledTask -TaskName "\Microsoft\Windows\Maps\MapsUpdateTask" -ErrorAction SilentlyContinue | Out-Null
    Write-Output "[OK] История и геолокация выключены."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
