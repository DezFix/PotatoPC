# NAME: Игровой режим Windows (Game Mode)
# DESC: Включает AutoGameMode + GameDVR-оптимизации для игр через реестр HKCU. Безопасно, только для игр
# TAGS: 1
# ICON: 🕹️
# PRESET: game

$ErrorActionPreference = "Stop"
try {
    $g = "HKCU:\Software\Microsoft\GameBar"
    if (-not (Test-Path $g)) { New-Item -Path $g -Force | Out-Null }
    Set-ItemProperty -Path $g -Name "AllowAutoGameMode" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $g -Name "AutoGameModeEnabled" -Value 1 -Type DWord -Force
    Write-Output "[OK] Игровой режим включён."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
