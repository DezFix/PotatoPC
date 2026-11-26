# NAME: Откат: Вернуть Copilot
# DESC: Снимает политики, отключавшие Copilot, и возвращает его кнопку
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot"
    Del-Prop "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot"
    Del-Prop "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowCopilotButton"
    Del-Prop "HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot" "IsCopilotAvailable"
    Write-Output "[OK] Copilot снова разрешён. Перезайди в систему."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
