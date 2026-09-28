# NAME: 01 · Выкл. скрытые журналы трассировки (WMI Autologger)
# DESC: Ставит Start=0 для 7 логгеров (DiagLog, SQM, WiFiSession и др.). Меньше постоянной записи на диск
# TAGS: 1
# ICON: 📝
# PRESET: potato, office, game

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $n = 0
    foreach ($l in @("AppModel","DiagLog","Diagtrack-Listener","LwtNetLog","SQMLogger","WdiContextLog","WiFiSession")) {
        $p = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$l"
        # Создавать отсутствующий ключ нельзя: у автологгера есть ещё поля
        # (FileName, Format, BufferSize), и ветка из одного Start=0 - это не
        # "отключение", а битая конфигурация. Нет логгера - пропускаем.
        if (-not (Test-Path -LiteralPath $p)) {
            Write-Output ("[=] Нет логгера на этой системе: " + $l)
            continue
        }
        Set-ItemProperty -LiteralPath $p -Name "Start" -Value 0 -Type DWord -Force
        if ([int](Get-ItemProperty -LiteralPath $p -Name "Start" -ErrorAction Stop).Start -ne 0) { throw ("Start не записался: " + $l) }
        $n++
    }
    if ($n -eq 0) { Write-Output "[=] Логгеров WMI на этой системе нет."; exit 0 }
    Write-Output ("[OK] Журналов выключено: " + $n)
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
