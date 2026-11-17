# NAME: Блокировать нежелательные программы (PUA)
# DESC: Включает в Защитнике Windows блокировку «потенциально нежелательных» программ: рекламные тулбары, «ускорители», навязанные установщики. Есть откат
# TAGS: 1
# ICON: 🧲
# PRESET: potato,office,game
# CHECK: (Get-MpPreference -ErrorAction Stop).PUAProtection -eq 1

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $pref = Get-MpPreference -ErrorAction Stop
    $status = $null
    try { $status = Get-MpComputerStatus -ErrorAction Stop } catch {}
    if ($status -and -not $status.AntivirusEnabled) {
        Write-Output "[=] Защитник Windows выключен (вероятно, стоит другой антивирус). Ничего не менял."
        exit 0
    }
    $backupDir = Join-Path $env:ProgramData 'PotatoPC\backups'
    try {
        if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
        @{ Time = (Get-Date -Format 's'); PUAProtection = [int]$pref.PUAProtection } | ConvertTo-Json |
            Out-File -LiteralPath (Join-Path $backupDir ('pua-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')) -Encoding UTF8 -Force
    } catch {}
    if ([int]$pref.PUAProtection -eq 1) { Write-Output "[=] Блокировка PUA уже включена."; exit 0 }
    Set-MpPreference -PUAProtection Enabled -ErrorAction Stop
    if ([int](Get-MpPreference).PUAProtection -ne 1) { throw "настройка не применилась (возможно, Защитник управляется политикой)" }
    Write-Output "[OK] Защитник теперь блокирует нежелательные программы."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
