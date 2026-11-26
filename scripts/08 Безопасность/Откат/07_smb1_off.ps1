# NAME: Откат: Включить SMBv1
# DESC: Возвращает устаревший протокол SMBv1 - нужен только для очень старых NAS и принтеров. Небезопасно
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    $r = Enable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -All -NoRestart -ErrorAction Stop
    if ($r.RestartNeeded) { Write-Output "[*] Нужна перезагрузка." }
    Write-Output "[OK] SMBv1 включён."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
