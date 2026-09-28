# NAME: 06 · Остановить службы телеметрии (5 шт.)
# DESC: Стоп + Startup=Disabled для DiagTrack, dmwappushservice, DiagnosticsHub, DusmSvc. DcpSvc - в Manual (иначе сломается «Передача рядом»). Есть откат
# TAGS: 1
# ICON: 🔇
# PRESET: potato, office, game

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $n = 0; $skip = 0
    foreach ($s in @("DiagTrack","dmwappushservice","DcpSvc","diagnosticshub.standardcollector.service","DusmSvc")) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if (-not $svc) { continue }
        try {
            # DcpSvc - не телеметрия, а Device Connection Page: он держит
            # «Передача рядом», «Трансляция на это устройство» и Miracast.
            # В Disabled он ломал их молча, без единого слова в описании.
            $mode = if ($s -eq 'DcpSvc') { 'Manual' } else { 'Disabled' }
            Set-Service -Name $s -StartupType $mode -ErrorAction Stop
            if ($mode -eq 'Disabled') { Stop-Service -Name $s -Force -NoWait -ErrorAction SilentlyContinue }
            $n++
        } catch {
            # Раньше -ErrorAction SilentlyContinue и безусловный $n++ давали
            # "[OK] Выключено служб: 5", когда не выключилась ни одна.
            $skip++
            Write-Output ("[!] " + $s + ": " + $_.Exception.Message)
        }
    }
    if ($n -eq 0) {
        Write-Output "[=] Службы телеметрии не найдены или защищены - ничего не менял."
        exit 0
    }
    Write-Output ("[OK] Выключено служб: " + $n)
    if ($skip -gt 0) { Write-Output ("[!] Не удалось: " + $skip) }
    Write-Output "[*] DcpSvc оставлен в Manual - иначе отвалится «Передача рядом» и Трансляция."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
