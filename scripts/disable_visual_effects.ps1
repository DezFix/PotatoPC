# NAME: Отключить визуальные эффекты
# DESC: Убирает анимации и тени, ускоряет интерфейс на слабых компьютерах
# CATEGORY: Производительность
# ICON: 🖥️
# RECOMMENDED: true

function Disable-VisualEffects {
    Write-Host "[+] Оптимизация интерфейса под стиль 'Наилучшее быстродействие'..." -ForegroundColor Cyan

    try {
        # 1. Глобальный флаг "Наилучшее быстродействие" (аналог кнопки в sysdm.cpl)
        $Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        if (!(Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        Set-ItemProperty -Path $Path -Name "VisualFXSetting" -Value 2 -Force

        # 2. Тонкая настройка: отключаем всё, КРОМЕ сглаживания шрифтов (чтобы текст не был "лесенкой")
        $UserKey = "HKCU:\Control Panel\Desktop"
        # Магический байт-массив, который Windows применяет при выборе "Наилучшее быстродействие" + "Сглаживание шрифтов"
        Set-ItemProperty -Path $UserKey -Name "UserPreferencesMask" -Value ([byte[]](0x90,0x12,0x01,0x80,0x10,0x00,0x00,0x00)) -Force
        Set-ItemProperty -Path $UserKey -Name "DragFullWindows" -Value 0 -Force
        Set-ItemProperty -Path $UserKey -Name "FontSmoothing" -Value 2 -Force
        Set-ItemProperty -Path $UserKey -Name "FontSmoothingType" -Value 2 -Force

        # 3. Отключение прозрачности (DWM) - главный пожиратель ресурсов на слабых GPU
        $ThemePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        if (Test-Path $ThemePath) {
            Set-ItemProperty -Path $ThemePath -Name "EnableTransparency" -Value 0 -Force
        }

        Write-Host "[+] Визуальные эффекты и прозрачность успешно отключены." -ForegroundColor Green
        Write-Host "[+] Сглаживание шрифтов (ClearType) сохранено для читаемости." -ForegroundColor Green
        
        # 4. Безопасный перезапуск Проводника для мгновенного применения
        Write-Host "[!] Перезапуск Проводника Windows для применения изменений..." -ForegroundColor Yellow
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Process explorer.exe -ErrorAction SilentlyContinue
        
        Write-Host "[✅] Оптимизация интерфейса полностью завершена!" -ForegroundColor Green
    }
    catch {
        Write-Host "[-] Ошибка при оптимизации интерфейса: $_" -ForegroundColor Red
    }
}

# Запуск функции
Disable-VisualEffects

