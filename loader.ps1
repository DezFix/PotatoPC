<#
    .SYNOPSIS
    PotatoPC Loader v6.0 (Policy Bypass Fix)
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
                                             
    :: Загрузка ядра (Bypass)... ::
" -ForegroundColor Yellow

# 1. СКАЧИВАНИЕ
try {
    Write-Host " [1/2] Скачивание..." -ForegroundColor Cyan -NoNewline
    
    $wc = New-Object System.Net.WebClient
    $wc.Encoding = [System.Text.Encoding]::UTF8
    $Content = $wc.DownloadString($CoreURL)
    [System.IO.File]::WriteAllText($LocalFile, $Content, [System.Text.Encoding]::UTF8)
    
    Write-Host " [OK]" -ForegroundColor Green
}
catch {
    Write-Host "`n [ERROR] Ошибка сети." -ForegroundColor Red
    Write-Host " Детали: $($_.Exception.Message)" -ForegroundColor Gray
    Read-Host " Нажмите Enter..."
    exit
}

# 2. ЗАПУСК С ОБХОДОМ БЛОКИРОВОК
try {
    Write-Host " [2/2] Запуск..." -ForegroundColor Cyan
    
    # ШАГ 1: Разблокируем скачанный файл (снимаем метку "из интернета")
    Unblock-File -Path $LocalFile -ErrorAction SilentlyContinue

    # ШАГ 2: Разрешаем выполнение скриптов ТОЛЬКО для этого окна (Process Scope)
    # Это обходит запрет "running scripts is disabled", который ты видишь на фото
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue

    # Запускаем файл
    & $LocalFile
}
catch {
    # ШАГ 3: Если всё равно ошибка - запускаем новый процесс с принудительными правами
    Write-Host " [!] Активация режима совместимости..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$LocalFile`"" -Verb RunAs
    exit
}
