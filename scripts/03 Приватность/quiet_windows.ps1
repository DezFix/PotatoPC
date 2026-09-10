# NAME: Тихая Windows
# DESC: Меньше слежки и отправки данных. ПК дышит свободнее
# TAGS: 1
# ICON: 🕵️
# PRESET: potato, office
# RECOMMENDED: true

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    foreach ($p in @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection","HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection")) {
        if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        Set-ItemProperty -Path $p -Name "AllowTelemetry" -Value 0 -Type DWord -Force
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "DoNotShowFeedbackNotifications" -Value 1 -Type DWord -Force

    $tasks = @(
        "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
        "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
        "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
        "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
        "\Microsoft\Windows\Feedback\Siuf\DmClient"
    )
    foreach ($t in $tasks) {
        Disable-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Output "[OK] Телеметрия выключена."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
