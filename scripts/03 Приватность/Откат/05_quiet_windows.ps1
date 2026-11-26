# NAME: Откат: Диагностические данные
# DESC: Снимает политику уровня диагностики (Windows вернётся к своему уровню) и включает задачи сбора
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    Del-Prop $p "AllowTelemetry"
    Del-Prop $p "DoNotShowFeedbackNotifications"
    $tasks = @(
        @{ TaskName = "Microsoft Compatibility Appraiser"; TaskPath = "\Microsoft\Windows\Application Experience\" },
        @{ TaskName = "ProgramDataUpdater"; TaskPath = "\Microsoft\Windows\Application Experience\" },
        @{ TaskName = "Consolidator"; TaskPath = "\Microsoft\Windows\Customer Experience Improvement Program\" },
        @{ TaskName = "UsbCeip"; TaskPath = "\Microsoft\Windows\Customer Experience Improvement Program\" },
        @{ TaskName = "DmClient"; TaskPath = "\Microsoft\Windows\Feedback\Siuf\" }
    )
    $on = 0
    foreach ($t in $tasks) {
        $task = $null
        try { $task = Get-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop } catch {}
        if (-not $task) { continue }
        try { if ($task.State -eq 'Disabled') { Enable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop | Out-Null }; $on++ }
        catch { Write-Output ("[!] " + $t.TaskName + ": " + $_.Exception.Message) }
    }
    Write-Output ("[*] Задач включено: " + $on)
    Write-Output "[OK] Диагностика возвращена к заводской."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
