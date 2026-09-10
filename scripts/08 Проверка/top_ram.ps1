# NAME: Что жрёт память?
# DESC: Показывает топ прожорливых программ. Только смотрит
# TAGS: 1
# ICON: 🔍

$ErrorActionPreference = "Stop"
try {
    Write-Output "=== Топ по памяти ==="
    Get-Process -ErrorAction Stop | Sort-Object WS -Descending | Select-Object -First 10 | ForEach-Object {
        Write-Output (($_.ProcessName + ": " + [math]::Round($_.WS / 1MB) + " МБ"))
    }
    Write-Output "[OK] Ничего не менялось."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
