# NAME: Вернуть скорость
# DESC: Отменяет раздел Скорость. Всё как было
# TAGS: 1
# ICON: ↩️

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    Write-Output "[*] Возвращаю эффекты..."
    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 1 -Force -ErrorAction SilentlyContinue
    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 1 -Force -ErrorAction SilentlyContinue
    Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name "DragFullWindows" -Value 1 -Force -ErrorAction SilentlyContinue
    Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "400" -Type String -Force -ErrorAction SilentlyContinue

    Write-Output "[*] Возвращаю фон и приоритеты..."
    Del-Prop "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled"
    Del-Prop "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" "BackgroundAppGlobalToggle"
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Value "1" -Type String -Force -ErrorAction SilentlyContinue

    Write-Output "[*] Возвращаю питание и рекламу..."
    powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>$null | Out-Null
    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 1 -Force -ErrorAction SilentlyContinue
    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    foreach ($n in @("ContentDeliveryAllowed","SubscribedContent-338387Enabled","SubscribedContent-338388Enabled","SubscribedContent-338389Enabled","SystemPaneSuggestionsEnabled","SilentInstalledAppsEnabled")) {
        Set-ItemProperty -Path $cdm -Name $n -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures"
    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 1 -Force -ErrorAction SilentlyContinue

    Write-Output "[*] Возвращаю игры, виджеты и вход..."
    Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR"
    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" "NoLockScreen"
    $mp = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    Del-Prop $mp "NoLazyMode"
    Set-ItemProperty -Path $mp -Name "NetworkThrottlingIndex" -Value 10 -Type DWord -Force -ErrorAction SilentlyContinue
    Del-Prop $mp "SystemResponsiveness"
    Remove-Item "$mp\Tasks\Games" -Recurse -Force -ErrorAction SilentlyContinue

    Write-Output "[OK] Раздел Скорость откачен. Перезайди или перезагрузись."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
