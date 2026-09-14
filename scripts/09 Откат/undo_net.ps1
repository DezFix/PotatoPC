# NAME: Откат сети: DNS на авто, вернуть NetBIOS и поиск имён
# DESC: Возвращает DNS на авто (DHCP), NetbiosOptions=0 и снимает политики DNS. SMBv1 специально НЕ включает — это дыра
# TAGS: 1
# ICON: ↩️

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" "EnableMulticast"
    Del-Prop "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" "EnableMDNS"
    $ifs = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces" -ErrorAction SilentlyContinue
    $n = 0
    foreach ($i in $ifs) {
        try { Set-ItemProperty -Path $i.PSPath -Name "NetbiosOptions" -Value 0 -Type DWord -Force; $n++ } catch {}
    }
    Del-Prop "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad" "WpadOverride"
    try {
        Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
            try { Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ResetServerAddresses -ErrorAction Stop } catch {}
        }
        Write-Output "[*] DNS возвращён на авто (DHCP)."
    } catch {}
    Write-Output ("[OK] Сеть как была (" + $n + " инт.). SMBv1 специально НЕ включаю - это дыра.")
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
