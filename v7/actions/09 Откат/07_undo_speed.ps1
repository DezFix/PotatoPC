# NAME: 07 · Откат «Скорости»: эффекты, фон, питание, мышь как было
# DESC: Возвращает VisualFX, UserPreferencesMask, схему «Сбалансированная», рекламу, GameDVR и ускорение мыши. Откат раздела «Скорость»
# TAGS: 1
# ICON: ↩️

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    # powercfg пишет ошибки в stderr; при $ErrorActionPreference='Stop' перенаправление
    # 2>&1 обрывает скрипт до проверки $LASTEXITCODE.
    function Invoke-Powercfg {
        param([Parameter(ValueFromRemainingArguments = $true)][string[]]$PcArgs)
        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $raw = & powercfg @PcArgs 2>&1
            return [PSCustomObject]@{ Code = $LASTEXITCODE; Text = (($raw | Out-String).Trim()) }
        } finally { $ErrorActionPreference = $prev }
    }

    Write-Output "[*] Возвращаю эффекты..."
    # VisualFXSetting=1 - это "лучшее оформление", заводское "пусть Windows
    # решает" = удалить значение.
    Del-Prop "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting"
    Set-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 1 -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -LiteralPath "HKCU:\Control Panel\Desktop" -Name "DragFullWindows" -Value 1 -Force -ErrorAction SilentlyContinue
    # UserPreferencesMask, FontSmoothing и FontSmoothingType скрипт менял, а
    # откат их не трогал - маска оставалась в режиме "быстродействие".
    Del-Prop "HKCU:\Control Panel\Desktop" "UserPreferencesMask"
    Set-ItemProperty -LiteralPath "HKCU:\Control Panel\Desktop" -Name "FontSmoothing" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -LiteralPath "HKCU:\Control Panel\Desktop" -Name "FontSmoothingType" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue

    Write-Output "[*] Возвращаю фон и приоритеты..."
    Del-Prop "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled"
    Del-Prop "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" "BackgroundAppGlobalToggle"
    Set-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue

    Write-Output "[*] Возвращаю питание и рекламу..."
    $r = Invoke-Powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e
    if ($r.Code -ne 0) { throw ("powercfg /setactive: код " + $r.Code + "; " + $r.Text) }
    # Схему «Высокая производительность», созданную скриптом через
    # -duplicatescheme, удаляем: иначе она оставалась висеть в списке.
    # Трогаем только копию этой схемы и только если её GUID не совпадает с
    # тремя встроенными - иначе под нож попали бы plans пользователя.
    $builtIn = @(
        '381b4222-f694-41f0-9685-ff5bb260df2e',   # Сбалансированная
        '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c',   # Высокая производительность
        'a1841308-3541-4fab-bc81-f71556f20b4a'    # Экономия энергии
    )
    $dupCount = 0
    foreach ($line in (Invoke-Powercfg /list).Text -split "`n") {
        if ($line -notmatch '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s+\((.+)\)') { continue }
        $g = $Matches[1]
        $title = $Matches[2]
        if ($builtIn -contains $g.ToLowerInvariant()) { continue }
        if ($title -notmatch '(?i)(Высокая производительность|High performance)') { continue }
        $d = Invoke-Powercfg /delete $g
        if ($d.Code -eq 0) { $dupCount++; Write-Output ("[*] Удалена копия схемы: " + $title) }
    }
    if ($dupCount -gt 0) { Write-Output ("[*] Удалено лишних схем питания: " + $dupCount) }

    Set-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 1 -Force -ErrorAction SilentlyContinue
    # AdvertisingInfo - политика, которую скрипт включал, а откат не снимал:
    # после "отката Скорости" реклама оставалась заблокированной.
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" "DisabledByGroupPolicy"
    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    # Заводского состояния для этих значений нет - их нужно удалить, а не ставить
    # в 1. SilentInstalledAppsEnabled=1, например, разрешает молчаливую
    # установку рекомендуемых приложений, то есть хуже исходного состояния.
    foreach ($n in @("ContentDeliveryAllowed","SubscribedContent-338387Enabled","SubscribedContent-338388Enabled",
                     "SubscribedContent-338389Enabled","SubscribedContent-338393Enabled","SubscribedContent-353698Enabled",
                     "SubscribedContent-353696Enabled","SystemPaneSuggestionsEnabled","SilentInstalledAppsEnabled",
                     "PreInstalledAppsEnabled","OemPreInstalledAppsEnabled","RotatingLockScreenOverlayEnabled")) {
        Del-Prop $cdm $n
    }
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableThirdPartySuggestions"
    Del-Prop "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableThirdPartySuggestions"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableSoftLanding"
    Del-Prop "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSyncProviderNotifications"
    Set-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 1 -Force -ErrorAction SilentlyContinue

    Write-Output "[*] Возвращаю игры, виджеты и вход..."
    $g = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"
    if (-not (Test-Path $g)) { New-Item -Path $g -Force | Out-Null }
    Set-ItemProperty -LiteralPath $g -Name "AppCaptureEnabled" -Value 1 -Type DWord -Force -ErrorAction Stop
    if ([int](Get-ItemProperty -LiteralPath $g -Name "AppCaptureEnabled" -ErrorAction Stop).AppCaptureEnabled -ne 1) { throw "AppCaptureEnabled не восстановлен" }
    $c = "HKCU:\System\GameConfigStore"
    if (-not (Test-Path $c)) { New-Item -Path $c -Force | Out-Null }
    Set-ItemProperty -LiteralPath $c -Name "GameDVR_Enabled" -Value 1 -Type DWord -Force -ErrorAction Stop
    if ([int](Get-ItemProperty -LiteralPath $c -Name "GameDVR_Enabled" -ErrorAction Stop).GameDVR_Enabled -ne 1) { throw "GameDVR_Enabled не восстановлен" }
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR"
    Set-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" "NoLockScreen"
    $mp = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    Del-Prop $mp "NoLazyMode"
    Set-ItemProperty -LiteralPath $mp -Name "NetworkThrottlingIndex" -Value 10 -Type DWord -Force -ErrorAction SilentlyContinue
    Del-Prop $mp "SystemResponsiveness"
    Remove-Item -LiteralPath "$mp\Tasks\Games" -Recurse -Force -ErrorAction SilentlyContinue
    Del-Prop "HKCU:\Software\Microsoft\GameBar" "AllowAutoGameMode"
    Del-Prop "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled"
    $mouse = "HKCU:\Control Panel\Mouse"
    if (-not (Test-Path $mouse)) { New-Item -Path $mouse -Force | Out-Null }
    Set-ItemProperty -LiteralPath $mouse -Name "MouseSpeed" -Value "1" -Type String -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -LiteralPath $mouse -Name "MouseThreshold1" -Value "6" -Type String -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -LiteralPath $mouse -Name "MouseThreshold2" -Value "10" -Type String -Force -ErrorAction SilentlyContinue

    Write-Output "[OK] Раздел Скорость откачен. Перезайди или перезагрузись."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
