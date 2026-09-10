# NAME: Крепкая сеть
# DESC: Закрывает старые дыры. Старый принтер может отвалиться
# TAGS: 2
# ICON: 🌐

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    Write-Output "[*] Закрываю SMBv1, LLMNR, NetBIOS..."
    try {
        $s = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
        if ($s.State -ne "Disabled") {
            Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction Stop | Out-Null
        }
    } catch { Write-Output ("[!] SMBv1: " + $_) }
    try { Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop } catch {}

    $d = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
    if (-not (Test-Path $d)) { New-Item -Path $d -Force | Out-Null }
    Set-ItemProperty -Path $d -Name "EnableMulticast" -Value 0 -Type DWord -Force

    $ifs = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces" -ErrorAction SilentlyContinue
    $n = 0
    foreach ($i in $ifs) {
        try { Set-ItemProperty -Path $i.PSPath -Name "NetbiosOptions" -Value 2 -Type DWord -Force; $n++ } catch {}
    }
    Write-Output ("[OK] Сеть укреплена. Интерфейсов: " + $n)
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
