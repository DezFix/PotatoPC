# NAME: Отключить гостевую учётную запись
# DESC: Выключает встроенного «Гостя» (ищется по SID, работает на русской и английской Windows). По умолчанию он и так выключен
# TAGS: 1
# ICON: 🚫
# PRESET: potato,office,game
# CHECK: -not (Get-LocalUser -ErrorAction Stop | Where-Object { $_.SID.Value -like 'S-1-5-21-*-501' -and $_.Enabled })

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    # Имя гостя локализовано («Гость», «Guest», «Invité»...), а SID всегда кончается на -501.
    $guest = Get-LocalUser -ErrorAction Stop | Where-Object { $_.SID.Value -like 'S-1-5-21-*-501' } | Select-Object -First 1
    if (-not $guest) { Write-Output "[=] Гостевая запись не найдена. Ничего не менял."; exit 0 }
    $backupDir = Join-Path $env:ProgramData 'PotatoPC\backups'
    try {
        if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
        @{ Time = (Get-Date -Format 's'); Enabled = [bool]$guest.Enabled } | ConvertTo-Json |
            Out-File -LiteralPath (Join-Path $backupDir ('guest-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')) -Encoding UTF8 -Force
    } catch { Write-Output ("[!] Снимок состояния не сохранён: " + $_.Exception.Message) }
    if (-not $guest.Enabled) { Write-Output ("[=] «" + $guest.Name + "» уже выключен. Ничего не менял."); exit 0 }
    Disable-LocalUser -SID $guest.SID -ErrorAction Stop
    if ((Get-LocalUser -SID $guest.SID -ErrorAction Stop).Enabled) { throw "гостевая запись осталась включённой" }
    Write-Output ("[OK] Гостевая учётная запись «" + $guest.Name + "» отключена.")
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
