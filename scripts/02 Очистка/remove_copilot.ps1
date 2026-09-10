# NAME: Убрать Copilot
# DESC: Выключает ИИ-помощника. Меньше памяти и нагрузки
# TAGS: 1
# ICON: 🤖
# PRESET: potato, office, game
# RECOMMENDED: true

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $items = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"; Name = "TurnOffWindowsCopilot"; Value = 1; Type = "DWord" },
        @{ Path = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"; Name = "TurnOffWindowsCopilot"; Value = 1; Type = "DWord" },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "ShowCopilotButton"; Value = 0; Type = "DWord" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot"; Name = "IsCopilotAvailable"; Value = 0; Type = "DWord" }
    )
    foreach ($i in $items) {
        if (-not (Test-Path $i.Path)) { New-Item -Path $i.Path -Force | Out-Null }
        Set-ItemProperty -Path $i.Path -Name $i.Name -Value $i.Value -Type $i.Type -Force
    }
    Write-Output "[OK] Copilot выключен."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
