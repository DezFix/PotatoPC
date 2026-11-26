# NAME: Откат: Задержка меню
# DESC: Возвращает заводскую задержку раскрытия меню (400 мс)
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    Set-ItemProperty -LiteralPath "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "400" -Type String -Force
    Write-Output "[OK] Задержка меню 400 мс. Применится после перезахода."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
