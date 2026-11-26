# NAME: Откат: Вход с экраном-заставкой
# DESC: Снимает политику NoLockScreen - экран блокировки снова показывается перед входом
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" "NoLockScreen"
    Write-Output "[OK] Экран блокировки вернётся при следующем входе."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
