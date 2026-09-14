# NAME: Остановить службы телеметрии (5 шт.)
# DESC: Стоп + Startup=Disabled для DiagTrack, dmwappushservice, DusmSvc и др. Безопасно, есть откат
# TAGS: 1
# ICON: 🔇
# PRESET: potato, office

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $n = 0
    foreach ($s in @("DiagTrack","dmwappushservice","DcpSvc","diagnosticshub.standardcollector.service","DusmSvc")) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc) {
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
            Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
            $n++
        }
    }
    Write-Output ("[OK] Выключено служб: " + $n)
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
