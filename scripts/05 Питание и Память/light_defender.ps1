# NAME: Легкий антивирус
# DESC: Меньше жрет процессор. Чуть слабее защита
# TAGS: 3
# ICON: 🛡️

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    Write-Output "[*] Облегчаю Defender..."
    Set-MpPreference -ScanAvgCPULoadFactor 20 -ErrorAction Stop
    Set-MpPreference -DisableArchiveScanning $true -ErrorAction Stop
    Set-MpPreference -DisableScanningMappedNetworkDrivesForFullScan $true -ErrorAction Stop
    Set-MpPreference -MAPSReporting Basic -ErrorAction Stop
    Set-MpPreference -SubmitSamplesConsent 1 -ErrorAction Stop
    Set-MpPreference -EnableLowCpuPriority $true -ErrorAction Stop
    Write-Output "[OK] Defender облегчен. Архивы больше не сканируются - учти риск."
    exit 0
} catch {
    Write-Output ("[X] Не вышло. Выключи 'Защиту от подделки' в Безопасности Windows и повтори: " + $_)
    exit 1
}
