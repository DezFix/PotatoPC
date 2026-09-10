# NAME: Вернуть экран
# DESC: Светлая тема и новое меню Win11 обратно
# TAGS: 1
# ICON: ↩️

$ErrorActionPreference = "Stop"
try {
    $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    Set-ItemProperty -Path $p -Name "AppsUseLightTheme" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $p -Name "SystemUsesLightTheme" -Value 1 -Type DWord -Force
    Remove-Item "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output "[OK] Экран как был. Перезайди чтобы увидеть."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
