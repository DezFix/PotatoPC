# NAME: 06 · Чистка WinSxS через DISM (освободить гигабайты)
# DESC: Команда DISM StartComponentCleanup: удаляет старые копии компонентов Windows. Идёт 10–30 мин, НЕ прерывать и не выключать ПК!
# TAGS: 2
# ICON: 🧰

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    Write-Output "[*] Запускаю DISM-чистку (долго, жди)..."
    $out = & dism /Online /Cleanup-Image /StartComponentCleanup 2>&1
    $code = $LASTEXITCODE
    $text = ($out | Out-String)
    Write-Output $text
    if ($code -notin @(0, 3010)) { throw ("DISM: код " + $code + "; " + $text.Trim()) }
    if ($code -eq 3010) { Write-Output "[=] WinSxS почищен, требуется перезагрузка." }
    else { Write-Output "[OK] WinSxS почищен." }
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
