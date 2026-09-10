# NAME: Быстрый вход
# DESC: Сразу ввод пароля, без лишней заставки. Пароль спросят
# TAGS: 1
# ICON: 🚪
# PRESET: potato, office

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -Path $p -Name "NoLockScreen" -Value 1 -Type DWord -Force
    Write-Output "[OK] Заставка убрана. Пароль по-прежнему спрашивается."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
