# NAME: Меню без задержки (мгновенное открытие)
# DESC: MenuShowDelay=0: контекстные меню и подсказки открываются сразу, без заводских 400 мс. Заметно на слабых ПК
# TAGS: 1
# ICON: 🖱️
# PRESET: potato,office,game

$ErrorActionPreference = "Stop"
try {
    $p = "HKCU:\Control Panel\Desktop"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -LiteralPath $p -Name "MenuShowDelay" -Value "0" -Type String -Force
    $v = [string](Get-ItemProperty -LiteralPath $p -Name "MenuShowDelay" -ErrorAction Stop).MenuShowDelay
    if ($v -ne "0") { throw "MenuShowDelay не записался (стало $v)" }
    Write-Output "[OK] Задержка меню убрана. Применится после перезахода."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
