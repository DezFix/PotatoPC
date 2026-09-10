# NAME: Вернуть питание
# DESC: Гибернация и файл подкачки - как решала Windows
# TAGS: 1
# ICON: ↩️

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    Write-Output "[*] Возвращаю гибернацию..."
    powercfg /hibernate on | Out-Null

    Write-Output "[*] Файл подкачки - под управление системы..."
    $cs = Get-CimInstance Win32_ComputerSystem
    Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true } -ErrorAction Stop

    Write-Output "[*] Выключаю автоочистку..."
    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" -Name "01" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

    Write-Output "[OK] Готово. Антивирус возвращается отдельной кнопкой."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
