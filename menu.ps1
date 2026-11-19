<#
.SYNOPSIS
    PotatoPC v7 - speed-up, cleanup and protection for Windows on weak PCs.
.DESCRIPTION
    Local:    powershell -STA -NoProfile -ExecutionPolicy Bypass -File menu.ps1
    By link:  irm https://raw.githubusercontent.com/DezFix/PotatoPC/main/menu.ps1 | iex
    This file must stay pure ASCII without a BOM: with "irm | iex" a BOM becomes
    an invisible character before "<#" and PowerShell refuses to run the script.
    Russian texts are stored as \uXXXX escapes and decoded by T.
#>
function T([string]$s) { return [regex]::Unescape($s) }

# Branch to run by link. For testing another branch:
#   $env:POTATOPC_BRANCH='name'; irm https://raw.githubusercontent.com/DezFix/PotatoPC/name/menu.ps1 | iex
$Branch = 'main'
if ($env:POTATOPC_BRANCH -and $env:POTATOPC_BRANCH -match '^[A-Za-z0-9._/-]{1,100}$') { $Branch = $env:POTATOPC_BRANCH }
$RemoteMenuUrl = 'https://raw.githubusercontent.com/DezFix/PotatoPC/' + $Branch + '/menu.ps1'
$RemoteZipUrl  = 'https://codeload.github.com/DezFix/PotatoPC/zip/refs/heads/' + $Branch

# --- 1. Administrator rights, Windows PowerShell 5.1 and STA (required by WPF) ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA'
$isDesktopPs = $PSVersionTable.PSEdition -ne 'Core'
if (-not ($isAdmin -and $isSta -and $isDesktopPs)) {
    $ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argLine = if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
        '-STA -NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    } else {
        # The elevated process does not inherit our environment: pass the branch explicitly.
        '-STA -NoProfile -ExecutionPolicy Bypass -Command "$env:POTATOPC_BRANCH=''' + $Branch + '''; irm ''' + $RemoteMenuUrl + ''' | iex"'
    }
    try {
        if ($isAdmin) { Start-Process -FilePath $ps -ArgumentList $argLine }
        else { Write-Host (T '\u041d\u0443\u0436\u043d\u044b \u043f\u0440\u0430\u0432\u0430 \u0430\u0434\u043c\u0438\u043d\u0438\u0441\u0442\u0440\u0430\u0442\u043e\u0440\u0430, \u043f\u0435\u0440\u0435\u0437\u0430\u043f\u0443\u0441\u043a\u0430\u044e...') -ForegroundColor Yellow; Start-Process -FilePath $ps -ArgumentList $argLine -Verb RunAs }
    } catch {
        Write-Host (T '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u043f\u0435\u0440\u0435\u0437\u0430\u043f\u0443\u0441\u0442\u0438\u0442\u044c\u0441\u044f \u043e\u0442 \u0430\u0434\u043c\u0438\u043d\u0438\u0441\u0442\u0440\u0430\u0442\u043e\u0440\u0430. \u0417\u0430\u043f\u0443\u0441\u0442\u0438\u0442\u0435 PowerShell \u043e\u0442 \u0438\u043c\u0435\u043d\u0438 \u0430\u0434\u043c\u0438\u043d\u0438\u0441\u0442\u0440\u0430\u0442\u043e\u0440\u0430 \u0432\u0440\u0443\u0447\u043d\u0443\u044e.') -ForegroundColor Red
        try { Read-Host (T 'Enter - \u0432\u044b\u0445\u043e\u0434') | Out-Null } catch {}
    }
    return
}
# Files from a ZIP carry Mark-of-the-Web: without a process-level Bypass, dot-sourcing
# the modules fails with PSSecurityException. Always done, before touching files.
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# --- 2. Where the app lives ---
function Get-PotatoHash([string]$Path) {
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $text = @('.bat', '.cfg', '.cmd', '.conf', '.cs', '.css', '.csv', '.editorconfig', '.gitattributes', '.gitignore', '.htm', '.html', '.ini', '.js', '.json', '.md', '.ps1', '.psd1', '.psm1', '.toml', '.txt', '.svg', '.xml', '.xaml', '.yaml', '.yml', '.yar', '.yara')
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($text -contains $ext -or [System.IO.Path]::GetFileName($Path) -match '^(?i)(license|notice|copying|readme)$') {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([System.Text.Encoding]::UTF8.GetString($bytes).Replace("`r`n", "`n").Replace("`r", "`n"))
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') } finally { $sha.Dispose() }
}

if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
    # Local run: use the folder as is. User plugins in scripts\ are always
    # picked up (in v6 an extra .ps1 failed the manifest check and the app
    # silently downloaded a GitHub copy, losing the plugin).
    $script:AppRoot = Split-Path -Parent $PSCommandPath
    # One-time v6 migration: old modules, the YARA scanner and retired plugins are
    # moved (not deleted) to _archive_v6. Retired plugins are found by file name,
    # so this file stays pure ASCII.
    $legacy = @('modules', 'protect', 'assets\window.xaml', 'assets\icons')
    foreach ($old in @('04_foreground_boost.ps1', '05_game_mode.ps1', '09_clean_autostart.ps1')) {
        foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $script:AppRoot 'scripts') -Filter $old -File -Recurse -ErrorAction SilentlyContinue)) {
            $legacy += $f.FullName.Substring($script:AppRoot.Length).TrimStart('\')
        }
    }
    foreach ($rel in $legacy) {
        $src = Join-Path $script:AppRoot $rel
        if (-not (Test-Path -LiteralPath $src)) { continue }
        try {
            $dst = Join-Path (Join-Path $script:AppRoot '_archive_v6') $rel
            New-Item -ItemType Directory -Path (Split-Path $dst -Parent) -Force -ErrorAction Stop | Out-Null
            if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue }
            Move-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop
        } catch {}
    }
} else {
    # Link run: fresh archive into a temp folder + SHA256SUMS check.
    $dl = Join-Path $env:TEMP ('PotatoPC-run-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $zip = Join-Path $dl 'repo.zip'
    try {
        New-Item -ItemType Directory -Path $dl -Force -ErrorAction Stop | Out-Null
        Write-Host (T '\u0417\u0430\u0433\u0440\u0443\u0436\u0430\u044e PotatoPC...') -ForegroundColor Cyan
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri ($RemoteZipUrl + '?nocache=' + [guid]::NewGuid().ToString('N')) -OutFile $zip -UseBasicParsing -TimeoutSec 90 -ErrorAction Stop
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $dl)
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        $root = Get-ChildItem -LiteralPath $dl -Directory -ErrorAction Stop | Where-Object { Test-Path (Join-Path $_.FullName 'menu.ps1') } | Select-Object -First 1
        if (-not $root) { throw (T '\u0432 \u0430\u0440\u0445\u0438\u0432\u0435 \u043d\u0435\u0442 menu.ps1') }
        Get-ChildItem -LiteralPath $root.FullName -Recurse -File -ErrorAction Stop | Unblock-File -ErrorAction SilentlyContinue
        $man = Join-Path $root.FullName 'SHA256SUMS'
        if (-not (Test-Path -LiteralPath $man)) { throw (T '\u0432 \u0430\u0440\u0445\u0438\u0432\u0435 \u043d\u0435\u0442 SHA256SUMS') }
        $bad = @()
        foreach ($line in [System.IO.File]::ReadAllLines($man)) {
            if ($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$') { continue }
            $f = Join-Path $root.FullName ($Matches[2].Replace('/', '\'))
            if (-not (Test-Path -LiteralPath $f) -or (Get-PotatoHash $f) -ne $Matches[1].ToUpperInvariant()) { $bad += $Matches[2] }
        }
        if ($bad.Count -gt 0) { throw ((T '\u0444\u0430\u0439\u043b\u044b \u043d\u0435 \u0441\u043e\u0432\u043f\u0430\u043b\u0438 \u0441 SHA256SUMS: ') + (($bad | Select-Object -First 5) -join ', ')) }
        $script:AppRoot = $root.FullName
    } catch {
        Write-Host ((T '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u0437\u0430\u0433\u0440\u0443\u0437\u0438\u0442\u044c PotatoPC: ') + $_.Exception.Message) -ForegroundColor Red
        Write-Host (T '\u041f\u0440\u043e\u0432\u0435\u0440\u044c\u0442\u0435 \u0438\u043d\u0442\u0435\u0440\u043d\u0435\u0442, VPN \u0438\u043b\u0438 \u0430\u043d\u0442\u0438\u0432\u0438\u0440\u0443\u0441 \u0438 \u0437\u0430\u043f\u0443\u0441\u0442\u0438\u0442\u0435 \u043a\u043e\u043c\u0430\u043d\u0434\u0443 \u0435\u0449\u0451 \u0440\u0430\u0437.') -ForegroundColor Yellow
        try { Read-Host (T 'Enter - \u0432\u044b\u0445\u043e\u0434') | Out-Null } catch {}
        return
    }
}

# --- 3. Load the core ---
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
$script:CoreDir = Join-Path $script:AppRoot 'core'
$coreFiles = @('Config.ps1', 'Runtime.ps1', 'Plugins.ps1', 'System.ps1', 'Winget.ps1', 'Profiles.ps1', 'Ui.ps1')
foreach ($cf in $coreFiles) {
    $p = Join-Path $script:CoreDir $cf
    if (-not (Test-Path -LiteralPath $p)) {
        [void][System.Windows.MessageBox]::Show(((T '\u041d\u0435 \u043d\u0430\u0439\u0434\u0435\u043d \u0444\u0430\u0439\u043b \u043f\u0440\u0438\u043b\u043e\u0436\u0435\u043d\u0438\u044f: core\\') + $cf + "`n" + (T '\u0421\u043a\u0430\u0447\u0430\u0439\u0442\u0435 PotatoPC \u0437\u0430\u043d\u043e\u0432\u043e.')), 'PotatoPC', 'OK', 'Error')
        return
    }
    . $p
}
if (Test-Path -LiteralPath $script:CleanGuardPath) { . $script:CleanGuardPath }

# --- 4. Window ---
try {
    $script:Window = Import-Shell
} catch {
    [void][System.Windows.MessageBox]::Show((T '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u043f\u043e\u0441\u0442\u0440\u043e\u0438\u0442\u044c \u043e\u043a\u043d\u043e: ') + $_.Exception.Message, 'PotatoPC', 'OK', 'Error')
    return
}
Initialize-ShellEvents
Register-Pages
# Pages are dot-sourced here at script level: dot-sourcing inside a function
# would lose their functions when it returns.
foreach ($pg in @($script:Pages.Values)) {
    try { . $pg.File }
    catch { Write-Log ((T '\u0421\u0442\u0440\u0430\u043d\u0438\u0446\u0430 ') + [System.IO.Path]::GetFileName($pg.File) + (T ' \u043d\u0435 \u0437\u0430\u0433\u0440\u0443\u0437\u0438\u043b\u0430\u0441\u044c: ') + $_.Exception.Message) 'err' }
}
Initialize-Nav

$script:Window.Dispatcher.Add_UnhandledException({
    param($s, $e)
    try { Write-Log ((T '\u041e\u0448\u0438\u0431\u043a\u0430 \u0438\u043d\u0442\u0435\u0440\u0444\u0435\u0439\u0441\u0430 (\u043e\u043a\u043d\u043e \u043f\u0440\u043e\u0434\u043e\u043b\u0436\u0430\u0435\u0442 \u0440\u0430\u0431\u043e\u0442\u0430\u0442\u044c): ') + $e.Exception.Message) 'err' } catch {}
    $e.Handled = $true
})

# Window size and state between runs.
try {
    if (Test-Path -LiteralPath $script:UIStatePath) {
        $ui = Get-Content -LiteralPath $script:UIStatePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($ui.Width -ge 980 -and $ui.Height -ge 620) { $script:Window.Width = [double]$ui.Width; $script:Window.Height = [double]$ui.Height }
        if ($ui.Maximized) { $script:Window.WindowState = 'Maximized' }
        if ([bool]$ui.LogOpen) { Set-LogVisible $true }
    }
} catch {}
$script:Window.Add_Closing({
    foreach ($j in @(Get-RunningTasks)) { Stop-BgTask $j }
    try {
        @{ Width = $script:Window.RestoreBounds.Width; Height = $script:Window.RestoreBounds.Height
           Maximized = ($script:Window.WindowState -eq 'Maximized'); LogOpen = ($script:LogPanel.Visibility -eq 'Visible') } |
            ConvertTo-Json | Set-Content -LiteralPath $script:UIStatePath -Encoding UTF8 -ErrorAction Stop
    } catch {}
})
$script:Window.Add_Loaded({
    Write-Log ('PotatoPC ' + $AppVersion + ' (' + $BuildTag + (T ') \u00b7 ') + $WinInfo.Name + (T ' \u0441\u0431\u043e\u0440\u043a\u0430 ') + $WinInfo.Build + $(if ($PortableMode) { (T ' \u00b7 \u043f\u043e\u0440\u0442\u0430\u0442\u0438\u0432\u043d\u044b\u0439 \u0440\u0435\u0436\u0438\u043c') } else { '' }))
    Write-Log ((T '\u041f\u0430\u043f\u043a\u0430 \u043f\u0440\u0438\u043b\u043e\u0436\u0435\u043d\u0438\u044f: ') + $AppRoot)
    $start = if ($script:Pages.Contains('home')) { 'home' } else { @($script:Pages.Keys)[0] }
    Show-Page -Id $start
})

[void]$script:Window.ShowDialog()
try { $script:PollTimer.Stop() } catch {}
