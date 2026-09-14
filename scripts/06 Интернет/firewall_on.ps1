# NAME: Включить брандмауэр для всех сетей
# DESC: Включает профили Domain + Private + Public через Set-NetFirewallProfile. Вкладка «Защита» только показывает статус — это чинит
# TAGS: 1
# ICON: 🧱

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled True -ErrorAction Stop
    $off = @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { -not $_.Enabled })
    if ($off.Count -gt 0) { Write-Output ("[X] Остались выключены: " + (($off | ForEach-Object { $_.Name }) -join ", ")); exit 1 }
    Write-Output "[OK] Брандмауэр включён везде (Domain, Private, Public)."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
