# NAME: Обновления Windows только Безопасность
# DESC: Настраивает Центр обновлений Windows на получение только обновлений безопасности (блокирует обновления функций)
# CATEGORY: Производительность
# ICON: 🛡️
# RECOMMENDED: true

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

try {
    Write-Host "=== Настройка обновлений Windows (Только безопасность) ===" -ForegroundColor Cyan

    # 1. Получаем текущую версию Windows (например, "23H2")
    $currentVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").DisplayVersion
    if ([string]::IsNullOrWhiteSpace($currentVersion)) {
        $currentVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ReleaseId
    }
    Write-Host "💻 Текущая версия Windows зафиксирована на: $currentVersion" -ForegroundColor Gray

    # 2. Путь к политикам Windows Update
    $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    if (-not (Test-Path $wuPath)) {
        New-Item -Path $wuPath -Force | Out-Null
    }

    # 3. Блокируем обновления функций (Feature Updates), оставляя только качественные (Security/Quality)
    Write-Host "⚙️ Блокировка обновлений функций..." -ForegroundColor Cyan
    
    # Фиксация на текущей версии (официальный метод Microsoft)
    Set-ItemProperty -Path $wuPath -Name "TargetReleaseVersion" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $wuPath -Name "TargetReleaseVersionInfo" -Value $currentVersion -Type String -Force
    
    # Максимальная отсрочка обновлений функций как дополнительный уровень защиты
    Set-ItemProperty -Path $wuPath -Name "DeferFeatureUpdates" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $wuPath -Name "DeferFeatureUpdatesPeriodInDays" -Value 365 -Type DWord -Force

    # 4. Разрешаем получение обновлений безопасности (Quality Updates) без задержек
    Write-Host "🛡️ Настройка получения обновлений безопасности..." -ForegroundColor Cyan
    Set-ItemProperty -Path $wuPath -Name "DeferQualityUpdates" -Value 0 -Type DWord -Force
    
    # Исключить драйверы из качественных обновлений для максимальной стабильности системы
    Set-ItemProperty -Path $wuPath -Name "ExcludeWUDriversInQualityUpdate" -Value 1 -Type DWord -Force

    # 5. Перезапуск службы обновлений для немедленного применения политик
    Write-Host "🔄 Перезапуск службы Центра обновлений Windows..." -ForegroundColor Cyan
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue

    Write-Host "✅ Настройки успешно применены!" -ForegroundColor Green
    Write-Host "ℹ️ Windows будет получать только ежемесячные обновления безопасности и качества для версии $currentVersion." -ForegroundColor Yellow
    Write-Host "ℹ️ Для возврата к стандартным настройкам выполните в PowerShell от админа:" -ForegroundColor Gray
    Write-Host "   Remove-ItemProperty -Path '$wuPath' -Name TargetReleaseVersion, TargetReleaseVersionInfo, DeferFeatureUpdates, DeferFeatureUpdatesPeriodInDays, ExcludeWUDriversInQualityUpdate -ErrorAction SilentlyContinue" -ForegroundColor DarkGray
}
catch {
    Write-Error "❌ Ошибка при настройке обновлений: $_"
    exit 1
}