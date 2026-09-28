# NAME: 03 · Показать расширения файлов и скрытые файлы (Проводник)
# DESC: Ставит HideFileExt=0 + Hidden=1: видно .exe/.txt и скрытые папки. Системные файлы остаются скрыты
# TAGS: 1
# ICON: 👁️
# PRESET: office

$ErrorActionPreference = "Stop"
try {
    $a = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    if (-not (Test-Path $a)) { New-Item -Path $a -Force | Out-Null }
    Set-ItemProperty -LiteralPath $a -Name "HideFileExt" -Value 0 -Type DWord -Force
    Set-ItemProperty -LiteralPath $a -Name "Hidden" -Value 1 -Type DWord -Force
    # Explorer читает эти ключи на лету - перезапуск Проводника не нужен,
    # раньше сообщение о нём было лишним.
    Write-Output "[OK] Расширения и скрытые файлы видны (применится сразу)."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
