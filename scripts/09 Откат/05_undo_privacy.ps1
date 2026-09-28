# NAME: 05 · Откат «Приватности»: базовый уровень диагностических данных и службы
# DESC: Возвращает базовый уровень AllowTelemetry=1, службы DiagTrack/DcpSvc/WerSvc на их заводские режимы, журналы WMI и задачи планировщика. Откат раздела «Приватность»
# TAGS: 1
# ICON: ↩️

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    Write-Output "[*] Возвращаю базовый уровень диагностических данных..."
    $telemetryValue = 1
    try {
        $edition = [string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -ErrorAction Stop).EditionID
        if ([string]::IsNullOrWhiteSpace($edition)) { throw 'EditionID пуст' }
        $telemetryValue = if ($edition -match '(?i)(Enterprise|Education|Server|IoT)') { 0 } else { 1 }
    } catch { Write-Output ("[!] Не удалось определить редакцию (" + $_.Exception.Message + "); ставлю AllowTelemetry=1") }
    # Ключ создаём только если скрипт 05_quiet_windows.ps1 его создавал - не
    # оставляем после отката пустые ветки политик там, где их не было.
    $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    if (Test-Path -LiteralPath $p) {
        Set-ItemProperty -LiteralPath $p -Name "AllowTelemetry" -Value $telemetryValue -Type DWord -Force -ErrorAction Stop
        Del-Prop $p "DoNotShowFeedbackNotifications"
    }
    $wer = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting"
    if (Test-Path -LiteralPath $wer) { Set-ItemProperty -LiteralPath $wer -Name "Disabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue }

    Write-Output "[*] Возвращаю службы на их заводские режимы..."
    # Заводские значения: DiagTrack - Manual, dmwappushservice - Disabled,
    # DusmSvc - Manual, DcpSvc и DiagnosticsHub - Automatic (Delayed Start).
    # Раньше DcpSvc/DiagnosticsHub ставились в Manual, то есть после отката
    # «Передача рядом» и сборщик диагностики не возвращались, а DiagTrack
    # наоборот стартовал каждый раз, хотя раньше не стартовал.
    $restore = @(
        @{ Name = 'DiagTrack'; Mode = 'Manual' },
        @{ Name = 'dmwappushservice'; Mode = 'Disabled' },
        @{ Name = 'DusmSvc'; Mode = 'Manual' },
        @{ Name = 'DcpSvc'; Mode = 'Automatic' },
        @{ Name = 'diagnosticshub.standardcollector.service'; Mode = 'Automatic' },
        @{ Name = 'WerSvc'; Mode = 'Manual' }
    )
    foreach ($s in $restore) {
        if (-not (Get-Service -Name $s.Name -ErrorAction SilentlyContinue)) { continue }
        try { Set-Service -Name $s.Name -StartupType $s.Mode -ErrorAction Stop; Write-Output ("[*] " + $s.Name + " -> " + $s.Mode) }
        catch { Write-Output ("[!] " + $s.Name + ": " + $_.Exception.Message) }
    }
    try { Start-Service -Name "DiagTrack" -ErrorAction SilentlyContinue } catch {}

    Write-Output "[*] Возвращаю историю, геолокацию и журналы..."
    foreach ($n in @("PublishUserActivities","EnableActivityFeed","UploadUserActivities")) {
        Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" $n
    }
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" "DisableLocation"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" "DisableSensors"
    foreach ($l in @("AppModel","DiagLog","Diagtrack-Listener","LwtNetLog","SQMLogger","WdiContextLog","WiFiSession")) {
        $k = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$l"
        if (-not (Test-Path -LiteralPath $k)) { continue }
        try { Set-ItemProperty -LiteralPath $k -Name "Start" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue } catch {}
    }

    # Блок «советы и контент» убран: ContentDeliveryManager относится к
    # 01 Скорость/09_no_ads.ps1, и его откат здесь молча отменял «без рекламы».
    # За него отвечает 07_undo_speed.ps1.

    Write-Output "[*] Включаю задачи планировщика..."
    $tasks = @(
        @{ TaskName = "Microsoft Compatibility Appraiser"; TaskPath = "\Microsoft\Windows\Application Experience\" },
        @{ TaskName = "ProgramDataUpdater"; TaskPath = "\Microsoft\Windows\Application Experience\" },
        @{ TaskName = "Consolidator"; TaskPath = "\Microsoft\Windows\Customer Experience Improvement Program\" },
        @{ TaskName = "UsbCeip"; TaskPath = "\Microsoft\Windows\Customer Experience Improvement Program\" },
        @{ TaskName = "DmClient"; TaskPath = "\Microsoft\Windows\Feedback\Siuf\" },
        @{ TaskName = "QueueReporting"; TaskPath = "\Microsoft\Windows\Windows Error Reporting\" }
    )
    $on = 0
    foreach ($t in $tasks) {
        $task = $null
        try { $task = Get-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop } catch { $task = $null }
        if ($null -eq $task) { continue }
        if ($task.State -eq 'Disabled') {
            try { Enable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop | Out-Null; $on++ } catch { Write-Output ("[!] " + $t.TaskName + ": " + $_.Exception.Message) }
        } else { $on++ }
    }
    Write-Output ("[OK] Уровень AllowTelemetry=" + $telemetryValue + ", службы и задачи (" + $on + ") восстановлены.")
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
