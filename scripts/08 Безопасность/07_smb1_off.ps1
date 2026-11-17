# NAME: Отключить устаревший протокол SMBv1
# DESC: Старый протокол общих папок, через который распространялись WannaCry и NotPetya. Нужен только очень старым NAS и принтерам
# TAGS: 1
# ICON: 🔒
# PRESET: potato,office,game
# CHECK: (-not (Get-SmbServerConfiguration -ErrorAction Stop).EnableSMB1Protocol) -and ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\mrxsmb10' -Name Start -ErrorAction SilentlyContinue).Start -in @(4, $null))
# TIMEOUT: 900

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $f = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
    if ($f.State -ne 'Enabled') { Write-Output "[=] SMBv1 уже выключен."; exit 0 }
    Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue
    $r = Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction Stop
    Write-Output ("[OK] SMBv1 отключён." + $(if ($r.RestartNeeded) { " Нужна перезагрузка." } else { "" }))
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
