# NAME: Отключение отчетов об ошибках (WER)
# DESC: Отключает Windows Error Reporting и Compatibility Assistant
# TAGS: 2
# ICON: 🚫

Write-Host "[+] Отключение отчетов об ошибках..." -ForegroundColor Yellow

$werPath = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"
if (!(Test-Path $werPath)) { New-Item -Path $werPath -Force | Out-Null }
Set-ItemProperty -Path $werPath -Name "Disabled" -Value 1 -Type DWord -Force

$hwPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\HandwritingErrorReports"
if (!(Test-Path $hwPath)) { New-Item -Path $hwPath -Force | Out-Null }
Set-ItemProperty -Path $hwPath -Name "PreventHandwritingErrorReports" -Value 1 -Type DWord -Force

foreach ($svc in @("WerSvc", "PcaSvc")) {
    try {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
    } catch {}
}

$tasks = @(
    "\Microsoft\Windows\Windows Error Reporting\QueueReporting",
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticResolver",
    "\Microsoft\Windows\Diagnosis\Scheduled"
)
foreach ($task in $tasks) {
    try { Disable-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue | Out-Null } catch {}
}
Write-Host "[+] WER успешно отключен!" -ForegroundColor Green
