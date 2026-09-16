# NAME: 02 03 · Не раздавать обновления другим ПК (Delivery Optimization)
# DESC: Ставит DODownloadMode=0: качает обновления только с серверов Microsoft. Экономит отдачу интернета
# TAGS: 1
# ICON: 📥
# PRESET: potato, office, game

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -Path $p -Name "DODownloadMode" -Value 0 -Type DWord -Force
    Write-Output "[OK] Раздача обновлений выключена."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
