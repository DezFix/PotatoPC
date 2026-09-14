# NAME: Откат «Экрана»: тема, меню Win11, вид Проводника
# DESC: Возвращает светлую тему, новое меню Win11 (сносит CLSID-твик), скрывает расширения и старт Проводника — «Главная»
# TAGS: 1
# ICON: ↩️

$ErrorActionPreference = "Stop"
try {
    $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    Set-ItemProperty -Path $p -Name "AppsUseLightTheme" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $p -Name "SystemUsesLightTheme" -Value 1 -Type DWord -Force
    Remove-Item "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Force -ErrorAction SilentlyContinue
    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Output "[OK] Экран как был. Перезайди чтобы увидеть."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
