# NAME: 13 · Запрет фоновой работы магазинных приложений (UWP)
# DESC: Ставит GlobalUserDisabled=1 и BackgroundAppGlobalToggle=0: новые UWP не стартуют в фоне. Уже запущенные закроются после перезахода. Обычные .exe не трогает
# TAGS: 1
# ICON: ✋
# PRESET: potato, office, game

$ErrorActionPreference = "Stop"
try {
    $a = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
    if (-not (Test-Path $a)) { New-Item -Path $a -Force | Out-Null }
    Set-ItemProperty -Path $a -Name "GlobalUserDisabled" -Value 1 -Type DWord -Force

    $s = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"
    if (-not (Test-Path $s)) { New-Item -Path $s -Force | Out-Null }
    Set-ItemProperty -Path $s -Name "BackgroundAppGlobalToggle" -Value 0 -Type DWord -Force

    # Скрипт меняет только разрешение на фоновый запуск. Уже работающие UWP
    # продолжают работать до перезахода - обещать "не висят в фоне" сразу
    # было неправдой.
    Write-Output "[OK] Фоновый запуск UWP запрещён. Перезайди в систему, чтобы уже запущенные закрылись."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
