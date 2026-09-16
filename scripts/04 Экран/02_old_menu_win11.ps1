# NAME: 02 · Классическое меню правого клика как в Win10 (Win11)
# DESC: Возвращает полное контекстное меню через CLSID {86ca1aa0…}. Без пункта «Показать доп. параметры». Нужен перезаход
# TAGS: 1,win11
# ICON: 🖱️
# PRESET: potato, office, game

$ErrorActionPreference = "Stop"
try {
    $p = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -Path $p -Name "(Default)" -Value "" -Force
    Write-Output "[OK] Старое меню включено. Перезайди чтобы увидеть."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
