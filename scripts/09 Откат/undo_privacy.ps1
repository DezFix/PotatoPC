# NAME: Вернуть слежку
# DESC: Отменяет раздел Приватность. Все как было
# TAGS: 1
# ICON: ↩️

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    Write-Output "[*] Возвращаю телеметрию..."
    Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
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
    foreach ($t in @(
        "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
        "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
        "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
        "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
        "\Microsoft\Windows\Feedback\Siuf\DmClient",
        "\Microsoft\Windows\Windows Error Reporting\QueueReporting",
        "\Microsoft\Windows\Maps\MapsUpdateTask"
    )) {
        try { Enable-ScheduledTask -TaskName $t -ErrorAction Stop | Out-Null } catch {}
    }

    Write-Output "[OK] Приватность откачена."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
