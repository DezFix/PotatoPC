# NAME: Убрать Кортану
# DESC: Выключает голосовой поиск. Пуск ищет быстрее
# TAGS: 1
# ICON: 🎤
# PRESET: potato, office, game
# RECOMMENDED: true

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $items = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "AllowCortana"; Value = 0; Type = "DWord" },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "AllowCloudSearch"; Value = 0; Type = "DWord" },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "DisableWebSearch"; Value = 1; Type = "DWord" },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "CortanaConsent"; Value = 0; Type = "DWord" }
    )
    foreach ($i in $items) {
        if (-not (Test-Path $i.Path)) { New-Item -Path $i.Path -Force | Out-Null }
        Set-ItemProperty -Path $i.Path -Name $i.Name -Value $i.Value -Type $i.Type -Force
    }
    Write-Output "[OK] Кортана выключена."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
