# NAME: Включение Гибернации
# DESC: Включает гибернацию и проводит ее настройку
# CATEGORY: Разное
# ICON: ⚡

Write-Host "=== Настройка гибернации Windows ===" -ForegroundColor Cyan

# 1. Включение гибернации
Write-Host "1. Включение функции гибернации..." -ForegroundColor Yellow
try {
    powercfg /hibernate on
    Write-Host "   [УСПЕХ] Гибернация включена." -ForegroundColor Green
} catch {
    Write-Host "   [ОШИБКА] Не удалось включить гибернацию." -ForegroundColor Red
}

# 2. Настройка гибернации (использование полного файла гибернации для надежности)
# Полный файл (full) гарантирует, что все данные приложения будут сохранены корректно.
Write-Host "2. Настройка типа файла гибернации (полный режим для надежности)..." -ForegroundColor Yellow
try {
    powercfg /h /type full
    Write-Host "   [УСПЕХ] Установлен полный тип файла гибернации." -ForegroundColor Green
} catch {
    Write-Host "   [ОШИБКА] Не удалось настроить тип файла гибернации." -ForegroundColor Red
}

# 3. Добавление пункта "Гибернация" в меню Пуск (через реестр)
Write-Host "3. Добавление пункта 'Гибернация' в меню выключения..." -ForegroundColor Yellow
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings"

# Создаем ключ реестра, если его не существует
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

# Устанавливаем или обновляем параметр ShowHibernateOption
try {
    New-ItemProperty -Path $regPath -Name "ShowHibernateOption" -Value 1 -PropertyType DWORD -Force | Out-Null
    Write-Host "   [УСПЕХ] Пункт 'Гибернация' добавлен в меню Пуск." -ForegroundColor Green
} catch {
    Write-Host "   [ОШИБКА] Не удалось изменить реестр." -ForegroundColor Red
}

Write-Host "===================================" -ForegroundColor Cyan
Write-Host "Настройка завершена!" -ForegroundColor Green