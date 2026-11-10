# NAME: 03 · Включить UAC (контроль учётных записей)
# DESC: EnableLUA=1: программы не получают админа молча. Заводское состояние Windows; скрипт возвращает его, если кто-то выключил
# TAGS: 1
# ICON: 🛡️
# PRESET: potato,office,game

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $p = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    $cur = 0
    try { $cur = [int](Get-ItemProperty -LiteralPath $p -Name "EnableLUA" -ErrorAction Stop).EnableLUA } catch {}
    if ($cur -eq 1) {
        Write-Output "[=] UAC уже включён. Ничего не менял."
        exit 0
    }
    # Снимок до изменения: откат вернёт исходное значение, а не «0».
    try {
        $backupDir = Join-Path $env:ProgramData 'PotatoPC\backups'
        if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction Stop | Out-Null }
        $file = Join-Path $backupDir ('uac-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
        @{ Time = (Get-Date -Format 's'); EnableLUA = $cur } | ConvertTo-Json -Depth 3 |
            Out-File -LiteralPath $file -Encoding UTF8 -Force -ErrorAction Stop
        Write-Output ("[*] Исходное значение сохранено: " + $file)
    } catch {
        Write-Output ("[!] Не удалось сохранить исходное значение UAC: " + $_.Exception.Message)
    }
    Set-ItemProperty -LiteralPath $p -Name "EnableLUA" -Value 1 -Type DWord -Force
    $v = [int](Get-ItemProperty -LiteralPath $p -Name "EnableLUA" -ErrorAction Stop).EnableLUA
    if ($v -ne 1) { throw "EnableLUA не записался (стало $v)" }
    Write-Output "[OK] UAC включён. Перезагрузись, чтобы применилось."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
