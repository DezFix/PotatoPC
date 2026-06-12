# NAME: Приоритет процессов
# DESC: Устанавливает высокий приоритет для активных окон и короткое переменное переключение
# CATEGORY: Производительность
# ICON: ⚡
# RECOMMENDED: true

$regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
$win32Priority = 38  # Short, Variable, High foreground boost

if (!(Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
Set-ItemProperty -Path $regPath -Name "Win32PrioritySeparation" -Value $win32Priority -Type DWord -Force
Write-Host "Приоритет активных окон установлен в высокий (значение: $win32Priority)"