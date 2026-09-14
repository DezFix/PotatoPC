# NAME: Тёмная тема Windows и приложений
# DESC: Ставит AppsUseLightTheme=0 + SystemUsesLightTheme=0 в реестре. Только внешний вид, на скорость не влияет
# TAGS: 1
# ICON: 🌙

$ErrorActionPreference = "Stop"
try {
    $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -Path $p -Name "AppsUseLightTheme" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $p -Name "SystemUsesLightTheme" -Value 0 -Type DWord -Force
    Write-Output "[OK] Темная тема включена."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
