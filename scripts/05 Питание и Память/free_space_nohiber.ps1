# NAME: Освободить место
# DESC: Убирает гибернацию ради гигабайтов. Запуск станет дольше
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
