# NAME: 12 · Отключить виджеты и Новости (TaskbarDa + AllowNewsAndInterests)
# DESC: Отключает TaskbarDa + AllowNewsAndInterests. Работает на Win10 и Win11.
# TAGS: 1
# ICON: 📰
# PRESET: game,office,potato

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $a = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    if (-not (Test-Path -LiteralPath $a)) { New-Item -Path $a -Force -ErrorAction Stop | Out-Null }
    try { Set-ItemProperty -LiteralPath $a -Name "TaskbarDa" -Value 0 -Type DWord -Force -ErrorAction Stop } catch {}

    $d = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
    if (-not (Test-Path -LiteralPath $d)) { try { New-Item -Path $d -Force -ErrorAction SilentlyContinue | Out-Null } catch {} }
    try { Set-ItemProperty -LiteralPath $d -Name "AllowNewsAndInterests" -Value 0 -Type DWord -Force -ErrorAction Stop } catch { Write-Output ("[*] Политика Dsh недоступна: " + $_.Exception.Message) }

    $ok = $false
    try { if ((Get-ItemProperty $a -Name TaskbarDa -ErrorAction Stop).TaskbarDa -eq 0) { $ok = $true } } catch {}
    if (-not $ok) { throw "Widget TaskbarDa не удалось установить" }
    Write-Output "[OK] Виджеты и Новости и интересы отключены."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
