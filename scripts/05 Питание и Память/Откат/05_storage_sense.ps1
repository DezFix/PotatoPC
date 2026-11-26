# NAME: Откат: Выключить контроль памяти
# DESC: Убирает настройки авточистки, которые поставил твик
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
    foreach ($n in @("01","04","256")) { Del-Prop $p $n }
    Write-Output "[OK] Контроль памяти выключен."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
