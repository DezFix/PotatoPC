# NAME: Откат оптимизации Defender
# DESC: Возвращает настройки Windows Defender к балансу по умолчанию (включая сканирование архивов)
# TAGS: 1
# ICON: 🛡️

#Requires -RunAsAdministrator

function Undo-DefenderOptimization {
    Write-Host "[+] Откат оптимизации Defender..." -ForegroundColor Yellow
    try {
        Set-MpPreference -ScanAvgCPULoadFactor 50 -ErrorAction Stop
        Write-Host "[+] CPU-нагрузка сканирования -> 50%" -ForegroundColor Green

        Set-MpPreference -DisableArchiveScanning $false -ErrorAction Stop
        Write-Host "[+] Сканирование архивов ВКЛЮЧЕНО обратно" -ForegroundColor Green

        Set-MpPreference -DisableScanningMappedNetworkDrivesForFullScan $false -ErrorAction Stop
        Write-Host "[+] Сетевые диски вернулись в полное сканирование" -ForegroundColor Green

        Set-MpPreference -MAPSReporting Advanced -ErrorAction Stop
        Write-Host "[+] MAPS -> Advanced" -ForegroundColor Green

        Set-MpPreference -SubmitSamplesConsent 2 -ErrorAction Stop
        Write-Host "[+] Отправка образцов -> только безопасные" -ForegroundColor Green

        Set-MpPreference -EnableLowCpuPriority $false -ErrorAction Stop
        Write-Host "[+] Обычный приоритет фоновых проверок" -ForegroundColor Green

        Write-Host "[+] Defender возвращен к умолчанию!" -ForegroundColor Green
    } catch {
        Write-Host "[-] ОШИБКА: $_" -ForegroundColor Red
        Write-Host "[-] Проверьте Tamper Protection: Защита от вирусов и угроз -> Параметры." -ForegroundColor Red
    }
}

Undo-DefenderOptimization
