# NAME: 05 02 · Включить гибернацию (сон с сохранением окон)
# DESC: Команды powercfg /hibernate on + пункт в меню выключения. Съест гигабайты на C: (hiberfil.sys). Противоположность кнопки выше
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
