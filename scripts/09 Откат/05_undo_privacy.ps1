# NAME: 05 · Откат «Приватности»: базовый уровень диагностических данных и службы
# DESC: Возвращает базовый уровень AllowTelemetry=1, службы DiagTrack/WerSvc, журналы и задачи планировщика. Откат всего раздела «Приватность»
# TAGS: 1
# ICON: ↩️

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    Write-Output "[*] Возвращаю базовый уровень диагностических данных..."
    $telemetryValue = $null
    try {
        $edition = [string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -ErrorAction Stop).EditionID
        if ([string]::IsNullOrWhiteSpace($edition)) { throw 'EditionID пуст' }
        $telemetryValue = if ($edition -match '(?i)(Enterprise|Education|Server|IoT)') { 0 } else { 1 }
    } catch { throw ("Не удалось определить редакцию Windows; AllowTelemetry не изменён: " + $_.Exception.Message) }
    foreach ($p in @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection","HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection")) {
        if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        Set-ItemProperty -Path $p -Name "AllowTelemetry" -Value $telemetryValue -Type DWord -Force -ErrorAction Stop
    }
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "DoNotShowFeedbackNotifications"
    Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-Service DiagTrack -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service DiagTrack -ErrorAction SilentlyContinue
    foreach ($s in @("dmwappushservice","DcpSvc","diagnosticshub.standardcollector.service","DusmSvc")) {
        Set-Service $s -StartupType Manual -ErrorAction SilentlyContinue
    }
    Set-Service WerSvc -StartupType Manual -ErrorAction SilentlyContinue

    Write-Output "[*] Возвращаю историю, геолокацию и журналы..."
    foreach ($n in @("PublishUserActivities","EnableActivityFeed","UploadUserActivities")) {
        Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" $n
    }
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" "DisableLocation"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" "DisableSensors"
    foreach ($l in @("AppModel","DiagLog","Diagtrack-Listener","LwtNetLog","SQMLogger","WdiContextLog","WiFiSession")) {
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$l" -Name "Start" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }

    Write-Output "[*] Возвращаю советы и контент..."
    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    foreach ($n in @("ContentDeliveryAllowed","SubscribedContent-338387Enabled","SubscribedContent-338388Enabled","SubscribedContent-338389Enabled","SubscribedContent-353698Enabled","SystemPaneSuggestionsEnabled","SilentInstalledAppsEnabled")) {
        Set-ItemProperty -Path $cdm -Name $n -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }

    Write-Output "[*] Включаю задачи планировщика..."
    $tasks = @(
        @{ TaskName = "Microsoft Compatibility Appraiser"; TaskPath = "\Microsoft\Windows\Application Experience\" },
        @{ TaskName = "ProgramDataUpdater"; TaskPath = "\Microsoft\Windows\Application Experience\" },
        @{ TaskName = "Consolidator"; TaskPath = "\Microsoft\Windows\Customer Experience Improvement Program\" },
        @{ TaskName = "UsbCeip"; TaskPath = "\Microsoft\Windows\Customer Experience Improvement Program\" },
        @{ TaskName = "DmClient"; TaskPath = "\Microsoft\Windows\Feedback\Siuf\" },
        @{ TaskName = "QueueReporting"; TaskPath = "\Microsoft\Windows\Windows Error Reporting\" },
        @{ TaskName = "MapsUpdateTask"; TaskPath = "\Microsoft\Windows\Maps\" }
    )
    foreach ($t in $tasks) {
        try { Enable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop | Out-Null } catch {}
    }

    Write-Output ("[OK] Уровень AllowTelemetry=" + $telemetryValue + " и службы приватности восстановлены.")
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
