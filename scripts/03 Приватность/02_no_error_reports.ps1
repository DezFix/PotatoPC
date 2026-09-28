# NAME: 02 · Выкл. отчёты об ошибках в Microsoft (WER)
# DESC: Ставит WER Disabled=1, службу WerSvc в Disabled и гасит задачу QueueReporting. Отчёты в Microsoft не уходят (и локальные дампы тоже не пишутся)
# TAGS: 1
# ICON: 🔕
# PRESET: potato, office, game

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -LiteralPath $p -Name "Disabled" -Value 1 -Type DWord -Force
    if ([int](Get-ItemProperty -LiteralPath $p -Name "Disabled" -ErrorAction Stop).Disabled -ne 1) { throw "Политика WER не записалась" }

    # WerSvc часто защищён: молчаливый SilentlyContinue давал "[OK] Отчеты
    # выключены" при службе, которую так и не отключили.
    $svcFail = $false
    if (Get-Service -Name "WerSvc" -ErrorAction SilentlyContinue) {
        try { Set-Service -Name "WerSvc" -StartupType Disabled -ErrorAction Stop }
        catch { $svcFail = $true; Write-Output ("[!] WerSvc: " + $_.Exception.Message) }
        Stop-Service -Name "WerSvc" -Force -ErrorAction SilentlyContinue
    }
    $taskOff = $false
    try {
        $t = Get-ScheduledTask -TaskName "QueueReporting" -TaskPath "\Microsoft\Windows\Windows Error Reporting\" -ErrorAction Stop
        if ($t.State -ne 'Disabled') {
            Disable-ScheduledTask -TaskName "QueueReporting" -TaskPath "\Microsoft\Windows\Windows Error Reporting\" -ErrorAction Stop | Out-Null
        }
        $taskOff = $true
    } catch {}
    Write-Output "[OK] Отчёты в Microsoft выключены. Локальные отчёты о падениях тоже не собираются."
    if ($svcFail) { Write-Output "[!] Службу WerSvc отключить не вышло - политика WER всё равно блокирует отправку." }
    if (-not $taskOff) { Write-Output "[*] Задачи QueueReporting на этой системе нет." }
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
