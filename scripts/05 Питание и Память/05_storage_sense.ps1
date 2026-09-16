# NAME: 05 05 · Контроль памяти: авточистка диска Windows
# DESC: Включает Storage Sense (StoragePolicy 01=1): Windows сама чистит Temp и Корзину ~раз в месяц
# TAGS: 1
# ICON: 🧽
# PRESET: potato, office

$ErrorActionPreference = "Stop"
try {
    $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -Path $p -Name "01" -Value 1 -Type DWord -Force
    Write-Output "[OK] Контроль памяти включен."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
