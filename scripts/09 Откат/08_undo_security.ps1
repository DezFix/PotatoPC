# NAME: Откат «Безопасности»: обновления, UAC, гость, автозапуск
# DESC: Снимает политики обновлений, возвращает UAC и автозапуск к исходным, включает гостевую запись. Брандмауэр не откатывается — его включение только усиливает защиту
# TAGS: 1
# ICON: ↩️
# UNDOFOR: 08

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    Write-Output "[*] Снимаю отложку крупных обновлений..."
    $w = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    foreach ($n in @("TargetReleaseVersion","TargetReleaseVersionInfo","DeferFeatureUpdates","DeferFeatureUpdatesPeriodInDays","DeferQualityUpdates","ExcludeWUDriversInQualityUpdate")) {
        try { Remove-ItemProperty -Path $w -Name $n -Force -ErrorAction Stop } catch {}
    }
    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    Start-Service wuauserv -ErrorAction SilentlyContinue
    if ((Get-Service -Name wuauserv -ErrorAction SilentlyContinue) -and (Get-Service -Name wuauserv).Status -ne 'Running') {
        Write-Output "[!] Служба wuauserv не запустилась - обновления не придут, проверь её вручную."
    }

    Write-Output "[*] Возвращаю UAC..."
    $backupDir = Join-Path $env:ProgramData 'PotatoPC\backups'
    $snap = @(Get-ChildItem -LiteralPath $backupDir -Filter 'uac-*.json' -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    if ($snap.Count -gt 0) {
        try {
            $data = Get-Content -LiteralPath $snap[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            $p = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
            if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
            Set-ItemProperty -LiteralPath $p -Name "EnableLUA" -Value ([int]$data.EnableLUA) -Type DWord -Force
            Write-Output ("[*] UAC возвращён по снимку " + $snap[0].Name + ".")
        } catch {
            Write-Output ("[!] Снимок UAC не применился: " + $_.Exception.Message)
        }
    } else {
        Write-Output "[=] Снимок UAC не найден - оставляю как есть."
    }

    # Гостя включаем только если он был включён до PotatoPC: по умолчанию в
    # Windows он выключен, и старый откат открывал его без спроса.
    Write-Output "[*] Гостевая запись..."
    $gsnap = @(Get-ChildItem -LiteralPath $backupDir -Filter 'guest-*.json' -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime | Select-Object -First 1)
    $guest = Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.SID.Value -like 'S-1-5-21-*-501' } | Select-Object -First 1
    if ($guest -and $gsnap.Count -gt 0) {
        try {
            $g = Get-Content -LiteralPath $gsnap[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([bool]$g.Enabled) { Enable-LocalUser -SID $guest.SID -ErrorAction Stop; Write-Output "[*] Гостевая запись включена, как было." }
            else { Write-Output "[=] Гость был выключен и до PotatoPC - оставляю выключенным." }
        } catch { Write-Output ("[!] Гостевая запись: " + $_.Exception.Message) }
    } else {
        Write-Output "[=] Снимка гостевой записи нет - оставляю как есть (выключенный гость - заводское состояние)."
    }

    Write-Output "[*] Блокировка нежелательных программ (PUA)..."
    $psnap = @(Get-ChildItem -LiteralPath $backupDir -Filter 'pua-*.json' -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime | Select-Object -First 1)
    if ($psnap.Count -gt 0) {
        try {
            $pv = [int](Get-Content -LiteralPath $psnap[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json).PUAProtection
            Set-MpPreference -PUAProtection $pv -ErrorAction Stop
            Write-Output ("[*] PUAProtection = " + $pv)
        } catch { Write-Output ("[!] PUA: " + $_.Exception.Message) }
    }

    Write-Output "[*] Возвращаю автозапуск..."
    foreach ($p in @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer", "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer")) {
        if (Test-Path -LiteralPath $p) {
            try { Remove-ItemProperty -LiteralPath $p -Name "NoDriveTypeAutoRun" -Force -ErrorAction Stop } catch {}
        }
    }

    Write-Output "[OK] Раздел Безопасность откачен. Перезагрузись."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
