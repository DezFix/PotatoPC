# NAME: 02 · Откат Defender: вернуть защиту на максимум
# DESC: Возвращает Set-MpPreference к заводским: CPU 50%, скан архивов/сети вкл., облако Basic, образцы SendSafeSamples. Нужен, если Defender меняли сторонней утилитой
# TAGS: 1
# ICON: 🛡️

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    # В приложении нет скрипта, который облегчает Defender (05/03_light_defender.ps1
    # только читает состояние, и тест это проверяет). Этот откат нужен, когда
    # настройки меняли руками или сторонней утилитой, поэтому DESC так и говорит.
    $applied = @()
    $failed = @()
    $prefs = @(
        @{ Name = 'ScanAvgCPULoadFactor'; Args = @{ ScanAvgCPULoadFactor = 50 } },
        @{ Name = 'DisableArchiveScanning'; Args = @{ DisableArchiveScanning = $false } },
        @{ Name = 'DisableScanningMappedNetworkDrivesForFullScan'; Args = @{ DisableScanningMappedNetworkDrivesForFullScan = $false } },
        # Заводские значения, а не "максимум": MAPSReporting по умолчанию Disabled
        # (0), SubmitSamplesConsent - SendSafeSamples (1). Раньше ставились
        # Advanced и NeverSend, то есть "как из коробки" было неправдой.
        @{ Name = 'MAPSReporting'; Args = @{ MAPSReporting = 0 } },
        @{ Name = 'SubmitSamplesConsent'; Args = @{ SubmitSamplesConsent = 1 } },
        @{ Name = 'EnableLowCpuPriority'; Args = @{ EnableLowCpuPriority = $false } }
    )
    foreach ($p in $prefs) {
        try { Set-MpPreference @($p.Args) -ErrorAction Stop; $applied += $p.Name }
        catch { $failed += ($p.Name + ": " + $_.Exception.Message); Write-Output ("[!] " + $p.Name + ": " + $_.Exception.Message) }
    }
    if ($failed.Count -gt 0) {
        Write-Output ("[X] Часть настроек Defender не вернулась (" + $applied.Count + " из " + $prefs.Count + "). Обычно мешает «Защита от подделки».")
        exit 1
    }
    Write-Output "[OK] Defender вернулся к заводским настройкам (облако Basic, образцы SendSafeSamples)."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
