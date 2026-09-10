# NAME: Что тормозит?
# DESC: Только смотрит, ничего не меняет
# TAGS: 1
# ICON: 🔬

$ErrorActionPreference = "Stop"
try {
    Write-Output "=== Только чтение ==="
    try {
        $s = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
        Write-Output ("[*] SMBv1: " + $s.State)
    } catch { Write-Output "[!] SMBv1 не проверился" }
    foreach ($svc in @("DiagTrack","dmwappushservice","DusmSvc")) {
        $o = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($o) { Write-Output ("[*] " + $svc + ": " + $o.Status) }
    }
    Write-Output "[OK] Проверка закончена."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
