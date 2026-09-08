# NAME: Откат отключения телеметрии
# DESC: Возвращает службы, задачи планировщика и политики телеметрии к значениям по умолчанию
# TAGS: 1
# ICON: ↩️

function Undo-Telemetry {
    Write-Host "[+] Откат телеметрии к значениям по умолчанию..." -ForegroundColor Yellow

    # --- 1. Политики ---
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "DoNotShowFeedbackNotifications" -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host "[+] Политики возвращены" -ForegroundColor Green
    } catch {
        Write-Host "[!] Политики: $_" -ForegroundColor DarkGray
    }

    # --- 2. Службы: DiagTrack=Auto+старт, остальные=Manual ---
    $autoSvc = @("DiagTrack")
    $manualSvc = @("dmwappushservice", "DcpSvc", "diagnosticshub.standardcollector.service", "DusmSvc")
    foreach ($svc in $autoSvc) {
        try {
            Set-Service -Name $svc -StartupType Automatic -ErrorAction Stop
            Start-Service -Name $svc -ErrorAction SilentlyContinue
            Write-Host "[+] Служба '$svc' -> Automatic + запущена" -ForegroundColor Green
        } catch {
            Write-Host "[!] Служба '$svc': $_" -ForegroundColor DarkGray
        }
    }
    foreach ($svc in $manualSvc) {
        try {
            Set-Service -Name $svc -StartupType Manual -ErrorAction Stop
            Write-Host "[+] Служба '$svc' -> Manual" -ForegroundColor Green
        } catch {
            Write-Host "[!] Служба '$svc': $_" -ForegroundColor DarkGray
        }
    }

    # --- 3. Задачи планировщика ---
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
            Enable-ScheduledTask -TaskName $task -ErrorAction Stop | Out-Null
            Write-Host "[+] Задача включена: $(Split-Path $task -Leaf)" -ForegroundColor Cyan
        } catch {
            Write-Host "[!] Задача '$task' не найдена" -ForegroundColor DarkGray
        }
    }

    Write-Host "[+] Откат завершен!" -ForegroundColor Green
}

Undo-Telemetry
