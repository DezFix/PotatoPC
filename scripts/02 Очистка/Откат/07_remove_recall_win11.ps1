# NAME: Откат: Вернуть Recall
# DESC: Снимает политики, блокирующие Recall (сам Recall включается в Параметрах)
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis"
    Del-Prop "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis"
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "AllowRecallEnablement"
    Write-Output "[OK] Политики Recall сняты. Нужна перезагрузка."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
