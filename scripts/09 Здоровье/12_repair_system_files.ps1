# NAME: Проверить и починить системные файлы (DISM + SFC)
# DESC: Лечит «необъяснимые» сбои: битые системные файлы восстанавливаются из Центра обновления. Долго - 10-40 минут, нужен интернет. Разовое действие - откатывать нечего
# TAGS: 1
# ICON: wrench
# TIMEOUT: 3600

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Set-Reg($Path, $Name, $Value, $Type = "DWord") {
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -Type $Type -Force
}
function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}
# Внешние утилиты пишут ошибки в stderr; при Stop это обрывало бы скрипт.
function Invoke-Tool {
    param([string]$Exe, [string[]]$ToolArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $raw = & $Exe @ToolArgs 2>&1
        return [PSCustomObject]@{ Code = $LASTEXITCODE; Text = ((($raw | Out-String) -replace "`0", '').Trim()) }
    } finally { $ErrorActionPreference = $prev }
}
function Save-Snapshot([string]$Kind, $Data) {
    try {
        $dir = Join-Path $env:ProgramData 'PotatoPC\backups'
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $f = Join-Path $dir ($Kind + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
        $Data | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $f -Encoding UTF8 -Force
        Write-Output ("[*] Как было - сохранено: " + $f)
    } catch { Write-Output ("[!] Снимок не сохранён: " + $_.Exception.Message) }
}
function Get-FirstSnapshot([string]$Kind) {
    $dir = Join-Path $env:ProgramData 'PotatoPC\backups'
    $f = @(Get-ChildItem -LiteralPath $dir -Filter ($Kind + '-*.json') -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -First 1)
    if ($f.Count -eq 0) { return $null }
    try { return (Get-Content -LiteralPath $f[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}
function Clear-Snapshots([string]$Kind) {
    $dir = Join-Path $env:ProgramData 'PotatoPC\backups'
    Get-ChildItem -LiteralPath $dir -Filter ($Kind + '-*.json') -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

try {
    Write-Output "[*] DISM: проверяю и чиню хранилище компонентов (самая долгая часть)..."
    $d = Invoke-Tool 'dism.exe' @('/Online', '/Cleanup-Image', '/RestoreHealth')
    $dLast = @($d.Text -split "`r?`n" | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*\[' }) | Select-Object -Last 2
    foreach ($l in $dLast) { Write-Output ("    " + $l.Trim()) }
    if ($d.Code -ne 0) { Write-Output ("[!] DISM: код " + $d.Code + " - SFC всё равно запускаю") }
    Write-Output "[*] SFC: проверяю системные файлы..."
    # sfc пишет в UTF-16 - читаем его вывод в этой кодировке.
    $prevEnc = [Console]::OutputEncoding
    try { [Console]::OutputEncoding = [System.Text.Encoding]::Unicode; $s = Invoke-Tool 'sfc.exe' @('/scannow') } finally { [Console]::OutputEncoding = $prevEnc }
    $sLast = @($s.Text -split "`r?`n" | Where-Object { $_ -match '[A-Za-zА-Яа-я]' -and $_ -notmatch '%' }) | Select-Object -Last 3
    foreach ($l in $sLast) { Write-Output ("    " + $l.Trim()) }
    if ($s.Code -ne 0 -and $d.Code -ne 0) { throw ("DISM код " + $d.Code + ", SFC код " + $s.Code + ". Подробности: C:\Windows\Logs\CBS\CBS.log") }
    Write-Output "[OK] Проверка закончена. Если что-то починено - перезагрузись."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
