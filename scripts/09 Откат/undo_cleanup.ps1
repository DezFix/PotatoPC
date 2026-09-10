# NAME: Вернуть убранное
# DESC: Отменяет раздел Очистка. Удаленное из образа вернется через Store
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
    foreach ($pkg in (Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)) {
        try {
            Add-AppxPackage -Register ($pkg.InstallLocation + "\AppXManifest.xml") -DisableDevelopmentMode -ErrorAction Stop | Out-Null
            $n++
        } catch {}
    }
    Write-Output ("[*] Переподключено пакетов: " + $n)

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
    $setup = Join-Path $env:SystemRoot "SysWOW64\OneDriveSetup.exe"
    if (-not (Test-Path $setup)) { $setup = Join-Path $env:SystemRoot "System32\OneDriveSetup.exe" }
    if (Test-Path $setup) { Start-Process $setup -Wait -ErrorAction SilentlyContinue }
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode"

    Write-Output "[OK] Готово. Что снесено из образа - докачай в Microsoft Store."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
