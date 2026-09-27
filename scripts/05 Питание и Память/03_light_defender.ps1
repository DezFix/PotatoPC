# NAME: 03 · Проверить Defender (без изменений)
# DESC: Только читает состояние Microsoft Defender. Настройки Defender не изменяются.
# TAGS: 3
# ICON: 🛡️

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $status = Get-MpComputerStatus -ErrorAction Stop
    $mode = [string]$status.AMRunningMode
    $age = [int]$status.AntivirusSignatureAge
    $realtime = [bool]$status.RealTimeProtectionEnabled
    Write-Output ("[*] Defender: " + $mode + ", защита в реальном времени: " + $realtime + ", подпись: " + $age + " дн.")
    Write-Output "[OK] Настройки Defender не изменялись."
    exit 0
} catch {
    Write-Output ("[X] Не удалось прочитать состояние Defender: " + $_)
    exit 1
}
