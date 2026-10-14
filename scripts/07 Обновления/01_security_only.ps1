# NAME: 01 · Обновления Windows: только безопасность, без новых версий
# DESC: Фиксирует текущую сборку (TargetReleaseVersion) + откладывает «фичи» на 365 дней, без драйверов из центра обновлений. Патчи безопасности ставятся
# TAGS: 2
# ICON: 🛡️
# PRESET: potato, office

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $cv = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop
    $build = [string]$cv.CurrentBuildNumber
    $cur   = [string]$cv.DisplayVersion
    # TargetReleaseVersionInfo MS документирует как маркетинговую версию
    # ("23H2"/"24H2") или голый номер сборки ("19041"). Строка "26100.4652"
    # (сборка.UBR) недокументирована: если цель не резолвится, Windows Update
    # перестаёт обновляться вообще - ровно то, что скрипт обещает не допустить.
    $target = if ($cur) { $cur } else { $build }
    Write-Output ("[*] Фиксирую версию: " + $(if ($cur) { $cur } else { '(без DisplayVersion) -> сборка ' + $build }) + " (сборка " + $build + ")")

    $w = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    if (-not (Test-Path $w)) { New-Item -Path $w -Force | Out-Null }
    Set-ItemProperty -LiteralPath $w -Name "TargetReleaseVersion" -Value 1 -Type DWord -Force
    Set-ItemProperty -LiteralPath $w -Name "TargetReleaseVersionInfo" -Value $target -Type String -Force
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

    # Контрольная проверка: значение записалось и wuauserv реально работает.
    $check = Get-ItemProperty -LiteralPath $w -Name "TargetReleaseVersionInfo" -ErrorAction Stop
    if ([string]$check.TargetReleaseVersionInfo -ne [string]$target) {
        throw ("Политика записалась неверно: ожидалось '$target', получено '" + $check.TargetReleaseVersionInfo + "'")
    }
    if ((Get-Service -Name "wuauserv" -ErrorAction Stop).Status -ne 'Running') {
        throw "wuauserv не работает после применения политики - откатываю"
    }
    Write-Output "[OK] Только безопасность: новая версия '$target' зафиксирована, драйверы не ставятся, служба обновлений работает."
    Write-Output "[i] Проверка обновлений: Параметры -> Центр обновления Windows -> Проверить наличие обновлений."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
