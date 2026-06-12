# NAME: Disable Copilot
# DESC: Disables Windows Copilot AI assistant
# CATEGORY: Privacy
# ICON: 🤖

$regItems = @(
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"; Name = "TurnOffWindowsCopilot"; Value = 1; Type = "DWord" },
    @{ Path = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"; Name = "TurnOffWindowsCopilot"; Value = 1; Type = "DWord" },
    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "ShowCopilotButton"; Value = 0; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot"; Name = "IsCopilotAvailable"; Value = 0; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot"; Name = "CopilotDisabledReason"; Value = "IsEnabledForGeographicRegionFailed"; Type = "String" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsCopilot"; Name = "AllowCopilotRuntime"; Value = 0; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked"; Name = "{CB3B0003-8088-4EDE-8769-8B354AB2FF8C}"; Value = ""; Type = "String" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot\BingChat"; Name = "IsUserEligible"; Value = 0; Type = "DWord" }
)

foreach ($item in $regItems) {
    if (!(Test-Path $item.Path)) { New-Item -Path $item.Path -Force | Out-Null }
    Set-ItemProperty -Path $item.Path -Name $item.Name -Value $item.Value -Type $item.Type -Force
}

Write-Host "Windows Copilot disabled successfully"