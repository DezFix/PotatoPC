# NAME: 03 · Сброс сети: winsock + IP + DNS (лечит интернет)
# DESC: Команды netsh winsock reset + netsh int ip reset + чистка DNS-кэша. Помогает когда сайты не открываются. Нужна перезагрузка!
# TAGS: 2
# ICON: 🔄

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    Write-Output "[*] Сбрасываю winsock..."
    netsh winsock reset | Out-String | Write-Output
    Write-Output "[*] Сбрасываю IP-стек..."
    netsh int ip reset | Out-String | Write-Output
    try { ipconfig /flushdns 2>&1 | Out-Null } catch {}
    Write-Output "[OK] Сеть сброшена. ПЕРЕЗАГРУЗИСЬ чтобы применилось."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
