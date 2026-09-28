# NAME: 04 · Приоритет активного окна (процессор)
# DESC: Укорачивает квант активного окна (Win32PrioritySeparation=24). Нужна перезагрузка
# TAGS: 1
# ICON: ⚡
# PRESET: potato, office, game

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $p = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    # 0x18 = короткий квант для активного окна. Значение 38 (0x26) - это заводская
    # настройка Windows, скрипт с ней не делал ничего, но обещал разницу.
    Set-ItemProperty -Path $p -Name "Win32PrioritySeparation" -Value 0x18 -Type DWord -Force
    $check = [int](Get-ItemProperty -LiteralPath $p -Name "Win32PrioritySeparation" -ErrorAction Stop).Win32PrioritySeparation
    if ($check -ne 0x18) { throw "значение не записалось (стало $check)" }
    Write-Output "[OK] Активное окно получило приоритет. Нужно перезагрузиться."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
