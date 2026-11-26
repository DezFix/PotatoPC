# NAME: Откат: Фоновая работа приложений Магазина
# DESC: Снова разрешает приложениям из Microsoft Store работать в фоне (уведомления, синхронизация)
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    Del-Prop "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled"
    Del-Prop "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" "BackgroundAppGlobalToggle"
    Write-Output "[OK] Фоновая работа разрешена. Перезайди в систему."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
