# NAME: Без задержки автозагрузки после входа
# DESC: StartupDelayInMSec=0 и WaitForIdleState=0: программы автозагрузки стартуют сразу, а не через ~10 секунд. Заметно на слабых ПК
# TAGS: 1
# ICON: ⏱️
# PRESET: potato,office,game
# CHECK: Test-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0

$ErrorActionPreference = "Stop"
try {
    $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -LiteralPath $p -Name "StartupDelayInMSec" -Value 0 -Type DWord -Force
    Set-ItemProperty -LiteralPath $p -Name "WaitForIdleState" -Value 0 -Type DWord -Force
    $a = [int](Get-ItemProperty -LiteralPath $p -Name "StartupDelayInMSec" -ErrorAction Stop).StartupDelayInMSec
    $b = [int](Get-ItemProperty -LiteralPath $p -Name "WaitForIdleState" -ErrorAction Stop).WaitForIdleState
    if ($a -ne 0 -or $b -ne 0) { throw "значения не записались (StartupDelayInMSec=$a, WaitForIdleState=$b)" }
    Write-Output "[OK] Задержка автозагрузки убрана. Применится при следующем входе."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
