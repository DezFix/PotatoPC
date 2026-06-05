# NAME: Нет рекламе
# DESC: Отключает рекламу в Windows 10/11.
# CATEGORY: Производительность
# ICON: 🛡️
# RECOMMENDED: true

# Проверка прав администратора
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "⚠️ Для выполнения этого скрипта требуются права Администратора."
    Write-Host "Запустите PowerShell от имени Администратора и повторите попытку." -ForegroundColor Red
    break
}

$ErrorActionPreference = "SilentlyContinue"
Write-Host "=== 🛡️ Отключение рекламы и рекомендаций Windows ===" -ForegroundColor Cyan
Write-Host "Изменение параметров реестра..." -ForegroundColor Gray

# Функция для безопасного создания ключа и установки значения
function Set-RegValue {
    param (
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [string]$Type = "DWord"
    )
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
}

Write-Host "`n🚫 1. Отключение рекламного идентификатора (Advertising ID)..." -ForegroundColor Yellow
Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0
Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\AdvertisingInfo" -Name "DisabledByGroupPolicy" -Value 1

Write-Host "🚫 2. Отключение рекомендаций и рекламы в меню Пуск..." -ForegroundColor Yellow
$cdmPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
Set-RegValue -Path $cdmPath -Name "SubscribedContent-338387Enabled" -Value 0 # Рекомендации в Пуске
Set-RegValue -Path $cdmPath -Name "SubscribedContent-338388Enabled" -Value 0 # Советы и подсказки
Set-RegValue -Path $cdmPath -Name "SubscribedContent-338389Enabled" -Value 0 # Предложения Windows
Set-RegValue -Path $cdmPath -Name "SystemPaneSuggestionsEnabled" -Value 0
Set-RegValue -Path $cdmPath -Name "SilentInstalledAppsEnabled" -Value 0 # Запрет автоустановки "мусорных" приложений (Candy Crush и т.д.)
Set-RegValue -Path $cdmPath -Name "PreInstalledAppsEnabled" -Value 0
Set-RegValue -Path $cdmPath -Name "OemPreInstalledAppsEnabled" -Value 0

Write-Host "🚫 3. Отключение рекламы на экране блокировки..." -ForegroundColor Yellow
Set-RegValue -Path $cdmPath -Name "RotatingLockScreenOverlayEnabled" -Value 0
Set-RegValue -Path $cdmPath -Name "SubscribedContent-338393Enabled" -Value 0 # Показать рекомендуемый контент на экране блокировки

Write-Host "🚫 4. Отключение рекламы и рекомендаций в Проводнике (Explorer)..." -ForegroundColor Yellow
$expPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-RegValue -Path $expPath -Name "ShowSyncProviderNotifications" -Value 0 # Уведомления синхронизации (OneDrive ads)
Set-RegValue -Path $expPath -Name "LaunchTo" -Value 1 # Открывать "Этот компьютер" вместо "Быстрого доступа" (где есть реклама)

Write-Host "🚫 5. Отключение рекламы в приложении Параметры (Settings)..." -ForegroundColor Yellow
Set-RegValue -Path $cdmPath -Name "SubscribedContent-353698Enabled" -Value 0
Set-RegValue -Path $cdmPath -Name "SubscribedContent-353696Enabled" -Value 0
Set-RegValue -Path $cdmPath -Name "SoftLandingEnabled" -Value 0

Write-Host "🚫 6. Отключение таргетированного опыта и веб-поиска в Пуске..." -ForegroundColor Yellow
Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 0
Set-RegValue -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -Value 1 # Убирает Bing-предложения при поиске в Пуске

Write-Host "🚫 7. Ограничение телеметрии (уровень 'Базовый'), чтобы уменьшить сбор данных для рекламы..." -ForegroundColor Yellow
Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 1

Write-Host "🚫 8. Отключение автоматического обновления приложений из Store (опционально, для контроля)..." -ForegroundColor Yellow
Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\WindowsStore" -Name "AutoDownload" -Value 2

# Очистка кэша Content Delivery Manager (принудительный сброс рекомендаций)
Write-Host "`n🧹 Очистка кэша рекомендательных служб..." -ForegroundColor Cyan
Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps" -Recurse -Force -ErrorAction SilentlyContinue

# Перезапуск проводника для применения изменений
Write-Host "`n🔄 Перезапуск Проводника Windows для применения настроек..." -ForegroundColor Cyan
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Process explorer.exe

Write-Host "`n✅ Готово! Реклама и навязчивые рекомендации Windows отключены." -ForegroundColor Green