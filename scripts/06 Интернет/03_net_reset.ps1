# NAME: 03 · Сброс сети: winsock + IP + DNS (лечит интернет)
# DESC: Команды netsh winsock reset + netsh int ip reset + чистка DNS-кэша. Помогает когда сайты не открываются. Нужна перезагрузка!
# TAGS: 2
# ICON: 🔄

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    Write-Output "[*] Сбрасываю winsock..."
    $out = & netsh winsock reset 2>&1
    $code = $LASTEXITCODE
    $text = ($out | Out-String)
    Write-Output $text
    if ($code -ne 0) { throw ("netsh winsock reset: код " + $code + "; " + $text.Trim()) }
    Write-Output "[*] Сбрасываю IP-стек..."
    $out = & netsh int ip reset 2>&1
    $code = $LASTEXITCODE
    $text = ($out | Out-String)
    Write-Output $text
    if ($code -ne 0) { throw ("netsh int ip reset: код " + $code + "; " + $text.Trim()) }
    $out = & ipconfig /flushdns 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw ("ipconfig /flushdns: код " + $code + "; " + (($out | Out-String).Trim())) }
    Write-Output "[OK] Сеть сброшена. ПЕРЕЗАГРУЗИСЬ чтобы применилось."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
