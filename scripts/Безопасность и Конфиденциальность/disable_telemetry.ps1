# NAME: Отключение телеметрии Windows
# DESC: Запрещает сбор и отправку диагностических данных, отключает задачи планировщика и настраивает политики конфиденциальности
# TAGS: 1
# ICON: 🕵️
# RECOMMENDED: true


function Disable-Telemetry {
    Write-Host "[+] Начало отключения телеметрии и настроек конфиденциальности..." -ForegroundColor Yellow

    # --- 1. Реестр: Политики телеметрии, Cortana, реклама и WER ---
    $regPaths = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager",
        "HKCU:\Software\Microsoft\InputPersonalization",
        "HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore",
        "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"
    )

    foreach ($path in $regPaths) {
        if (-not (Test-Path $path)) { 
            New-Item -Path $path -Force | Out-Null 
        }
    }

    # AllowTelemetry в политиках (Group Policy)
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -Force
    
    # Дополнительные параметры телеметрии из C# кода
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "DoNotShowFeedbackNotifications" -Value 1 -Type DWord -Force

    # Отключение Cortana и веб-поиска
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch" -Value 1 -Type DWord -Force

    # Отключение рекламы и контента
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338387Enabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SystemPaneSuggestionsEnabled" -Value 0 -Type DWord -Force

    # Отключение сбора рукописного ввода и текста
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\InputPersonalization" -Name "RestrictImplicitTextCollection" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\InputPersonalization" -Name "RestrictImplicitInkCollection" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore" -Name "HarvestContacts" -Value 0 -Type DWord -Force

    # Отключение Windows Error Reporting
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Value 1 -Type DWord -Force

    Write-Host "[+] Реестр настроен" -ForegroundColor Green

    # --- 2. Задачи планировщика (телеметрия + диагностика) ---
    $tasks = @(
        "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
        "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
        "\Microsoft\Windows\Application Experience\PcaPatchDbTask",
        "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
        "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
        "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
        "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticResolver",
        "\Microsoft\Windows\Feedback\Siuf\DmClient",
        "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload",
        "\Microsoft\Windows\Windows Error Reporting\QueueReporting"
    )

    foreach ($task in $tasks) {
        try {
            Disable-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue | Out-Null
            Write-Host "[−] Задача '$task' отключена" -ForegroundColor Cyan
        } catch {
            Write-Host "[!] Не удалось отключить задачу '$task'" -ForegroundColor DarkGray
        }
    }

    Write-Host "[+] Телеметрия и диагностика успешно отключены!" -ForegroundColor Green
    Start-Sleep -Seconds 2
}

Disable-Telemetry
