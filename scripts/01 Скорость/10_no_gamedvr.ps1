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
    if ([int](Get-ItemProperty -Path $g -Name "AppCaptureEnabled" -ErrorAction Stop).AppCaptureEnabled -ne 0) { throw "AppCaptureEnabled не отключён" }
    $c = "HKCU:\System\GameConfigStore"
    if (-not (Test-Path $c)) { New-Item -Path $c -Force | Out-Null }
    Set-ItemProperty -Path $c -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force
    if ([int](Get-ItemProperty -Path $c -Name "GameDVR_Enabled" -ErrorAction Stop).GameDVR_Enabled -ne 0) { throw "GameDVR_Enabled не отключён" }
    $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -Path $p -Name "AllowGameDVR" -Value 0 -Type DWord -Force
    if ([int](Get-ItemProperty -Path $p -Name "AllowGameDVR" -ErrorAction Stop).AllowGameDVR -ne 0) { throw "AllowGameDVR не отключён" }
    Write-Output "[OK] Фоновая запись выключена."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
