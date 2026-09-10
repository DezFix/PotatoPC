# NAME: Без отчетов об ошибках
# DESC: Не шлет отчеты в Microsoft. Чуть меньше нагрузки
# TAGS: 1
# ICON: 🔕
# PRESET: potato, office
# RECOMMENDED: true

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $p = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -Path $p -Name "Disabled" -Value 1 -Type DWord -Force

    foreach ($s in @("WerSvc")) {
        Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
        Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
    }
    Disable-ScheduledTask -TaskName "\Microsoft\Windows\Windows Error Reporting\QueueReporting" -ErrorAction SilentlyContinue | Out-Null
    Write-Output "[OK] Отчеты выключены."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
