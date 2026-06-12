# NAME: Отключение служб Xbox
# DESC: Отключает фоновые службы Xbox Live, сохранения игр и игрового мониторинга (безопасно и рекомендуется для офисных ПК)
# CATEGORY: Производительность
# ICON: 🎮

$xboxServices = @(
    "XblGameSave",          # Служба сохранения игр Xbox Live
    "XboxNetApiSvc",        # Сетевая служба Xbox Live
    "XboxGipSvc",           # Служба управления аксессуарами Xbox
    "xbgm",                 # Служба мониторинга игр Xbox (Xbox Game Monitoring)
    "XboxSpeechToText"      # Служба преобразования речи в текст Xbox (если присутствует)
)

Write-Host "[+] Начало отключения служб Xbox..." -ForegroundColor Yellow

foreach ($svc in $xboxServices) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service) {
        # Останавливаем службу
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        # Отключаем автозапуск
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host "[−] Служба '$svc' остановлена и отключена" -ForegroundColor Cyan
    } else {
        Write-Host "[!] Служба '$svc' не найдена в системе (это нормально)" -ForegroundColor DarkGray
    }
}

Write-Host "[+] Службы Xbox успешно отключены!" -ForegroundColor Green
Start-Sleep -Seconds 2