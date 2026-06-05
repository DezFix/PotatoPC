# NAME: Отключение служб
# DESC: Отключение неиспользуемых служб Windows и перевод некоторых в ручной запуск
# CATEGORY: Производительность
# ICON: ⚙️
# RECOMMENDED: true

function Disable-Unused-Services {
    Write-Host "[+] Настройка служб..." -ForegroundColor Yellow
    
    $disableList = @(
        "XblGameSave", "XboxNetApiSvc", "Fax", "MapsBroker", 
        "RetailDemo", "SysMain", "WMPNetworkSvc", "XboxGipSvc",
        "OneSyncSvc", "UnistoreSvc", "MessagingService", 
        "PrintNotify", "TabletInputService", "BthAvctpSvc"
    )

    $manualList = @(
        "WSearch", "PcaSvc", "DiagSvcs", "TrkWks"      
    )

    # Отключаем ненужные
    foreach ($svc in $disableList) {
        if (Get-Service $svc -ErrorAction SilentlyContinue) {
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Host "[−] Служба $svc отключена" -ForegroundColor Cyan
        }
    }

    # Переводим в ручной запуск
    foreach ($svc in $manualList) {
        if (Get-Service $svc -ErrorAction SilentlyContinue) {
            Set-Service -Name $svc -StartupType Manual -ErrorAction SilentlyContinue
            Write-Host "[~] Служба $svc переведена в Manual" -ForegroundColor DarkCyan
        }
    }
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WSearch" -Name "Start" -Value 4 -Type DWord -Force
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\OneSyncSvc" -Name "Start" -Value 4 -Type DWord -Force

    Write-Host "[+] Все службы обработаны" -ForegroundColor Green
    Start-Sleep -Seconds 2
}