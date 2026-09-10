# NAME: Убрать Recall (Win11)
# DESC: Выключает снимки экрана. Только Windows 11
# TAGS: 1,win11
# ICON: 🪟
# PRESET: potato, office, game
# RECOMMENDED: true

$ErrorActionPreference = "Stop"
try {
    $build = [int](Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuildNumber
    if ($build -lt 22000) { Write-Output "[=] Не Win11, пропускаю."; exit 0 }

    $pols = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"; Name = "TurnOffWindowsCopilot"; Value = 1 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Name = "DisableAIDataAnalysis"; Value = 1 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Name = "AllowRecallEnablement"; Value = 0 }
    )
    foreach ($r in $pols) {
        if (-not (Test-Path $r.Path)) { New-Item -Path $r.Path -Force | Out-Null }
        Set-ItemProperty -Path $r.Path -Name $r.Name -Value $r.Value -Type DWord -Force
    }
    Write-Output "[OK] Recall заблокирован политиками."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
