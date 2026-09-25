# NAME: 05 · Winget: полный аудит (только показ)
# DESC: Собирает всё про winget: команда, пакет, алиас, источники, кэши, метка. Только читает — пришли лог для разбора
# TAGS: 1
# ICON: ⚙️

$ErrorActionPreference = "Stop"

function Invoke-WithTimeout {
    param([string]$Exe, [string]$Arguments, [int]$TimeoutSec = 60)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = $null
    try { $p = [System.Diagnostics.Process]::Start($psi) }
    catch { return @{ Ok = $false; TimedOut = $false; Out = ""; Code = -1 } }
    try {
        $outTask = $null; $errTask = $null
        try { $outTask = $p.StandardOutput.ReadToEndAsync() } catch {}
        try { $errTask = $p.StandardError.ReadToEndAsync() } catch {}
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch {}
            try { $p.WaitForExit(5000) } catch {}
            return @{ Ok = $false; TimedOut = $true; Out = ""; Code = -1 }
        }
        $o = ''; $e = ''
        try { if ($outTask -and $outTask.Wait(2000)) { $o = [string]$outTask.Result } } catch {}
        try { if ($errTask -and $errTask.Wait(2000)) { $e = [string]$errTask.Result } } catch {}
        $c = 0
        try { $c = $p.ExitCode } catch {}
        return @{ Ok = ($c -eq 0); TimedOut = $false; Out = [string]$o; Error = [string]$e; Code = $c }
    } finally { try { $p.Dispose() } catch {} }
}

function Test-TrustedWingetAuditPath {
    param([string]$Path)
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
        $root = [System.IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'WindowsApps')).TrimEnd('\')
        if (-not $full.StartsWith($root + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
        $i = Get-Item -LiteralPath $full -Force -ErrorAction Stop
        if ($i.PSIsContainer -or (($i.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) { return $false }
        $s = Get-AuthenticodeSignature -LiteralPath $full -ErrorAction Stop
        return [bool]($s.Status -eq 'Valid' -and [string]$s.SignerCertificate.Subject -match '(?i)Microsoft')
    } catch { return $false }
}

function Get-TrustedWingetAuditPath {
    $c = @()
    try { foreach ($p in @(Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction Stop)) { if ($p.InstallLocation) { $c += (Join-Path ([string]$p.InstallLocation) 'winget.exe') } } } catch {}
    foreach ($p in $c) { if (Test-TrustedWingetAuditPath -Path $p) { return $p } }
    return ''
}

try {
    Write-Output "=== Аудит winget (только чтение) ==="
    Write-Output "[1/6] Команда:"
    try {
        $cmd = Get-Command winget -ErrorAction Stop
        if (Test-TrustedWingetAuditPath -Path $cmd.Source) { Write-Output ("[*] Проверенный winget найден: " + $cmd.Source) }
        else { Write-Output ("[!] PATH-ссылка не доверена: " + $cmd.Source) }
    } catch { Write-Output "[!] winget НЕТ в PATH." }

    Write-Output "[2/6] Пакет AppX:"
    try {
        $pkgs = @(Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -AllUsers -ErrorAction Stop)
        if ($pkgs.Count -eq 0) { Write-Output "[!] Пакет Microsoft.DesktopAppInstaller НЕ установлен." }
        foreach ($p in $pkgs) {
            Write-Output ("[*] " + $p.PackageFullName)
            Write-Output ("    InstallLocation есть: " + (Test-Path -LiteralPath $p.InstallLocation))
        }
    } catch {
        Write-Output ("[!] Список пакетов не прочитался (нужны права?): " + $_.Exception.Message)
        try {
            $p1 = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction Stop | Select-Object -First 1
            if ($p1) { Write-Output ("[*] Текущий юзер: " + $p1.PackageFullName) }
            else { Write-Output "[!] Пакет НЕ установлен у текущего юзера." }
        } catch { Write-Output "[!] Пакет НЕ установлен." }
    }

    Write-Output "[3/6] Образ (provisioned):"
    try {
        $provs = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq "Microsoft.DesktopAppInstaller" })
        if ($provs.Count -eq 0) { Write-Output "[*] В образе пакета нет (для новых юзеров не предустановлен)." }
        foreach ($pr in $provs) { Write-Output ("[*] В образе: " + $pr.PackageName) }
    } catch { Write-Output ("[!] Образ не прочитался: " + $_.Exception.Message) }

    Write-Output "[4/6] Алиас запуска:"
    $alias = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
    Write-Output ("[*] Алиас winget.exe есть: " + (Test-Path -LiteralPath $alias))
    $inPath = ($env:PATH -split ';' | Where-Object { $_ -like '*WindowsApps*' }).Count -gt 0
    Write-Output ("[*] WindowsApps в PATH: " + $inPath)
    Write-Output "[5/6] Данные и кэши:"
    foreach ($d in @(
        (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe"),
        (Join-Path $env:TEMP "WinGet"),
        (Join-Path $env:TEMP "winget-install")
    )) {
        Write-Output ("[*] " + $d + " есть: " + (Test-Path -LiteralPath $d))
    }
    $marker = $null
    try { if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\PotatoPC') { $marker = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\PotatoPC' -Name 'WingetInstalledByPotatoPC' -ErrorAction SilentlyContinue } } catch {}
    if ($marker) { Write-Output ("[*] Метка PotatoPC: " + [string]$marker.WingetInstalledByPotatoPC) }
    else { Write-Output "[*] Метки PotatoPC нет (ставил не наш скрипт или вручную)." }
    foreach ($fw in @("Microsoft.VCLibs", "Microsoft.UI.Xaml")) {
        try {
            $f = Get-AppxPackage -Name ($fw + "*") -ErrorAction Stop | Select-Object -First 1
            if ($f) { Write-Output ("[*] Фреймворк " + $fw + ": " + $f.Version) }
            else { Write-Output ("[!] Фреймворк " + $fw + " НЕ найден!") }
        } catch { Write-Output ("[!] Фреймворк " + $fw + " НЕ найден!") }
    }

    Write-Output "[6/6] Запуск и источники:"
    $auditWg = Get-TrustedWingetAuditPath
    if ([string]::IsNullOrWhiteSpace($auditWg)) { Write-Output "[!] Проверенный winget.exe не найден." }
    else {
        $wr = Invoke-WithTimeout -Exe $auditWg -Arguments "--version" -TimeoutSec 25
        if ($wr.TimedOut) { Write-Output "[!] winget --version ВИСИТ (убит по таймауту 25с)." }
        elseif (-not $wr.Ok) { Write-Output ("[!] winget --version код " + $wr.Code + " (нет winget или сломан).") }
        else {
            Write-Output ("[*] Версия: " + $wr.Out.Trim())
            $sr = Invoke-WithTimeout -Exe $auditWg -Arguments "source list" -TimeoutSec 60
            if ($sr.TimedOut) { Write-Output "[!] winget source list ВИСИТ." }
            elseif ($sr.Ok) {
                foreach ($ln in ($sr.Out -split "`r?`n" | Where-Object { $_ -match '\S' })) { Write-Output ("    " + $ln.Trim()) }
            } else { Write-Output ("[!] winget source list код " + $sr.Code) }
        }
    }
    Write-Output "[OK] Аудит закончен, ничего не менялось."
    exit 0
} catch {
    Write-Output ("[X] Ошибка аудита: " + $_)
    exit 1
}
