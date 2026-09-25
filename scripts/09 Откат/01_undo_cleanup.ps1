# NAME: 01 · Откат «Очистки»: вернуть OneDrive, Xbox, Copilot…
# DESC: Снимает политики Copilot/Кортаны/OneDrive, службы Xbox в Manual. Снесённое из образа — докачать в Microsoft Store
# TAGS: 1
# ICON: ↩️

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    Write-Output "[*] Переподключаю встроенные приложения..."
    $n = 0
    $appxErrors = 0
    $packages = @(Get-AppxPackage -AllUsers -ErrorAction Stop)
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
    foreach ($s in @("XblGameSave","XboxNetApiSvc","XboxGipSvc","xbgm")) {
        Set-Service -Name $s -StartupType Manual -ErrorAction SilentlyContinue
    }

    Write-Output "[*] Снимаю политики Copilot, Кортаны и Recall..."
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot"
    Del-Prop "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot"
    Del-Prop "HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot" "IsCopilotAvailable"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCloudSearch"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "DisableWebSearch"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "AllowRecallEnablement"

    Write-Output "[*] Возвращаю OneDrive и раздачу обновлений..."
    $setupCandidates = @(
        (Join-Path $env:SystemRoot "SysWOW64\OneDriveSetup.exe"),
        (Join-Path $env:SystemRoot "System32\OneDriveSetup.exe")
    )
    if ($env:LOCALAPPDATA) { $setupCandidates += (Join-Path $env:LOCALAPPDATA "Microsoft\OneDrive\OneDriveSetup.exe") }
    $setup = $null
    foreach ($candidate in $setupCandidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $setup = $candidate; break }
    }
    if ($null -eq $setup) { throw "OneDriveSetup не найден; OneDrive восстановить не удалось" }
    $proc = Start-Process -FilePath $setup -Wait -PassThru -ErrorAction Stop
    if ($null -eq $proc) { throw "OneDriveSetup не запустился" }
    $code = [int]$proc.ExitCode
    if ($code -ne 0) { throw ("OneDriveSetup: код " + $code) }
    $restored = $false
    for ($i = 0; $i -lt 15; $i++) {
        if (@(Get-Process -Name OneDrive -ErrorAction SilentlyContinue).Count -gt 0) { $restored = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $restored -and $env:LOCALAPPDATA) {
        $oneDriveExe = Join-Path $env:LOCALAPPDATA "Microsoft\OneDrive\OneDrive.exe"
        if (Test-Path -LiteralPath $oneDriveExe -PathType Leaf) { $restored = $true }
    }
    if (-not $restored) { throw "OneDriveSetup завершился, но OneDrive не найден" }
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode"

    if ($appxErrors -gt 0) {
        Write-Output ("[X] OneDrive восстановлен, но часть пакетов AppX не переподключена: " + $appxErrors)
        exit 1
    }
    Write-Output "[OK] Готово. Что снесено из образа - докачай в Microsoft Store."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
