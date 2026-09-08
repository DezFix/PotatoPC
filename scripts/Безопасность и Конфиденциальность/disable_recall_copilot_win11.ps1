# NAME: Отключение Recall и Copilot+ (Win11)
# DESC: Политики против Recall, Copilot в панели задач и Edge Discover на Windows 11 23H2/24H2
# TAGS: 1,win11
# ICON: 🪟
# RECOMMENDED: true

function Disable-RecallCopilot {
    Write-Host "[+] Отключение Recall / Copilot+ ..." -ForegroundColor Yellow

    try {
        $build = [int](Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuildNumber
        if ($build -lt 22000) {
            Write-Host "[!] Это не Windows 11 (build $build) — пропускаю." -ForegroundColor DarkGray
            return
        }
        Write-Host "[*] Windows 11 build $build" -ForegroundColor Cyan
    } catch {}

    $pols = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"; Name = "TurnOffWindowsCopilot"; Value = 1 },
        @{ Path = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"; Name = "TurnOffWindowsCopilot"; Value = 1 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI";      Name = "DisableAIDataAnalysis"; Value = 1 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI";      Name = "AllowRecallEnablement"; Value = 0 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge";                   Name = "HubsSidebarEnabled";    Value = 0 }
    )
    foreach ($r in $pols) {
        try {
            if (-not (Test-Path $r.Path)) { New-Item -Path $r.Path -Force | Out-Null }
            Set-ItemProperty -Path $r.Path -Name $r.Name -Value $r.Value -Type DWord -Force
            Write-Host "[+] $($r.Path | Split-Path -Leaf)\$($r.Name) = $($r.Value)" -ForegroundColor Green
        } catch {
            Write-Host "[!] $($r.Name): $_" -ForegroundColor DarkGray
        }
    }

    # Кнопка Copilot на панели задач
    try {
        $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Set-ItemProperty -Path $p -Name "ShowCopilotButton" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host "[+] Кнопка Copilot скрыта" -ForegroundColor Green
    } catch {}

    Write-Host "[i] Recall полностью выпиливается только на Copilot+ PC через удаление компонента; политики блокируют сбор снимков." -ForegroundColor Yellow
    Write-Host "[+] Recall / Copilot+ отключены!" -ForegroundColor Green
}

Disable-RecallCopilot
