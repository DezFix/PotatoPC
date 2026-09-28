# NAME: 03 · Выкл. историю действий и геолокацию
# DESC: Ставит PublishUserActivities/UploadUserActivities/EnableActivityFeed=0 + DisableLocation/DisableSensors=1. Погода/Карты потеряют геопозицию
# TAGS: 1
# ICON: 📍
# PRESET: potato, office, game

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $s = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    if (-not (Test-Path $s)) { New-Item -Path $s -Force | Out-Null }
    foreach ($n in @("PublishUserActivities","EnableActivityFeed","UploadUserActivities")) {
        Set-ItemProperty -LiteralPath $s -Name $n -Value 0 -Type DWord -Force
    }
    $l = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"
    if (-not (Test-Path $l)) { New-Item -Path $l -Force | Out-Null }
    Set-ItemProperty -LiteralPath $l -Name "DisableLocation" -Value 1 -Type DWord -Force
    Set-ItemProperty -LiteralPath $l -Name "DisableSensors" -Value 1 -Type DWord -Force

    # Задачу загрузки карт (MapsUpdateTask) убрали: она не про историю и не про
    # геолокацию, а правило "1 скрипт = 1 задача" не предполагает молчаливых
    # побочных изменений. Задача появится в откате 05_undo_privacy при нужде.
    Write-Output "[OK] История действий и геолокация выключены."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
