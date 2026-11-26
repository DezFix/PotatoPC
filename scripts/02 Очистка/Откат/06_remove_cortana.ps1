# NAME: Откат: Вернуть Кортану и веб-поиск
# DESC: Снимает политики поиска: Кортана и результаты из интернета в Пуске возвращаются
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    $s = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
    foreach ($n in @("AllowCortana","AllowCloudSearch","DisableWebSearch")) { Del-Prop $s $n }
    Del-Prop "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "CortanaConsent"
    Write-Output "[OK] Поиск возвращён к заводскому. Перезайди в систему."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
