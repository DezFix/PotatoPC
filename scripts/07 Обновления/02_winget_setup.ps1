# NAME: 02 · Winget: снос под чистую и установка (не Store!)
# DESC: Убивает процессы, сносит пакет/образ/данные, ставит заново с GitHub. Каждый шаг с таймаутом — не виснет. Нужен вкладке «Приложения»
# TAGS: 2
# ICON: 📦
# PRESET: potato, office, game

$ErrorActionPreference = "Stop"

function Invoke-WithTimeout {
    # Запуск с таймаутом: зависший процесс убивается, а не висит вечно.
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
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch {}
            try { $p.WaitForExit(5000) } catch {}
            return @{ Ok = $false; TimedOut = $true; Out = ""; Code = -1 }
        }
        $o = ""
        try { $o = $p.StandardOutput.ReadToEnd() } catch {}
        $c = 0
        try { $c = $p.ExitCode } catch {}
        return @{ Ok = ($c -eq 0); TimedOut = $false; Out = [string]$o; Code = $c }
    } finally { try { $p.Dispose() } catch {} }
}

function Install-AppxWithTimeout {
    # Add-AppxPackage в джобе: зависший Store не вешает скрипт.
    param([string]$Path, [int]$TimeoutSec = 300)
    $j = $null
    try { $j = Start-Job -ScriptBlock { param($p) Add-AppxPackage -Path $p -ForceApplicationShutdown -ErrorAction Stop } -ArgumentList $Path -ErrorAction Stop }
    catch { throw ("Не запустился установщик пакетов: " + $_) }
    try {
        $done = Wait-Job $j -Timeout $TimeoutSec
        if (-not $done) { throw ("Add-AppxPackage завис ${TimeoutSec}с (Store подвис?) — убиваю.") }
        if ($j.State -eq 'Failed') {
            $reason = $null
            try { $reason = $j.ChildJobs[0].JobStateInfo.Reason } catch {}
            throw ("Пакет не встал: " + $(if ($reason) { $reason.Message } else { $j.State }))
        }
        try { [void](Receive-Job $j -ErrorAction SilentlyContinue) } catch {}
    } finally {
        try { Stop-Job $j -ErrorAction SilentlyContinue } catch {}
        try { Remove-Job $j -Force -ErrorAction SilentlyContinue } catch {}
    }
}

function Get-WingetVersion {
    # Версия с таймаутом: сломанный winget вешает обычный вызов навсегда.
    param([int]$TimeoutSec = 25)
    try {
        $cmd = Get-Command winget -ErrorAction Stop
        $r = Invoke-WithTimeout -Exe $cmd.Source -Arguments "--version" -TimeoutSec $TimeoutSec
        if ($r.Ok -and -not [string]::IsNullOrWhiteSpace($r.Out)) { return $r.Out.Trim() }
        if ($r.TimedOut) { Write-Output "[!] winget висит — буду сносить." }
    } catch {}
    return ""
}

function Repair-WingetSources {
    # Чинит источники: update, при неудаче — сброс двух штатных + update.
    param([string]$Wg)
    $r = Invoke-WithTimeout -Exe $Wg -Arguments "source update --accept-source-agreements" -TimeoutSec 120
    if ($r.Ok) { Write-Output "[*] Источники обновлены."; return $true }
    if ($r.TimedOut) { Write-Output "[!] Источники зависли — сбрасываю штатные..." }
    else { Write-Output "[*] Источники битые — сбрасываю штатные..." }
    foreach ($s in @("msstore", "winget")) {
        try {
            $rr = Invoke-WithTimeout -Exe $Wg -Arguments ("source reset " + $s + " --force") -TimeoutSec 60
            if ($rr.TimedOut) { Write-Output ("[!] Сброс $s завис — пропускаю.") }
        } catch {}
    }
    $r2 = Invoke-WithTimeout -Exe $Wg -Arguments "source update --accept-source-agreements" -TimeoutSec 120
    if ($r2.Ok) { Write-Output "[*] Источники обновлены после сброса."; return $true }
    Write-Output "[!] Источники не чинятся."
    return $false
}

function Remove-WingetClean {
    # Снос под чистую: процессы, пакет у всех, образ, данные и кэш.
    Write-Output "[*] Сношу winget под чистую..."
    try { Stop-Process -Name "winget" -Force -ErrorAction SilentlyContinue } catch {}
    foreach ($p in @(Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -AllUsers -ErrorAction SilentlyContinue)) {
        try {
            Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
            Write-Output ("[*] Снесён пакет: " + $p.PackageFullName)
        } catch { Write-Output ("[!] Пакет не снесся: " + $_.Exception.Message) }
    }
    foreach ($prov in @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq "Microsoft.DesktopAppInstaller" })) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop
            Write-Output "[*] Убран из образа системы."
        } catch { Write-Output ("[!] Из образа не убрался: " + $_.Exception.Message) }
    }
    foreach ($d in @(
        (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe"),
        (Join-Path $env:TEMP "WinGet"),
        (Join-Path $env:TEMP "winget-install")
    )) {
        try {
            if (Test-Path -LiteralPath $d) {
                Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction Stop
                Write-Output ("[*] Удалён кэш: " + $d)
            }
        } catch { Write-Output ("[!] Не удалилось: " + $d) }
    }
}

function Write-WingetMarker {
    param([string]$Ver)
    try {
        $md = Join-Path $env:LOCALAPPDATA "PotatoPC"
        if (-not (Test-Path $md)) { New-Item -ItemType Directory -Path $md -Force | Out-Null }
        ("winget $Ver installed by PotatoPC " + (Get-Date -Format "yyyy-MM-dd HH:mm")) | Out-File -LiteralPath (Join-Path $md "winget-by-potatopc.txt") -Encoding UTF8 -Force
    } catch {}
}

try {
    $cur = Get-WingetVersion -TimeoutSec 25
    if ($cur) {
        Write-Output ("[*] Winget отзывается: " + $cur + ". Проверяю источники...")
        $wgSrc = (Get-Command winget -ErrorAction Stop).Source
        if (Repair-WingetSources -Wg $wgSrc) {
            Write-Output ("[OK] Winget в порядке: " + $cur)
            exit 0
        }
        Write-Output "[*] Ремонт не помог — сношу и ставлю заново..."
    } else {
        Write-Output "[*] Winget нет или висит — сношу остатки и ставлю заново..."
    }

    Remove-WingetClean

    $arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
    $tmp = Join-Path $env:TEMP "winget-install"
    if (-not (Test-Path $tmp)) { New-Item -ItemType Directory -Path $tmp -Force | Out-Null }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $xaml = Join-Path $tmp "ui.xaml.appx"
    $libs = Join-Path $tmp "vclibs.appx"
    try { Invoke-WebRequest "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.$arch.appx" -OutFile $xaml -UseBasicParsing -TimeoutSec 180 -ErrorAction Stop }
    catch { Write-Output ("[!] Зависимость XAML не скачалась, иду дальше: " + $_.Exception.Message) }
    try { Invoke-WebRequest "https://aka.ms/Microsoft.VCLibs.$arch.14.00.Desktop.appx" -OutFile $libs -UseBasicParsing -TimeoutSec 180 -ErrorAction Stop }
    catch { Write-Output ("[!] Зависимость VCLibs не скачалась, иду дальше: " + $_.Exception.Message) }
    if (Test-Path -LiteralPath $xaml) {
        try { Install-AppxWithTimeout -Path $xaml -TimeoutSec 180 }
        catch { Write-Output ("[!] XAML: " + $_) }
    }
    if (Test-Path -LiteralPath $libs) {
        try { Install-AppxWithTimeout -Path $libs -TimeoutSec 180 }
        catch { Write-Output ("[!] VCLibs: " + $_) }
    }

    $url = ""
    try {
        $rel = Invoke-RestMethod "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -TimeoutSec 60 -ErrorAction Stop
        $url = ($rel.assets | Where-Object { $_.name -like "Microsoft.DesktopAppInstaller_*.msixbundle" } | Select-Object -First 1).browser_download_url
    } catch { Write-Output ("[!] API GitHub недоступен (лимит?): " + $_.Exception.Message) }
    if ([string]::IsNullOrWhiteSpace($url)) {
        $url = "https://github.com/microsoft/winget-cli/releases/download/v1.29.290/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        Write-Output "[*] Беру запасную версию v1.29.290 напрямую."
    }
    $pkg = Join-Path $tmp "winget.msixbundle"
    Invoke-WebRequest $url -OutFile $pkg -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop
    Install-AppxWithTimeout -Path $pkg -TimeoutSec 300

    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

    $okV = Get-WingetVersion -TimeoutSec 40
    if ([string]::IsNullOrWhiteSpace($okV)) {
        try { $p = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction Stop | Select-Object -First 1; if ($p) { $okV = "пакет " + [string]$p.Version } } catch {}
    }
    if ([string]::IsNullOrWhiteSpace($okV)) {
        Write-Output "[X] Поставил, но winget не отзывается — перезайди в систему и проверь командой winget."
        Write-Output "[*] Если снова глухо — ставь «App Installer» из Microsoft Store вручную."
        exit 1
    }
    Write-WingetMarker -Ver $okV
    try {
        $wg2 = (Get-Command winget -ErrorAction Stop).Source
        [void](Repair-WingetSources -Wg $wg2)
    } catch {}
    Write-Output ("[OK] Winget готов: " + $okV)
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
