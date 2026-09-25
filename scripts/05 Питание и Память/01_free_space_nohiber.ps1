# NAME: 01 · Удалить файл гибернации hiberfil.sys (освободить ГБ)
# DESC: Команда powercfg /hibernate off: удаляет hiberfil.sys (~40% RAM). Пропадут гибернация и быстрый запуск
# TAGS: 2
# ICON: 💽
# PRESET: potato

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $out = & powercfg /hibernate off 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw ("powercfg /hibernate off: код " + $code + "; " + (($out | Out-String).Trim())) }
    Write-Output "[OK] Файл гибернации удален. Место освобождено."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
