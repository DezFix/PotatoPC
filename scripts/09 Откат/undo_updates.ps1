# NAME: Вернуть обновления
# DESC: Убирает блок больших обновлений. Winget останется
# TAGS: 1
# ICON: ↩️

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $w = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    foreach ($n in @("TargetReleaseVersion","TargetReleaseVersionInfo","DeferFeatureUpdates","DeferFeatureUpdatesPeriodInDays","DeferQualityUpdates","ExcludeWUDriversInQualityUpdate")) {
        try { Remove-ItemProperty -Path $w -Name $n -Force -ErrorAction Stop } catch {}
    }
    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    Start-Service wuauserv -ErrorAction SilentlyContinue
    Write-Output "[OK] Обновления как были. Winget удаляется через Программы."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
