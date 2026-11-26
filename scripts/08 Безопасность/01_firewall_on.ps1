# NAME: Включить брандмауэр для всех сетей
# DESC: Включает профили Domain + Private + Public через Set-NetFirewallProfile. Вкладка «Защита» только показывает статус — это чинит
# TAGS: 1
# ICON: 🧱
# PRESET: potato,office,game
# CHECK: -not @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { -not $_.Enabled }).Count

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    # Снимок «как было» для отката (Откат\01_firewall_on.ps1).
    $before = @(Get-NetFirewallProfile -PolicyStore PersistentStore -ErrorAction Stop)
    if (@($before | Where-Object { $_.Enabled -ne 'True' }).Count -gt 0) {
        try {
            $bd = Join-Path $env:ProgramData 'PotatoPC\backups'
            if (-not (Test-Path -LiteralPath $bd)) { New-Item -ItemType Directory -Path $bd -Force | Out-Null }
            @{ Time = (Get-Date -Format 's'); Profiles = @($before | ForEach-Object { @{ Name = [string]$_.Name; Enabled = ([string]$_.Enabled -eq 'True') } }) } |
                ConvertTo-Json -Depth 4 | Out-File -LiteralPath (Join-Path $bd ('firewall-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')) -Encoding UTF8 -Force
        } catch { Write-Output ("[!] Снимок не сохранён: " + $_.Exception.Message) }
    }
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
