# NAME: 08 01 · Аудит исключений Defender (только показ)
# DESC: Показывает исключения сканирования (папки/файлы/процессы). Вирусы любят прятаться в исключениях. Ничего не меняет
# TAGS: 1
# ICON: 📋

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    Write-Output "=== Исключения Defender (только чтение) ==="
    $p = Get-MpPreference -ErrorAction Stop
    $found = 0
    foreach ($e in @($p.ExclusionPath)) { if ($e) { Write-Output ("[!] Путь: " + $e); $found++ } }
    foreach ($e in @($p.ExclusionProcess)) { if ($e) { Write-Output ("[!] Процесс: " + $e); $found++ } }
    foreach ($e in @($p.ExclusionExtension)) { if ($e) { Write-Output ("[!] Расширение: " + $e); $found++ } }
    foreach ($e in @($p.ExclusionIpAddress)) { if ($e) { Write-Output ("[!] IP: " + $e); $found++ } }
    if ($found -eq 0) { Write-Output "[OK] Исключений нет — так и должно быть." }
    else { Write-Output ("[!] Всего исключений: " + $found + ". Не узнаёшь — удали в Безопасности Windows.") }
    exit 0
} catch {
    Write-Output ("[X] Не вышло. Выключи 'Защиту от подделки' и повтори: " + $_)
    exit 1
}
