# NAME: 12 · Убрать Виджеты и ленту новостей с панели
# DESC: Выключает TaskbarDa + политику AllowNewsAndInterests. Меньше памяти в фоне, работает на Win10 и 11
# TAGS: 1
# ICON: 📰
# PRESET: potato, office, game

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    # Тег win11 был лишним: обе величины (TaskbarDa, AllowNewsAndInterests)
    # работают на Windows 10, а тег прятал скрипт во всех трёх пресетах на Win10.
    $a = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    if (-not (Test-Path -LiteralPath $a)) { New-Item -Path $a -Force | Out-Null }
    Set-ItemProperty -LiteralPath $a -Name "TaskbarDa" -Value 0 -Type DWord -Force
    $d = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
    if (-not (Test-Path -LiteralPath $d)) { New-Item -Path $d -Force | Out-Null }
    Set-ItemProperty -LiteralPath $d -Name "AllowNewsAndInterests" -Value 0 -Type DWord -Force
    Write-Output "[OK] Виджеты убраны с панели."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
