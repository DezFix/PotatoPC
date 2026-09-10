# NAME: Только защита
# DESC: Без больших обновлений. Экономит место и время
# TAGS: 2
# ICON: 🛡️
# PRESET: potato, office
# RECOMMENDED: true

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $cur = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").DisplayVersion
    if ([string]::IsNullOrWhiteSpace($cur)) { $cur = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ReleaseId }
    Write-Output ("[*] Фиксирую версию: " + $cur)

    $w = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    if (-not (Test-Path $w)) { New-Item -Path $w -Force | Out-Null }
    Set-ItemProperty -Path $w -Name "TargetReleaseVersion" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $w -Name "TargetReleaseVersionInfo" -Value $cur -Type String -Force
    Set-ItemProperty -Path $w -Name "DeferFeatureUpdates" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $w -Name "DeferFeatureUpdatesPeriodInDays" -Value 365 -Type DWord -Force
    Set-ItemProperty -Path $w -Name "DeferQualityUpdates" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $w -Name "ExcludeWUDriversInQualityUpdate" -Value 1 -Type DWord -Force

    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    Start-Service wuauserv -ErrorAction SilentlyContinue
    Write-Output "[OK] Только защита. Большие версии ставиться не будут."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
