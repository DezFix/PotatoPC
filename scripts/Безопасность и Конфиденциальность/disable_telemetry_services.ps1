# NAME: Отключение служб телеметрии
# DESC: Безопасно отключает службы сбора диагностических данных и отчетов об ошибках, не затрагивая критические функции системы
# TAGS: 1
# ICON: 🕵️
# RECOMMENDED: true

function Disable-TelemetryServices {
    Write-Host "[+] Начало отключения служб телеметрии..." -ForegroundColor Yellow

    # Безопасный список служб телеметрии и диагностики (безопасно отключать)
    $safeServices = @(
        "DiagTrack",                                # Служба журналирования отслеживания (основная телеметрия)
        "dmwappushservice",                         # Служба маршрутизации push-сообщений WAP
        "DcpSvc",                                   # Служба совместимости данных
        "diagnosticshub.standardcollector.service", # Стандартная служба сборщика центра диагностики
        "DusmSvc"                                   # Служба измерения сети (сбор данных об использовании)
    )

    foreach ($svc in $safeServices) {
        $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($service) {
            # Останавливаем службу
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            # Отключаем автозапуск
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Host "[−] Служба '$svc' остановлена и отключена" -ForegroundColor Cyan
        } else {
            Write-Host "[!] Служба '$svc' не найдена в системе" -ForegroundColor DarkGray
        }
    }

    Write-Host "[+] Службы телеметрии успешно отключены!" -ForegroundColor Green
    Write-Host "[i] Примечание: Службы WpnService, DPS и Xbox были намеренно исключены во избежание поломки уведомлений, сети и игровых функций." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
}

Disable-TelemetryServices
