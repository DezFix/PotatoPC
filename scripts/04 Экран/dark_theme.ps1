# NAME: Темная тема
# DESC: Глазам легче вечером
# TAGS: 1
# ICON: 🌙

$ErrorActionPreference = "Stop"
try {
    $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    Set-ItemProperty -Path $p -Name "AppsUseLightTheme" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $p -Name "SystemUsesLightTheme" -Value 0 -Type DWord -Force
    Write-Output "[OK] Темная тема включена."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
