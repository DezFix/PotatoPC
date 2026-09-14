# NAME: Убрать Виджеты и ленту новостей с панели
# DESC: Выключает TaskbarDa + политику AllowNewsAndInterests. Меньше памяти в фоне, работает на Win10 и 11
# TAGS: 1
# ICON: 📰
# PRESET: potato, office, game
# RECOMMENDED: true

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $a = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-ItemProperty -Path $a -Name "TaskbarDa" -Value 0 -Type DWord -Force
    $d = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
    if (-not (Test-Path $d)) { New-Item -Path $d -Force | Out-Null }
    Set-ItemProperty -Path $d -Name "AllowNewsAndInterests" -Value 0 -Type DWord -Force
    Write-Output "[OK] Виджеты убраны с панели."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
