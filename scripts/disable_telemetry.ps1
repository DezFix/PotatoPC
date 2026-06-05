# NAME: Отключить телеметрию Windows
# DESC: Запрещает отправку диагностических данных в Microsoft
# CATEGORY: Конфиденциальность
# ICON: 🔒
# RECOMMENDED: true

function Disable-Telemetry {
    Write-Host "[+] Расширенное отключение телеметрии..." -ForegroundColor Yellow

    # --- Службы на отключение ---
    $services = @(
        "DiagTrack", "dmwappushservice", "DPS", "WdiServiceHost", 
        "WdiSystemHost", "Wecsvc", "WerSvc", "WMPNetworkSvc", 
        "WpnService", "XboxGameMonitoring", "XboxSpeechToTextService", 
        "XboxGipSvc", "XblGameSave", "XboxNetApiSvc"
    )
    foreach ($svc in $services) {
        if (Get-Service $svc -ErrorAction SilentlyContinue) {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Host "[−] Служба $svc отключена" -ForegroundColor Cyan
        }
    }

    # --- Задачи планировщика (телеметрия + диагностика) ---
    $tasks = @(
        "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
        "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
        "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
        "\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask",
        "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
        "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
        "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticResolver",
        "\Microsoft\Windows\Feedback\Siuf\DmClient",
        "\Microsoft\Windows\Feedback\Siuf\SiufTask",
        "\Microsoft\Windows\Windows Error Reporting\QueueReporting"
    )
    foreach ($task in $tasks) {
        schtasks /Change /TN $task /Disable 2>$null
        Write-Host "[−] Задача $task отключена" -ForegroundColor DarkCyan
    }

    # --- Реестр: AllowTelemetry, Cortana, реклама, WER ---
    $regPaths = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager",
        "HKCU:\Software\Microsoft\InputPersonalization",
        "HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore"
    )
    foreach ($path in $regPaths) {
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    }

    # AllowTelemetry в политиках (Group Policy)
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -Force

    # Отключение Cortana
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0 -Type DWord -Force

    # Отключение рекламы/контента
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338387Enabled" -Value 0 -Type DWord -Force

    # Отключение сбора рукописного ввода и текста
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\InputPersonalization" -Name "RestrictImplicitTextCollection" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\InputPersonalization" -Name "RestrictImplicitInkCollection" -Value 1 -Type DWord -Force

    # Отключение Windows Error Reporting
    if (-not (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting")) {
        New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Force | Out-Null
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Value 1 -Type DWord -Force

    Write-Host "[+] Телеметрия и диагностика отключены" -ForegroundColor Green
    Start-Sleep -Seconds 2
}