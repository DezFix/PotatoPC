# NAME: 04 · Откат «Питания»: гибернация и подкачка как было
# DESC: Включает hibernate on + файл подкачки в Auto + выключает Storage Sense. Откат трёх кнопок раздела «Питание и Память»
# TAGS: 1
# ICON: ↩️

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    Write-Output "[*] Возвращаю гибернацию..."
    $out = & powercfg /hibernate on 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw ("powercfg /hibernate on: код " + $code + "; " + (($out | Out-String).Trim())) }

    Write-Output "[*] Файл подкачки - под управление системы..."
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true } -ErrorAction Stop
    $after = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    if (-not [bool]$after.AutomaticManagedPagefile) { throw "Автоматическое управление pagefile не восстановлено" }

    Write-Output "[*] Выключаю автоочистку..."
    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" -Name "01" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

    Write-Output "[OK] Готово. Антивирус возвращается отдельной кнопкой."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
