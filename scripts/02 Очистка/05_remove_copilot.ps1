# NAME: 05 · Отключить Copilot (ИИ-помощник)
# DESC: Блокирует политиками TurnOffWindowsCopilot (HKLM+HKCU) + убирает кнопку с панели. Сам пакет Copilot не удаляет. Нужен перезаход
# TAGS: 1
# ICON: 🤖
# PRESET: potato, office, game

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $items = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"; Name = "TurnOffWindowsCopilot"; Value = 1; Type = "DWord" },
        @{ Path = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"; Name = "TurnOffWindowsCopilot"; Value = 1; Type = "DWord" },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "ShowCopilotButton"; Value = 0; Type = "DWord" },
        # IsCopilotAvailable - undocumented в Policy CSP, оставлен как есть:
        # на части сборок кнопка убирается только им.
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot"; Name = "IsCopilotAvailable"; Value = 0; Type = "DWord" }
    )
    foreach ($i in $items) {
        if (-not (Test-Path $i.Path)) { New-Item -Path $i.Path -Force | Out-Null }
        Set-ItemProperty -LiteralPath $i.Path -Name $i.Name -Value $i.Value -Type $i.Type -Force
    }
    Write-Output "[OK] Copilot выключен. Нужен перезаход, чтобы кнопка исчезла с панели."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
