# NAME: Откат обновлений: снять блок новых версий
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

    # Метку ищем по всем профилям: откат идёт из-под админа, а ставил обычный юзер
    $markers = @()
    try {
        $markers += @(Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Join-Path $_.FullName "AppData\Local\PotatoPC\winget-by-potatopc.txt"
        } | Where-Object { Test-Path -LiteralPath $_ })
        $own = Join-Path $env:LOCALAPPDATA "PotatoPC\winget-by-potatopc.txt"
        if ((Test-Path -LiteralPath $own) -and ($markers -notcontains $own)) { $markers += $own }
    } catch {}
    if (@($markers).Count -gt 0) {
        Write-Output "[*] Winget ставил PotatoPC — сношу начисто..."
        $removed = $false
        foreach ($p in @(Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -AllUsers -ErrorAction SilentlyContinue)) {
            try {
                Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
                Write-Output ("[*] Снесён пакет: " + $p.PackageFullName)
                $removed = $true
            } catch { Write-Output ("[!] Пакет не снесся: " + $_) }
        }
        foreach ($prov in @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq "Microsoft.DesktopAppInstaller" })) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop
                Write-Output "[*] Убран из образа системы."
                $removed = $true
            } catch { Write-Output ("[!] Из образа не убрался: " + $_) }
        }
        if (-not $removed) { Write-Output "[=] Пакета уже нет (снесён вручную?)." }
        foreach ($m in @($markers)) { try { Remove-Item -LiteralPath $m -Force -ErrorAction SilentlyContinue } catch {} }
    } else {
        Write-Output "[=] Winget ставил не PotatoPC (встроен или вручную) — не трогаю."
        Write-Output "[*] Удалить вручную при желании: Параметры -> Приложения -> Установщик приложений."
    }
    Write-Output "[OK] Обновления как были."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
