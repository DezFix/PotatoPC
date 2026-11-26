# NAME: Откат: Фоновая запись игр (Game DVR)
# DESC: Снимает политику AllowGameDVR и включает запись игр обратно
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    $g = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"
    if (-not (Test-Path -LiteralPath $g)) { New-Item -Path $g -Force | Out-Null }
    Set-ItemProperty -LiteralPath $g -Name "AppCaptureEnabled" -Value 1 -Type DWord -Force
    $c = "HKCU:\System\GameConfigStore"
    if (-not (Test-Path -LiteralPath $c)) { New-Item -Path $c -Force | Out-Null }
    Set-ItemProperty -LiteralPath $c -Name "GameDVR_Enabled" -Value 1 -Type DWord -Force
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR"
    Write-Output "[OK] Запись игр снова доступна."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
