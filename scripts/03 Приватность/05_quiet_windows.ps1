# NAME: 05 · Диагностические данные на минимум
# DESC: Ставит минимальный поддерживаемый уровень AllowTelemetry и отключает 5 задач сбора данных в Планировщике (CEIP, Appraiser и др.)
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
    } catch { throw ("Не удалось определить редакцию Windows; AllowTelemetry не изменён: " + $_.Exception.Message) }
    foreach ($p in @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection","HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection")) {
        if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        Set-ItemProperty -Path $p -Name "AllowTelemetry" -Value $telemetryValue -Type DWord -Force
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "DoNotShowFeedbackNotifications" -Value 1 -Type DWord -Force

    $tasks = @(
        @{ TaskName = "Microsoft Compatibility Appraiser"; TaskPath = "\Microsoft\Windows\Application Experience\" },
        @{ TaskName = "ProgramDataUpdater"; TaskPath = "\Microsoft\Windows\Application Experience\" },
        @{ TaskName = "Consolidator"; TaskPath = "\Microsoft\Windows\Customer Experience Improvement Program\" },
        @{ TaskName = "UsbCeip"; TaskPath = "\Microsoft\Windows\Customer Experience Improvement Program\" },
        @{ TaskName = "DmClient"; TaskPath = "\Microsoft\Windows\Feedback\Siuf\" }
    )
    foreach ($t in $tasks) {
        Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Output ("[OK] Диагностические данные переведены на минимальный уровень (AllowTelemetry=" + $telemetryValue + ").")
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
