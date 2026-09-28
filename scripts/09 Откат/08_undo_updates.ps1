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
    if ((Get-Service -Name wuauserv -ErrorAction SilentlyContinue) -and (Get-Service -Name wuauserv).Status -ne 'Running') {
        Write-Output "[!] Служба wuauserv не запустилась - обновления не придут, проверь её вручную."
    }
    Write-Output "[*] Блок больших версий снят."

    $marker = $null
    try {
        $key = 'HKLM:\SOFTWARE\PotatoPC'
        if (Test-Path -LiteralPath $key) { $marker = Get-ItemProperty -LiteralPath $key -Name 'WingetInstalledByPotatoPC' -ErrorAction SilentlyContinue }
    } catch {}
    $hasPotatoMarker = ($null -ne $marker -and -not [string]::IsNullOrWhiteSpace([string]$marker.WingetInstalledByPotatoPC))
    $inbox = 0
    try {
        $key = 'HKLM:\SOFTWARE\PotatoPC'
        if (Test-Path -LiteralPath $key) {
            $ib = Get-ItemProperty -LiteralPath $key -Name 'WingetInboxPreexisted' -ErrorAction SilentlyContinue
            if ($null -ne $ib) { $inbox = [int]$ib.WingetInboxPreexisted }
        }
    } catch {}
    $appxFailed = $false
    if ($hasPotatoMarker) {
        if ($inbox -eq 1) {
            # Winget был встроен в образ: снести его - значит оставить машину
            # вовсе без winget, то есть хуже исходного состояния. В этом случае
            # сносим только ту копию, что ставил PotatoPC.
            Write-Output "[*] Winget был встроенным - уберу только копию PotatoPC, из образа не трогаю."
        } else {
            Write-Output "[*] Winget ставил PotatoPC — сношу начисто..."
        }
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
        if ($inbox -eq 1) {
            if ($provs.Count -gt 0) { Write-Output "[*] Пакет встроен в образ - оставляю, winget останется доступен." }
        } else {
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
        }
        try {
            $remaining = @(Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -AllUsers -ErrorAction Stop)
            if ($inbox -ne 1) {
                $remaining += @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq "Microsoft.DesktopAppInstaller" })
            }
            if ($remaining.Count -gt 0 -and $inbox -ne 1) { throw "часть пакетов AppX осталась" }
            if ($inbox -eq 1 -and $remaining.Count -eq 0) { Write-Output "[!] Встроенный winget не вернулся - возможно, нужен перезапуск виндоуса." }
        } catch {
            $appxFailed = $true
            Write-Output ("[!] Проверка AppX не пройдена: " + $_)
        }
        if (-not $removed) { Write-Output "[=] Пакета уже нет (снесён вручную?)." }
        if (-not $appxFailed) {
            try { Remove-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\PotatoPC' -Name 'WingetInstalledByPotatoPC' -Force -ErrorAction Stop } catch {}
            try { Remove-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\PotatoPC' -Name 'WingetInboxPreexisted' -Force -ErrorAction Stop } catch {}
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
