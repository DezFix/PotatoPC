# NAME: 02 · Выкл. отчёты об ошибках в Microsoft (WER)
# DESC: Ставит WER Disabled=1 + служба WerSvc в Disabled. Отчёты о падениях больше не отправляются
# TAGS: 1
# ICON: 🔕
# PRESET: potato, office, game

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
    Disable-ScheduledTask -TaskName "QueueReporting" -TaskPath "\Microsoft\Windows\Windows Error Reporting\" -ErrorAction SilentlyContinue | Out-Null
    Write-Output "[OK] Отчеты выключены."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
