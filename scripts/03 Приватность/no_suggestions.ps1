# NAME: Без навязчивых советов
# DESC: Убирает автоустановку мусора из Пуска
# TAGS: 1
# ICON: 📦
# PRESET: potato, office
# RECOMMENDED: true

$ErrorActionPreference = "Stop"
try {
    $p = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    foreach ($n in @("ContentDeliveryAllowed","SubscribedContent-338387Enabled","SubscribedContent-338388Enabled","SubscribedContent-338389Enabled","SubscribedContent-353698Enabled","SystemPaneSuggestionsEnabled","SilentInstalledAppsEnabled")) {
        Set-ItemProperty -Path $p -Name $n -Value 0 -Type DWord -Force
    }
    Write-Output "[OK] Мусор из Пуска больше не ставится сам."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
