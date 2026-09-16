# NAME: 05 06 · Чистка WinSxS через DISM (освободить гигабайты)
# DESC: Команда DISM StartComponentCleanup: удаляет старые копии компонентов Windows. Идёт 10–30 мин, НЕ прерывать и не выключать ПК!
# TAGS: 2
# ICON: 🧰

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    Write-Output "[*] Запускаю DISM-чистку (долго, жди)..."
    $out = dism /Online /Cleanup-Image /StartComponentCleanup 2>&1 | Out-String
    Write-Output $out
    Write-Output "[OK] WinSxS почищен."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
