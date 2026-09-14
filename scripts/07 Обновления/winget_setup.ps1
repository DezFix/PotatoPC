# NAME: Winget — установщик программ от Microsoft (не Store!)
# DESC: Ставит winget с GitHub (при лимите API — запасная версия): нужен вкладке «Приложения». Оставляет метку для отката
# TAGS: 1
# ICON: 📦
# PRESET: potato, office
# RECOMMENDED: true

$ErrorActionPreference = "Stop"
try {
    try { $v = winget --version 2>$null; if ($v) { Write-Output ("[=] Уже стоит: " + $v); exit 0 } } catch {}

    $arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
    $tmp = Join-Path $env:TEMP "winget-install"
    if (-not (Test-Path $tmp)) { New-Item -ItemType Directory -Path $tmp -Force | Out-Null }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $xaml = Join-Path $tmp "ui.xaml.appx"
    $libs = Join-Path $tmp "vclibs.appx"
    Invoke-WebRequest "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.$arch.appx" -OutFile $xaml -UseBasicParsing -ErrorAction Stop
    Invoke-WebRequest "https://aka.ms/Microsoft.VCLibs.$arch.14.00.Desktop.appx" -OutFile $libs -UseBasicParsing -ErrorAction Stop
    Add-AppxPackage -Path $xaml -ErrorAction SilentlyContinue
    Add-AppxPackage -Path $libs -ErrorAction SilentlyContinue

    $url = ""
    try {
        $rel = Invoke-RestMethod "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -ErrorAction Stop
        $url = ($rel.assets | Where-Object { $_.name -like "Microsoft.DesktopAppInstaller_*.msixbundle" } | Select-Object -First 1).browser_download_url
    } catch { Write-Output ("[!] API GitHub недоступен (лимит?): " + $_.Exception.Message) }
    if ([string]::IsNullOrWhiteSpace($url)) {
        $url = "https://github.com/microsoft/winget-cli/releases/download/v1.29.290/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        Write-Output "[*] Беру запасную версию v1.29.290 напрямую."
    }
    $pkg = Join-Path $tmp "winget.msixbundle"
    Invoke-WebRequest $url -OutFile $pkg -UseBasicParsing -ErrorAction Stop
    Add-AppxPackage -Path $pkg -ErrorAction Stop

    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

    $okV = ""
    try { $okV = (winget --version 2>$null) } catch {}
    if ([string]::IsNullOrWhiteSpace($okV)) {
        try { $p = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction Stop | Select-Object -First 1; if ($p) { $okV = "пакет " + [string]$p.Version } } catch {}
    }
    if ([string]::IsNullOrWhiteSpace($okV)) {
        Write-Output "[X] Пакет встал, но winget не отзывается — перезайди в систему и проверь командой winget."
        exit 1
    }
    try {
        $md = Join-Path $env:LOCALAPPDATA "PotatoPC"
        if (-not (Test-Path $md)) { New-Item -ItemType Directory -Path $md -Force | Out-Null }
        ("winget $okV installed by PotatoPC " + (Get-Date -Format "yyyy-MM-dd HH:mm")) | Out-File -LiteralPath (Join-Path $md "winget-by-potatopc.txt") -Encoding UTF8 -Force
    } catch {}
    Write-Output ("[OK] Winget поставлен: " + $okV)
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
