# NAME: 07 · Отключить Recall — скриншоты для ИИ (Win11)
# DESC: Блокирует политиками AllowRecallEnablement=0: Windows не делает постоянные снимки экрана. Только Win11 24H2+ (build 26100+)
# TAGS: 1,win11
# ICON: 🪟
# PRESET: potato, office, game

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $cv = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop
    $build = [int]$cv.CurrentBuildNumber
    $displayVersion = [string]$cv.DisplayVersion
    if ($build -lt 26100) {
        Write-Output ("[=] Recall доступен только в Windows 11 24H2+ (build 26100+); текущая версия: " + $displayVersion + " (build " + $build + ").")
        exit 0
    }

    $pols = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"; Name = "TurnOffWindowsCopilot"; Value = 1 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Name = "DisableAIDataAnalysis"; Value = 1 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Name = "AllowRecallEnablement"; Value = 0 }
    )
    foreach ($r in $pols) {
        if (-not (Test-Path $r.Path)) { New-Item -Path $r.Path -Force | Out-Null }
        Set-ItemProperty -Path $r.Path -Name $r.Name -Value $r.Value -Type DWord -Force
    }
    Write-Output ("[OK] Recall заблокирован политиками (" + $displayVersion + ", build " + $build + ").")
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
