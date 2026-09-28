# NAME: 01 · Откат «Очистки»: вернуть OneDrive, Xbox, Copilot…
# DESC: Переподключает удалённые AppX, снимает политики Copilot/Кортаны/OneDrive, службы Xbox в Manual. Снесённое из образа — докачать в Microsoft Store
# TAGS: 1
# ICON: ↩️

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    Write-Output "[*] Переподключаю встроенные приложения..."
    # Переподключаем ровно те пакеты, которые сносит 02 Очистка/04_remove_bloat.ps1.
    # Раньше здесь был Get-AppxPackage -AllUsers и Add-AppxPackage -Register для
    # каждого пакета системы - это сотни регистраций, скрипт не укладывался в
    # отведённое время и его перезапускали с начала, так и не доходя до OneDrive.
    $names = @(
        "Microsoft.3DBuilder","Microsoft.GetHelp",
        "Microsoft.ZuneMusic","Microsoft.ZuneVideo","Microsoft.windowscommunicationsapps",
        "Microsoft.BingWeather","Microsoft.Getstarted","Microsoft.Microsoft3DViewer",
        "Microsoft.MicrosoftOfficeHub","Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.MixedReality.Portal","Microsoft.Office.OneNote","Microsoft.OutlookForWindows",
        "Microsoft.People","Microsoft.ScreenSketch","Microsoft.SkypeApp","Microsoft.Wallet",
        "Microsoft.WindowsAlarms","Microsoft.WindowsFeedbackHub","Microsoft.WindowsMaps",
        "Microsoft.WindowsSoundRecorder","Microsoft.YourPhone",
        "Microsoft.BingNews","Microsoft.NewsAndInterests","Microsoft.549981C3F5F10"
    )
    $n = 0
    $appxErrors = 0
    $packages = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object { $names -contains $_.Name })
    if ($packages.Count -eq 0) {
        Write-Output "[*] Удалённых пакетов из списка не найдено - переподключать нечего."
    }
    foreach ($pkg in $packages) {
        try {
            if ([string]::IsNullOrWhiteSpace([string]$pkg.InstallLocation)) { throw "нет InstallLocation" }
            $manifest = Join-Path ([string]$pkg.InstallLocation) "AppXManifest.xml"
            if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw "нет AppXManifest.xml" }
            Add-AppxPackage -Register $manifest -DisableDevelopmentMode -ErrorAction Stop | Out-Null
            $n++
        } catch {
            $appxErrors++
            Write-Output ("[!] Пакет " + [string]$pkg.PackageFullName + ": " + $_)
        }
    }
    Write-Output ("[*] Переподключено пакетов: " + $n + "; ошибок: " + $appxErrors)

    Write-Output "[*] Возвращаю службы Xbox..."
    # Start=3 пишем в реестр: XboxGipSvc/xbgm под защитой PPL и Set-Service на
    # них отвечает отказом даже админу.
    $svcN = 0
    foreach ($s in @("XblAuthManager","XblGameSave","XboxNetApiSvc","XboxGipSvc","xbgm")) {
        $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$s"
        if (-not (Test-Path -LiteralPath $k)) { continue }
        try {
            Set-ItemProperty -LiteralPath $k -Name "Start" -Value 3 -Type DWord -Force -ErrorAction Stop
            if ([int](Get-ItemProperty -LiteralPath $k -Name "Start" -ErrorAction Stop).Start -ne 3) { throw "Start не вернулся в Manual" }
            $svcN++
        } catch { Write-Output ("[!] Служба " + $s + ": " + $_.Exception.Message) }
    }
    Write-Output ("[*] Служб Xbox возвращено в Manual: " + $svcN)

    Write-Output "[*] Снимаю политики Copilot, Кортаны и Recall..."
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot"
    Del-Prop "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot"
    Del-Prop "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowCopilotButton"
    Del-Prop "HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot" "IsCopilotAvailable"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCloudSearch"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "DisableWebSearch"
    Del-Prop "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "CortanaConsent"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis"
    Del-Prop "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "AllowRecallEnablement"

    Write-Output "[*] Возвращаю OneDrive и раздачу обновлений..."
    $dir = if ([Environment]::Is64BitProcess) { "System32" } else { "SysWOW64" }
    $setupCandidates = @(
        (Join-Path $env:SystemRoot "$dir\OneDriveSetup.exe"),
        (Join-Path $env:SystemRoot "SysWOW64\OneDriveSetup.exe"),
        (Join-Path $env:SystemRoot "System32\OneDriveSetup.exe")
    )
    if ($env:LOCALAPPDATA) { $setupCandidates += (Join-Path $env:LOCALAPPDATA "Microsoft\OneDrive\OneDriveSetup.exe") }
    $setup = $null
    foreach ($candidate in $setupCandidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $setup = $candidate; break }
    }
    $oneDriveBack = $false
    if ($null -eq $setup) {
        # Раньше здесь был throw - и он срабатывал уже после успешного отката
        # политик, так что весь раздел откатывался в "[X] Ошибка".
        Write-Output "[!] OneDriveSetup не найден - OneDrive автоматически не вернуть. Скачай OneDrive из microsoft.com."
    } else {
        $proc = Start-Process -FilePath $setup -Wait -PassThru -ErrorAction Stop
        if ($null -eq $proc) { Write-Output "[!] OneDriveSetup не запустился." }
        else {
            $code = [int]$proc.ExitCode
            if ($code -ne 0) { Write-Output ("[*] OneDriveSetup вернул код " + $code + "; проверяю результат...") }
            for ($i = 0; $i -lt 15; $i++) {
                if (@(Get-Process -Name OneDrive -ErrorAction SilentlyContinue).Count -gt 0) { $oneDriveBack = $true; break }
                Start-Sleep -Seconds 1
            }
            if (-not $oneDriveBack -and $env:LOCALAPPDATA) {
                $oneDriveExe = Join-Path $env:LOCALAPPDATA "Microsoft\OneDrive\OneDrive.exe"
                if (Test-Path -LiteralPath $oneDriveExe -PathType Leaf) { $oneDriveBack = $true }
            }
            if (-not $oneDriveBack) { Write-Output "[!] OneDriveSetup отработал, но OneDrive не появился - докачай вручную." }
        }
    }
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode"

    # Часть пакетов может быть занята - это не провал отката, поэтому код 0.
    if ($appxErrors -gt 0) {
        Write-Output ("[OK] Готово. Не переподключено пакетов: " + $appxErrors + " (докачай в Microsoft Store).")
    } else {
        Write-Output "[OK] Готово. Что снесено из образа - докачай в Microsoft Store."
    }
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
