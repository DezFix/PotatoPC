# NAME: Откат: Задержка автозагрузки
# DESC: Возвращает заводскую паузу перед запуском программ из автозагрузки
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    Del-Prop "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" "StartupDelayInMSec"
    Del-Prop "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" "WaitForIdleState"
    Write-Output "[OK] Задержка автозагрузки возвращена."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
