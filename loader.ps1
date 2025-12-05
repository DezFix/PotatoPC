<#
    .SYNOPSIS
    PotatoPC Loader v5.5 (Encoding BOM Fix)
#>
$ErrorActionPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Ссылка на твой Core.ps1
$CoreURL = "https://raw.githubusercontent.com/DezFix/PotatoPC/main/Core.ps1"
$LocalFile = "$env:TEMP\PotatoPC_Core.ps1"

Clear-Host
Write-Host "
  _____      _        _        _____   _____ 
 |  __ \    | |      | |      |  __ \ / ____|
 | |__) |__ | |_ __ _| |_ ___ | |__) | |     
 |  ___/ _ \| __/ _` | __/ _ \|  ___/| |     
 | |  | (_) | || (_| | || (_) | |    | |____ 
 |_|   \___/ \__\__,_|\__\___/|_|     \_____|
                                             
    :: Загрузка ядра (UTF-8)... ::
" -ForegroundColor Yellow

try {
    Write-Host " [1/2] Скачивание..." -ForegroundColor Cyan -NoNewline
    
    # ИСПОЛЬЗУЕМ WEBCLIENT С ЯВНОЙ КОДИРОВКОЙ UTF-8
    $wc = New-Object System.Net.WebClient
    $wc.Encoding = [System.Text.Encoding]::UTF8
    $Content = $wc.DownloadString($CoreURL)
    
    # СОХРАНЯЕМ С BOM (Byte Order Mark), ЧТОБЫ POWERSHELL 5.1 ПОНЯЛ КИРИЛЛИЦУ
    [System.IO.File]::WriteAllText($LocalFile, $Content, [System.Text.Encoding]::UTF8)
    
    Write-Host " [OK]" -ForegroundColor Green
}
catch {
    Write-Host "`n [ERROR] Ошибка сети или кодировки." -ForegroundColor Red
    Write-Host " Детали: $($_.Exception.Message)" -ForegroundColor Gray
    Read-Host " Нажмите Enter..."
    exit
}

try {
    Write-Host " [2/2] Запуск..." -ForegroundColor Cyan
    # Запуск файла
    & $LocalFile
}
catch {
    Write-Host " [FATAL] Скрипт поврежден: $_" -ForegroundColor Red
    Read-Host " Нажмите Enter..."
}
