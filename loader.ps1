<#
    .SYNOPSIS
    PotatoPC Loader v4.0
#>

# 1. Проверка прав Админа (Жесткая)
$params = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell.exe -ArgumentList $params -Verb RunAs
    exit
}

# 2. Настройка
$Host.UI.RawUI.WindowTitle = "PotatoPC: Loading..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# === ССЫЛКА НА ЯДРО (ЗАМЕНИ DezFix НА СВОЙ НИК, ЕСЛИ ДРУГОЙ) ===
$CoreURL = "https://raw.githubusercontent.com/DezFix/PotatoPC/main/Core.ps1"

Clear-Host
Write-Host "
  _____      _        _        _____   _____ 
 |  __ \    | |      | |      |  __ \ / ____|
 | |__) |__ | |_ __ _| |_ ___ | |__) | |     
 |  ___/ _ \| __/ _` | __/ _ \|  ___/| |     
 | |  | (_) | || (_| | || (_) | |    | |____ 
 |_|   \___/ \__\__,_|\__\___/|_|     \_____|
                                             
    :: Загрузка ядра в память... ::
" -ForegroundColor Yellow

try {
    # Скачиваем и запускаем Core.ps1 без сохранения на диск
    $CoreScript = Invoke-RestMethod -Uri $CoreURL -UseBasicParsing
    Invoke-Expression $CoreScript
}
catch {
    Write-Host "`n[FATAL ERROR] Не удалось загрузить ядро." -ForegroundColor Red
    Write-Host "Ошибка: $($_.Exception.Message)" -ForegroundColor Gray
    Read-Host "Нажмите Enter для выхода..."
}