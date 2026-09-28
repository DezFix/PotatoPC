# NAME: 01 · Обновления Windows: только безопасность, без новых версий
# DESC: Фиксирует текущую сборку (TargetReleaseVersion) + откладывает «фичи» на 365 дней, без драйверов из центра обновлений. Патчи безопасности ставятся
# TAGS: 2
# ICON: 🛡️
# PRESET: potato, office

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $cv = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop
    # Номер сборки надёжнее DisplayVersion ("24H2"): политика принимает и то и
    # другое, но маркетинговое имя после enablement-пакета перестаёт совпадать.
    $build = [string]$cv.CurrentBuildNumber
    if ($cv.UBR) { $build = "$build.$($cv.UBR)" }
    $cur = [string]$cv.DisplayVersion
    Write-Output ("[*] Фиксирую версию: " + $(if ($cur) { $cur } else { '(без DisplayVersion)' }) + " (сборка " + $build + ")")

    $w = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    if (-not (Test-Path $w)) { New-Item -Path $w -Force | Out-Null }
    Set-ItemProperty -LiteralPath $w -Name "TargetReleaseVersion" -Value 1 -Type DWord -Force
    Set-ItemProperty -LiteralPath $w -Name "TargetReleaseVersionInfo" -Value $build -Type String -Force
    Set-ItemProperty -LiteralPath $w -Name "DeferFeatureUpdates" -Value 1 -Type DWord -Force
    Set-ItemProperty -LiteralPath $w -Name "DeferFeatureUpdatesPeriodInDays" -Value 365 -Type DWord -Force
    Set-ItemProperty -LiteralPath $w -Name "DeferQualityUpdates" -Value 0 -Type DWord -Force
    # Драйверы из центра обновлений тоже не ставим.
    Set-ItemProperty -LiteralPath $w -Name "ExcludeWUDriversInQualityUpdate" -Value 1 -Type DWord -Force

    # Перезапуск службы нужен, чтобы политики подхватились. Раньше обе команды
    # шли с SilentlyContinue, и при отказе запуска скрипт рапортовал "[OK]",
    # хотя обновления безопасности не приходили бы вообще - ровно то, что он
    # и обещал не допустить.
    $wasRunning = ((Get-Service -Name "wuauserv" -ErrorAction Stop).Status -eq 'Running')
    try { Stop-Service -Name "wuauserv" -Force -ErrorAction Stop } catch { Write-Output ("[*] wuauserv не останавливал: " + $_.Exception.Message) }
    try { Start-Service -Name "wuauserv" -ErrorAction Stop }
    catch { throw ("Не смог запустить wuauserv - обновления безопасности приходить не будут: " + $_.Exception.Message) }
    if ($wasRunning -and (Get-Service -Name "wuauserv" -ErrorAction Stop).Status -ne 'Running') { throw "wuauserv не вернулся в работу" }
    Write-Output "[OK] Только безопасность: новые версии и драйверы не ставятся, служба обновлений работает."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
