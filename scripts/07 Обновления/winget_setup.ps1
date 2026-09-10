# NAME: Магазин программ
# DESC: Ставит программы одной кнопкой. Нужен для вкладки Приложения
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

    $rel = Invoke-RestMethod "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -ErrorAction Stop
    $url = ($rel.assets | Where-Object { $_.name -like "*.msixbundle" } | Select-Object -First 1).browser_download_url
    $pkg = Join-Path $tmp "winget.msixbundle"
    Invoke-WebRequest $url -OutFile $pkg -UseBasicParsing -ErrorAction Stop
    Add-AppxPackage -Path $pkg -ErrorAction Stop

    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output "[OK] Winget поставлен. Перезапусти окно."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
