# NAME: Сетевые диски не вешают Проводник
# DESC: Недоступный сетевой диск (другая сеть, выключенный NAS) больше не тормозит вход и Проводник: Windows подключит его при первом обращении, а не ищет при старте
# TAGS: 1
# ICON: network
# PRESET: potato,office,game
# CHECK: Test-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\NetworkProvider' 'RestoreConnection' 0

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
    Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\NetworkProvider" "RestoreConnection" 0
    $drives = @(Get-CimInstance Win32_MappedLogicalDisk -ErrorAction SilentlyContinue)
    if ($drives.Count) { Write-Output ("[*] Сетевых дисков сейчас: " + $drives.Count + " (" + (($drives | ForEach-Object { $_.DeviceID }) -join ", ") + ") - буквы остаются, просто не ищутся при входе.") }
    Write-Output "[OK] Готово. Применится при следующем входе."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
