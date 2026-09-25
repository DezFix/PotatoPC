# NAME: 08 · Откат обновлений: снять блок новых версий
# DESC: Удаляет политики TargetReleaseVersion/Defer* + сносит winget, только если его ставил PotatoPC. Чужой/встроенный winget не трогает
# TAGS: 2
# ICON: ↩️

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $w = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    foreach ($n in @("TargetReleaseVersion","TargetReleaseVersionInfo","DeferFeatureUpdates","DeferFeatureUpdatesPeriodInDays","DeferQualityUpdates","ExcludeWUDriversInQualityUpdate")) {
        try { Remove-ItemProperty -Path $w -Name $n -Force -ErrorAction Stop } catch {}
    }
    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    Start-Service wuauserv -ErrorAction SilentlyContinue
    Write-Output "[*] Блок больших версий снят."

    $marker = $null
    try {
        $key = 'HKLM:\SOFTWARE\PotatoPC'
        if (Test-Path -LiteralPath $key) { $marker = Get-ItemProperty -LiteralPath $key -Name 'WingetInstalledByPotatoPC' -ErrorAction SilentlyContinue }
    } catch {}
    $hasPotatoMarker = ($null -ne $marker -and -not [string]::IsNullOrWhiteSpace([string]$marker.WingetInstalledByPotatoPC))
    $appxFailed = $false
    if ($hasPotatoMarker) {
        Write-Output "[*] Winget ставил PotatoPC — сношу начисто..."
        $removed = $false
        try {
            $pkgs = @(Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -AllUsers -ErrorAction Stop)
        } catch {
            $appxFailed = $true
            $pkgs = @()
            Write-Output ("[!] Пакеты AppX не прочитались: " + $_)
        }
        foreach ($p in $pkgs) {
            try {
                Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
                Write-Output ("[*] Снесён пакет: " + $p.PackageFullName)
                $removed = $true
            } catch {
                $appxFailed = $true
                Write-Output ("[!] Пакет не снесся: " + $_)
            }
        }
        try {
            $provs = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq "Microsoft.DesktopAppInstaller" })
        } catch {
            $appxFailed = $true
            $provs = @()
            Write-Output ("[!] Пакеты образа не прочитались: " + $_)
        }
        foreach ($prov in $provs) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop
                Write-Output "[*] Убран из образа системы."
                $removed = $true
            } catch {
                $appxFailed = $true
                Write-Output ("[!] Из образа не убрался: " + $_)
            }
        }
        try {
            $remaining = @(Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -AllUsers -ErrorAction Stop)
            $remaining += @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq "Microsoft.DesktopAppInstaller" })
            if ($remaining.Count -gt 0) { throw "часть пакетов AppX осталась" }
        } catch {
            $appxFailed = $true
            Write-Output ("[!] Проверка AppX не пройдена: " + $_)
        }
        if (-not $removed) { Write-Output "[=] Пакета уже нет (снесён вручную?)." }
        if (-not $appxFailed) {
            try { Remove-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\PotatoPC' -Name 'WingetInstalledByPotatoPC' -Force -ErrorAction Stop }
            catch { $appxFailed = $true; Write-Output ("[!] Системную метку не удалил: " + $_) }
        }
    } else {
        Write-Output "[=] Winget ставил не PotatoPC (встроен или вручную) — не трогаю."
        Write-Output "[*] Удалить вручную при желании: Параметры -> Приложения -> Установщик приложений."
    }
    if ($appxFailed) {
        Write-Output "[X] Обновления откачены частично."
        exit 1
    }
    Write-Output "[OK] Обновления как были."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
