# NAME: Меньше задержек в играх
# DESC: Только для игр. Обычному ПК не нужно
# TAGS: 2
# ICON: 🎮
# PRESET: game

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $k = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
    Set-ItemProperty -Path $k -Name "NoLazyMode" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $k -Name "NetworkThrottlingIndex" -Value 0xFFFFFFFF -Type DWord -Force
    Set-ItemProperty -Path $k -Name "SystemResponsiveness" -Value 10 -Type DWord -Force

    $g = "$k\Tasks\Games"
    if (-not (Test-Path $g)) { New-Item -Path $g -Force | Out-Null }
    Set-ItemProperty -Path $g -Name "GPU Priority" -Value 8 -Type DWord -Force
    Set-ItemProperty -Path $g -Name "Priority" -Value 2 -Type DWord -Force
    Set-ItemProperty -Path $g -Name "Scheduling Category" -Value "High" -Type String -Force

    Write-Output "[OK] Игровой приоритет включен. Нужна перезагрузка."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
