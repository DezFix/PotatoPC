# NAME: Install-Winget
# DESC: Устанавливает Windows Package Manager (winget) со всеми зависимостями, если он не установлен
# CATEGORY: Системные утилиты
# ICON: 📦
# RECOMMENDED: true

$ErrorActionPreference = "Stop"

try {
    Write-Host "=== Установка Windows Package Manager ===" -ForegroundColor Cyan

    # 1. Проверяем, установлен ли winget
    Write-Host "🔍 Проверка наличия winget..." -ForegroundColor Gray
    try {
        $wingetVersion = winget --version 2>$null
        if ($wingetVersion) {
            Write-Host "✅ Winget уже установлен. Версия: $wingetVersion" -ForegroundColor Green
            Write-Host "Дополнительные действия не требуются." -ForegroundColor Gray
            exit 0
        }
    }
    catch {
        Write-Host "⚠️ Winget не найден. Переходим к установке..." -ForegroundColor Yellow
    }

    # 2. Определяем архитектуру системы
    $architecture = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
    Write-Host "💻 Архитектура системы: $architecture" -ForegroundColor Gray

    # 3. Создаем временную директорию
    $tempDir = Join-Path $env:TEMP "winget-install"
    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }

    # 4. Функция для скачивания файлов
    function Download-File {
        param($url, $outputPath, $description)
        Write-Host "📥 Скачивание: $description" -ForegroundColor Gray
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $outputPath -UseBasicParsing
    }

    # 5. URL для скачивания зависимостей
    $uiXamlUrl = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.$architecture.appx"
    $vclibsUrl = "https://aka.ms/Microsoft.VCLibs.$architecture.14.00.Desktop.appx"

    $uiXamlPath = Join-Path $tempDir "Microsoft.UI.Xaml.2.8.appx"
    $vclibsPath = Join-Path $tempDir "Microsoft.VCLibs.appx"

    # 6. Скачиваем зависимости
    Download-File -url $uiXamlUrl -outputPath $uiXamlPath -description "Microsoft.UI.Xaml.2.8"
    Download-File -url $vclibsUrl -outputPath $vclibsPath -description "Microsoft.VCLibs.14.00"

    # 7. Устанавливаем зависимости
    Write-Host "⚙️ Установка зависимостей..." -ForegroundColor Cyan
    Add-AppxPackage -Path $uiXamlPath -ErrorAction SilentlyContinue
    Add-AppxPackage -Path $vclibsPath -ErrorAction SilentlyContinue
    Write-Host "✅ Зависимости установлены" -ForegroundColor Green

    # 8. Получаем последнюю версию winget
    Write-Host "🔍 Получение информации о последней версии winget..." -ForegroundColor Cyan
    $releasesUrl = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
    $release = Invoke-RestMethod -Uri $releasesUrl
    $msixbundleUrl = $release.assets | Where-Object { $_.name -like "*.msixbundle" } | Select-Object -First 1 -ExpandProperty browser_download_url

    Write-Host "📥 Найдена версия: $($release.tag_name)" -ForegroundColor Cyan

    # 9. Скачиваем winget
    $wingetPath = Join-Path $tempDir "Microsoft.DesktopAppInstaller.msixbundle"
    Download-File -url $msixbundleUrl -outputPath $wingetPath -description "Windows Package Manager"

    # 10. Устанавливаем winget
    Write-Host "⚙️ Установка Windows Package Manager..." -ForegroundColor Cyan
    Add-AppxPackage -Path $wingetPath

    # 11. Добавляем в PATH
    $windowsAppsPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps"
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -notlike "*$windowsAppsPath*") {
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$windowsAppsPath", "User")
        Write-Host "✅ Winget добавлен в PATH" -ForegroundColor Green
    }

    # 12. Очистка временных файлов
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "🧹 Временные файлы очищены" -ForegroundColor Gray

    # 13. Финальная проверка
    Write-Host "`n=== Финальная проверка ===" -ForegroundColor Cyan
    try {
        $finalVersion = winget --version 2>$null
        Write-Host "🎉 Winget успешно установлен и готов к работе!" -ForegroundColor Green
        Write-Host "Версия: $finalVersion" -ForegroundColor White
        Write-Host "Перезапустите терминал для использования winget" -ForegroundColor Yellow
    }
    catch {
        Write-Warning "⚠️ Установка завершена, но команда winget не отвечает. Попробуйте перезапустить терминал."
    }
}
catch {
    Write-Error "❌ Ошибка при установке winget: $_"
    
    # Очистка в случае ошибки
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    exit 1
}