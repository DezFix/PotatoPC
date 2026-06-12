# NAME: Disable Cortana
# DESC: Disables Cortana and web search integration
# TAGS: 3
# ICON: 🎤

$regItems = @(
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "AllowCortana"; Value = 0; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "AllowCloudSearch"; Value = 0; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "AllowCortanaAboveLock"; Value = 0; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "AllowSearchToUseLocation"; Value = 0; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "ConnectedSearchUseWeb"; Value = 0; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "DisableWebSearch"; Value = 1; Type = "DWord" },
    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "CortanaConsent"; Value = 0; Type = "DWord" },
    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "CortanaConsent2"; Value = 0; Type = "DWord" }
)

foreach ($item in $regItems) {
    if (!(Test-Path $item.Path)) { New-Item -Path $item.Path -Force | Out-Null }
    Set-ItemProperty -Path $item.Path -Name $item.Name -Value $item.Value -Type $item.Type -Force
}

Write-Host "Cortana and web search disabled successfully"
