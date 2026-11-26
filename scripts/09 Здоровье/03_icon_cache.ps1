# NAME: Пересобрать кэш значков и миниатюр
# DESC: Лечит белые, чужие или пропавшие значки и неверные миниатюры. Проводник на пару секунд перезапустится. Разовое действие - откатывать нечего
# TAGS: 1
# ICON: refresh

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
    $exp = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
    $files = @()
    $files += @(Get-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'IconCache.db') -Force -ErrorAction SilentlyContinue)
    $files += @(Get-ChildItem -LiteralPath $exp -Filter 'iconcache_*.db' -Force -ErrorAction SilentlyContinue)
    $files += @(Get-ChildItem -LiteralPath $exp -Filter 'thumbcache_*.db' -Force -ErrorAction SilentlyContinue)
    Write-Output "[*] Перезапускаю Проводник..."
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    $n = 0
    foreach ($f in $files) { try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $n++ } catch {} }
    # Windows обычно сама поднимает Проводник; если нет - запускаем.
    Start-Sleep -Seconds 3
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Write-Output ("[*] Удалено файлов кэша: " + $n + " из " + $files.Count)
    Write-Output "[OK] Кэш пересоздаётся. Если какой-то значок остался старым - перезагрузись."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
