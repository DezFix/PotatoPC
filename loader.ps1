<#
    .SYNOPSIS
    PotatoPC Loader v5.1 (Encoding Fix)
#>

$ErrorActionPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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
                                             
    :: Загрузка... ::
" -ForegroundColor Yellow

try {
    Write-Host " [1/2] Скачивание..." -ForegroundColor Cyan -NoNewline
    
    # 1. Скачиваем содержимое как текст (String)
    $Content = Invoke-RestMethod -Uri $CoreURL -UseBasicParsing
    
    # 2. Сохраняем в файл с явной кодировкой UTF8 (чтобы русский язык не ломался)
    $Content | Out-File -FilePath $LocalFile -Encoding UTF8 -Force
    
    Write-Host " [OK]" -ForegroundColor Green
}
catch {
    Write-Host "`n [ERROR] Ошибка скачивания." -ForegroundColor Red
    Write-Host " Детали: $($_.Exception.Message)" -ForegroundColor Gray
    Read-Host " Нажмите Enter..."
    exit
}

try {
    Write-Host " [2/2] Запуск..." -ForegroundColor Cyan
    & $LocalFile
}
catch {
    Write-Host " [FATAL] Сбой запуска: $_" -ForegroundColor Red
    Read-Host " Нажмите Enter..."
}
