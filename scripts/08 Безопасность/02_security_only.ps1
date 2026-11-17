# NAME: Отложить крупные обновления Windows на год
# DESC: Обновления безопасности приходят как обычно, а переход на новую версию Windows откладывается на 365 дней. Работает в Pro/Enterprise; в Home Windows правило игнорирует
# TAGS: 2
# ICON: 🛡️
# PRESET: potato,office
# CHECK: Test-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'DeferFeatureUpdatesPeriodInDays' 365

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $w = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    if (-not (Test-Path $w)) { New-Item -Path $w -Force | Out-Null }

    # Прошлая версия скрипта навсегда фиксировала текущую версию Windows
    # (TargetReleaseVersion). Когда у версии кончается поддержка, обновления
    # безопасности перестают приходить вообще. Снимаем эту фиксацию.
    $hadPin = $false
    foreach ($n in @('TargetReleaseVersion','TargetReleaseVersionInfo','ProductVersion')) {
        if ($null -ne (Get-ItemProperty -LiteralPath $w -Name $n -ErrorAction SilentlyContinue)) {
            Remove-ItemProperty -LiteralPath $w -Name $n -Force -ErrorAction SilentlyContinue
            $hadPin = $true
        }
    }
    if ($hadPin) { Write-Output "[*] Снята старая фиксация версии Windows (из прошлых версий PotatoPC)." }
    # Драйверы из Центра обновлений снова разрешены: вкладка «Драйверы» берёт их оттуда.
    Remove-ItemProperty -LiteralPath $w -Name 'ExcludeWUDriversInQualityUpdate' -Force -ErrorAction SilentlyContinue

    Set-ItemProperty -LiteralPath $w -Name "DeferFeatureUpdates" -Value 1 -Type DWord -Force
    Set-ItemProperty -LiteralPath $w -Name "DeferFeatureUpdatesPeriodInDays" -Value 365 -Type DWord -Force
    Set-ItemProperty -LiteralPath $w -Name "DeferQualityUpdates" -Value 0 -Type DWord -Force
    if ([int](Get-ItemProperty -LiteralPath $w -Name "DeferFeatureUpdatesPeriodInDays").DeferFeatureUpdatesPeriodInDays -ne 365) { throw "политика не записалась" }

    $edition = ''
    try { $edition = [string](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID } catch {}
    if ($edition -match '(?i)^Core') {
        Write-Output "[!] Редакция Home: Windows не выполняет отложку крупных обновлений. Политика записана, но работать не будет."
    }
    $svc = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    if ($svc -and $svc.StartType -eq 'Disabled') {
        Write-Output "[!] Служба Центра обновления отключена - обновления безопасности не приходят. Включаю её (вручную)."
        Set-Service -Name wuauserv -StartupType Manual
    }
    Write-Output "[OK] Крупные обновления отложены на год, обновления безопасности приходят как обычно."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
