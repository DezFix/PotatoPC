# NAME: 06 01 · DNS Cloudflare 1.1.1.1 (сайты открываются быстрее)
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
    foreach ($a in $adapters) {
        try {
            Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses ('1.1.1.1','1.0.0.1') -ErrorAction Stop
            Write-Output ("[*] " + $a.Name + ": DNS 1.1.1.1, 1.0.0.1")
            $n++
        } catch { Write-Output ("[!] " + $a.Name + ": " + $_) }
    }
    try { ipconfig /flushdns 2>&1 | Out-Null } catch {}
    if ($n -eq 0) { Write-Output "[X] Ни один адаптер не настроен."; exit 1 }
    Write-Output ("[OK] DNS сменён на " + $n + " адапт. Откат: раздел Откат -> сеть.")
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
