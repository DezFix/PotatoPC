# NAME: 01 · Тёмная тема Windows и приложений
# DESC: Ставит AppsUseLightTheme=0 + SystemUsesLightTheme=0 в реестре. Только внешний вид, на скорость не влияет
# TAGS: 1
# ICON: 🌙
# PRESET: potato, office, game

$ErrorActionPreference = "Stop"
try {
    $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -LiteralPath $p -Name "AppsUseLightTheme" -Value 0 -Type DWord -Force
    Set-ItemProperty -LiteralPath $p -Name "SystemUsesLightTheme" -Value 0 -Type DWord -Force
    # Строка PRESET отсутствовала - скрипт не попадал ни в один пресет,
    # хотя остальные три скрипта этого раздела входят во все.
    Write-Output "[OK] Темная тема включена. Перезайди в систему (или перезапусти Проводник), чтобы применилось."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
