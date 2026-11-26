# NAME: Откат: История действий и геолокация
# DESC: Снимает политики, запрещавшие историю действий и определение местоположения
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    foreach ($n in @("PublishUserActivities","EnableActivityFeed","UploadUserActivities")) { Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" $n }
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" "DisableLocation"
    Write-Output "[OK] История действий и геолокация снова разрешены."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
