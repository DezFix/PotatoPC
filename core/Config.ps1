# PotatoPC v7 - пути, версия, настройки.
# Все пути, которые нужны фоновым задачам, перечислены в $script:ConfigVarNames:
# Start-BgTask передаёт их в каждый фоновый поток.

$script:AppVersion = '7.1.0'
$script:BuildTag   = '2026-11-26-v7.1'

# Корень приложения: папка, где лежит menu.ps1.
if (-not $script:AppRoot) { $script:AppRoot = Split-Path $script:CoreDir -Parent }
$script:LocalRepoRoot  = $script:AppRoot
$script:ScriptsFolder  = Join-Path $script:AppRoot 'scripts'
$script:PagesFolder    = Join-Path $script:AppRoot 'pages'
$script:AssetsFolder   = Join-Path $script:AppRoot 'assets'
$script:CleanRulesPath = Join-Path $script:AppRoot 'cleaner\rules.json'
$script:CleanGuardPath = Join-Path $script:AppRoot 'cleaner\CleanGuard.ps1'
$script:AppsJsonPath   = Join-Path $script:AppRoot 'apps.json'
$script:ManifestPath   = Join-Path $script:AppRoot 'SHA256SUMS'

# Портативный режим: файл portable.txt рядом с menu.ps1 -> все данные
# (журнал, история, отчёты) хранятся в .\data и на ПК ничего не остаётся,
# кроме резервных копий, которые пишут сами скрипты-плагины (ProgramData\PotatoPC\backups).
$script:PortableMode = Test-Path -LiteralPath (Join-Path $script:AppRoot 'portable.txt')
if ($script:PortableMode) {
    $script:DataRoot = Join-Path $script:AppRoot 'data'
} else {
    $pd = if ($env:ProgramData) { $env:ProgramData } else { $env:TEMP }
    $script:DataRoot = Join-Path $pd 'PotatoPC'
}
$script:WorkFolder     = Join-Path $env:TEMP 'PotatoPC'
$script:BackupFolder   = Join-Path $env:ProgramData 'PotatoPC\backups'
$script:LogFolder      = Join-Path $script:DataRoot 'logs'
$script:LogPath        = Join-Path $script:LogFolder ('potatopc-' + (Get-Date -Format 'yyyyMMdd') + '.log')
$script:HistoryPath    = Join-Path $script:DataRoot 'history.jsonl'
$script:ReportFolder   = Join-Path $script:DataRoot 'reports'
$script:SettingsPath   = Join-Path $script:DataRoot 'settings.json'
$script:UIStatePath    = Join-Path $script:DataRoot 'ui.json'

foreach ($d in @($script:DataRoot, $script:WorkFolder, $script:LogFolder, $script:ReportFolder)) {
    try { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force -ErrorAction Stop | Out-Null } } catch {}
}

# Замеры «до/после» убраны с Главной - удаляем их старую папку.
try {
    $oldSnaps = Join-Path $script:DataRoot 'snapshots'
    if (Test-Path -LiteralPath $oldSnaps) { Remove-Item -LiteralPath $oldSnaps -Recurse -Force -ErrorAction SilentlyContinue }
} catch {}

# v6 качал сканер YARA (tools\yara64.exe, potato.yar) и правила (protect-rules).
# v7 их не использует - убираем остатки. Трогаем только эти файлы, а папку
# tools удаляем, лишь если в ней больше ничего нет.
foreach ($yaraRoot in @($script:DataRoot, (Join-Path $env:ProgramData 'PotatoPC')) | Select-Object -Unique) {
    try {
        $rules = Join-Path $yaraRoot 'protect-rules'
        if (Test-Path -LiteralPath $rules) { Remove-Item -LiteralPath $rules -Recurse -Force -ErrorAction SilentlyContinue }
        $tools = Join-Path $yaraRoot 'tools'
        if (Test-Path -LiteralPath $tools) {
            Get-ChildItem -LiteralPath $tools -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like 'yara*.exe' -or $_.Extension -in @('.yar', '.yara') } |
                Remove-Item -Force -ErrorAction SilentlyContinue
            if (-not (Get-ChildItem -LiteralPath $tools -Force -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $tools -Force -ErrorAction SilentlyContinue }
        }
    } catch {}
}

function Get-WindowsInfo {
    $r = @{ Major = 10; Build = 0; Display = ''; Edition = ''; Name = 'Windows' }
    try {
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $r.Build = [int]$cv.CurrentBuildNumber
        $r.Major = if ($r.Build -ge 22000) { 11 } else { 10 }
        $r.Display = [string]$cv.DisplayVersion
        if (-not $r.Display) { $r.Display = [string]$cv.ReleaseId }
        $r.Edition = [string]$cv.EditionID
        $r.Name = 'Windows ' + $r.Major + $(if ($r.Display) { ' ' + $r.Display } else { '' })
    } catch {}
    return $r
}
$script:WinInfo = Get-WindowsInfo
$script:WindowsMajorVersion = $script:WinInfo.Major

# Переменные, которые получает каждый фоновый поток.
$script:ConfigVarNames = @(
    'AppVersion','BuildTag','AppRoot','LocalRepoRoot','CoreDir','ScriptsFolder','PagesFolder','AssetsFolder',
    'CleanRulesPath','CleanGuardPath','AppsJsonPath','ManifestPath','PortableMode','DataRoot','WorkFolder',
    'BackupFolder','LogFolder','LogPath','HistoryPath','ReportFolder','SettingsPath',
    'WinInfo','WindowsMajorVersion'
)

# --- Настройки (settings.json) ---
$script:Settings = @{}
function Get-Setting {
    param([string]$Name, $Default = $null)
    if ($script:Settings.ContainsKey($Name)) { return $script:Settings[$Name] }
    return $Default
}
function Set-Setting {
    param([string]$Name, $Value)
    $script:Settings[$Name] = $Value
    try { ($script:Settings | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8 -ErrorAction Stop } catch {}
}
try {
    if (Test-Path -LiteralPath $script:SettingsPath) {
        $o = Get-Content -LiteralPath $script:SettingsPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        foreach ($p in $o.PSObject.Properties) { $script:Settings[$p.Name] = $p.Value }
    }
} catch {}
