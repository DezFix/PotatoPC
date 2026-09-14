# NAME: Удалить файл гибернации hiberfil.sys (освободить ГБ)
# DESC: Команда powercfg /hibernate off: удаляет hiberfil.sys (~40% RAM). Пропадут гибернация и быстрый запуск
# TAGS: 2
# ICON: 💽
# PRESET: potato
# RECOMMENDED: true

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    powercfg /hibernate off | Out-Null
    Write-Output "[OK] Файл гибернации удален. Место освобождено."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
