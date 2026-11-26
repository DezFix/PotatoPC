# NAME: Синхронизировать часы
# DESC: Лечит «уплывающее» время и ошибки сайтов «сертификат недействителен» из-за него: перезапускает службу времени и сверяет часы с сервером. Разовое действие - откатывать нечего
# TAGS: 1
# ICON: clock

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
    $svc = Get-Service -Name w32time -ErrorAction Stop
    if ($svc.StartType -eq 'Disabled') { Set-Service -Name w32time -StartupType Manual; Write-Output "[*] Служба времени была отключена - включил (вручную)" }
    Restart-Service -Name w32time -Force -ErrorAction SilentlyContinue
    if ((Get-Service -Name w32time).Status -ne 'Running') { Start-Service -Name w32time -ErrorAction Stop }
    $null = Invoke-Tool 'w32tm.exe' @('/config', '/update')
    $r = Invoke-Tool 'w32tm.exe' @('/resync', '/force')
    if ($r.Code -ne 0) {
        Write-Output ("[!] Первая попытка: " + $r.Text)
        $null = Invoke-Tool 'w32tm.exe' @('/config', '/manualpeerlist:time.windows.com,0x9', '/syncfromflags:manual', '/update')
        $r = Invoke-Tool 'w32tm.exe' @('/resync', '/force')
        if ($r.Code -ne 0) { throw ("w32tm: " + $r.Text + " (проверь интернет)") }
    }
    Write-Output ("[*] Сейчас: " + (Get-Date -Format 'dd.MM.yyyy HH:mm:ss'))
    Write-Output "[OK] Часы сверены."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
