# NAME: Проводник стартует с «Этот компьютер»
# DESC: Ставит LaunchTo=1 в реестре: вместо «Главная/Быстрый доступ» сразу диски. Только удобство
# TAGS: 1
# ICON: 📁
# PRESET: office

$ErrorActionPreference = "Stop"
try {
    $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -Path $p -Name "LaunchTo" -Value 1 -Type DWord -Force
    Write-Output "[OK] Проводник будет открываться в «Этот компьютер». Переоткрой окна."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
