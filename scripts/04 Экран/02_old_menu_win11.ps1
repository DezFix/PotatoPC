# NAME: 02 · Классическое меню правого клика как в Win10 (Win11)
# DESC: Возвращает полное контекстное меню через CLSID {86ca1aa0…}. Без пункта «Показать доп. параметры». Перезапусти Проводник
# TAGS: 1,win11
# ICON: 🖱️
# PRESET: potato, office, game

$ErrorActionPreference = "Stop"
try {
    # На Win11 24H2/25H2 этот CLSID на части сборок перестал давать эффект.
    # Раньше скрипт обещал меню в заголовке и молча ничего не делал.
    $cv = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
    if ($null -ne $cv -and $cv.CurrentBuildNumber) {
        $build = [int]$cv.CurrentBuildNumber
        if ($build -ge 26200) {
            Write-Output ("[=] На сборке " + $build + " этот способ с меню правого клика не работает - Microsoft убрала CLSID.")
            Write-Output "    Ничего не менял. Используй обновление или оставь меню как есть."
            exit 0
        }
    }
    $p = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -LiteralPath $p -Name "(Default)" -Value "" -Force
    Write-Output "[OK] Старое меню включено. Перезапусти Проводник (или войди заново), чтобы увидеть."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
