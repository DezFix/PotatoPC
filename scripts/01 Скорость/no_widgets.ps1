# NAME: Без виджетов
# DESC: Убирает ленту новостей. Меньше памяти в фоне
# TAGS: 1,win11
# ICON: 📰
# PRESET: potato, office, game
# RECOMMENDED: true

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
