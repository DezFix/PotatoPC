# NAME: Без рекламы
# DESC: Убирает рекламу и советы. Проводник открывается быстрее
# TAGS: 1
# ICON: 🚫
# PRESET: potato, office, game
# RECOMMENDED: true

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Set-Reg($Path, $Name, $Value, $Type = "DWord") {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}

try {
    Write-Output "[*] Убираю рекламу..."
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0
    Set-Reg "HKLM:\Software\Policies\Microsoft\Windows\AdvertisingInfo" "DisabledByGroupPolicy" 1

    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    foreach ($n in @("SubscribedContent-338387Enabled","SubscribedContent-338388Enabled","SubscribedContent-338389Enabled","SystemPaneSuggestionsEnabled","SilentInstalledAppsEnabled","PreInstalledAppsEnabled","OemPreInstalledAppsEnabled","RotatingLockScreenOverlayEnabled","SubscribedContent-338393Enabled","SubscribedContent-353698Enabled","SubscribedContent-353696Enabled")) {
        Set-Reg $cdm $n 0
    }
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" 1
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableThirdPartySuggestions" 1
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableSoftLanding" 1

    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSyncProviderNotifications" 0
    Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled" 0
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests" 0

    Remove-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps" -Recurse -Force -ErrorAction SilentlyContinue

    Write-Output "[OK] Реклама выключена. Зайди заново чтобы увидеть результат."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
