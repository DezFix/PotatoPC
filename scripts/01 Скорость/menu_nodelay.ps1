# NAME: Меню без задержки (400→0 мс)
# DESC: Ставит MenuShowDelay=0 в реестре: Пуск и контекстные меню открываются мгновенно
# TAGS: 1
# ICON: 🖱️
# PRESET: potato, office

$ErrorActionPreference = "Stop"
try {
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "0" -Type String -Force
    Write-Output "[OK] Задержка меню убрана."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
