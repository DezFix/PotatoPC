# NAME: Отключение legacy сетевых протоколов
# DESC: Отключает SMBv1, LLMNR, NetBIOS и WPAD — закрывает классические векторы lateral movement в локальной сети
# TAGS: 2
# ICON: 🌐
# RECOMMENDED: true

function Disable-LegacyNetProtocols {
    Write-Host "[+] Сетевой харденинг: SMBv1 / LLMNR / NetBIOS / WPAD..." -ForegroundColor Yellow

    # --- 1. SMBv1: компонент + серверный флаг ---
    try {
        $smb1 = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
        if ($smb1.State -ne "Disabled") {
            Write-Host "[*] Отключение компонента SMB1Protocol..." -ForegroundColor Cyan
            Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction Stop | Out-Null
            Write-Host "[+] Компонент SMBv1 отключен (нужна перезагрузка)" -ForegroundColor Green
        } else {
            Write-Host "[=] SMBv1 уже отключен" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "[!] SMBv1 компонент: $_" -ForegroundColor DarkGray
    }
    try {
        Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop
        Write-Host "[+] SMB-сервер: SMB1 запрещен" -ForegroundColor Green
    } catch {
        Write-Host "[!] SmbServerConfiguration: $_" -ForegroundColor DarkGray
    }

    # --- 2. LLMNR off (спуфинг имени через multicast) ---
    try {
        $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
        if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        Set-ItemProperty -Path $p -Name "EnableMulticast" -Value 0 -Type DWord -Force
        Write-Host "[+] LLMNR отключен (EnableMulticast=0)" -ForegroundColor Green
    } catch {
        Write-Host "[!] LLMNR: $_" -ForegroundColor DarkGray
    }

    # --- 3. NetBIOS over TCP/IP off на всех интерфейсах (NetbiosOptions=2) ---
    try {
        $ifaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces" -ErrorAction Stop
        $n = 0
        foreach ($i in $ifaces) {
            try {
                Set-ItemProperty -Path $i.PSPath -Name "NetbiosOptions" -Value 2 -Type DWord -Force -ErrorAction Stop
                $n++
            } catch {}
        }
        Write-Host "[+] NetBIOS отключен на интерфейсов: $n" -ForegroundColor Green
    } catch {
        Write-Host "[!] NetBIOS: $_" -ForegroundColor DarkGray
    }

    # --- 4. mDNS off (Windows 10 1809+) ---
    try {
        $p = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters"
        if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        Set-ItemProperty -Path $p -Name "EnableMDNS" -Value 0 -Type DWord -Force
        Write-Host "[+] mDNS отключен" -ForegroundColor Green
    } catch {
        Write-Host "[!] mDNS: $_" -ForegroundColor DarkGray
    }

    # --- 5. WPAD: автообнаружение прокси off (текущий пользователь + машина) ---
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name "AutoDetect" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        $p = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad"
        if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        Set-ItemProperty -Path $p -Name "WpadOverride" -Value 1 -Type DWord -Force
        Write-Host "[+] WPAD отключен" -ForegroundColor Green
    } catch {
        Write-Host "[!] WPAD: $_" -ForegroundColor DarkGray
    }

    Write-Host "[i] Старые NAS/принтеры только с SMBv1 перестанут открываться — включайте SMBv1 точечно, если нужно." -ForegroundColor Yellow
    Write-Host "[+] Сетевой харденинг завершен!" -ForegroundColor Green
}

Disable-LegacyNetProtocols
