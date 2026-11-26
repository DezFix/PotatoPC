# NAME: Откат: Журналы трассировки WMI
# DESC: Включает обратно 7 скрытых журналов (DiagLog, SQM, WiFiSession и др.)
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    $n = 0
    foreach ($l in @("AppModel","DiagLog","Diagtrack-Listener","LwtNetLog","SQMLogger","WdiContextLog","WiFiSession")) {
        $k = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$l"
        if (-not (Test-Path -LiteralPath $k)) { continue }
        Set-ItemProperty -LiteralPath $k -Name "Start" -Value 1 -Type DWord -Force
        $n++
    }
    Write-Output ("[*] Журналов включено: " + $n)
    Write-Output "[OK] Журналы включатся после перезагрузки."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
