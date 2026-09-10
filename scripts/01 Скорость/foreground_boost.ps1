# NAME: Активное окно быстрее
# DESC: Больше процессора текущей программе, меньше фону
# TAGS: 1
# ICON: ⚡
# PRESET: potato, office, game
# RECOMMENDED: true

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $p = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    # 38 = короткий квант + высокий буст активному окну
    Set-ItemProperty -Path $p -Name "Win32PrioritySeparation" -Value 38 -Type DWord -Force
    Write-Output "[OK] Активное окно получило приоритет. Нужно перезагрузиться."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
