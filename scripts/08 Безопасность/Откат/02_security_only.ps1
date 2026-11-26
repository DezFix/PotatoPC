# NAME: Откат: Крупные обновления без отсрочки
# DESC: Снимает политику отсрочки крупных обновлений - Windows снова ставит их по своему графику
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    $w = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    foreach ($n in @("DeferFeatureUpdates","DeferFeatureUpdatesPeriodInDays","DeferQualityUpdates")) { Del-Prop $w $n }
    Write-Output "[OK] Отсрочка обновлений снята."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
