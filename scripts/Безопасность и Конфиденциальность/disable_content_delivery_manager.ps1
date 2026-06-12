# NAME: Отключение менеджера доставки контента (CDM)
# DESC: Отключает менеджер доставки контента и системные рекомендации
# TAGS: 2
# ICON: 📦

$regPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
if (!(Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }

$regItems = @(
    @{ Name = "ContentDeliveryAllowed"; Value = 0 },
    @{ Name = "SubscribedContent-338387Enabled"; Value = 0 },
    @{ Name = "SubscribedContent-338388Enabled"; Value = 0 },
    @{ Name = "SubscribedContent-338389Enabled"; Value = 0 },
    @{ Name = "SubscribedContent-353698Enabled"; Value = 0 },
    @{ Name = "SystemPaneSuggestionsEnabled"; Value = 0 }
)

foreach ($item in $regItems) {
    Set-ItemProperty -Path $regPath -Name $item.Name -Value $item.Value -Type DWord -Force
}

Write-Host "Content Delivery Manager disabled successfully"
