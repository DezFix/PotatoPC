<#
.SYNOPSIS
    PotatoPC v7 - ускорение, очистка и защита Windows для слабых ПК.
.DESCRIPTION
    Локально:  powershell -STA -NoProfile -ExecutionPolicy Bypass -File menu.ps1
    По ссылке: irm https://raw.githubusercontent.com/DezFix/PotatoPC/main/menu.ps1 | iex
#>

$RemoteMenuUrl = 'https://raw.githubusercontent.com/DezFix/PotatoPC/main/menu.ps1'
$RemoteZipUrl  = 'https://codeload.github.com/DezFix/PotatoPC/zip/refs/heads/main'

# --- 1. Права администратора, Windows PowerShell 5.1 и STA (нужно для WPF) ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA'
$isDesktopPs = $PSVersionTable.PSEdition -ne 'Core'
if (-not ($isAdmin -and $isSta -and $isDesktopPs)) {
    $ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argLine = if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
        '-STA -NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    } else {
        '-STA -NoProfile -ExecutionPolicy Bypass -Command "irm ''' + $RemoteMenuUrl + ''' | iex"'
    }
    try {
        if ($isAdmin) { Start-Process -FilePath $ps -ArgumentList $argLine }
        else { Write-Host 'Нужны права администратора, перезапускаю...' -ForegroundColor Yellow; Start-Process -FilePath $ps -ArgumentList $argLine -Verb RunAs }
    } catch {
        Write-Host 'Не удалось перезапуститься от администратора. Запустите PowerShell от имени администратора вручную.' -ForegroundColor Red
        try { Read-Host 'Enter - выход' | Out-Null } catch {}
    }
    return
}
# Файлы из ZIP несут Mark-of-the-Web: без Bypass для процесса точечная загрузка
# модулей падает с PSSecurityException. Делается всегда и до работы с файлами.
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# --- 2. Где лежит приложение ---
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
    # Локальный запуск: работаем с папкой как есть. Свои плагины в scripts\
    # подхватываются всегда (раньше лишний .ps1 ломал проверку и приложение
    # молча скачивало копию с GitHub, а плагин пропадал).
    $script:AppRoot = Split-Path -Parent $PSCommandPath
    # Разовая миграция с v6: старые модули, сканер YARA и упразднённые плагины
    # уезжают в _archive_v6 (не удаляются). Иначе старые плагины показались бы
    # как «сторонние», а 04_foreground_boost и сейчас делал бы хуже.
    $legacy = @('modules', 'protect', 'assets\window.xaml', 'assets\icons',
        'scripts\01 Скорость\04_foreground_boost.ps1', 'scripts\01 Скорость\05_game_mode.ps1', 'scripts\02 Очистка\09_clean_autostart.ps1')
    foreach ($rel in $legacy) {
        $src = Join-Path $script:AppRoot $rel
        if (-not (Test-Path -LiteralPath $src)) { continue }
        try {
            $dst = Join-Path (Join-Path $script:AppRoot '_archive_v6') $rel
            New-Item -ItemType Directory -Path (Split-Path $dst -Parent) -Force | Out-Null
            if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue }
            Move-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop
        } catch {}
    }
} else {
    # Запуск по ссылке: свежий архив во временную папку + сверка SHA256SUMS.
    $dl = Join-Path $env:TEMP ('PotatoPC-run-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $zip = Join-Path $dl 'repo.zip'
    try {
        New-Item -ItemType Directory -Path $dl -Force | Out-Null
        Write-Host 'Загружаю PotatoPC...' -ForegroundColor Cyan
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri ($RemoteZipUrl + '?nocache=' + [guid]::NewGuid().ToString('N')) -OutFile $zip -UseBasicParsing -TimeoutSec 90 -ErrorAction Stop
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $dl)
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        $root = Get-ChildItem -LiteralPath $dl -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'menu.ps1') } | Select-Object -First 1
        if (-not $root) { throw 'в архиве нет menu.ps1' }
        Get-ChildItem -LiteralPath $root.FullName -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
        $man = Join-Path $root.FullName 'SHA256SUMS'
        if (-not (Test-Path -LiteralPath $man)) { throw 'в архиве нет SHA256SUMS' }
        $bad = @()
        foreach ($line in [System.IO.File]::ReadAllLines($man)) {
            if ($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$') { continue }
            $f = Join-Path $root.FullName ($Matches[2].Replace('/', '\'))
            if (-not (Test-Path -LiteralPath $f) -or (Get-PotatoHash $f) -ne $Matches[1].ToUpperInvariant()) { $bad += $Matches[2] }
        }
        if ($bad.Count -gt 0) { throw ('файлы не совпали с SHA256SUMS: ' + (($bad | Select-Object -First 5) -join ', ')) }
        $script:AppRoot = $root.FullName
    } catch {
        Write-Host ('Не удалось загрузить PotatoPC: ' + $_.Exception.Message) -ForegroundColor Red
        Write-Host 'Проверьте интернет, VPN или антивирус и запустите команду ещё раз.' -ForegroundColor Yellow
        try { Read-Host 'Enter - выход' | Out-Null } catch {}
        return
    }
}

# --- 3. Загрузка ядра ---
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
$script:CoreDir = Join-Path $script:AppRoot 'core'
$coreFiles = @('Config.ps1', 'Runtime.ps1', 'Plugins.ps1', 'System.ps1', 'Winget.ps1', 'Ui.ps1')
foreach ($cf in $coreFiles) {
    $p = Join-Path $script:CoreDir $cf
    if (-not (Test-Path -LiteralPath $p)) {
        [void][System.Windows.MessageBox]::Show("Не найден файл приложения: core\$cf`nСкачайте PotatoPC заново.", 'PotatoPC', 'OK', 'Error')
        return
    }
    . $p
}
if (Test-Path -LiteralPath $script:CleanGuardPath) { . $script:CleanGuardPath }

# --- 4. Окно ---
try {
    $script:Window = Import-Shell
} catch {
    [void][System.Windows.MessageBox]::Show('Не удалось построить окно: ' + $_.Exception.Message, 'PotatoPC', 'OK', 'Error')
    return
}
Initialize-ShellEvents
Register-Pages
# Страницы подключаются здесь, на уровне скрипта: точка-источник внутри функции
# потеряла бы их функции при выходе из неё.
foreach ($pg in @($script:Pages.Values)) {
    try { . $pg.File }
    catch { Write-Log ('Страница ' + [System.IO.Path]::GetFileName($pg.File) + ' не загрузилась: ' + $_.Exception.Message) 'err' }
}
Initialize-Nav

$script:Window.Dispatcher.Add_UnhandledException({
    param($s, $e)
    try { Write-Log ('Ошибка интерфейса (окно продолжает работать): ' + $e.Exception.Message) 'err' } catch {}
    $e.Handled = $true
})

# Размер и положение окна между запусками.
try {
    if (Test-Path -LiteralPath $script:UIStatePath) {
        $ui = Get-Content -LiteralPath $script:UIStatePath -Raw | ConvertFrom-Json
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
            ConvertTo-Json | Set-Content -LiteralPath $script:UIStatePath -Encoding UTF8
    } catch {}
})
$script:Window.Add_Loaded({
    Write-Log ('PotatoPC ' + $AppVersion + ' (' + $BuildTag + ') · ' + $WinInfo.Name + ' сборка ' + $WinInfo.Build + $(if ($PortableMode) { ' · портативный режим' } else { '' }))
    Write-Log ('Папка приложения: ' + $AppRoot)
    $start = if ($script:Pages.Contains('home')) { 'home' } else { @($script:Pages.Keys)[0] }
    Show-Page -Id $start
})

[void]$script:Window.ShowDialog()
try { $script:PollTimer.Stop() } catch {}
