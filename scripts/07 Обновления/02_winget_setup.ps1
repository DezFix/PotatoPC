# NAME: 02 · Winget: снос под чистую и установка (не Store!)
# DESC: Убивает процессы, сносит пакет/образ/данные, ставит заново с GitHub. Каждый шаг с таймаутом — не виснет. Нужен вкладке «Приложения»
# TAGS: 2
# ICON: 📦
# PRESET: potato, office, game

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

function Invoke-AppxJob {
    # Любая AppX/DISM-операция с таймаутом: зависший servicing убивается, а не висит.
    param([scriptblock]$Code, [int]$TimeoutSec = 300, [string]$What = "операция", [object[]]$JobArgs = @())
    $j = $null
    try { $j = Start-Job -ScriptBlock $Code -ArgumentList $JobArgs -ErrorAction Stop }
    catch { throw ("Не запустился фон для «" + $What + "»: " + $_) }
    try {
        if (-not (Wait-Job $j -Timeout $TimeoutSec)) { throw ("«" + $What + "» завис " + $TimeoutSec + "с — убиваю.") }
        if ($j.State -eq 'Failed') {
            $reason = $null
            try { $reason = $j.ChildJobs[0].JobStateInfo.Reason } catch {}
            throw ("«" + $What + "»: " + $(if ($reason) { $reason.Message } else { $j.State }))
        }
        return (Receive-Job $j -ErrorAction SilentlyContinue)
    } finally {
        try { Stop-Job $j -ErrorAction SilentlyContinue } catch {}
        try { Remove-Job $j -Force -ErrorAction SilentlyContinue } catch {}
    }
}

function Install-AppxWithTimeout {
    # Установка пакета с таймаутом (зависший Store не вешает скрипт).
    param([string]$Path, [int]$TimeoutSec = 300)
    Invoke-AppxJob -Code { param($p) Add-AppxPackage -Path $p -ForceApplicationShutdown -ErrorAction Stop } -TimeoutSec $TimeoutSec -What ("установка " + (Split-Path $Path -Leaf)) -JobArgs @($Path) | Out-Null
}

function Test-TrustedWingetPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
        $root = [System.IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'WindowsApps')).TrimEnd('\')
        if (-not $full.StartsWith($root + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
        $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
        if ($item.PSIsContainer -or (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) { return $false }
        $sig = Get-AuthenticodeSignature -LiteralPath $full -ErrorAction Stop
        return [bool]($sig.Status -eq 'Valid' -and [string]$sig.SignerCertificate.Subject -match '(?i)Microsoft')
    } catch { return $false }
}

function Get-TrustedWingetPath {
    $candidates = @()
    try { foreach ($p in @(Get-AppxPackage -Name Microsoft.DesktopAppInstaller -AllUsers -ErrorAction Stop)) { if ($p.InstallLocation) { $candidates += (Join-Path ([string]$p.InstallLocation) 'winget.exe') } } } catch {}
    $candidates += "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
    foreach ($candidate in $candidates) {
        if ($candidate -like '*`*') {
            try { $found = Get-ChildItem -Path $candidate -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1; if ($found -and (Test-TrustedWingetPath -Path $found.FullName)) { return $found.FullName } } catch {}
        } elseif (Test-TrustedWingetPath -Path $candidate) { return $candidate }
    }
    return ''
}

function Get-WingetTrustState {
    $packageFound = $false
    try {
        $packages = @(Get-AppxPackage -Name Microsoft.DesktopAppInstaller -AllUsers -ErrorAction Stop)
        $packageFound = ($packages.Count -gt 0)
    } catch { return [pscustomobject]@{ State = 'Error'; Path = ''; Error = $_.Exception.Message } }
    $path = Get-TrustedWingetPath
    if (-not [string]::IsNullOrWhiteSpace($path)) { return [pscustomobject]@{ State = 'Trusted'; Path = $path; Error = '' } }
    if ($packageFound) { return [pscustomobject]@{ State = 'Error'; Path = ''; Error = 'Установленный winget не прошёл проверку подписи' } }
    return [pscustomobject]@{ State = 'Missing'; Path = ''; Error = '' }
}

function Get-WingetVersion {
    param([int]$TimeoutSec = 25)
    try {
        $exe = Get-TrustedWingetPath
        if ([string]::IsNullOrWhiteSpace($exe)) { return "" }
        $r = Invoke-WithTimeout -Exe $exe -Arguments "--version" -TimeoutSec $TimeoutSec
        if ($r.Ok -and -not [string]::IsNullOrWhiteSpace($r.Out)) { return $r.Out.Trim() }
        if ($r.TimedOut) { Write-Verbose "winget завис — будет сброшен." }
    } catch {}
    return ""
}

function Save-UrlWithProgress {
    # Скачивание с видимым прогрессом: на медленном канале видно движение, а не "вис".
    param([string]$Url, [string]$OutFile, [int]$TimeoutSec = 600)
    try { Add-Type -AssemblyName System.Net.Http -ErrorAction Stop } catch {}
    $client = $null
    try {
        $h = New-Object System.Net.Http.HttpClientHandler
        $client = New-Object System.Net.Http.HttpClient($h)
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
        $resp = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
        [void]$resp.EnsureSuccessStatusCode()
        $total = 0L
        try { $total = [long]$resp.Content.Headers.ContentLength } catch {}
        $stream = $resp.Content.ReadAsStreamAsync().Result
        $fs = [System.IO.File]::OpenWrite($OutFile)
        try {
            $buf = New-Object byte[] 65536
            $read = 0L; $lastLog = 0L
            while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
                $fs.Write($buf, 0, $n)
                $read += $n
                if (($read - $lastLog) -ge 5MB) {
                    $lastLog = $read
                    if ($total -gt 0) { Write-Output ("[*] Качаю: {0} МБ из {1} МБ" -f [math]::Round($read/1MB,1), [math]::Round($total/1MB,1)) }
                    else { Write-Output ("[*] Качаю: {0} МБ..." -f [math]::Round($read/1MB,1)) }
                }
            }
        } finally { try { $fs.Dispose() } catch {}; try { $stream.Dispose() } catch {} }
        if ($read -lt 1MB) { Write-Output ("[*] Скачано: {0} КБ" -f [math]::Round($read/1KB,1)) }
        else { Write-Output ("[*] Скачано: {0} МБ" -f [math]::Round($read/1MB,1)) }
        return [long]$read
    } finally { try { if ($client) { $client.Dispose() }; } catch {} }
}

function Repair-WingetSources {
    # Чинит источники: update, при неудаче — сброс двух штатных + update.
    param([string]$Wg)
    $r = Invoke-WithTimeout -Exe $Wg -Arguments "source update" -TimeoutSec 120
    if ($r.Ok) { Write-Host "[*] Источники обновлены."; return $true }
    if ($r.TimedOut) { Write-Host "[!] Источники зависли — сбрасываю штатные..." }
    else { Write-Host "[*] Источники битые — сбрасываю штатные..." }
    foreach ($s in @("msstore", "winget")) {
        try {
            $rr = Invoke-WithTimeout -Exe $Wg -Arguments ("source reset " + $s + " --force") -TimeoutSec 60
            if ($rr.TimedOut) { Write-Host ("[!] Сброс $s завис — пропускаю.") }
        } catch {}
    }
    $r2 = Invoke-WithTimeout -Exe $Wg -Arguments "source update" -TimeoutSec 120
    if ($r2.Ok) { Write-Host "[*] Источники обновлены после сброса."; return $true }
    Write-Host "[!] Источники не чинятся."
    return $false
}

function Remove-WingetClean {
    # Снос под чистую: процессы, пакет у всех, образ, данные и кэш.
    # Долгие шаги тоже в джобах с таймаутом — виснуть негде.
    Write-Output "[2/7] Сношу winget под чистую..."
    try { Stop-Process -Name "winget" -Force -ErrorAction SilentlyContinue } catch {}
    try {
        $pkgs = @(Invoke-AppxJob -Code { Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -AllUsers -ErrorAction Stop | Select-Object -ExpandProperty PackageFullName } -TimeoutSec 120 -What "поиск пакета")
    } catch { Write-Output ("[!] Поиск пакета: " + $_); $pkgs = @() }
    foreach ($full in @($pkgs | Where-Object { $_ })) {
        try {
            Invoke-AppxJob -Code { param($f) Remove-AppxPackage -Package $f -AllUsers -ErrorAction Stop } -TimeoutSec 300 -What "снос пакета" -JobArgs @($full)
            Write-Output ("[*] Снесён пакет: " + $full)
        } catch { Write-Output ("[!] Пакет не снесся, ставлю поверх: " + $_) }
    }
    try {
        $provs = @(Invoke-AppxJob -Code { Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq "Microsoft.DesktopAppInstaller" } | Select-Object -ExpandProperty PackageName } -TimeoutSec 120 -What "поиск в образе")
    } catch { Write-Output ("[!] Образ не прочитался: " + $_); $provs = @() }
    foreach ($pn in @($provs | Where-Object { $_ })) {
        try {
            Invoke-AppxJob -Code { param($n) Remove-AppxProvisionedPackage -Online -PackageName $n -ErrorAction Stop } -TimeoutSec 300 -What "уборка образа" -JobArgs @($pn)
            Write-Output "[*] Убран из образа системы."
        } catch { Write-Output ("[!] Из образа не убрался, иду дальше: " + $_) }
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
        $key = 'HKLM:\SOFTWARE\PotatoPC'
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        New-ItemProperty -LiteralPath $key -Name 'WingetInstalledByPotatoPC' -PropertyType String -Value ("$Ver|" + (Get-Date -Format "yyyy-MM-dd HH:mm")) -Force | Out-Null
    } catch { throw ("Не удалось записать системную метку установки: " + $_) }
}

try {
    Write-Output "[1/7] Проверяю текущий winget..."
    $trustState = Get-WingetTrustState
    if ($trustState.State -eq 'Error') { throw ("Проверка winget не выполнена: " + $trustState.Error) }
    $cur = Get-WingetVersion -TimeoutSec 25
    if ($cur) {
        Write-Output ("[*] Winget отзывается: " + $cur + ". Проверяю источники...")
        $wgSrc = Get-TrustedWingetPath
        if (-not [string]::IsNullOrWhiteSpace($wgSrc) -and (Repair-WingetSources -Wg $wgSrc)) {
            Write-Output ("[OK] Winget в порядке: " + $cur)
            exit 0
        }
        Write-Output "[*] Ремонт не помог — сношу и ставлю заново..."
    } else {
        Write-Output "[*] Winget нет или висит — сношу остатки и ставлю заново..."
    }

    Remove-WingetClean

    $arch = "x64"
    try {
        $oa = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
        if ("$oa" -eq "Arm64") { $arch = "arm64" }
        elseif ("$oa" -eq "X86") { $arch = "x86" }
    } catch { if (-not [Environment]::Is64BitOperatingSystem) { $arch = "x86" } }
    $tmp = Join-Path $env:TEMP "winget-install"
    if (-not (Test-Path $tmp)) { New-Item -ItemType Directory -Path $tmp -Force | Out-Null }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Output "[3/7] Качаю официальные зависимости версии..."
    $url = ""
    $depUrl = ""
    try {
        $rel = Invoke-RestMethod "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -TimeoutSec 60 -ErrorAction Stop
        $url = ($rel.assets | Where-Object { $_.name -like "Microsoft.DesktopAppInstaller_*.msixbundle" } | Select-Object -First 1).browser_download_url
        $depUrl = ($rel.assets | Where-Object { $_.name -eq "DesktopAppInstaller_Dependencies.zip" } | Select-Object -First 1).browser_download_url
    } catch { Write-Output ("[!] API GitHub недоступен (лимит?): " + $_.Exception.Message) }
    if ([string]::IsNullOrWhiteSpace($url)) {
        $url = "https://github.com/microsoft/winget-cli/releases/download/v1.29.290/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        $depUrl = "https://github.com/microsoft/winget-cli/releases/download/v1.29.290/DesktopAppInstaller_Dependencies.zip"
        Write-Output "[*] Беру запасную версию v1.29.290 напрямую."
    }
    $depOk = $false
    try {
        $depZip = Join-Path $tmp "deps.zip"
        $depDir = Join-Path $tmp "deps"
        [void](Save-UrlWithProgress -Url $depUrl -OutFile $depZip -TimeoutSec 600)
        if (Test-Path -LiteralPath $depDir) { Remove-Item -LiteralPath $depDir -Recurse -Force -ErrorAction SilentlyContinue }
        Expand-Archive -LiteralPath $depZip -DestinationPath $depDir -Force -ErrorAction Stop
        $archDir = Join-Path $depDir $arch
        if (-not (Test-Path -LiteralPath $archDir)) { $archDir = $depDir }
        foreach ($a in @(Get-ChildItem -LiteralPath $archDir -Filter "*.appx" -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
            try {
                Install-AppxWithTimeout -Path $a.FullName -TimeoutSec 180
                Write-Output ("[*] Зависимость встала: " + $a.Name)
            } catch { Write-Output ("[!] Зависимость " + $a.Name + ": " + $_) }
        }
        $depOk = $true
    } catch { Write-Output ("[!] Официальный пак не встал: " + $_.Exception.Message) }
    if (-not $depOk) {
        Write-Output "[*] Пробую старые прямые ссылки (XAML + VCLibs)..."
        $xaml = Join-Path $tmp "ui.xaml.appx"
        $libs = Join-Path $tmp "vclibs.appx"
        try { [void](Save-UrlWithProgress -Url "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.$arch.appx" -OutFile $xaml -TimeoutSec 300) }
        catch { Write-Output ("[!] Зависимость XAML не скачалась, иду дальше: " + $_.Exception.Message) }
        try { [void](Save-UrlWithProgress -Url "https://aka.ms/Microsoft.VCLibs.$arch.14.00.Desktop.appx" -OutFile $libs -TimeoutSec 300) }
        catch { Write-Output ("[!] Зависимость VCLibs не скачалась, иду дальше: " + $_.Exception.Message) }
        if (Test-Path -LiteralPath $xaml) {
            try { Install-AppxWithTimeout -Path $xaml -TimeoutSec 180 }
            catch { Write-Output ("[!] XAML: " + $_) }
        }
        if (Test-Path -LiteralPath $libs) {
            try { Install-AppxWithTimeout -Path $libs -TimeoutSec 180 }
            catch { Write-Output ("[!] VCLibs: " + $_) }
        }
    }

    $pkg = Join-Path $tmp "winget.msixbundle"
    Write-Output "[4/7] Качаю пакет winget..."
    [void](Save-UrlWithProgress -Url $url -OutFile $pkg -TimeoutSec 900)
    $pkgSize = 0
    try { $pkgSize = (Get-Item -LiteralPath $pkg -ErrorAction Stop).Length } catch {}
    Write-Output ("[*] Скачано байт: " + $pkgSize)
    if ($pkgSize -lt 5MB) { throw "Файл пакета подозрительно мал ($pkgSize байт) — докачка оборвалась, проверь интернет." }
    Write-Output "[5/7] Устанавливаю пакет..."
    Install-AppxWithTimeout -Path $pkg -TimeoutSec 300

    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

    Write-Output "[6/7] Проверяю установку..."
    $finalTrust = Get-WingetTrustState
    if ($finalTrust.State -ne 'Trusted') { throw ("Установленный winget не прошёл проверку: " + $finalTrust.Error) }
    $okV = Get-WingetVersion -TimeoutSec 40
    if ([string]::IsNullOrWhiteSpace($okV)) {
        Write-Output "[X] Поставил, но проверенный winget не отвечает — перезайди в систему и проверь вручную."
        exit 1
    }
    Write-WingetMarker -Ver $okV
    Write-Output "[7/7] Настраиваю источники..."
    try { [void](Repair-WingetSources -Wg ([string]$finalTrust.Path)) } catch {}
    Write-Output ("[OK] Winget готов: " + $okV)
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
