# NAME: 06 · Откат «Экрана»: тема, меню Win11, вид Проводника
# DESC: Возвращает светлую тему, новое меню Win11 (сносит CLSID-твик), скрывает расширения и снимает старт Проводника с «Этот компьютер». Откат раздела «Экран»
# TAGS: 1
# ICON: ↩️

$ErrorActionPreference = "Stop"
try {
    $fail = 0
    # Раньше строки 9-10 шли без проверки существования ключа и без
    # -ErrorAction: при $ErrorActionPreference='Stop' отсутствие ключа
    # Themes\Personalize обрывало откат, и CLSID/расширения/старт Проводника
    # оставались не откаченными.
    $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    try {
        if (-not (Test-Path -LiteralPath $p)) { New-Item -Path $p -Force | Out-Null }
        Set-ItemProperty -LiteralPath $p -Name "AppsUseLightTheme" -Value 1 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -LiteralPath $p -Name "SystemUsesLightTheme" -Value 1 -Type DWord -Force -ErrorAction Stop
    } catch { $fail++; Write-Output ("[!] Тема: " + $_.Exception.Message) }
    try {
        Remove-Item -LiteralPath "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Force -ErrorAction Stop
    } catch {}
    $a = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    if (-not (Test-Path -LiteralPath $a)) { New-Item -Path $a -Force | Out-Null }
    Set-ItemProperty -LiteralPath $a -Name "HideFileExt" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -LiteralPath $a -Name "Hidden" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
    # Заводского значения у LaunchTo нет - его удаление надёжнее, чем запись
    # «магической» двойки, о которой источники спорят.
    try { Remove-ItemProperty -LiteralPath $a -Name "LaunchTo" -Force -ErrorAction Stop } catch {}
    if ($fail -gt 0) { Write-Output ("[X] Экран откатан частично; ошибок: " + $fail); exit 1 }
    Write-Output "[OK] Экран как был. Перезапусти Проводник."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
