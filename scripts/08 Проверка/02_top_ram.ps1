# NAME: 02 · Диагностика: топ-10 по памяти (только показ)
# DESC: Выводит Get-Process по рабочему набору (МБ). Ничего не меняет и не закрывает — просто отчёт
# TAGS: 1
# ICON: 🔍

$ErrorActionPreference = "Stop"
try {
    Write-Output "=== Топ по памяти ==="
    $totalMB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)
    Get-Process -ErrorAction Stop | Sort-Object WS -Descending | Select-Object -First 10 | ForEach-Object {
        $mb = [math]::Round($_.WS / 1MB)
        $pct = if ($totalMB -gt 0) { [math]::Round($mb / $totalMB * 100, 1) } else { 0 }
        Write-Output ("{0}: {1} МБ ({2}% RAM)" -f $_.ProcessName, $mb, $pct)
    }
    $freeMB = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1KB)
    Write-Output ("[*] Всего RAM: {0} МБ, свободно: {1} МБ" -f $totalMB, $freeMB)
    Write-Output "[OK] Ничего не менялось."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
