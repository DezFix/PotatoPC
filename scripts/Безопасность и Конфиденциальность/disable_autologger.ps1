# NAME: Отключение автоматического логирования (AutoLogger)
# DESC: Отключает сеансы автоматического логирования WMI для различных системных компонентов
# CATEGORY: Конфиденциальность
# ICON: 📝

$loggers = @(
    "AppModel",
    "Cellcore",
    "CloudExperienceHostOobe",
    "DataMarket",
    "DiagLog",
    "Diagtrack-Listener",
    "LwtNetLog",
    "SQMLogger",
    "WdiContextLog",
    "WiFiSession"
)

foreach ($logger in $loggers) {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$logger"
    if (!(Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name "Start" -Value 0 -Type DWord -Force
}

Write-Host "WMI AutoLogger sessions disabled successfully"