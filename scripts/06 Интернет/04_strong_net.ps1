# NAME: 04 · Безопасность сети: выкл. SMBv1, LLMNR, NetBIOS
# DESC: Отключает древние протоколы (дыры типа WannaCry, спуфинг имён). Старые принтеры и NAS могут отвалиться!
# TAGS: 2
# ICON: 🌐

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    Write-Output "[*] Закрываю SMBv1, LLMNR, NetBIOS..."
    $failed = 0
    $smbPending = $false
    try {
        # На части сборок (в т.ч. чистых установок Win11) компонента SMB1Protocol
        # в образе просто нет, и Get-WindowsOptionalFeature на ней падает. Раньше
        # это давало "✗ Ошибка" на совершенно безопасной системе.
        $smb = $null
        try { $smb = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop }
        catch { Write-Output "[=] SMB1Protocol в этой сборке отсутствует - SMBv1 уже недоступен." }
        if ($null -ne $smb) {
            if ($smb.State -notin @("Disabled", "DisablePending", "DisabledWithPayloadRemoved")) {
                Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction Stop | Out-Null
                $smb = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
            }
            if ($smb.State -eq "DisablePending") { $smbPending = $true }
            if ($smb.State -notin @("Disabled", "DisablePending", "DisabledWithPayloadRemoved")) { throw "SMB1Protocol не отключён" }
        }
    } catch {
        $failed++
        Write-Output ("[!] SMBv1: " + $_)
    }
    try {
        Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop | Out-Null
    } catch {
        $failed++
        Write-Output ("[!] SMB-сервер: " + $_)
    }
    if ($smbPending) { Write-Output "[=] SMBv1 отключение ожидает перезагрузки" }

    $d = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
    try {
        if (-not (Test-Path $d)) { New-Item -Path $d -Force | Out-Null }
        Set-ItemProperty -Path $d -Name "EnableMulticast" -Value 0 -Type DWord -Force -ErrorAction Stop
        if ([int](Get-ItemProperty -Path $d -Name "EnableMulticast" -ErrorAction Stop).EnableMulticast -ne 0) { throw "EnableMulticast не отключён" }
    } catch {
        $failed++
        Write-Output ("[!] LLMNR: " + $_)
    }

    $n = 0
    $ifs = @()
    $netbtPath = "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces"
    try {
        if (Test-Path -LiteralPath $netbtPath) { $ifs = @(Get-ChildItem -LiteralPath $netbtPath -ErrorAction Stop) }
    } catch {
        $failed++
        Write-Output ("[!] Интерфейсы NetBIOS: " + $_)
    }
    foreach ($i in $ifs) {
        try {
            Set-ItemProperty -Path $i.PSPath -Name "NetbiosOptions" -Value 2 -Type DWord -Force -ErrorAction Stop
            if ([int](Get-ItemProperty -Path $i.PSPath -Name "NetbiosOptions" -ErrorAction Stop).NetbiosOptions -ne 2) { throw "NetbiosOptions не применён" }
            $n++
        } catch {
            $failed++
            Write-Output ("[!] Интерфейс " + $i.PSChildName + ": " + $_)
        }
    }
    if ($failed -gt 0) {
        Write-Output ("[X] Сеть укреплена частично; ошибок: " + $failed)
        exit 1
    }
    # dnscache и NetBT читают эти ключи при старте службы, а не на лету: без
    # перезагрузки (или рестарта служб) LLMNR и NetBIOS останутся включены.
    if ($n -eq 0) {
        Write-Output "[=] SMBv1/LLMNR настроены; интерфейсов NetBIOS нет. Нужна перезагрузка."
    } else {
        Write-Output ("[OK] Сеть укреплена. Интерфейсов: " + $n + ". ПЕРЕЗАГРУЗИСЬ, чтобы LLMNR и NetBIOS отключились.")
    }
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
