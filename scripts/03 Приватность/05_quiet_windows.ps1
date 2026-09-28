# NAME: 05 · Диагностические данные на минимум
# DESC: Ставит минимальный уровень AllowTelemetry, гасит подсказки отзывов и отключает 5 задач сбора данных в Планировщике (CEIP, Appraiser и др.)
# TAGS: 1
# ICON: 🕵️
# PRESET: potato, office, game

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $telemetryValue = 1
    try {
        $edition = [string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -ErrorAction Stop).EditionID
        if ($edition -match '(?i)(Enterprise|Education|Server|IoT)') { $telemetryValue = 0 }
    } catch {
        # Раньше здесь был throw - и до отключения пяти задач планировщика
        # управление не доходило вовсе, хотя они к редакции Windows отношения
        # не имеют. Теперь предупреждение и работа продолжается.
        Write-Output ("[!] Не удалось определить редакцию (" + $_.Exception.Message + "); ставлю AllowTelemetry=1")
    }
    # Только политика. Ветка ...\CurrentVersion\Policies\DataCollection - это
    # устаревшее зеркало, при наличии настоящей политики оно игнорируется, а
    # любой будущий аудит может по нему ошибочно судить о настройке.
    $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -LiteralPath $p -Name "AllowTelemetry" -Value $telemetryValue -Type DWord -Force
    if ([int](Get-ItemProperty -LiteralPath $p -Name "AllowTelemetry" -ErrorAction Stop).AllowTelemetry -ne $telemetryValue) {
        throw "AllowTelemetry не записался"
    }
    Set-ItemProperty -LiteralPath $p -Name "DoNotShowFeedbackNotifications" -Value 1 -Type DWord -Force

    $tasks = @(
        @{ TaskName = "Microsoft Compatibility Appraiser"; TaskPath = "\Microsoft\Windows\Application Experience\" },
        @{ TaskName = "ProgramDataUpdater"; TaskPath = "\Microsoft\Windows\Application Experience\" },
        @{ TaskName = "Consolidator"; TaskPath = "\Microsoft\Windows\Customer Experience Improvement Program\" },
        @{ TaskName = "UsbCeip"; TaskPath = "\Microsoft\Windows\Customer Experience Improvement Program\" },
        @{ TaskName = "DmClient"; TaskPath = "\Microsoft\Windows\Feedback\Siuf\" }
    )
    $off = 0
    foreach ($t in $tasks) {
        $task = $null
        try { $task = Get-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop } catch { $task = $null }
        if ($null -eq $task) { continue }
        if ($task.State -eq 'Disabled') { $off++; continue }
        try { Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop | Out-Null; $off++ }
        catch { Write-Output ("[!] Задача " + $t.TaskName + ": " + $_.Exception.Message) }
    }
    Write-Output ("[OK] Диагностические данные на минимуме (AllowTelemetry=" + $telemetryValue + "), задач сбора отключено: " + $off + " из " + $tasks.Count + ".")
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
