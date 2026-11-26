# NAME: Откат: Реклама и советы Windows
# DESC: Снимает запреты на рекламный ID, советы в Пуске и на экране блокировки - Windows решает сама, как из коробки
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    Set-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" "DisabledByGroupPolicy"
    # Заводского значения у этих параметров нет - их удаляем, а не ставим 1:
    # SilentInstalledAppsEnabled=1, например, хуже исходного состояния.
    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    foreach ($n in @("SubscribedContent-338387Enabled","SubscribedContent-338388Enabled","SubscribedContent-338389Enabled",
                     "SubscribedContent-338393Enabled","SubscribedContent-353698Enabled","SubscribedContent-353696Enabled",
                     "SystemPaneSuggestionsEnabled","SilentInstalledAppsEnabled","PreInstalledAppsEnabled",
                     "OemPreInstalledAppsEnabled","RotatingLockScreenOverlayEnabled")) { Del-Prop $cdm $n }
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableThirdPartySuggestions"
    Del-Prop "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableThirdPartySuggestions"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableSoftLanding"
    Del-Prop "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSyncProviderNotifications"
    Del-Prop "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled"
    Write-Output "[OK] Настройки рекламы возвращены к заводским. Перезайди в систему."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
