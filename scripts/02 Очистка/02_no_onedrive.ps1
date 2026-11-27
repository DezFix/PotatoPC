# NAME: Отключить OneDrive (облако Microsoft)
# DESC: Закрывает OneDrive, убирает его из автозагрузки и запрещает синхронизацию политикой DisableFileSyncNGSC. Программу не удаляет, файлы в облаке и на диске не трогает - откат включает всё обратно
# TAGS: 2
# ICON: ☁️
# PRESET: potato,game
# CHECK: Test-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    # 1. Закрываем OneDrive.
    try { Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue } catch {}

    # 2. Убираем из автозагрузки (текущий пользователь и вся машина).
    $off = 0
    foreach ($run in @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Run", "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run", "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run")) {
        try {
            $props = Get-ItemProperty -LiteralPath $run -ErrorAction Stop
            foreach ($p in $props.PSObject.Properties) {
                if ($p.Name -match '^OneDrive' -and [string]$p.Value -match '(?i)OneDrive\.exe') {
                    Remove-ItemProperty -LiteralPath $run -Name $p.Name -Force -ErrorAction Stop
                    $off++
                }
            }
        } catch {}
    }

    # 3. Политика: OneDrive не запускается и не синхронизирует, пока её не снимет откат.
    $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -Path $p -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force
    if ([int](Get-ItemProperty -Path $p -Name "DisableFileSyncNGSC" -ErrorAction Stop).DisableFileSyncNGSC -ne 1) { throw "Политика OneDrive не применена" }

    Start-Sleep -Seconds 1
    if (@(Get-Process -Name OneDrive -ErrorAction SilentlyContinue).Count -gt 0) { Write-Output "[*] OneDrive ещё запущен - после перезагрузки он не стартует." }
    Write-Output ("[OK] OneDrive отключён" + $(if ($off) { ", убран из автозагрузки" } else { "" }) + ". Программа и файлы на месте - вернуть можно откатом.")
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
