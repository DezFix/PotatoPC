# NAME: Откат: Виджеты и «Новости и интересы»
# DESC: Снимает политику AllowNewsAndInterests и возвращает кнопку виджетов на панель задач
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests"
    # TaskbarDa на Windows 11 защищён от записи - если не вышло, кнопку
    # можно вернуть в Параметры > Персонализация > Панель задач.
    try { Del-Prop "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa" } catch {}
    Write-Output "[OK] Виджеты возвращены. Перезайди в систему."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
