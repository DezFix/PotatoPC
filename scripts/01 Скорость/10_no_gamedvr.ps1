# NAME: 10 · Выкл. фоновую запись игр (Game DVR)
# DESC: Отключает GameDVR/AppCapture в реестре: +FPS, меньше лагов. Запись через Win+G перестанет работать
# TAGS: 1
# ICON: ⏺️
# PRESET: potato, office, game

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $g = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"
    if (-not (Test-Path $g)) { New-Item -Path $g -Force | Out-Null }
    Set-ItemProperty -Path $g -Name "AppCaptureEnabled" -Value 0 -Type DWord -Force
    $c = "HKCU:\System\GameConfigStore"
    Set-ItemProperty -Path $c -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force
    $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -Path $p -Name "AllowGameDVR" -Value 0 -Type DWord -Force
    Write-Output "[OK] Фоновая запись выключена."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
