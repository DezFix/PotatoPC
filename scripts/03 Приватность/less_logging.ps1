# NAME: Выкл. скрытые журналы трассировки (WMI Autologger)
# DESC: Ставит Start=0 для 7 логгеров (DiagLog, SQM, WiFiSession и др.). Меньше постоянной записи на диск
# TAGS: 1
# ICON: 📝
# PRESET: potato, office
# RECOMMENDED: true

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $n = 0
    foreach ($l in @("AppModel","DiagLog","Diagtrack-Listener","LwtNetLog","SQMLogger","WdiContextLog","WiFiSession")) {
        $p = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$l"
        if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        Set-ItemProperty -Path $p -Name "Start" -Value 0 -Type DWord -Force
        $n++
    }
    Write-Output ("[OK] Журналов выключено: " + $n)
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
