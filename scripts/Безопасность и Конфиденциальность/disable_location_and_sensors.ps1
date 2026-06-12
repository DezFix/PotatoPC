# NAME: Отключение геолокации и датчиков
# DESC: Отключает отслеживание местоположения, работу датчиков и автоматическое обновление офлайн-карт
# TAGS: 2
# ICON: 📍
# RECOMMENDED: true

$regItems = @(
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"; Name = "DisableLocation"; Value = 1; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"; Name = "DisableSensors"; Value = 1; Type = "DWord" },
    @{ Path = "HKLM:\SYSTEM\Maps"; Name = "AutoUpdateEnabled"; Value = 0; Type = "DWord" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Permissions\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}"; Name = "SensorPermissionState"; Value = 0; Type = "DWord" },
    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"; Name = "Value"; Value = "Deny"; Type = "String" },
    @{ Path = "HKLM:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"; Name = "Value"; Value = "Deny"; Type = "String" },
    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Geolocation"; Name = "Status"; Value = 0; Type = "DWord" },
    @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration"; Name = "Status"; Value = 0; Type = "DWord" },
    @{ Path = "HKLM:\Software\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting"; Name = "Value"; Value = 0; Type = "DWord" },
    @{ Path = "HKLM:\Software\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots"; Name = "Value"; Value = 0; Type = "DWord" }
)

foreach ($item in $regItems) {
    if (!(Test-Path $item.Path)) { New-Item -Path $item.Path -Force | Out-Null }
    Set-ItemProperty -Path $item.Path -Name $item.Name -Value $item.Value -Type $item.Type -Force
}

# Disable maps update task
try {
    Disable-ScheduledTask -TaskName "\Microsoft\Windows\Maps\MapsUpdateTask" -ErrorAction SilentlyContinue | Out-Null
} catch {}

Write-Host "Location tracking and sensors disabled successfully"
