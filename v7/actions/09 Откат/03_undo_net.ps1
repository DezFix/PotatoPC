# NAME: 03 · Откат сети: DNS на авто, вернуть NetBIOS и поиск имён
# DESC: Возвращает DNS на авто (DHCP) и NetbiosOptions=0, снимает политику LLMNR. SMBv1, mDNS и WPAD намеренно НЕ трогаем — их PotatoPC не менял
# TAGS: 1
# ICON: ↩️

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" "EnableMulticast"
    # EnableMDNS и WpadOverride удаляли, хотя ни один скрипт приложения их не
    # пишет: если пользователь или другой инструмент выключил mDNS/WPAD
    # намеренно, "откат" молча включал их обратно.
    $n = 0; $nFail = 0
    $ifs = @(Get-ChildItem -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces" -ErrorAction SilentlyContinue)
    foreach ($i in $ifs) {
        try { Set-ItemProperty -LiteralPath $i.PSPath -Name "NetbiosOptions" -Value 0 -Type DWord -Force -ErrorAction Stop; $n++ }
        catch { $nFail++; Write-Output ("[!] Интерфейс " + $i.PSChildName + ": " + $_.Exception.Message) }
    }
    $dnsFailed = 0
    try {
        # Только физические адаптеры: прямо скрипт 01_dns_cloudflare.ps1 менял
        # лишь их, а -ResetServerAddresses на всех Up затирал корпоративный
        # DNS у VPN- и виртуальных адаптеров.
        $dnsAdapters = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })
        if ($dnsAdapters.Count -eq 0) { $dnsAdapters = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' }) }
        foreach ($adapter in $dnsAdapters) {
            try { Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction Stop }
            catch { $dnsFailed++; Write-Output ("[!] DNS для " + $adapter.Name + ": " + $_) }
        }
        if ($dnsAdapters.Count -eq 0) { Write-Output "[=] Активных адаптеров нет; DNS не менялся." }
        elseif ($dnsFailed -eq 0) { Write-Output "[*] DNS возвращён на авто (DHCP)." }
    } catch {
        $dnsFailed++
        Write-Output ("[!] DNS: " + $_)
    }
    if ($dnsFailed -gt 0) {
        Write-Output ("[X] Сеть откатана частично; ошибок DNS: " + $dnsFailed)
        exit 1
    }
    $tail = ""
    if ($nFail -gt 0) { $tail = " (интерфейсов NetBIOS с ошибкой: " + $nFail + ")" }
    Write-Output ("[OK] Сеть как была (" + $n + " инт." + $tail + "). SMBv1, mDNS и WPAD намеренно не трогаю.")
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
