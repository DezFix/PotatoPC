# NAME: Откат: Автозапуск с носителей
# DESC: Снимает запрет автозапуска - Windows снова спрашивает, что делать с флешкой или диском
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    foreach ($p in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer", "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer")) { Del-Prop $p "NoDriveTypeAutoRun" }
    Write-Output "[OK] Автозапуск возвращён. Перезагрузись."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
