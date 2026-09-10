# NAME: Без OneDrive
# DESC: Убирает облако из автозапуска. Меньше нагрузки
# TAGS: 2
# ICON: ☁️
# PRESET: potato, game

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
    $setup = Join-Path $env:SystemRoot "SysWOW64\OneDriveSetup.exe"
    if (-not (Test-Path $setup)) { $setup = Join-Path $env:SystemRoot "System32\OneDriveSetup.exe" }
    if (Test-Path $setup) { Start-Process $setup "/uninstall" -Wait -ErrorAction SilentlyContinue }
    $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -Path $p -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force
    Write-Output "[OK] OneDrive убран. Файлы в облаке не тронуты."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
