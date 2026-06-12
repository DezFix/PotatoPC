# NAME: Оптимизация задержки клавиатуры
# DESC: Устанавливает минимальную задержку и максимальную скорость повторного нажатия клавиш
# TAGS: 1
# ICON: ⌨️
# RECOMMENDED: true


$keyboardPath = "HKCU:\Control Panel\Keyboard"

Set-ItemProperty -Path $keyboardPath -Name "KeyboardDelay" -Value "0" -Type String -Force
Set-ItemProperty -Path $keyboardPath -Name "KeyboardSpeed" -Value "31" -Type String -Force

Write-Host "Задержка клавиатуры оптимизирована (задержка: 0, скорость: 31)"
