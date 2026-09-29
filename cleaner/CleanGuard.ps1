<#
.SYNOPSIS
    PotatoPC: общий модуль очистки (правила cleaner/rules.json + защита от самоудаления).
.DESCRIPTION
    Единственная реализация движка чистки. Используется дважды:
      1) modules/_clean.ps1 - вкладка «Очистка» в GUI;
      2) scripts/02 Очистка/01_clean_junk.ps1 - скрипт из общего списка модулей.
    Оба места раньше держали свои копии одних и тех же функций, поэтому любая
    правка защиты расходилась с реальностью.

    ЗАЩИТА. Модуль ничего не удаляет, пока не доказано обратное:
      - свои папки PotatoPC (рабочая, кэш репозитория, карантин, YARA-тулы) и
        корень репозитория, из которого запущен скрипт, защищены всегда;
      - папки пользователя с данными (Рабочий стол, Документы, Загрузки...)
        защищены целиком - правила туда не ходят;
      - системные корни защищены только сами (равенство, не префикс): C:\Windows
        как цель чистить нельзя, а %WINDIR%\Temp - можно и нужно. Иначе защита
        видела бы всё и проверка возвращала бы 0;
      - junction/symlink (reparse point) не обходится и не удаляется вообще -
        за ссылкой может лежать что угодно, а чистка не должна решать за
        пользователя, что удалять;
      - обход папок свой (DirectoryInfo), а не рекурсивным Get-ChildItem: в 5.1
        тот идёт по junction'ам и способен зависнуть или снести чужое содержимое;
      - нечитаемый/неизвестный путь считается опасным и пропускается.
.NOTES
    Только определения функций. Никаких вызовов удаления и никакого exit на
    этапе загрузки: файл подключается и в GUI-сессию, и в отдельный процесс.
#>

# Корень репозитория фиксируется на момент подключения: $PSScriptRoot внутри
# функций нельзя использовать как опору — при dot-source уезжает.
$script:CleanGuardRepoRoot = ''
try { $script:CleanGuardRepoRoot = [System.IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent)).TrimEnd('\','/') } catch {}
$script:CleanGuardExtraRoots = @()
$script:CleanGuardSkipped = @()
# Списки защиты строятся один раз на ранспейс: они не меняются, а проверка
# идёт на каждый файл в Temp (десятки тысяч раз за проход).
$script:CleanGuardPrefixes = $null
$script:CleanGuardExactCache = $null

function ConvertTo-CleanFullPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    try {
        $p = [System.IO.Path]::GetFullPath($Path)
        # Корень диска ("C:\") трогать нельзя - обрезание слэша ломает префикс.
        if ($p.Length -gt 3) { $p = $p.TrimEnd('\','/') }
        return $p
    } catch { return '' }
}

function Test-CleanPathWithin {
    # Чистая арифметика префиксов: лежит ли Path внутри Root.
    param([string]$Path, [string]$Root)
    $p = ConvertTo-CleanFullPath $Path
    $r = ConvertTo-CleanFullPath $Root
    if (-not $p -or -not $r) { return $false }
    if ($p.Equals($r, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    $prefix = $r
    if (-not $prefix.EndsWith('\')) { $prefix = $prefix + '\' }
    return $p.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Add-CleanGuardRoot {
    # Дополнительные защищённые корни от вызывающего (папка скрипта, его файл).
    # Корень диска не принимаем: как точечный корень он отравил бы всю защиту
    # (под него подпадает вообще всё) и чистка не тронула бы ни одного файла.
    param([string[]]$Path)
    foreach ($p in @($Path)) {
        $f = ConvertTo-CleanFullPath $p
        if (-not $f) { continue }
        if ($f -match '^[A-Za-z]:\\?$') { continue }
        $script:CleanGuardExtraRoots += $f
    }
    $script:CleanGuardExtraRoots = @($script:CleanGuardExtraRoots | Select-Object -Unique)
    $script:CleanGuardPrefixes = $null
    $script:CleanGuardExactCache = $null
}

function Get-CleanGuardAppPath {
    # Пути приложения читаем из переменных окружения движка, когда они есть.
    # GUI чистит в фоновом ранспейсе, куда $script:CleanGuardRepoRoot и
    # $script:CleanGuardExtraRoots не переносятся - без этого чтения фоновый
    # проход не знал бы про кэш репозитория и снёс бы его вместе с Temp.
    # Возвращает готовые корни (не файлы).
    $out = @()
    $read = {
        param([string]$Name)
        try {
            $v = Get-Variable -Name $Name -Scope Script -ErrorAction SilentlyContinue
            if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v.Value)) { return [string]$v.Value }
        } catch {}
        return ''
    }
    foreach ($n in @('CleanGuardRepoRoot','LocalRepoRoot','WorkFolder','RepoCacheFolder')) {
        $v = & $read $n
        if ($v) { $out += $v }
    }
    # <repo>/scripts -> <repo>
    $sf = & $read 'ScriptsFolder'
    if ($sf) {
        $out += $sf
        $parent = Split-Path $sf -Parent
        if ($parent) { $out += $parent }
    }
    # <repo>/cleaner/rules.json -> <repo>/cleaner и <repo>
    $rp = & $read 'CleanRulesPath'
    if ($rp) {
        $dir = Split-Path $rp -Parent
        if ($dir) {
            $out += $dir
            $repo = Split-Path $dir -Parent
            if ($repo) { $out += $repo }
        }
    }
    try { $out += @($script:CleanGuardExtraRoots) } catch {}
    return @($out | Where-Object { $_ })
}

function Get-CleanGuardRoots {
    # Полный список корней, которые чистка не имеет права трогать.
    $roots = @()

    # 1. Наше собственное. Имена папок не выдумываем - ищем на диске.
    foreach ($base in @($env:TEMP, $env:TMP, $env:LOCALAPPDATA, $env:APPDATA, $env:ProgramData)) {
        if ([string]::IsNullOrWhiteSpace($base)) { continue }
        foreach ($name in @('PotatoPC', 'PotatoPC-*')) {
            $p = Join-Path $base $name
            try {
                if (Test-Path -LiteralPath $p) {
                    $roots += (Get-ChildItem -LiteralPath $p -Force -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
                } else { $roots += $p }
            } catch { $roots += $p }
        }
    }
    # Пути, названные самим приложением, плюс корень репозитория с правилами.
    foreach ($p in (Get-CleanGuardAppPath)) {
        $roots += $p
        if ([System.IO.Path]::GetFileName($p) -ieq 'scripts') { $roots += (Split-Path $p -Parent) }
    }

    # 2. Пользовательские данные. Ни один пункт очистки их не удаляет.
    if ($env:USERPROFILE) {
        foreach ($name in @('Desktop','Documents','Downloads','Pictures','Videos','Music','Favorites','Links','Contacts','3D Objects')) {
            $roots += (Join-Path $env:USERPROFILE $name)
        }
    }

    # 3. Точки, под которыми лежит незаменимое, защищаем точечно.
    # Сюда НЕЛЬЗЯ класть C:\Windows, C:\Users, Program Files и ProgramData как
    # "всё внутри": правила чистки легитимно ходят по их подпапкам
    # (%WINDIR%\Temp, Steam под Program Files (x86), GOG под ProgramData) -
    # иначе проверка видела бы всё защищённым и возвращала 0.
    $sys = @()
    if ($env:SystemRoot) {
        $sys += (Join-Path $env:SystemRoot 'System32\config')   # кусты реестра SAM/SYSTEM
        $sys += (Join-Path $env:SystemRoot 'System32\DriverStore')
    }
    if ($env:SystemDrive) {
        $sys += (Join-Path $env:SystemDrive '$Recycle.Bin')
        $sys += (Join-Path $env:SystemDrive 'System Volume Information')
    }
    $roots += $sys

    $out = @()
    foreach ($r in @($roots)) {
        $f = ConvertTo-CleanFullPath $r
        if ($f) { $out += $f }
    }
    return @($out | Select-Object -Unique)
}

function Get-CleanGuardExactRoots {
    # Папки, которые нельзя чистить САМИ (как цель), но по чьим подпапкам
    # правила ходят легитимно. Проверка здесь - на равенство, а не префикс.
    if ($null -ne $script:CleanGuardExactCache) { return $script:CleanGuardExactCache }
    $roots = @()
    if ($env:SystemRoot) { $roots += $env:SystemRoot }
    if ($env:ProgramData) { $roots += $env:ProgramData }
    if ($env:USERPROFILE) { $roots += $env:USERPROFILE }
    if ($env:SystemDrive) {
        $roots += (Join-Path $env:SystemDrive 'Users')
        $roots += (Join-Path $env:SystemDrive 'Program Files')
        $roots += (Join-Path $env:SystemDrive 'Program Files (x86)')
    }
    $out = @()
    foreach ($r in @($roots)) {
        $f = ConvertTo-CleanFullPath $r
        if ($f) { $out += $f }
    }
    $script:CleanGuardExactCache = @($out | Select-Object -Unique)
    return $script:CleanGuardExactCache
}

function Get-CleanGuardPrefixList {
    # Кэш префиксов на ранспейс. Проверка защиты идёт на каждый файл, поэтому
    # список строится один раз, а не на каждый вызов.
    if ($null -ne $script:CleanGuardPrefixes) { return $script:CleanGuardPrefixes }
    $list = @()
    foreach ($r in (Get-CleanGuardRoots)) {
        $list += $r
        if (-not $r.EndsWith('\')) { $list += ($r + '\') }
    }
    $script:CleanGuardPrefixes = @($list | Select-Object -Unique)
    return $script:CleanGuardPrefixes
}

function Test-CleanProtectedPath {
    # Сам путь или любой его родитель под точечной защитой? Пустой/
    # неразобранный - считаем опасным. Папки из "точного" списка запрещены
    # только сами: их подпапки чистят правила.
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }
    $p = ConvertTo-CleanFullPath $Path
    if (-not $p) { return $true }
    if ($p -match '^[A-Za-z]:\\?$') { return $true }
    foreach ($e in (Get-CleanGuardExactRoots)) {
        if ($p.Equals($e, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    foreach ($pre in (Get-CleanGuardPrefixList)) {
        if ($p.StartsWith($pre, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Test-CleanReparseItem {
    # junction/symlink: содержимое цели не наше, рекурсивно не идём.
    param($Item)
    if ($null -eq $Item) { return $false }
    try { return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) } catch { return $true }
}

function Get-CleanEntry {
    # Прямые потомки каталога без рекурсии и без обхода reparse-точек.
    param([string]$Path)
    $out = @()
    try {
        $di = New-Object System.IO.DirectoryInfo -ArgumentList $Path
        foreach ($i in $di.EnumerateFileSystemInfos()) { $out += $i }
    } catch {}
    return @($out)
}

function Expand-CleanEnv {
    # ${VAR} -> путь Windows. Неизвестную переменную оставляем: путь с ${...}
    # отбрасывается выше как невалидный.
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

function Resolve-CleanPaths {
    # Шаблоны правил (* поддерживаются) -> существующие пути.
    # ChildSubdir: для версионных папок (JetBrains/<версия>/caches): base/*/ChildSubdir.
    param([string[]]$Paths, [string]$ChildSubdir = '')
    $out = @()
    foreach ($p in @($Paths)) {
        $e = Expand-CleanEnv $p
        if ([string]::IsNullOrWhiteSpace($e) -or $e -match '\$\{') { continue }
        try {
            if ([string]::IsNullOrWhiteSpace($ChildSubdir)) {
                if (Test-Path -LiteralPath $e) { $out += $e; continue }
                foreach ($f in @(Get-ChildItem -Path $e -Force -ErrorAction SilentlyContinue)) { $out += $f.FullName }
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
    return @($out)
}

function Get-CleanTreeSize {
    # Сумма байт в дереве. Свой обход: без junction'ов, без захода в наши папки.
    param([string]$Path, $Cutoff)
    $total = 0L
    $stack = New-Object System.Collections.Stack
    $stack.Push($Path)
    while ($stack.Count -gt 0) {
        $cur = [string]$stack.Pop()
        foreach ($e in (Get-CleanEntry -Path $cur)) {
            if ($e -is [System.IO.DirectoryInfo]) {
                if (Test-CleanReparseItem -Item $e) { continue }
                if (Test-CleanProtectedPath -Path $e.FullName) { continue }
                $stack.Push($e.FullName)
            } else {
                if (Test-CleanReparseItem -Item $e) { continue }
                if (Test-CleanProtectedPath -Path $e.FullName) { continue }
                if ($Cutoff -and $e.LastWriteTime -ge $Cutoff) { continue }
                try { $total += [long]$e.Length } catch {}
            }
        }
    }
    return $total
}

function Measure-CleanPaths {
    # Суммарный размер мусора в байтах. MinAgeDays>0 - только файлы старше N дней.
    param([string[]]$Resolved, [int]$MinAgeDays = 0)
    $cutoff = $null
    if ($MinAgeDays -gt 0) { $cutoff = (Get-Date).AddDays(-$MinAgeDays) }
    $sum = 0L
    foreach ($r in @($Resolved)) {
        if (Test-CleanProtectedPath -Path $r) {
            $script:CleanGuardSkipped += [string]$r
            continue
        }
        try {
            $item = Get-Item -LiteralPath $r -Force -ErrorAction Stop
        } catch { continue }
        if (-not $item.PSIsContainer) {
            if ($null -eq $cutoff -or $item.LastWriteTime -lt $cutoff) { $sum += [long]$item.Length }
            continue
        }
        if (Test-CleanReparseItem -Item $item) {
            $script:CleanGuardSkipped += ([string]$r + ' (ссылка)')
            continue
        }
        $sum += [long](Get-CleanTreeSize -Path $r -Cutoff $cutoff)
    }
    return $sum
}

function Remove-CleanFileSafe {
    # Файл + снятие ReadOnly. Прямые вызовы .NET вместо провайдера PowerShell:
    # на десятках тысяч файлов в %TEMP% провайдер тормозит, тут проход занимает
    # секунды. Удаление всё равно идёт по одному файлу, поэтому защита выше
    # успевает отработать для каждого.
    param([string]$Path)
    try {
        $attr = [System.IO.File]::GetAttributes($Path)
        if (($attr -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
            [System.IO.File]::SetAttributes($Path, ($attr -band (-bnot [System.IO.FileAttributes]::ReadOnly)))
        }
        [System.IO.File]::Delete($Path)
    } catch {
        $script:CleanGuardSkipped += ([string]$Path + ' (занят)')
        throw
    }
}

function Remove-CleanTreeContent {
    # Удаляет СОДЕРЖИМОЕ каталога. Корень остаётся на месте, если не пуст.
    # junction/symlink не трогаем вообще: за ним может лежать что угодно, а
    # «почистить мусор» — не повод решать за пользователя, что удалять.
    param([string]$Path, $Cutoff, [switch]$IsRoot)
    $err = 0
    $entries = Get-CleanEntry -Path $Path
    $dirs = @()
    foreach ($e in $entries) {
        $full = [string]$e.FullName
        if (Test-CleanReparseItem -Item $e) {
            $script:CleanGuardSkipped += ($full + ' (ссылка)')
            continue
        }
        if ($e -is [System.IO.DirectoryInfo]) {
            if (Test-CleanProtectedPath -Path $full) { $script:CleanGuardSkipped += $full; continue }
            $dirs += $full
            continue
        }
        if (Test-CleanProtectedPath -Path $full) { $script:CleanGuardSkipped += $full; continue }
        if ($Cutoff -and $e.LastWriteTime -ge $Cutoff) { continue }
        try { Remove-CleanFileSafe -Path $full } catch { $err++ }
    }
    foreach ($d in $dirs) { $err += Remove-CleanTreeContent -Path $d -Cutoff $Cutoff }
    if ($IsRoot) { return $err }
    try {
        if ((Get-CleanEntry -Path $Path).Count -eq 0) { [System.IO.Directory]::Delete($Path, $false) }
    } catch {}
    return $err
}

function Clear-CleanPaths {
    # Удаляет содержимое папок и файлы. Возвращает число ошибок.
    # MinAgeDays>0: свежие файлы не трогаем, пустые папки подчищаем.
    param([string[]]$Resolved, [int]$MinAgeDays = 0)
    $cutoff = $null
    if ($MinAgeDays -gt 0) { $cutoff = (Get-Date).AddDays(-$MinAgeDays) }
    $err = 0
    foreach ($r in @($Resolved)) {
        if (Test-CleanProtectedPath -Path $r) {
            $script:CleanGuardSkipped += [string]$r
            continue
        }
        try { $item = Get-Item -LiteralPath $r -Force -ErrorAction Stop } catch { continue }
        if (-not $item.PSIsContainer) {
            if ($cutoff -and $item.LastWriteTime -ge $cutoff) { continue }
            try { Remove-CleanFileSafe -Path $r } catch { $err++ }
            continue
        }
        if (Test-CleanReparseItem -Item $item) {
            $script:CleanGuardSkipped += ([string]$r + ' (ссылка)')
            continue
        }
        $err += Remove-CleanTreeContent -Path $r -Cutoff $cutoff -IsRoot
    }
    return $err
}

function Get-CleanSkippedReport {
    # Что защита не дала тронуть (для честного лога).
    return @($script:CleanGuardSkipped | Select-Object -Unique)
}

function Clear-CleanSkipped {
    $script:CleanGuardSkipped = @()
}

function Format-CleanSize {
    param([long]$Bytes)
    if ($Bytes -le 0) { return "нет" }
    if ($Bytes -ge 1GB) { return ("{0} ГБ" -f [math]::Round($Bytes / 1GB, 1)) }
    if ($Bytes -ge 1MB) { return ("{0} МБ" -f [math]::Round($Bytes / 1MB, 1)) }
    return ("{0} КБ" -f [math]::Max(1, [int]($Bytes / 1KB)))
}

function Invoke-CleanAction {
    # Именованные действия сети. Возвращает строки для лога.
    param([string]$Name)
    $out = @()
    try {
        if ($Name -eq 'flushdns') {
            $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            try { $r = ipconfig /flushdns 2>&1 | Out-String } finally { $ErrorActionPreference = $prev }
            $code = $LASTEXITCODE
            if ($code -eq 0) { $out += @('DNS-кэш сброшен') }
            else { $out += @(('DNS-кэш не сброшен (ipconfig код ' + $code + ')')) }
        } elseif ($Name -eq 'arpclear') {
            try {
                Get-NetNeighbor -ErrorAction Stop | Remove-NetNeighbor -Confirm:$false -ErrorAction Stop
                $out += @('ARP-кэш очищен (Remove-NetNeighbor)')
            } catch {
                $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
                try { $r = arp -d * 2>&1 | Out-String } catch { $r = '' } finally { $ErrorActionPreference = $prev }
                $code = $LASTEXITCODE
                $out += @(($r -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -First 3))
                if ($code -eq 0) { $out += @('ARP-кэш очищен (arp -d)') }
            }
        } else { $out += @('Неизвестное действие') }
    } catch { $out += @('Ошибка: ' + $_) }
    return $out
}
