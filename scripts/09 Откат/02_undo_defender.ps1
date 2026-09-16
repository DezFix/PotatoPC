# NAME: 02 · Откат Defender: вернуть защиту на максимум
# DESC: Возвращает Set-MpPreference к заводским: CPU 50%, скан архивов/сети вкл., облако Advanced. Откат кнопки «Облегчить Defender»
# TAGS: 1
# ICON: 🛡️

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    Set-MpPreference -ScanAvgCPULoadFactor 50 -ErrorAction Stop
    Set-MpPreference -DisableArchiveScanning $false -ErrorAction Stop
    Set-MpPreference -DisableScanningMappedNetworkDrivesForFullScan $false -ErrorAction Stop
    Set-MpPreference -MAPSReporting Advanced -ErrorAction Stop
    Set-MpPreference -SubmitSamplesConsent 2 -ErrorAction Stop
    Set-MpPreference -EnableLowCpuPriority $false -ErrorAction Stop
    Write-Output "[OK] Defender как из коробки."
    exit 0
} catch {
    Write-Output ("[X] Выключи 'Защиту от подделки' и повтори: " + $_)
    exit 1
}
