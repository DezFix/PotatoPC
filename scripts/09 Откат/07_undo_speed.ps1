# NAME: 07 · Откат «Скорости»: эффекты, фон, питание, мышь как было
# DESC: Возвращает VisualFX, схему «Сбалансированная», рекламу, GameDVR и ускорение мыши. Откат раздела «Скорость»
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

    Write-Output "[*] Возвращаю фон и приоритеты..."
    Del-Prop "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled"
    Del-Prop "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" "BackgroundAppGlobalToggle"
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue

    Write-Output "[*] Возвращаю питание и рекламу..."
    $out = & powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw ("powercfg /setactive: код " + $code + "; " + (($out | Out-String).Trim())) }
    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 1 -Force -ErrorAction SilentlyContinue
    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    foreach ($n in @("ContentDeliveryAllowed","SubscribedContent-338387Enabled","SubscribedContent-338388Enabled","SubscribedContent-338389Enabled","SystemPaneSuggestionsEnabled","SilentInstalledAppsEnabled")) {
        Set-ItemProperty -Path $cdm -Name $n -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures"
    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 1 -Force -ErrorAction SilentlyContinue

    Write-Output "[*] Возвращаю игры, виджеты и вход..."
    $g = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"
    if (-not (Test-Path $g)) { New-Item -Path $g -Force | Out-Null }
    Set-ItemProperty -Path $g -Name "AppCaptureEnabled" -Value 1 -Type DWord -Force -ErrorAction Stop
    if ([int](Get-ItemProperty -Path $g -Name "AppCaptureEnabled" -ErrorAction Stop).AppCaptureEnabled -ne 1) { throw "AppCaptureEnabled не восстановлен" }
    $c = "HKCU:\System\GameConfigStore"
    if (-not (Test-Path $c)) { New-Item -Path $c -Force | Out-Null }
    Set-ItemProperty -Path $c -Name "GameDVR_Enabled" -Value 1 -Type DWord -Force -ErrorAction Stop
    if ([int](Get-ItemProperty -Path $c -Name "GameDVR_Enabled" -ErrorAction Stop).GameDVR_Enabled -ne 1) { throw "GameDVR_Enabled не восстановлен" }
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR"
    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" "NoLockScreen"
    $mp = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    Del-Prop $mp "NoLazyMode"
    Set-ItemProperty -Path $mp -Name "NetworkThrottlingIndex" -Value 10 -Type DWord -Force -ErrorAction SilentlyContinue
    Del-Prop $mp "SystemResponsiveness"
    Remove-Item "$mp\Tasks\Games" -Recurse -Force -ErrorAction SilentlyContinue
    Del-Prop "HKCU:\Software\Microsoft\GameBar" "AllowAutoGameMode"
    Del-Prop "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled"
    Set-ItemProperty "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Value "1" -Type String -Force -ErrorAction SilentlyContinue
    Set-ItemProperty "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Value "6" -Type String -Force -ErrorAction SilentlyContinue
    Set-ItemProperty "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Value "10" -Type String -Force -ErrorAction SilentlyContinue

    Write-Output "[OK] Раздел Скорость откачен. Перезайди или перезагрузись."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
