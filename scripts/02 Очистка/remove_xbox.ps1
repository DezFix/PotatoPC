# NAME: Убрать Xbox
# DESC: Выключает службы Xbox. Офисному ПК да, геймеру нет
# TAGS: 2
# ICON: 🎮
# PRESET: potato, office

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $list = @("XblGameSave","XboxNetApiSvc","XboxGipSvc","xbgm")
    $n = 0
    foreach ($s in $list) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc) {
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
            Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
            $n++
        }
    }
    Write-Output ("[OK] Служб Xbox выключено: " + $n)
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
