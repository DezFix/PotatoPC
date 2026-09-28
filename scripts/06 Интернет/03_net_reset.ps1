# NAME: 03 · Сброс сети: winsock + IP + DNS (лечит интернет)
# DESC: Команды netsh winsock reset + netsh int ip reset + чистка DNS-кэша. ВНИМАНИЕ: сбрасывает DNS на DHCP, т.е. отменяет 06 Интернет/01_dns_cloudflare. Нужна перезагрузка!
# TAGS: 2
# ICON: 🔄

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    # netsh и ipconfig пишут ошибки в stderr; при $ErrorActionPreference='Stop'
    # перенаправление 2>&1 обрывает скрипт до проверки $LASTEXITCODE.
    function Invoke-Native {
        param([string]$Exe, [string[]]$NativeArgs)
        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $raw = & $Exe @NativeArgs 2>&1
            return [PSCustomObject]@{ Code = $LASTEXITCODE; Text = (($raw | Out-String).Trim()) }
        } finally { $ErrorActionPreference = $prev }
    }
    Write-Output "[*] Сбрасываю winsock..."
    $r = Invoke-Native -Exe netsh -NativeArgs @('winsock', 'reset')
    if ($r.Text) { Write-Output $r.Text }
    if ($r.Code -ne 0) { throw ("netsh winsock reset: код " + $r.Code + "; " + $r.Text) }
    Write-Output "[*] Сбрасываю IP-стек..."
    $r = Invoke-Native -Exe netsh -NativeArgs @('int', 'ip', 'reset')
    if ($r.Text) { Write-Output $r.Text }
    if ($r.Code -ne 0) { throw ("netsh int ip reset: код " + $r.Code + "; " + $r.Text) }
    $r = Invoke-Native -Exe ipconfig -NativeArgs @('/flushdns')
    if ($r.Code -ne 0) { throw ("ipconfig /flushdns: код " + $r.Code + "; " + $r.Text) }
    Write-Output "[OK] Сеть сброшена. DNS адаптеров вернулся к DHCP (Cloudflare сброшен). ПЕРЕЗАГРУЗИСЬ чтобы применилось."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
