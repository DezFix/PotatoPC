# NAME: 02 · Включить брандмауэр для всех сетей
# DESC: Включает профили Domain + Private + Public через Set-NetFirewallProfile. Вкладка «Защита» только показывает статус — это чинит
# TAGS: 1
# ICON: 🧱

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled True -ErrorAction Stop
    $local = @(Get-NetFirewallProfile -PolicyStore PersistentStore -ErrorAction Stop | Where-Object { -not $_.Enabled })
    if ($local.Count -gt 0) {
        Write-Output ("[X] Локально остались выключены: " + (($local | ForEach-Object { $_.Name }) -join ", "))
        exit 1
    }
    # Проверяем действующее состояние, а не локальное: на доменной машине
    # политика может держать профиль выключенным поверх нашего значения, и
    # тогда "[OK] везде" было бы прямой неправдой.
    $effective = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop | Where-Object { $_.Enabled -eq 'False' })
    if ($effective.Count -gt 0) {
        Write-Output ("[!] Эффективно выключены политикой (GPO/локальная настройка): " + (($effective | ForEach-Object { $_.Name }) -join ", "))
        Write-Output "    Свою настройку поставили, но она перекрыта. Правь политику домена."
        exit 1
    }
    Write-Output "[OK] Брандмауэр включён везде (Domain, Private, Public)."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
