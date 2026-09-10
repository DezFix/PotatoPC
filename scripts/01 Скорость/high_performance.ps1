# NAME: Полная мощность
# DESC: ПК не тормозит ради экономии. На ноутбуке съест батарею
# TAGS: 1
# ICON: 🔌
# PRESET: potato, game
# RECOMMENDED: true

$ErrorActionPreference = "Stop"
try {
    $guid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
    $out = powercfg /setactive $guid 2>&1
    if ($LASTEXITCODE -ne 0) {
        # Запасной вариант: своя схема от текущей
        powercfg -duplicatescheme $guid 2>$null | Out-Null
        powercfg /setactive $guid 2>&1 | Out-Null
    }
    Write-Output "[OK] План 'Высокая производительность' включен."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
