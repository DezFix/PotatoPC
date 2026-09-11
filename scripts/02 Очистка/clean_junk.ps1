# NAME: Почистить мусор
# DESC: Полная чистка по cleaner/rules.json: система, браузеры, игры, программы, сеть, шейдеры
# TAGS: 1
# ICON: 🧹
# PRESET: potato, office, game
# RECOMMENDED: true

$ErrorActionPreference = "Stop"

function Expand-JunkEnv {
    param([string]$Path)
    $pfx86 = ${env:ProgramFiles(x86)}
    if ([string]::IsNullOrWhiteSpace($pfx86)) { $pfx86 = $env:ProgramFiles }
    $map = @{
        'LOCALAPPDATA' = $env:LOCALAPPDATA; 'APPDATA' = $env:APPDATA
        'PROGRAMDATA' = $env:PROGRAMDATA; 'WINDIR' = $env:SystemRoot
        'SYSTEMROOT' = $env:SystemRoot; 'PROGRAMFILES' = $env:ProgramFiles
        'PROGRAMFILES_X86' = $pfx86; 'USERPROFILE' = $env:USERPROFILE
        'TEMP' = $env:TEMP; 'TMP' = $env:TEMP; 'SYSTEMDRIVE' = $env:SystemDrive
    }
    return [regex]::Replace([string]$Path, '\$\{(\w+)\}', {
        param($m)
        $k = $m.Groups[1].Value
        if ($map.ContainsKey($k) -and $map[$k]) { return $map[$k] }
        return $m.Value
    })
}

function Resolve-JunkPaths {
    param([string[]]$Paths, [string]$ChildSubdir = '')
    $out = @()
    foreach ($p in $Paths) {
        $e = Expand-JunkEnv $p
        if ([string]::IsNullOrWhiteSpace($e) -or $e -match '\$\{') { continue }
        try {
            if ([string]::IsNullOrWhiteSpace($ChildSubdir)) {
                if (Test-Path -LiteralPath $e) { $out += $e; continue }
                foreach ($f in @(Get-ChildItem -Path $e -Force -ErrorAction SilentlyContinue)) {
                    $out += $f.FullName
                }
            } else {
                $bases = @()
                if (Test-Path -LiteralPath $e) { $bases += $e }
                else { foreach ($f in @(Get-ChildItem -Path $e -Force -ErrorAction SilentlyContinue)) { $bases += $f.FullName } }
                foreach ($b in $bases) {
                    foreach ($d in @(Get-ChildItem -LiteralPath $b -Directory -Force -ErrorAction SilentlyContinue)) {
                        $cand = Join-Path $d.FullName $ChildSubdir
                        if (Test-Path -LiteralPath $cand) { $out += $cand }
                    }
                }
            }
        } catch {}
    }
    return $out
}

function Measure-Junk {
    param([string[]]$Resolved, [int]$MinAgeDays = 0)
    $cutoff = $null
    if ($MinAgeDays -gt 0) { $cutoff = (Get-Date).AddDays(-$MinAgeDays) }
    $sum = 0L
    foreach ($r in $Resolved) {
        try {
            if (Test-Path -LiteralPath $r -PathType Leaf) {
                $it = Get-Item -LiteralPath $r -Force -ErrorAction SilentlyContinue
                if ($it -and ($null -eq $cutoff -or $it.LastWriteTime -lt $cutoff)) { $sum += $it.Length }
            } else {
                $files = @(Get-ChildItem -LiteralPath $r -Recurse -File -Force -ErrorAction SilentlyContinue)
                if ($cutoff) { $files = @($files | Where-Object { $_.LastWriteTime -lt $cutoff }) }
                $s = ($files | Measure-Object Length -Sum).Sum
                if ($s) { $sum += [long]$s }
            }
        } catch {}
    }
    return $sum
}

function Clear-Junk {
    param([string[]]$Resolved, [int]$MinAgeDays = 0)
    $cutoff = $null
    if ($MinAgeDays -gt 0) { $cutoff = (Get-Date).AddDays(-$MinAgeDays) }
    $err = 0
    foreach ($r in $Resolved) {
        try {
            if (Test-Path -LiteralPath $r -PathType Leaf) {
                if ($cutoff) {
                    try { if ((Get-Item -LiteralPath $r -Force -ErrorAction Stop).LastWriteTime -ge $cutoff) { continue } } catch {}
                }
                Remove-Item -LiteralPath $r -Force -ErrorAction Stop
            } elseif ($cutoff) {
                foreach ($f in @(Get-ChildItem -LiteralPath $r -Recurse -File -Force -ErrorAction SilentlyContinue |
                        Where-Object { $_.LastWriteTime -lt $cutoff })) {
                    try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop }
                    catch { $err++ }
                }
                foreach ($d in @(Get-ChildItem -LiteralPath $r -Recurse -Directory -Force -ErrorAction SilentlyContinue |
                        Sort-Object { $_.FullName.Length } -Descending)) {
                    try {
                        if ((Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction Stop | Measure-Object).Count -eq 0) {
                            Remove-Item -LiteralPath $d.FullName -Force -ErrorAction Stop
                        }
                    } catch {}
                }
            } else {
                Get-ChildItem -LiteralPath $r -Force -ErrorAction SilentlyContinue |
                    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch { $err++ }
    }
    return $err
}

try {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $rulesPath = Join-Path $repoRoot 'cleaner\rules.json'
    $groups = $null
    if (Test-Path -LiteralPath $rulesPath) {
        try { $groups = (Get-Content $rulesPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop).Groups } catch {}
    }
    if (-not $groups) {
        $groups = @(@{ Name = 'Система'; Items = @(
            @{ Name = 'Временные файлы'; Paths = @('${TEMP}', '${WINDIR}/Temp') } ) })
    }
    $freed = 0L; $errs = 0; $n = 0
    foreach ($g in $groups) {
        foreach ($item in $g.Items) {
            $iname = [string]$item.Name
            if ([string]$item.Action -eq 'flushdns') {
                try { ipconfig /flushdns 2>&1 | Out-Null } catch {}
                Write-Output "[*] DNS-кэш сброшен."
                continue
            }
            if ([string]$item.Action -eq 'arpclear') {
                try { Get-NetNeighbor -ErrorAction Stop | Remove-NetNeighbor -Confirm:$false -ErrorAction Stop }
                catch { try { arp -d * 2>&1 | Out-Null } catch {} }
                Write-Output "[*] ARP-кэш очищен."
                continue
            }
            $rp = @(Resolve-JunkPaths -Paths @($item.Paths) -ChildSubdir ([string]$item.ChildSubdir))
            if ($rp.Count -eq 0) { continue }
            $before = [long](Measure-Junk -Resolved $rp -MinAgeDays ([int]$item.MinAgeDays))
            $errs += [int](Clear-Junk -Resolved $rp -MinAgeDays ([int]$item.MinAgeDays))
            $freed += $before
            $n++
            if ($before -ge 1MB) { Write-Output ("[*] {0}: ~{1} МБ" -f $iname, [math]::Round($before / 1MB, 1)) }
        }
    }
    Write-Output ("[OK] Почищено пунктов: {0}, освобождено ~{1} МБ, ошибок: {2}" -f $n, [math]::Round($freed / 1MB, 1), $errs)
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
