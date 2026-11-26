# NAME: Видно компьютеры и папки в локальной сети
# DESC: Лечит пустую «Сеть» в Проводнике: включает службы сетевого обнаружения и правила брандмауэра для частной (домашней) сети. В общественных сетях ПК остаётся невидимым
# TAGS: 1
# ICON: network
# CHECK: (Get-Service FDResPub -ErrorAction Stop).StartType -eq 'Automatic'

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
    $names = @('FDResPub', 'fdPHost', 'SSDPSRV', 'upnphost')
    $snap = @{ Services = @(); Rules = @() }
    foreach ($s in $names) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc) { $snap.Services += @{ Name = $s; Mode = [string]$svc.StartType } }
    }
    # Группа «Сетевое обнаружение» - только правила частного профиля, которые выключены.
    $rules = @(Get-NetFirewallRule -Group '@FirewallAPI.dll,-32752' -ErrorAction SilentlyContinue | Where-Object { [string]$_.Profile -match 'Private' -and $_.Enabled -ne 'True' })
    $snap.Rules = @($rules | ForEach-Object { [string]$_.Name })
    Save-Snapshot 'netdisc' $snap
    foreach ($s in $names) {
        if (-not (Get-Service -Name $s -ErrorAction SilentlyContinue)) { continue }
        try { Set-Service -Name $s -StartupType Automatic -ErrorAction Stop; Start-Service -Name $s -ErrorAction SilentlyContinue; Write-Output ("[*] " + $s + " -> Автоматически") }
        catch { Write-Output ("[!] " + $s + ": " + $_.Exception.Message) }
    }
    if ($rules.Count) { $rules | Enable-NetFirewallRule -ErrorAction Stop; Write-Output ("[*] Правил брандмауэра включено: " + $rules.Count) }
    $cat = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object { [string]$_.NetworkCategory -eq 'Public' })
    if ($cat.Count) { Write-Output ("[!] Сеть «" + $cat[0].Name + "» помечена как общественная - в ней обнаружение выключено. Дома переключи её на «Частная» в Параметрах.") }
    Write-Output "[OK] Сетевое обнаружение включено. Другие ПК появятся в «Сети» через минуту-две."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
