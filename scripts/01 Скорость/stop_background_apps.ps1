# NAME: Стоп фон
# DESC: Запрещает приложениям жрать память в фоне
# TAGS: 1
# ICON: ✋
# PRESET: potato, office, game
# RECOMMENDED: true

$ErrorActionPreference = "Stop"
try {
    $a = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
    if (-not (Test-Path $a)) { New-Item -Path $a -Force | Out-Null }
    Set-ItemProperty -Path $a -Name "GlobalUserDisabled" -Value 1 -Type DWord -Force

    $s = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"
    if (-not (Test-Path $s)) { New-Item -Path $s -Force | Out-Null }
    Set-ItemProperty -Path $s -Name "BackgroundAppGlobalToggle" -Value 0 -Type DWord -Force

    Write-Output "[OK] Фоновые приложения выключены. Больше памяти для твоих программ."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
