# NAME: Откат: Обычный приоритет для игр
# DESC: Возвращает заводские значения MMCSS: NetworkThrottlingIndex=10, SystemResponsiveness=20, профиль Games по умолчанию
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    $k = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    if (Test-Path -LiteralPath $k) {
        Del-Prop $k "NoLazyMode"
        Set-ItemProperty -LiteralPath $k -Name "NetworkThrottlingIndex" -Value 10 -Type DWord -Force
        Set-ItemProperty -LiteralPath $k -Name "SystemResponsiveness" -Value 20 -Type DWord -Force
        $g = "$k\Tasks\Games"
        if (Test-Path -LiteralPath $g) {
            # Заводской профиль Games: GPU Priority 8, Priority 2, Scheduling Category Medium.
            Set-ItemProperty -LiteralPath $g -Name "Scheduling Category" -Value "Medium" -Type String -Force
        }
    }
    Write-Output "[OK] Приоритеты игр возвращены. Нужна перезагрузка."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
