# NAME: 02 · Включить гибернацию (сон с сохранением окон)
# DESC: Команды powercfg /hibernate on + пункт в меню выключения. Съест гигабайты на C: (hiberfil.sys). Противоположность кнопки выше
# TAGS: 2
# ICON: 💤

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $out = & powercfg /hibernate on 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw ("powercfg /hibernate on: код " + $code + "; " + (($out | Out-String).Trim())) }
    $out = & powercfg /h /type full 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw ("powercfg /h /type full: код " + $code + "; " + (($out | Out-String).Trim())) }
    $r = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings"
    if (-not (Test-Path $r)) { New-Item -Path $r -Force | Out-Null }
    New-ItemProperty -Path $r -Name "ShowHibernateOption" -Value 1 -PropertyType DWORD -Force | Out-Null
    Write-Output "[OK] Гибернация включена."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
