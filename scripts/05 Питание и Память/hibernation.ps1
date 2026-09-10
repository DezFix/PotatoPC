# NAME: Гибернация
# DESC: Запоминает открытые окна. Съест место на диске
# TAGS: 2
# ICON: 💤

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    powercfg /hibernate on | Out-Null
    powercfg /h /type full | Out-Null
    $r = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings"
    if (-not (Test-Path $r)) { New-Item -Path $r -Force | Out-Null }
    New-ItemProperty -Path $r -Name "ShowHibernateOption" -Value 1 -PropertyType DWORD -Force | Out-Null
    Write-Output "[OK] Гибернация включена."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
