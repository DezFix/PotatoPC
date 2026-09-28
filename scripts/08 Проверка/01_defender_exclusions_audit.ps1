# NAME: 01 · Аудит исключений Defender (только показ)
# DESC: Показывает исключения сканирования (папки/файлы/процессы/расширения/IP). Вирусы любят прятаться в исключениях. Ничего не меняет
# TAGS: 1
# ICON: 📋

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    Write-Output "=== Исключения Defender (только чтение) ==="
    $p = $null
    try { $p = Get-MpPreference -ErrorAction Stop } catch { $p = $null }
    if ($null -eq $p) {
        # Defender выключен или заменён сторонним антивирусом - это нормальное
        # состояние машины, а не ошибка скрипта. Раньше здесь был exit 1 с
        # советом "выключи Защиту от подделки", которая к этому случаю
        # отношения не имеет.
        Write-Output "[*] Defender не активен (выключен или заменён сторонним антивирусом) - исключения смотреть негде."
        Write-Output "[OK] Это не ошибка. Ничего не менялось."
        exit 0
    }
    $found = 0
    foreach ($e in @($p.ExclusionPath)) { if ($e) { Write-Output ("[!] Папка: " + $e); $found++ } }
    foreach ($e in @($p.ExclusionFile)) { if ($e) { Write-Output ("[!] Файл: " + $e); $found++ } }
    foreach ($e in @($p.ExclusionProcess)) { if ($e) { Write-Output ("[!] Процесс: " + $e); $found++ } }
    foreach ($e in @($p.ExclusionExtension)) { if ($e) { Write-Output ("[!] Расширение: " + $e); $found++ } }
    foreach ($e in @($p.ExclusionIpAddress)) { if ($e) { Write-Output ("[!] IP: " + $e); $found++ } }
    foreach ($e in @($p.ExclusionDrive)) { if ($e) { Write-Output ("[!] Диск: " + $e); $found++ } }
    if ($found -eq 0) { Write-Output "[OK] Исключений нет — так и должно быть." }
    else { Write-Output ("[!] Всего исключений: " + $found + ". Не узнаёшь — удали в Безопасности Windows.") }
    exit 0
} catch {
    Write-Output ("[X] Не вышло прочитать состояние Defender: " + $_)
    exit 1
}
