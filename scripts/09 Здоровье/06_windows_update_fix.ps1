# NAME: Починить Центр обновления Windows
# DESC: Лечит зависшие на одном проценте и падающие с ошибкой обновления: останавливает службы, откладывает кэш обновлений в папку .old и запускает всё заново. Разовое действие - откатывать нечего
# TAGS: 1
# ICON: refresh
# TIMEOUT: 900

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
    $svcs = @('wuauserv', 'bits', 'cryptsvc', 'msiserver')
    Write-Output "[*] Останавливаю службы обновления..."
    foreach ($s in $svcs) { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    foreach ($d in @((Join-Path $env:SystemRoot 'SoftwareDistribution'), (Join-Path $env:SystemRoot 'System32\catroot2'))) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        # Старые .old от прошлых запусков убираем - иначе копятся гигабайты.
        Get-ChildItem -LiteralPath (Split-Path $d -Parent) -Directory -Filter ((Split-Path $d -Leaf) + '.old-*') -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
        try { Rename-Item -LiteralPath $d -NewName ((Split-Path $d -Leaf) + '.old-' + $stamp) -Force -ErrorAction Stop; Write-Output ("[*] Отложено: " + $d) }
        catch { Write-Output ("[!] Не переименовать " + $d + ": " + $_.Exception.Message) }
    }
    Write-Output "[*] Запускаю службы..."
    foreach ($s in $svcs) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc -and $svc.StartType -eq 'Disabled') { Set-Service -Name $s -StartupType Manual; Write-Output ("[*] " + $s + " была отключена - включил (вручную)") }
        Start-Service -Name $s -ErrorAction SilentlyContinue
    }
    Write-Output "[OK] Готово. Открой Параметры > Центр обновления и нажми «Проверить наличие обновлений»."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
