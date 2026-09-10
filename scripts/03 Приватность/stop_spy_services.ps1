# NAME: Стоп службы слежки
# DESC: Выключает 5 служб сбора данных. Безопасно
# TAGS: 1
# ICON: 🔇
# PRESET: potato, office
# RECOMMENDED: true

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
