# Generates v7/config/tweaks.json from the proven legacy action scripts.
# Run from the v7 root:  .\tools\Import-LegacyTweaks.ps1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$actions = Join-Path $root 'actions'
$outPath = Join-Path $root 'config\tweaks.json'

$categoryMap = @{
    '01 Скорость'             = 'speed'
    '02 Очистка'              = 'cleanup'
    '03 Приватность'          = 'privacy'
    '04 Экран'                = 'screen'
    '05 Питание и Память'     = 'power'
    '06 Интернет'             = 'internet'
    '07 Обновления'           = 'updates'
}

$undoMap = @{
    speed    = 'actions/09 Откат/07_undo_speed.ps1'
    cleanup  = 'actions/09 Откат/01_undo_cleanup.ps1'
    privacy  = 'actions/09 Откат/05_undo_privacy.ps1'
    screen   = 'actions/09 Откат/06_undo_screen.ps1'
    power    = 'actions/09 Откат/04_undo_power.ps1'
    internet = 'actions/09 Откат/03_undo_net.ps1'
    updates  = 'actions/09 Откат/08_undo_updates.ps1'
    autostart = 'actions/09 Откат/09_undo_autostart.ps1'
}

$timeoutMap = @{
    'clean-junk'       = 600
    'remove-bloat'     = 1200
    'winsxs-cleanup'   = 1800
    'winget-setup'     = 3600
    'security-only'    = 600
    'pagefile'         = 600
    'clean-autostart'  = 600
}

function Get-Field {
    param([string[]]$Lines, [string]$Name)
    foreach ($line in $Lines) {
        if ($line -match ('^\s*#\s*' + [regex]::Escape($Name) + ':\s*(.*)$')) {
            return $Matches[1].Trim()
        }
    }
    return ''
}

$tweaks = [ordered]@{}
$files = @(Get-ChildItem -LiteralPath $actions -Recurse -File -Filter '*.ps1' |
    Where-Object { $_.DirectoryName -notlike '*09 Откат*' })

foreach ($file in $files) {
    $lines = @(Get-Content -LiteralPath $file.FullName -TotalCount 14 -Encoding UTF8)
    $name = Get-Field -Lines $lines -Name 'NAME'
    if ([string]::IsNullOrWhiteSpace($name)) { continue }

    $folder = Split-Path $file.DirectoryName -Leaf
    $category = $categoryMap[$folder]
    if (-not $category) { continue }

    $id = $file.BaseName -replace '^\d+_', '' -replace '_', '-'
    $id = $id.ToLowerInvariant()

    $desc = Get-Field -Lines $lines -Name 'DESC'
    $tags = Get-Field -Lines $lines -Name 'TAGS'
    $icon = Get-Field -Lines $lines -Name 'ICON'
    $preset = Get-Field -Lines $lines -Name 'PRESET'

    $tagList = @($tags -split ',' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
    $risk = if ($tagList -contains '3') { 'advanced' } elseif ($tagList -contains '2') { 'caution' } else { 'safe' }
    $windows = if ($tagList -contains 'win11') { '11' } else { 'any' }
    $legacyProfiles = @($preset -split ',' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })

    $requiresAdmin = ($lines -join "`n") -match '(?m)^\s*#Requires\s+-RunAsAdministrator'
    if ($category -in @('cleanup', 'privacy', 'power', 'internet', 'updates')) { $requiresAdmin = $true }

    $needsReboot = (($name + ' ' + $desc) -match '(?i)(перезагруз|reboot)')

    $undoGroup = $category
    if ($id -eq 'clean-autostart') { $undoGroup = 'autostart' }
    if ($id -in @('clean-junk', 'winsxs-cleanup', 'firewall-on')) { $undoGroup = $null }
    $undoScript = if ($undoGroup) { $undoMap[$undoGroup] } else { $null }
    $undoQuality = if ($id -in @('clean-junk', 'winsxs-cleanup')) { 'none' }
                   elseif ($id -eq 'remove-bloat') { 'partial' }
                   elseif ($id -eq 'firewall-on') { 'manual' }
                   else { 'full' }
    $irreversible = ($id -in @('clean-junk', 'winsxs-cleanup'))

    $timeoutSec = if ($timeoutMap.ContainsKey($id)) { $timeoutMap[$id] } else { 300 }

    $tweaks[$id] = [ordered]@{
        name            = $name
        description     = $desc
        category        = $category
        risk            = $risk
        apply           = ('actions/' + $folder + '/' + $file.Name)
        undoGroup       = $undoGroup
        undoScript      = $undoScript
        undoQuality     = $undoQuality
        requiresAdmin   = [bool]$requiresAdmin
        requiresReboot  = [bool]$needsReboot
        irreversible    = [bool]$irreversible
        timeoutSec      = [int]$timeoutSec
        windows         = $windows
        icon            = $icon
        legacyTags      = $tags
        legacyProfiles  = $legacyProfiles
    }
}

$json = $tweaks | ConvertTo-Json -Depth 8
# Keep Cyrillic readable instead of \uXXXX escapes.
$json = [regex]::Replace($json, '\\u([0-9a-fA-F]{4})', {
    param($m)
    [string][char][Convert]::ToInt32($m.Groups[1].Value, 16)
})
[System.IO.File]::WriteAllText($outPath, $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("Wrote {0} tweaks to {1}" -f $tweaks.Count, $outPath)
