# PotatoPC v7 - плагины-твики (папка scripts\).
#
# Плагин = .ps1 в scripts\<NN Раздел>\NN_имя.ps1 с шапкой из комментариев:
#   # NAME:    название в списке
#   # DESC:    короткое описание
#   # TAGS:    1|2|3 (безопасно / осторожно / рискованно), win11 - только Windows 11
#   # ICON:    эмодзи или имя значка (bolt, broom, shield...)
#   # PRESET:  potato,office,game - в какие пресеты входит
#   # CHECK:   (необязательно) выражение PowerShell; $true = твик уже применён.
#              Есть помощник Test-Reg 'HKCU:\...' 'Имя' значение
#   # UNDO:    (необязательно) путь к своему скрипту отката относительно scripts\
#   # UNDOFOR: (необязательно) номер раздела для отката, лежащего вне папки «Откат»
#   # TIMEOUT: (необязательно) секунд на выполнение, по умолчанию 300
#
# Откат твика лежит рядом, в подпапке «Откат» его раздела, под тем же именем:
#   scripts\01 Скорость\02_fast_login.ps1  ->  scripts\01 Скорость\Откат\02_fast_login.ps1
# Все откаты раздела вместе = «Откатить раздел». У разовых действий (чистка)
# отката нет - откатывать там нечего.
#
# Скрипт выполняется отдельным процессом powershell.exe от администратора и
# сообщает результат кодом выхода: 0 - успех, иначе ошибка.
# Файлы, которых нет в SHA256SUMS (или изменённые), помечаются как «сторонние».

$script:PluginCache = $null
$script:ManifestCache = $null

function Read-PluginHeader {
    param([string]$Path)
    $meta = @{}
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try {
            $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true)
            for ($i = 0; $i -lt 25; $i++) {
                $line = $sr.ReadLine()
                if ($null -eq $line) { break }
                if ($line -match '^\s*#\s*([A-Za-z\-]+)\s*:\s*(.*)$') {
                    $k = $Matches[1].ToUpperInvariant()
                    if (-not $meta.ContainsKey($k)) { $meta[$k] = $Matches[2].Trim() }
                }
            }
            $sr.Dispose()
        } finally { $fs.Dispose() }
    } catch {}
    return $meta
}

function Get-ManifestMap {
    if ($null -ne $script:ManifestCache) { return $script:ManifestCache }
    $map = @{}
    try {
        if (Test-Path -LiteralPath $ManifestPath) {
            foreach ($line in [System.IO.File]::ReadAllLines($ManifestPath, [System.Text.Encoding]::UTF8)) {
                if ($line -match '^([0-9A-Fa-f]{64})  (.+)$') { $map[$Matches[2].Replace('/', '\').ToUpperInvariant()] = $Matches[1].ToUpperInvariant() }
            }
        }
    } catch {}
    $script:ManifestCache = $map
    return $map
}

function Get-RepoFileHash {
    # Та же нормализация, что в tools/New-ReleaseHashes.ps1: текст -> LF.
    param([string]$Path)
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $text = @('.bat', '.cfg', '.cmd', '.conf', '.cs', '.css', '.csv', '.editorconfig', '.gitattributes', '.gitignore', '.htm', '.html', '.ini', '.js', '.json', '.md', '.ps1', '.psd1', '.psm1', '.toml', '.txt', '.svg', '.xml', '.xaml', '.yaml', '.yml')
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($text -contains $ext -or [System.IO.Path]::GetFileName($Path) -match '^(?i)(license|notice|copying|readme)$') {
        $s = [System.Text.Encoding]::UTF8.GetString($bytes).Replace("`r`n", "`n").Replace("`r", "`n")
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($s)
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') } finally { $sha.Dispose() }
}

function Test-FileInManifest {
    param([string]$Path)
    try {
        $rel = $Path.Substring($AppRoot.Length).TrimStart('\', '/').ToUpperInvariant()
        $map = Get-ManifestMap
        if (-not $map.ContainsKey($rel)) { return $false }
        return ((Get-RepoFileHash -Path $Path) -eq $map[$rel])
    } catch { return $false }
}

function Get-Plugins {
    param([switch]$Force)
    if ($script:PluginCache -and -not $Force) { return $script:PluginCache }
    $list = New-Object System.Collections.ArrayList
    if (-not (Test-Path -LiteralPath $ScriptsFolder)) { $script:PluginCache = @(); return @() }
    $files = @(Get-ChildItem -LiteralPath $ScriptsFolder -Filter '*.ps1' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)
    foreach ($f in $files) {
        $h = Read-PluginHeader -Path $f.FullName
        $catDir = $f.Directory
        $inUndoDir = $catDir.Name -match '^(?i)откат$'
        if ($inUndoDir) { $catDir = $catDir.Parent }
        $dir = $catDir.Name
        $catNum = '99'; $catName = 'Другое'
        if ($catDir.FullName.TrimEnd('\') -ne $ScriptsFolder.TrimEnd('\')) {
            if ($dir -match '^(\d{1,2})\s*(.+)$') { $catNum = ('{0:D2}' -f [int]$Matches[1]); $catName = $Matches[2].Trim() }
            else { $catName = $dir }
        }
        $num = 0
        if ($f.BaseName -match '^(\d{1,3})_') { $num = [int]$Matches[1] }
        $tags = [string]$h['TAGS']
        $risk = 2
        if ($tags -match '^\s*([123])') { $risk = [int]$Matches[1] }
        $undoFor = [string]$h['UNDOFOR']
        if ($inUndoDir -and -not $undoFor) { $undoFor = $catNum }
        $isUndo = $inUndoDir -or [bool]$undoFor -or ($catName -match '(?i)^откат')
        $timeout = 300
        if ([string]$h['TIMEOUT'] -match '^\d+$') { $timeout = [int]$h['TIMEOUT'] }
        $presets = @()
        if ($h['PRESET']) { $presets = @(([string]$h['PRESET']).Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ }) }
        $rel = $f.FullName.Substring($ScriptsFolder.Length).TrimStart('\')
        $name = [string]$h['NAME']
        if (-not $name) { $name = ($f.BaseName -replace '^\d+_', '' -replace '_', ' ') }
        [void]$list.Add([pscustomobject]@{
            Id        = $rel
            Path      = $f.FullName
            Name      = $name
            Desc      = [string]$h['DESC']
            Icon      = [string]$h['ICON']
            Risk      = $risk
            Win11Only = ($tags -match '(?i)win11')
            Presets   = $presets
            Check     = [string]$h['CHECK']
            Undo      = [string]$h['UNDO']
            UndoId    = ''
            FileName  = $f.Name
            InUndoDir = $inUndoDir
            UndoFor   = @(($undoFor -split '[,\s]+') | Where-Object { $_ } | ForEach-Object { '{0:D2}' -f [int]$_ })
            IsUndo    = $isUndo
            Timeout   = $timeout
            CatNum    = $catNum
            Category  = $catName
            Num       = $num
            Trusted   = (Test-FileInManifest -Path $f.FullName)
            Applicable = -not (($tags -match '(?i)win11') -and $WindowsMajorVersion -lt 11)
        })
    }
    # Твик -> его откат: тот же файл в подпапке «Откат» раздела или путь из # UNDO:.
    $byId = @{}
    foreach ($p in $list) { $byId[$p.Id] = $p }
    foreach ($p in @($list | Where-Object { -not $_.IsUndo })) {
        $u = $null
        if ($p.Undo) { $u = $byId[($p.Undo -replace '/', '\').TrimStart('\')] }
        if (-not $u) { $u = @($list | Where-Object { $_.InUndoDir -and $_.CatNum -eq $p.CatNum -and $_.FileName -ieq $p.FileName } | Select-Object -First 1)[0] }
        if ($u) { $p.UndoId = $u.Id }
    }
    $script:PluginCache = @($list | Sort-Object CatNum, Num, Name)
    return $script:PluginCache
}

function Test-Reg {
    # Помощник для # CHECK: значение реестра равно ожидаемому.
    param([string]$Path, [string]$Name, $Value)
    try {
        $v = (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name
        if ($Value -is [int] -or $Value -is [long]) { return ([long]$v -eq [long]$Value) }
        return ([string]$v -eq [string]$Value)
    } catch { return $false }
}

function Get-PluginStates {
    # Фон. Для плагинов с # CHECK: $true / $false / $null (не проверить).
    param($Plugins)
    $states = @{}
    foreach ($p in @($Plugins)) {
        if (-not $p.Check) { continue }
        try {
            $sb = [scriptblock]::Create($p.Check)
            $r = & $sb
            $states[$p.Id] = [bool]$r
        } catch { $states[$p.Id] = $null }
    }
    return $states
}

function Get-LastApplied {
    # Последний успешный запуск каждого плагина по журналу истории.
    $map = @{}
    foreach ($h in (Get-History -Last 2000)) {
        if ($h.Kind -ne 'plugin' -or $h.Result -ne 'ok' -or -not $h.Ref) { continue }
        if (-not $map.ContainsKey($h.Ref)) { $map[$h.Ref] = $h.Time }
    }
    return $map
}

function Invoke-Plugin {
    # Фон. Один скрипт отдельным процессом. Возвращает $true при коде 0.
    param($Plugin)
    $path = [string]$Plugin.Path
    if (-not (Test-Path -LiteralPath $path)) { Write-Log ('Нет файла: ' + $path) 'err'; return $false }
    $exe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $q = $path.Replace("'", "''")
    $cmd = "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; `$env:POTATOPC_DATA='" + ([string]$DataRoot).Replace("'", "''") + "'; & '" + $q + "'; exit `$LASTEXITCODE"
    $argLine = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "' + $cmd.Replace('"', '\"') + '"'
    $r = Invoke-ProcessLive -FilePath $exe -Arguments $argLine -TimeoutSec ([int]$Plugin.Timeout) -Encoding utf8 -Prefix '     '
    if ($r.Cancelled) { Write-Log 'Остановлено пользователем' 'warn'; return $false }
    if ($r.TimedOut) { Write-Log ('Скрипт не уложился в ' + $Plugin.Timeout + ' с и был остановлен') 'err'; return $false }
    return ($r.Code -eq 0)
}

function Invoke-PluginBatch {
    # Фон. Пачка плагинов с журналом и историей. Возвращает сводку.
    param($Plugins, [bool]$RestorePoint = $true, [string]$Title = 'Применение твиков')
    $list = @($Plugins)
    $ok = 0; $fail = 0; $failed = @()
    Write-Log ($Title + ': ' + $list.Count) 'head'
    if ($RestorePoint) { Set-JobProgress -1 'Точка восстановления...'; [void](New-RestorePoint -Description ('PotatoPC: ' + $Title)) }
    $i = 0
    foreach ($p in $list) {
        if (Test-JobCancel) { Write-Log 'Остановлено пользователем' 'warn'; break }
        $i++
        Set-JobProgress (($i - 1) / [Math]::Max(1, $list.Count)) $p.Name
        Write-Log ('[' + $i + '/' + $list.Count + '] ' + $p.Name)
        $started = Get-Date
        $res = Invoke-Plugin -Plugin $p
        $secs = [int]((Get-Date) - $started).TotalSeconds
        if ($res) { $ok++; Write-Log ('Готово (' + $secs + ' с)') 'ok'; Add-History -Kind 'plugin' -Name $p.Name -Ref $p.Id }
        else { $fail++; $failed += $p.Name; Add-History -Kind 'plugin' -Name $p.Name -Result 'fail' -Ref $p.Id }
    }
    Set-JobProgress 1 ''
    $sum = 'Выполнено: ' + $ok + ' из ' + $list.Count
    if ($fail -gt 0) { Write-Log ($sum + '; с ошибкой: ' + ($failed -join ', ')) 'warn' } else { Write-Log $sum 'ok' }
    return @{ Ok = $ok; Fail = $fail; Failed = $failed }
}

function Get-UndoPlugin {
    # Откат одного твика (или $null, если у твика его нет - разовое действие).
    param([string]$Id)
    $p = @(Get-Plugins | Where-Object { $_.Id -eq $Id } | Select-Object -First 1)[0]
    if (-not $p -or -not $p.UndoId) { return $null }
    return @(Get-Plugins | Where-Object { $_.Id -eq $p.UndoId } | Select-Object -First 1)[0]
}

function Get-UndoPlugins {
    param([string]$CatNum = '')
    $all = @(Get-Plugins | Where-Object { $_.IsUndo })
    if (-not $CatNum) { return $all }
    return @($all | Where-Object { $_.UndoFor -contains $CatNum })
}

function Request-Reboot {
    param([int]$DelaySec = 60, [string]$Reason = 'PotatoPC')
    try {
        $exe = Join-Path $env:WINDIR 'System32\shutdown.exe'
        Start-Process -FilePath $exe -ArgumentList @('/r', '/t', [string]$DelaySec, '/c', ('"' + $Reason + '"')) -WindowStyle Hidden
        Write-Log ('Перезагрузка через ' + $DelaySec + ' с. Отменить: shutdown /a') 'warn'
    } catch { Write-Log ('Перезагрузка не запланирована: ' + $_.Exception.Message) 'err' }
}
