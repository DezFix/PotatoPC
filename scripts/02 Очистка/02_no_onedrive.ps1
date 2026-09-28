# NAME: 02 · Удалить OneDrive (облако Microsoft)
# DESC: Запускает OneDriveSetup /uninstall + политика DisableFileSyncNGSC. Файлы в облаке и локальные копии не удаляет
# TAGS: 2
# ICON: ☁️
# PRESET: potato, game

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    try { Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue } catch {}
    # OneDriveSetup берём под разрядность самого процесса: на 64-битной системе
    # SysWOW64-версия сносила только 32-битный клиент, 64-битный оставался.
    $dir = if ([Environment]::Is64BitProcess) { "System32" } else { "SysWOW64" }
    $setup = Join-Path $env:SystemRoot "$dir\OneDriveSetup.exe"
    if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) {
        $alt = if ($dir -eq "System32") { "SysWOW64" } else { "System32" }
        $setup = Join-Path $env:SystemRoot "$alt\OneDriveSetup.exe"
    }
    if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) {
        if (@(Get-Process -Name OneDrive -ErrorAction SilentlyContinue).Count -gt 0) { throw "OneDriveSetup не найден, но OneDrive всё ещё запущен" }
        # Раньше ветка не завершалась и падала в политику ниже: пользователь
        # видел "[=] не найден" и следом "[OK] убран" - то есть ничего не вышло.
        Write-Output "[=] OneDriveSetup не найден; OneDrive уже не запущен. Ничего не менял."
        exit 0
    }
    $proc = Start-Process -FilePath $setup -ArgumentList "/uninstall" -Wait -PassThru -ErrorAction Stop
    if ($null -eq $proc) { throw "OneDriveSetup не запустился" }
    $code = [int]$proc.ExitCode
    # OneDriveSetup на части сборок возвращает ненулевой код даже при успехе,
    # поэтому код - предупреждение, а приговор выносит проверка процесса ниже.
    if ($code -ne 0) { Write-Output ("[*] OneDriveSetup вернул код " + $code + "; проверяю результат...") }
    $gone = $false
    for ($i = 0; $i -lt 15; $i++) {
        if (@(Get-Process -Name OneDrive -ErrorAction SilentlyContinue).Count -eq 0) { $gone = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $gone) { throw "OneDriveSetup завершился, но процесс OneDrive остался" }
    $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -Path $p -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force
    if ([int](Get-ItemProperty -Path $p -Name "DisableFileSyncNGSC" -ErrorAction Stop).DisableFileSyncNGSC -ne 1) { throw "Политика OneDrive не применена" }
    Write-Output "[OK] OneDrive убран. Файлы в облаке не тронуты."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
