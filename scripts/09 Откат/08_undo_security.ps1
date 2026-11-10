# NAME: 08 · Откат «Безопасности»: обновления, UAC, гость, автозапуск
# DESC: Снимает политики обновлений, возвращает UAC и автозапуск к исходным, включает гостевую запись. Брандмауэр не откатывается — его включение только усиливает защиту
# TAGS: 1
# ICON: ↩️

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    Write-Output "[*] Снимаю блок новых версий..."
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
            Write-Output "[*] UAC возвращён по снимку " + $snap[0].Name + "."
        } catch {
            Write-Output ("[!] Снимок UAC не применился: " + $_.Exception.Message)
        }
    } else {
        Write-Output "[=] Снимок UAC не найден - оставляю как есть."
    }

    Write-Output "[*] Включаю гостевую запись..."
    $guest = Get-LocalUser -Name Guest -ErrorAction SilentlyContinue
    if ($guest) {
        try { Enable-LocalUser -Name Guest -ErrorAction Stop; Write-Output "[*] Гостевая запись включена." }
        catch { Write-Output ("[!] Гостевую запись не включить: " + $_.Exception.Message) }
    } else {
        Write-Output "[=] Гостевая запись не найдена."
    }

    Write-Output "[*] Возвращаю автозапуск..."
    $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    if (Test-Path -LiteralPath $p) {
        try { Remove-ItemProperty -LiteralPath $p -Name "NoDriveTypeAutoRun" -Force -ErrorAction Stop } catch {}
    }

    Write-Output "[OK] Раздел Безопасность откачен. Перезагрузись."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
