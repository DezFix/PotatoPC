# NAME: Быстрый отклик клавиш
# DESC: Печатать приятнее. На скорость ПК не влияет
# TAGS: 1
# ICON: ⌨️
# PRESET: game

$ErrorActionPreference = "Stop"
try {
    $p = "HKCU:\Control Panel\Keyboard"
    Set-ItemProperty -Path $p -Name "KeyboardDelay" -Value "0" -Type String -Force
    Set-ItemProperty -Path $p -Name "KeyboardSpeed" -Value "31" -Type String -Force
    Write-Output "[OK] Клавиатура стала отзывчивее."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
