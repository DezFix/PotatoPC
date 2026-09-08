# NAME: Проверка телеметрии и сети
# DESC: Диагностика без изменений: SMBv1, LLMNR, NetBIOS, службы телеметрии, DNS до серверов Microsoft
# TAGS: 1
# ICON: 🔬

function Test-TelemetryNet {
    Write-Host "=== Аудит телеметрии и сети (только чтение) ===" -ForegroundColor Yellow

    # --- SMBv1 ---
    try {
        $smb1 = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
        Write-Host ("[*] SMBv1 компонент: " + $smb1.State) -ForegroundColor Cyan
    } catch {
        Write-Host "[!] SMBv1: не удалось проверить" -ForegroundColor DarkGray
    }

    # --- LLMNR / mDNS ---
    try {
        $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name EnableMulticast -ErrorAction SilentlyContinue).EnableMulticast
        if ($null -eq $v) { Write-Host "[*] LLMNR: политика не задана (включен по умолчанию)" -ForegroundColor Cyan }
        else { Write-Host ("[*] LLMNR EnableMulticast = " + $v + $(if ($v -eq 0) { " (выкл)" } else { " (ВКЛ)" })) -ForegroundColor Cyan }
    } catch {}
    try {
        $v = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name EnableMDNS -ErrorAction SilentlyContinue).EnableMDNS
        if ($null -eq $v) { Write-Host "[*] mDNS: по умолчанию (включен)" -ForegroundColor Cyan }
        else { Write-Host ("[*] mDNS EnableMDNS = " + $v) -ForegroundColor Cyan }
    } catch {}

    # --- Службы телеметрии ---
    foreach ($svc in @("DiagTrack", "dmwappushservice", "DusmSvc")) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) { Write-Host ("[*] " + $svc + ": " + $s.Status + " / " + $s.StartType) -ForegroundColor Cyan }
        else { Write-Host ("[*] " + $svc + ": не найдена") -ForegroundColor DarkGray }
    }

    # --- DNS до телеметрии (резолв, без отправки данных) ---
    $hosts = @("vortex-win.data.microsoft.com", "settings-win.data.microsoft.com", "www.microsoft.com")
    foreach ($h in $hosts) {
        try {
            $ip = (Resolve-DnsName -Name $h -Type A -ErrorAction Stop | Where-Object { $_.IPAddress } | Select-Object -First 1).IPAddress
            Write-Host ("[*] DNS {0} -> {1}" -f $h, $ip) -ForegroundColor Cyan
        } catch {
            Write-Host ("[!] DNS {0}: не резолвится ({1})" -f $h, "блок или офлайн") -ForegroundColor DarkGray
        }
    }

    # --- Слушающие порты (топ по PID) ---
    try {
        $listeners = Get-NetTCPConnection -State Listen -ErrorAction Stop | Group-Object OwningProcess | Sort-Object Count -Descending | Select-Object -First 5
        Write-Host "[*] Топ слушающих процессов:" -ForegroundColor Cyan
        foreach ($g in $listeners) {
            try {
                $p = Get-Process -Id $g.Name -ErrorAction SilentlyContinue
                Write-Host ("    PID {0} ({1}): портов {2}" -f $g.Name, $p.ProcessName, $g.Count)
            } catch {}
        }
    } catch {
        Write-Host "[!] Get-NetTCPConnection недоступен" -ForegroundColor DarkGray
    }

    Write-Host "=== Аудит завершен (изменений не вносилось) ===" -ForegroundColor Green
}

Test-TelemetryNet
