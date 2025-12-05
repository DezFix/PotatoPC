<#
    .SYNOPSIS
    PotatoPC Loader v5.0 (Stable File Mode)
#>

# 1. Скрытие лишних ошибок
$ErrorActionPreference = "SilentlyContinue"

# 2. Настройка безопасности (для GitHub)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 3. Пути
$CoreURL = "https://raw.githubusercontent.com/DezFix/PotatoPC/main/Core.ps1"
$LocalFile = "$env:TEMP\PotatoPC_Core.ps1"

# 4. Визуал (Твой ASCII Art)
Clear-Host
Write-Host "
  _____      _        _        _____   _____ 
 |  __ \    | |      | |      |  __ \ / ____|
 | |__) |__ | |_ __ _| |_ ___ | |__) | |     
 |  ___/ _ \| __/ _` | __/ _ \|  ___/| |     
 | |  | (_) | || (_| | || (_) | |    | |____ 
 |_|   \___/ \__\__,_|\__\___/|_|     \_____|
                                             
    :: Загрузка ядра... ::
" -ForegroundColor Yellow

# 5. Скачивание (Главное исправление)
try {
    Write-Host " [1/2] Скачивание последней версии..." -ForegroundColor Cyan -NoNewline
    
    # Скачиваем файл на диск. Это предотвращает ошибки синтаксиса/скобок.
    Invoke-WebRequest -Uri $CoreURL -OutFile $LocalFile -UseBasicParsing | Out-Null
    
    Write-Host " [OK]" -ForegroundColor Green
}
catch {
    Write-Host "`n [ERROR] Не удалось скачать скрипт." -ForegroundColor Red
    Write-Host " Ошибка: $($_.Exception.Message)" -ForegroundColor Gray
    Write-Host " Проверьте интернет."
    Read-Host " Нажмите Enter для выхода..."
    exit
}

# 6. Запуск
try {
    Write-Host " [2/2] Запуск интерфейса..." -ForegroundColor Cyan
    
    # Запускаем скачанный файл. 
    # Теперь Core.ps1 сам проверит админа и покажет красный баннер, если прав нет.
    & $LocalFile
}
catch {
    Write-Host " [FATAL] Ошибка при запуске файла: $_" -ForegroundColor Red
    Read-Host " Нажмите Enter..."
}
