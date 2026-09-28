# NAME: 01 · DNS Cloudflare 1.1.1.1 (сайты открываются быстрее)
# DESC: Меняет DNS на активных адаптерах на 1.1.1.1 + 1.0.0.1 через Set-DnsClientServerAddress. В офисе с локальным сервером может сломать интранет!
# TAGS: 2
# ICON: 🛰️

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $adapters = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })
    if ($adapters.Count -eq 0) {
        $adapters = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })
    }
    if ($adapters.Count -eq 0) { Write-Output "[X] Нет активных адаптеров."; exit 1 }
    $n = 0
    $failed = 0
    foreach ($a in $adapters) {
        try {
            Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses ('1.1.1.1','1.0.0.1') -ErrorAction Stop
            # На адаптерах без IPv4 (Bluetooth PAN, IPv6-only, туннели) запрос
            # возвращает ошибку, и раньше она засчитывалась как "адаптер не настроен".
            $actual = @(Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                        ForEach-Object { $_.ServerAddresses })
            if ($actual.Count -gt 0 -and (($actual -notcontains '1.1.1.1') -or ($actual -notcontains '1.0.0.1'))) { throw "адрес не подтверждён" }
            Write-Output ("[*] " + $a.Name + ": DNS 1.1.1.1, 1.0.0.1")
            $n++
        } catch {
            $failed++
            Write-Output ("[!] " + $a.Name + ": " + $_)
        }
    }
    # Сброс кэша - косметика: сбой flushdns не должен превращать выполненную
    # настройку в "✗ Ошибка".
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try { $raw = & ipconfig /flushdns 2>&1; $fcode = $LASTEXITCODE } finally { $ErrorActionPreference = $prev }
    if ($fcode -ne 0) { Write-Output ("[*] DNS-кэш не сброшен (ipconfig код " + $fcode + ") - не критично.") }
    if ($n -eq 0) { Write-Output "[X] Ни один адаптер не настроен."; exit 1 }
    if ($failed -gt 0) { Write-Output ("[OK] DNS настроен на " + $n + " адапт. из " + $adapters.Count + "; не удалось: " + $failed) }
    else { Write-Output ("[OK] DNS сменён на " + $n + " адапт. Откат: раздел Откат -> сеть.") }
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
