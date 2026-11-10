# NAME: 04 · Отключить гостевую учётную запись
# DESC: Disable-LocalUser Guest: гостевая запись выключена. Заводское состояние Windows; скрипт закрывает её, если кто-то включал
# TAGS: 1
# ICON: 🚫
# PRESET: potato,office,game

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $guest = Get-LocalUser -Name Guest -ErrorAction SilentlyContinue
    if (-not $guest) { Write-Output "[=] Гостевая запись не найдена. Ничего не менял."; exit 0 }
    if (-not $guest.Enabled) { Write-Output "[=] Гостевая запись уже выключена. Ничего не менял."; exit 0 }
    Disable-LocalUser -Name Guest -ErrorAction Stop
    $check = Get-LocalUser -Name Guest -ErrorAction Stop
    if ($check.Enabled) { throw "Гостевая запись осталась включённой" }
    Write-Output "[OK] Гостевая учётная запись отключена."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
