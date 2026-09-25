# Очередь строк лога фон->UI. Thread-safe: фон только кладёт, UI-таймер забирает.
# Делегаты PowerShell между ранспейсами не пересылаем: привязанный к чужой сессии
# делегат на UI-диспетчере молча умирает. Только данные через очередь.
if (-not $global:BgLogQueue) {
    $global:BgLogQueue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
}

function Get-LogHexColor {
    # Чистая функция без $script (безопасна для фоновых ранспейсов).
    param([string]$ColorName)
    switch ($ColorName) {
        'Green'  { '#4ade80' }
        'Red'    { '#f87171' }
        'Yellow' { '#fbbf24' }
        'Orange' { '#fb9231' }
        'Blue'   { '#60a5fa' }
        'Cyan'   { '#22d3ee' }
        'Gray'   { '#9ca3af' }
        default  { '#d4d4e4' }
    }
}

function Get-LogAutoColor {
    # Linux-style: цвет по маркерам строки, если вызывающий цвет не указал.
    param([string]$m)
    if ([string]::IsNullOrEmpty($m)) { return 'Default' }
    if ($m -match '═══') { return 'Blue' }
    if ($m -match '✗|\[X\]|✖|КРИТИЧНО|ОШИБКА|Ошибк|ERROR|не удалось|Не удалось|ПРЕРВАНО| НЕТ\b') { return 'Red' }
    if ($m -match '⚠|\[!\]|ВНИМАНИЕ|пропущ|Пропущ|отмен|Отмен') { return 'Orange' }
    if ($m -match '✓|\[OK\]|Готово|готово|Готов|Успешно|успешно|заверш|Заверш|скопирован|Скопирован') { return 'Green' }
    if ($m -match '──|\[\*\]|▶') { return 'Cyan' }
    if ($m -match '^\[=\]|уже настроено|Нет данных|нет данных|не найден|не найдена|пропускаю|Пропускаю|не требуется|не требуется') { return 'Gray' }
    return 'Default'
}

function Get-LogConsoleColor {
    param([string]$color)
    switch ($color) {
        "Green"  { "Green" }
        "Red"    { "Red" }
        "Yellow" { "Yellow" }
        "Orange" { "DarkYellow" }
        "Blue"   { "Cyan" }
        "Cyan"   { "Cyan" }
        "Gray"   { "Gray" }
        default  { "White" }
    }
}

function Set-Progress {
    # Фон->UI: доля 0..1 или -1 = неопределённый (бегущий). Видно в шапке консоли и таскбаре.
    param([double]$Value = -1)
    try {
        if ($Value -lt 0) { Set-BgResult -Key 'progress' -Value @{ Mode = 'Marquee'; Value = 0 } }
        elseif ($Value -ge 1) { Set-BgResult -Key 'progress' -Value @{ Mode = 'None'; Value = 1 } }
        else { Set-BgResult -Key 'progress' -Value @{ Mode = 'Bar'; Value = $Value } }
    } catch {}
}

function Clear-Progress {
    try { Set-BgResult -Key 'progress' -Value @{ Mode = 'None'; Value = 0 } } catch {}
}

function Update-ProgressUI {
    # СТРОГО UI-поток: применяет состояние прогресса к полоске и таскбару.
    try {
        $p = $null
        try { $p = Get-BgResult -Key 'progress' } catch {}
        $bar = $null
        try { $bar = $taskProgressBar } catch {}
        $tbi = $null
        try { if ($window) { $tbi = $window.TaskbarItemInfo } } catch {}
        if (-not $p -or $p.Mode -eq 'None') {
            if ($bar) { $bar.Visibility = 'Collapsed' }
            if ($tbi) { $tbi.ProgressState = 'None' }
            return
        }
        if ($p.Mode -eq 'Marquee') {
            if ($bar) { $bar.Visibility = 'Visible'; $bar.IsIndeterminate = $true }
            if ($tbi) { $tbi.ProgressState = 'Indeterminate' }
        } else {
            $v = [double]$p.Value
            if ($v -lt 0) { $v = 0 }
            if ($v -gt 1) { $v = 1 }
            if ($bar) { $bar.Visibility = 'Visible'; $bar.IsIndeterminate = $false; $bar.Value = $v }
            if ($tbi) { $tbi.ProgressState = 'Normal'; $tbi.ProgressValue = $v }
        }
    } catch {}
}

function Add-LogColoredText {
    # СТРОГО UI-поток: дописывает строку в RichTextBox заданным цветом.
    param($Box, [string]$Text, [string]$ColorName = 'Default')
    try {
        $hex = Get-LogHexColor $ColorName
        $doc = $Box.Document
        $para = $null
        if ($doc.Blocks.Count -gt 0) { $para = $doc.Blocks.LastBlock }
        if (-not ($para -is [System.Windows.Documents.Paragraph])) {
            $para = New-Object System.Windows.Documents.Paragraph
            $para.Margin = [System.Windows.Thickness]::new(0)
            $doc.Blocks.Add($para) | Out-Null
        }
        $stamp = ''
        $body = $Text
        if ($Text -match '^(\[\d{2}:\d{2}:\d{2}\])\s?(.*)$') {
            $stamp = $Matches[1] + ' '
            $body = $Matches[2]
        }
        if ($stamp -ne '') {
            $rs = New-Object System.Windows.Documents.Run($stamp)
            $rs.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom('#6a6a85')
            $para.Inlines.Add($rs) | Out-Null
        }
        $run = New-Object System.Windows.Documents.Run($body + "`r`n")
        $run.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom($hex)
        $para.Inlines.Add($run) | Out-Null
        while ($doc.Blocks.Count -gt 2000) { $doc.Blocks.Remove($doc.Blocks.FirstBlock) }
        $Box.ScrollToEnd()
    } catch {}
}

function Get-LogPlainText {
    # СТРОГО UI-поток: весь текст лога для копирования.
    param($Box)
    try {
        $tr = New-Object System.Windows.Documents.TextRange($Box.Document.ContentStart, $Box.Document.ContentEnd)
        return $tr.Text
    } catch { return '' }
}

function Write-LogLine {
    # Низкоуровневая доставка строки: файл + (UI-напрямую | очередь для поллера).
    # Никаких делегатов в чужой поток — только данные.
    param([string]$line, [string]$color = 'Default')
    try {
        $lp = $null
        try { $lp = $script:LogPath } catch {}
        if ($lp) { "$line`n" | Out-File -FilePath $lp -Append -Encoding UTF8 -ErrorAction SilentlyContinue }
    } catch {}
    $delivered = $false
    try {
        $box = $null
        try { $box = $LogBox } catch {}
        if ($box -and $box.Dispatcher -and $box.Dispatcher.CheckAccess()) {
            Add-LogColoredText -Box $box -Text $line -ColorName $color
            $delivered = $true
        }
    } catch {}
    if (-not $delivered) {
        try {
            $q = $null
            try { $q = $bgLogQueue } catch {}
            if (-not $q) { try { $q = $global:BgLogQueue } catch {} }
            if ($q) {
                if ($q.Count -gt 5000) { try { $q.Dequeue() | Out-Null } catch {} }
                $q.Enqueue(@{ T = $line; C = $color })
            }
        } catch {}
    }
}

function Write-Log {
    param([string]$msg, [string]$color = "Default")
    if ([string]::IsNullOrWhiteSpace($msg)) { return }
    $knownLogColors = @('Green', 'Red', 'Yellow', 'Orange', 'Blue', 'Cyan', 'Gray', 'Default')
    if ([string]::IsNullOrEmpty($color) -or $color -eq 'Default') {
        $color = Get-LogAutoColor $msg
    } elseif ($knownLogColors -notcontains $color) {
        $color = 'Default'
    }
    $time = (Get-Date).ToString("HH:mm:ss")
    $line = "[$time] $msg"
    Write-LogLine -line $line -color $color
    Write-Host $line -ForegroundColor (Get-LogConsoleColor $color)
}

function Drain-BgLog {
    # Выполняется СТРОГО в UI-потоке (таймер поллера): прямой доступ к логу.
    try {
        $q = $null
        try { $q = $global:BgLogQueue } catch {}
        if (-not $q -or $q.Count -eq 0) { return }
        $box = $null
        try { $box = $LogBox } catch {}
        if (-not $box) { return }
        $n = 0
        while ($n -lt 500) {
            $item = $null
            try { if ($q.Count -eq 0) { break }; $item = $q.Dequeue() } catch { break }
            if ($null -eq $item) { break }
            try {
                if ($item -is [hashtable] -and $item.ContainsKey('T')) {
                    Add-LogColoredText -Box $box -Text ([string]$item.T) -ColorName ([string]$item.C)
                } else {
                    Add-LogColoredText -Box $box -Text ([string]$item) -ColorName 'Default'
                }
            } catch { break }
            $n++
        }
    } catch {}
}

# Определение Write-Log для runspace (Invoke-Async). Пишет в файл напрямую,
# в UI — только через очередь $bgLogQueue (см. Write-LogLine, без делегатов).
$script:AsyncLogWriter = {
    function Write-Log {
        param([string]$msg, [string]$color = "Default")
        # Автоцвет продублирован: в этот ранспейс Get-LogAutoColor не инжектится.
        if ([string]::IsNullOrEmpty($color) -or $color -eq 'Default') {
            if ($msg -match '═══') { $color = 'Blue' }
            elseif ($msg -match '✗|\[X\]|✖|КРИТИЧНО|ОШИБКА|Ошибк|ERROR|не удалось|Не удалось|ПРЕРВАНО| НЕТ\b') { $color = 'Red' }
            elseif ($msg -match '⚠|\[!\]|ВНИМАНИЕ|пропущ|Пропущ|отмен|Отмен') { $color = 'Orange' }
            elseif ($msg -match '✓|\[OK\]|Готово|готово|Успешно|успешно|заверш|Заверш|скопирован|Скопирован') { $color = 'Green' }
            elseif ($msg -match '──|\[\*\]|▶') { $color = 'Cyan' }
            elseif ($msg -match '^\[=\]|уже настроено|Нет данных|нет данных|не найден|не найдена|пропускаю') { $color = 'Gray' }
            else { $color = 'Default' }
        }
        $time = (Get-Date).ToString("HH:mm:ss")
        $line = "[$time] $msg"
        try {
            $lp = $null
            try { $lp = $bgLogPath } catch {}
            if (-not $lp) { try { $lp = $script:LogPath } catch {} }
            if ($lp) { "$line`n" | Out-File -FilePath $lp -Append -Encoding UTF8 -ErrorAction SilentlyContinue }
        } catch {}
        try {
            $q = $null
            try { $q = $bgLogQueue } catch {}
            if ($q) {
                if ($q.Count -gt 5000) { try { $q.Dequeue() | Out-Null } catch {} }
                $q.Enqueue(@{ T = $line; C = $color })
            }
        } catch {}
        $cc = switch ($color) {
            "Green" {"Green"} "Red" {"Red"} "Yellow" {"Yellow"} "Orange" {"DarkYellow"}
            "Blue" {"Cyan"} "Cyan" {"Cyan"} "Gray" {"Gray"} default {"White"}
        }
        Write-Host $line -ForegroundColor $cc
    }
}

function Get-ScriptTimeout {
    param([string]$FilePath)
    # Зависший плагин: 2 попытки по 60с, дальше скип (см. Run-SelectedScripts).
    # Исключения — WinSxS/DISM и winget (снос+установка): честные десятки минут, не вешать на них 60с.
    if ($FilePath -like '*winsxs*') { return 1800 }
    if ($FilePath -like '*winget*') { return 3600 }
    return 60
}

$global:BgResults = [hashtable]::Synchronized(@{})

function Set-BgResult {
    # Общая шина фон->UI. Работает из любой сессии: в фоне видит живую ссылку
    # $bgResults, в UI — $global:BgResults (один и тот же объект).
    param($Key, $Value)
    try {
        $t = $null
        try { $t = $bgResults } catch {}
        if (-not $t) { try { $t = $global:BgResults } catch {} }
        if ($t) { $t[$Key] = $Value }
    } catch {}
}

function Get-BgResult {
    param($Key)
    try {
        $t = $null
        try { $t = $global:BgResults } catch {}
        if (-not $t) { try { $t = $bgResults } catch {} }
        if ($t -and $t.ContainsKey($Key)) { return $t[$Key] }
    } catch {}
    return $null
}

function Start-BgPoller {
    # Таймер UI-потока: забирает готовые результаты из шины и рисует.
    # Создаётся в UI-сессии — все функции и контролы резолвятся всегда.
    if ($script:BgTimer) { try { $script:BgTimer.Start() } catch {}; return }
    $script:BgTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:BgTimer.Interval = [TimeSpan]::FromMilliseconds(400)
    $script:BgTimer.Add_Tick({
        if ($script:BgTickBusy) { return }
        $script:BgTickBusy = $true
        try { Test-BgQueue } catch { Write-Log "Ошибка очереди фона: $_" -Color "Red" }
        $script:BgTickBusy = $false
    })
    $script:BgTimer.Start()
}

function Stop-BgPoller {
    try { if ($script:BgTimer) { $script:BgTimer.Stop() } } catch {}
}

function Invoke-OnUI {
    # Неблокирующая доставка работы в UI-поток. Никогда не вешает фоновый поток:
    # Dispatcher.InvokeAsync ставит действие в очередь и сразу возвращается.
    # Работает и из основного ранспейса, и из фоновых (туда Invoke-Async
    # вшивает эту функцию и кладёт диспетчер в $bpDispatcher).
    param([scriptblock]$ScriptBlock)
    try {
        $d = $null
        try { if ($window -and $window.Dispatcher) { $d = $window.Dispatcher } } catch {}
        if (-not $d) { try { if ($bpDispatcher) { $d = $bpDispatcher } } catch {} }
        if ($d -and (-not $d.HasShutdownStarted) -and (-not $d.HasShutdownFinished)) {
            $d.InvokeAsync([System.Action]$ScriptBlock) | Out-Null
            return $true
        }
    } catch {}
    try {
        $t = (Get-Date).ToString("HH:mm:ss") + " [Invoke-OnUI] no dispatcher`r`n"
        [System.IO.File]::AppendAllText($script:LogPath, $t)
    } catch {}
    return $false
}

function Test-RequiredCommands {
    param([string[]]$Names)
    return @($Names | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
}

function Stop-ProcessTree {
    # Рубим всё дерево: дети наследуют перенаправленные пайпы и держат их
    # после смерти родителя — из-за этого ReadToEndAsync не завершается никогда
    # и раннер "висит без ошибки". Сначала внуки, потом сам процесс.
    # (Параметр НЕ называем $Pid — это read-only автовременная PowerShell.)
    param([int]$TargetPid)
    if ($TargetPid -le 4) { return }
    try {
        $kids = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$TargetPid" -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessId -ne $TargetPid } |
            Select-Object -ExpandProperty ProcessId)
        foreach ($k in $kids) { try { Stop-ProcessTree -TargetPid ([int]$k) } catch {} }
    } catch {}
    try { Stop-Process -Id $TargetPid -Force -ErrorAction SilentlyContinue } catch {}
}

function Read-ProcessOutput {
    # Забираем вывод с лимитом: висящий пайп не должен вешать раннер.
    param($Task, [int]$TimeoutMs = 15000)
    try {
        if ($Task -and $Task.Wait($TimeoutMs)) { return [string]$Task.Result }
    } catch {}
    return ""
}

function Invoke-ScriptFileWithRetry {
    param([string]$FilePath, [int]$MaxAttempts = 2, [int]$TimeoutSec = 60, [hashtable]$Control = $null)
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        if ($Control -and $Control.Abort) { throw "STOPPED_BY_USER: $(Split-Path $FilePath -Leaf)" }
        Write-Log "[$attempt/$MaxAttempts] Запуск: $(Split-Path $FilePath -Leaf)"
        try {
            $fiChk = Get-Item -LiteralPath $FilePath -ErrorAction Stop
            Write-Log ("Файл: " + $fiChk.FullName + " (" + $fiChk.Length + " байт)")
        } catch { Write-Log ("Нет файла скрипта: " + $FilePath) -Color "Red"; return $false }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
        if (-not (Test-Path $psi.FileName)) { $psi.FileName = "powershell" }
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$FilePath`""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $proc = $null
        try {
            $proc = [System.Diagnostics.Process]::Start($psi)
            if ($Control) { try { $Control.ChildPid = $proc.Id } catch {} }
            $outTask = $proc.StandardOutput.ReadToEndAsync()
            $errTask = $proc.StandardError.ReadToEndAsync()
            $exited = $proc.WaitForExit($TimeoutSec * 1000)
            if (-not $exited) {
                Write-Log "ЗАВИС: $(Split-Path $FilePath -Leaf) не отвечает ${TimeoutSec}c, убиваю дерево PID $($proc.Id)..." -Color Yellow
                try { Stop-ProcessTree -TargetPid $proc.Id } catch { Write-Log ("Не вышло убить дерево: " + $_) -Color Yellow }
                try { $null = $proc.WaitForExit(5000) } catch {}
                $null = Read-ProcessOutput -Task $outTask -TimeoutMs 5000
                $null = Read-ProcessOutput -Task $errTask -TimeoutMs 5000
                if ($Control -and $Control.Abort) { throw "STOPPED_BY_USER: $(Split-Path $FilePath -Leaf)" }
                if ($attempt -eq $MaxAttempts) {
                    throw "Скрипт `"$FilePath`" завис $MaxAttempts раза подряд (таймаут ${TimeoutSec}c)"
                }
                Write-Log "Перезапуск $(Split-Path $FilePath -Leaf) (попытка $($attempt+1)/$MaxAttempts)" -Color Yellow
                continue
            }
            if ($Control -and $Control.Abort) { throw "STOPPED_BY_USER: $(Split-Path $FilePath -Leaf)" }
            $stdout = Read-ProcessOutput -Task $outTask
            $stderr = Read-ProcessOutput -Task $errTask
            if ($stdout) { $stdout -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | ForEach-Object { Write-Log "   $_" } }
            if ($stderr) { $stderr -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | ForEach-Object { Write-Log "   $_" -Color Yellow } }
            if ($proc.ExitCode -ne 0) {
                if ($proc.ExitCode -eq -196608) {
                    Write-Log "Скрипт $(Split-Path $FilePath -Leaf) ПРОПАЛ с диска к моменту запуска (код -196608 = нет .ps1 файла)." -Color Red
                    Write-Log "Обычно виноват антивирус (глянь карантин Defender) или чистка TEMP. Жми «Обновить» в шапке Модулей." -Color Yellow
                } else {
                    Write-Log "Скрипт $(Split-Path $FilePath -Leaf) завершился с кодом $($proc.ExitCode)" -Color Yellow
                }
                return $false
            }
            return $true
        } catch {
            if ($_.Exception.Message -like "*завис $MaxAttempts раза*") { throw }
            Write-Log "Ошибка запуска $(Split-Path $FilePath -Leaf): $_" -Color Red
            if ($attempt -eq $MaxAttempts) { throw "Скрипт `"$FilePath`" упал $MaxAttempts раза: $_" }
        } finally {
            if ($Control) { try { $Control.ChildPid = 0 } catch {} }
            if ($proc) { try { $proc.Dispose() } catch {} }
        }
    }
    return $false
}

function Test-RepoManifestTextFile {
    param([string]$Path)
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $name = [System.IO.Path]::GetFileName($Path).ToLowerInvariant()
    return (@('.bat', '.cfg', '.cmd', '.conf', '.css', '.csv', '.editorconfig', '.gitattributes', '.gitignore', '.htm', '.html', '.ini', '.js', '.json', '.md', '.ps1', '.psd1', '.toml', '.txt', '.svg', '.xml', '.xaml', '.yaml', '.yml', '.yar', '.yara') -contains $ext) -or ($name -match '^(license|notice|copying|readme)$')
}

function Get-RepoManifestHash {
    param([string]$Path)
    if (Test-RepoManifestTextFile -Path $Path) {
        $text = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($Path))
        $text = $text.Replace("`r`n", "`n").Replace("`r", "`n")
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') } finally { $sha.Dispose() }
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}

function Test-RepoManifest {
    param([string]$Root, [switch]$Strict)
    if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root -PathType Container)) { return $false }
    try {
        $rootItem = Get-Item -LiteralPath $Root -Force -ErrorAction Stop
        if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        $ancestor = $Root
        while (-not [string]::IsNullOrEmpty($ancestor)) {
            $ancestorItem = $null
            try { $ancestorItem = Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop } catch {}
            if ($null -ne $ancestorItem -and (($ancestorItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) { return $false }
            $parent = [System.IO.Path]::GetDirectoryName($ancestor)
            if ([string]::IsNullOrEmpty($parent) -or $parent -eq $ancestor) { break }
            $ancestor = $parent
        }
    } catch { return $false }
    $manifestPath = Join-Path $Root 'SHA256SUMS'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $false }
    try {
        $manifestItem = Get-Item -LiteralPath $manifestPath -Force -ErrorAction Stop
        if (($manifestItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    } catch { return $false }
    $expected = @{}
    try {
        foreach ($line in [System.IO.File]::ReadAllLines($manifestPath, [System.Text.Encoding]::UTF8)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$') { return $false }
            $hash = $Matches[1].ToUpperInvariant()
            $rel = $Matches[2].Replace('/', '\')
            if ([System.IO.Path]::IsPathRooted($rel) -or $rel -match '(^|\\)\.\.(\\|$)' -or $rel.Contains(':')) { return $false }
            $key = $rel.ToUpperInvariant()
            if ($expected.ContainsKey($key)) { return $false }
            $expected[$key] = $hash
        }
        if ($expected.Count -eq 0) { return $false }
        $entries = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction Stop | Where-Object { $_.FullName -notmatch '[\\/]\.git([\\/]|$)' -and $_.Name -ne 'SHA256SUMS' })
        foreach ($entry in $entries) {
            if (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        }
        $actual = @($entries | Where-Object { -not $_.PSIsContainer })
        $releaseFiles = @($actual | Where-Object {
            $rel = $_.FullName.Substring($Root.Length).TrimStart('\', '/')
            $rel -notmatch '^(?i)mockup[\\/]'
        })
        if ($Strict -and $releaseFiles.Count -ne $expected.Count) { return $false }
        foreach ($key in $expected.Keys) {
            $path = Join-Path $Root $key
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
        }
        foreach ($file in $actual) {
            $rel = $file.FullName.Substring($Root.Length).TrimStart('\', '/')
            $key = $rel.ToUpperInvariant()
            if (-not $expected.ContainsKey($key)) {
                if ($rel -match '^(?i)(tests|mockup)[\\/]') { continue }
                if ($Strict -or ($file.Extension -ieq '.ps1')) { return $false }
                continue
            }
            $hash = [string](Get-RepoManifestHash -Path $file.FullName)
            if ($hash.ToUpperInvariant() -ne $expected[$key]) { return $false }
        }
        return $true
    } catch { return $false }
}

function Expand-RepoArchive {
    param([string]$ZipPath, [string]$Destination)
    try {
        Expand-Archive -Path $ZipPath -DestinationPath $Destination -Force -ErrorAction Stop
        return
    } catch {
        Write-Log "Expand-Archive недоступен ($($_.Exception.Message)), распаковка через .NET..." -Color "Yellow"
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $Destination)
}

function Set-RepoCacheAcl {
    param([string]$Path)
    try {
        $rootItem = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not $rootItem.PSIsContainer -or (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) { return $false }
        $entries = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction Stop)
        foreach ($entry in $entries) { if (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false } }
        & icacls.exe $rootItem.FullName '/inheritance:r' '/grant:r' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
        foreach ($entry in $entries) {
            $flags = if ($entry.PSIsContainer) { '(OI)(CI)F' } else { 'F' }
            & icacls.exe $entry.FullName '/inheritance:r' '/grant:r' ('*S-1-5-18:' + $flags) ('*S-1-5-32-544:' + $flags) 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { return $false }
        }
        try { & icacls.exe $rootItem.FullName '/setowner' '*S-1-5-32-544' 2>$null | Out-Null } catch {}
        return $true
    } catch { return $false }
}

function Initialize-RepoCache {
    $token = [Guid]::NewGuid().ToString('N').Substring(0, 12)
    $base = if (-not [string]::IsNullOrWhiteSpace($env:ProgramData)) { Join-Path $env:ProgramData ('PotatoPC-' + $token) } else { Join-Path ([string]$script:WorkFolder) ('PotatoPC-cache-' + $token) }
    $cache = Join-Path $base 'cache'
    try {
        if (-not (Test-Path -LiteralPath $base)) { New-Item -ItemType Directory -Path $base -Force -ErrorAction Stop | Out-Null }
        if (-not (Test-Path -LiteralPath $cache)) { New-Item -ItemType Directory -Path $cache -Force -ErrorAction Stop | Out-Null }
    } catch { Write-Log ('Не удалось создать каталог кэша: ' + $_.Exception.Message) -Color 'Red'; return '' }
    $secure = (Set-RepoCacheAcl -Path $base) -and (Set-RepoCacheAcl -Path $cache)
    if ($secure) {
        try {
            $probe = Join-Path $cache '.write-probe'
            [System.IO.File]::WriteAllText($probe, 'ok')
            Remove-Item -LiteralPath $probe -Force -ErrorAction Stop
        } catch { $secure = $false }
    }
    if ($secure) {
        $script:RepoCacheSecure = $true
        $script:RepoCacheFolder = $cache
        return $cache
    }
    $fallbackBase = Join-Path ([string]$script:WorkFolder) ('PotatoPC-cache-' + $token)
    $fallbackCache = Join-Path $fallbackBase 'cache'
    try {
        if (-not (Test-Path -LiteralPath $fallbackBase)) { New-Item -ItemType Directory -Path $fallbackBase -Force -ErrorAction Stop | Out-Null }
        if (-not (Test-Path -LiteralPath $fallbackCache)) { New-Item -ItemType Directory -Path $fallbackCache -Force -ErrorAction Stop | Out-Null }
        $probe = Join-Path $fallbackCache '.write-probe'
        [System.IO.File]::WriteAllText($probe, 'ok')
        Remove-Item -LiteralPath $probe -Force -ErrorAction Stop
    } catch { Write-Log ('Не удалось подготовить временный кэш: ' + $_.Exception.Message) -Color 'Red'; return '' }
    Write-Log 'Защищённый ProgramData-кэш недоступен; используется проверенный временный кэш текущего запуска' -Color 'Yellow'
    $script:RepoCacheSecure = $false
    $script:RepoCacheFolder = $fallbackCache
    return $fallbackCache
}

function Get-RepoDirectories {
    param([string]$Root = $script:RepoCacheFolder)
    if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
    try {
        return @(Get-ChildItem -LiteralPath $Root -Directory -Force -ErrorAction Stop |
            Where-Object { $_.Name -eq 'PotatoPC-main' -or $_.Name -like 'PotatoPC-main-*' -or $_.Name -like '*-main' } |
            Sort-Object LastWriteTime -Descending)
    } catch { return @() }
}

function Download-Repo {
    param([switch]$Force)
    $token = [Guid]::NewGuid().ToString('N')
    $cacheRoot = Initialize-RepoCache
    if ([string]::IsNullOrWhiteSpace($cacheRoot)) { Write-Log 'Не удалось создать защищённый кэш репозитория' -Color 'Red'; return $false }
    $zipPath = Join-Path $cacheRoot ('.repo-' + $token + '.zip')
    $stagePath = Join-Path $cacheRoot ('.stage-' + $token)
    $finalPath = Join-Path $cacheRoot ('PotatoPC-main-' + $token.Substring(0, 8))
    try {
        Write-Log "$(if($Force){'Обновление'}else{'Загрузка'}) репозитория с GitHub..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $script:RepoZipUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace([string]$script:RepoZipSha256)) {
            $zipHash = [string](Get-FileHash -LiteralPath $zipPath -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($zipHash -ne [string]$script:RepoZipSha256) { throw ('Хэш ZIP не совпадает: ' + $zipHash) }
        }
        New-Item -ItemType Directory -Path $stagePath -Force | Out-Null
        Expand-RepoArchive -ZipPath $zipPath -Destination $stagePath
        $candidate = @(Get-ChildItem -LiteralPath $stagePath -Directory -Force -ErrorAction Stop |
            Where-Object { (Test-Path (Join-Path $_.FullName 'menu.ps1')) -and (Test-Path (Join-Path $_.FullName 'apps.json')) } |
            Select-Object -First 1)
        if ($candidate.Count -eq 0) { throw 'В архиве нет menu.ps1 и apps.json' }
        Move-Item -LiteralPath $candidate[0].FullName -Destination $finalPath -ErrorAction Stop
        if (-not (Test-RepoManifest -Root $finalPath -Strict)) { throw 'Манифест SHA256SUMS не проходит проверку' }
        try { Get-ChildItem -LiteralPath $finalPath -Filter '*.ps1' -Recurse -File -Force -ErrorAction Stop | Unblock-File -ErrorAction Stop } catch { throw ('Не удалось снять блокировку: ' + $_.Exception.Message) }
        $scripts = Join-Path $finalPath 'scripts'
        $apps = Join-Path $finalPath 'apps.json'
        if (-not (Test-Path $scripts -PathType Container) -or -not (Test-Path $apps -PathType Leaf)) { throw 'В архиве отсутствуют scripts или apps.json' }
        $script:ScriptsFolder = $scripts
        $script:AppsJsonPath = $apps
        $n = @(Get-ChildItem -LiteralPath $scripts -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue).Count
        Write-Log "Готово. Скриптов: $n"
        return $true
    } catch {
        try { if (Test-Path -LiteralPath $finalPath) { Remove-Item -LiteralPath $finalPath -Recurse -Force -ErrorAction SilentlyContinue } } catch {}
        Write-Log ("Ошибка загрузки: " + $_.Exception.Message) -Color "Red"
        return $false
    } finally {
        try { if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue } } catch {}
        try { if (Test-Path -LiteralPath $stagePath) { Remove-Item -LiteralPath $stagePath -Recurse -Force -ErrorAction SilentlyContinue } } catch {}
    }
}

function Initialize-PotatoPC {
    Write-Log "Инициализация..."
    if (-not (Test-Path $script:WorkFolder)) {
        New-Item -ItemType Directory -Path $script:WorkFolder -Force | Out-Null
    }
    $localRoot = [string]$script:LocalRepoRoot
    if ([string]::IsNullOrWhiteSpace($localRoot)) {
        try { if ($script:ModuleDir) { $localRoot = Split-Path $script:ModuleDir -Parent } } catch {}
    }
    $localScripts = if ($localRoot) { Join-Path $localRoot 'scripts' } else { '' }
    $localApps = if ($localRoot) { Join-Path $localRoot 'apps.json' } else { '' }
    if ($localScripts -and $localApps -and (Test-Path -LiteralPath $localScripts -PathType Container) -and (Test-Path -LiteralPath $localApps -PathType Leaf) -and (Test-RepoManifest -Root $localRoot)) {
        $localCount = @(Get-ChildItem -LiteralPath $localScripts -Recurse -Filter '*.ps1' -File -ErrorAction SilentlyContinue).Count
        if ($localCount -gt 0) {
            $script:ScriptsFolder = $localScripts
            $script:AppsJsonPath = $localApps
            Write-Log ("Используется локальный репозиторий: $localScripts; скриптов: $localCount")
            Set-BgResult -Key 'paths' -Value @{ ScriptsFolder = $script:ScriptsFolder; AppsJsonPath = $script:AppsJsonPath }
            return
        }
    }
    $cacheRoot = Initialize-RepoCache
    if ([string]::IsNullOrWhiteSpace($cacheRoot)) { $script:ScriptsFolder = ''; $script:AppsJsonPath = ''; Set-BgResult -Key 'initError' -Value 'Не удалось подготовить защищённый кэш репозитория'; return }
    $repoFolder = @(Get-RepoDirectories -Root $cacheRoot | Select-Object -First 1)
    $cachedOk = $false
    if ($repoFolder.Count -gt 0) {
        $repoFolder = $repoFolder[0]
        $cachedScripts = Join-Path $repoFolder.FullName "scripts"
        $cachedN = @(Get-ChildItem -LiteralPath $cachedScripts -Recurse -Filter "*.ps1" -File -ErrorAction SilentlyContinue).Count
        $cachedOk = ((Test-Path $cachedScripts -PathType Container) -and ($cachedN -gt 0) -and (Test-Path (Join-Path $repoFolder.FullName "apps.json") -PathType Leaf) -and (Test-RepoManifest -Root $repoFolder.FullName -Strict) -and (($script:RepoCacheSecure -eq $true) -or (Set-RepoCacheAcl -Path $repoFolder.FullName)))
        if (-not $cachedOk) { Write-Log "Локальный кэш повреждён (скриптов: $cachedN), качаю заново..." -Color "Yellow" }
    }
    if ($cachedOk) {
        $script:ScriptsFolder = Join-Path $repoFolder.FullName "scripts"
        $script:AppsJsonPath  = Join-Path $repoFolder.FullName "apps.json"
        $n = @(Get-ChildItem -LiteralPath $script:ScriptsFolder -Recurse -Filter "*.ps1" -File -ErrorAction SilentlyContinue).Count
        Write-Log "Репозиторий найден локально. Скриптов: $n"
    } elseif (-not (Download-Repo)) {
        $fallback = $null
        foreach ($candidate in @(Get-RepoDirectories -Root $cacheRoot)) {
            if ((Test-RepoManifest -Root $candidate.FullName -Strict) -and (($script:RepoCacheSecure -eq $true) -or (Set-RepoCacheAcl -Path $candidate.FullName))) { $fallback = $candidate; break }
        }
        if ($null -eq $fallback) { $script:ScriptsFolder = ''; $script:AppsJsonPath = ''; Set-BgResult -Key 'initError' -Value 'Репозиторий недоступен или не прошёл проверку'; return }
        $script:ScriptsFolder = Join-Path $fallback.FullName "scripts"
        $script:AppsJsonPath = Join-Path $fallback.FullName "apps.json"
    }
    # Пути живут и в UI-сессии: кладём в шину, Test-BgQueue применит до построения панелей
    Set-BgResult -Key 'paths' -Value @{ ScriptsFolder = $script:ScriptsFolder; AppsJsonPath = $script:AppsJsonPath }
}

function Test-TrustedWingetPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
        $root = [System.IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'WindowsApps')).TrimEnd('\')
        if (-not ($full.StartsWith($root + '\', [System.StringComparison]::OrdinalIgnoreCase))) { return $false }
        $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
        if ($item.PSIsContainer -or (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) { return $false }
        $signature = Get-AuthenticodeSignature -LiteralPath $full -ErrorAction Stop
        if ($signature.Status -ne 'Valid' -or [string]::IsNullOrWhiteSpace([string]$signature.SignerCertificate.Subject) -or $signature.SignerCertificate.Subject -notmatch '(?i)Microsoft') { return $false }
        return $true
    } catch { return $false }
}

function Get-WingetPath {
    try {
        $cmd = Get-Command winget -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source -and (Test-Path $cmd.Source) -and (Test-TrustedWingetPath -Path $cmd.Source)) { return $cmd.Source }
    } catch {}
    $candidates = @()
    try {
        $appx = @(Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction Stop)
        foreach ($package in $appx) { if ($package.InstallLocation) { $candidates += (Join-Path ([string]$package.InstallLocation) 'winget.exe') } }
    } catch {}
    $candidates += @(
        "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
    )
    foreach ($p in $candidates) {
        if ($p -like "*`*") {
            try {
                $found = Get-ChildItem -Path $p -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found -and (Test-Path $found.FullName) -and (Test-TrustedWingetPath -Path $found.FullName)) { return $found.FullName }
            } catch {}
        } elseif ((Test-Path $p) -and (Test-TrustedWingetPath -Path $p)) { return $p }
    }
    return ""
}

function Invoke-WingetCommand {
    param([string]$Exe, [string]$Arguments, [int]$TimeoutSec = 300)
    $result = @{ Code = -1; Out = ''; Error = ''; TimedOut = $false; Ok = $false }
    if ([string]::IsNullOrWhiteSpace($Exe) -or $Exe -eq 'winget') { return $result }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $process = $null
    try {
        $process = [System.Diagnostics.Process]::Start($psi)
        if ($null -eq $process) { return $result }
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit([Math]::Max(1000, $TimeoutSec * 1000))) {
            try { Stop-ProcessTree -TargetPid $process.Id } catch {}
            try { $null = $process.WaitForExit(5000) } catch {}
            $result.TimedOut = $true
            return $result
        }
        try { if ($outTask.Wait(5000)) { $result.Out = [string]$outTask.Result } } catch {}
        try { if ($errTask.Wait(5000)) { $result.Error = [string]$errTask.Result } } catch {}
        $result.Code = [int]$process.ExitCode
        $result.Ok = ($result.Code -eq 0)
        return $result
    } catch { $result.Error = $_.Exception.Message; return $result }
    finally { if ($process) { try { $process.Dispose() } catch {} } }
}

function Get-SystemInfo {
    try {
        $os    = Get-CimInstance Win32_OperatingSystem
        $cpu   = (Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).Name
        $ramB  = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory
        $disk  = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
        $boot  = $os.LastBootUpTime
        $upMin = [int]((Get-Date) - $boot).TotalMinutes
        $upStr = if ($upMin -ge 1440) { "$([int]($upMin/1440))д $([int](($upMin%1440)/60))ч $(($upMin%60))м" }
                 elseif ($upMin -ge 60) { "$([int]($upMin/60))ч $(($upMin%60))м" }
                 else { "$upMin мин" }
        return @{
            OS     = "$($os.Caption) Build $($os.BuildNumber)"
            CPU    = $cpu.Trim()
            RAM    = "$([math]::Round($ramB/1GB,1)) ГБ"
            Disk   = "C: $([math]::Round($disk.FreeSpace/1GB,1)) ГБ своб. / $([math]::Round($disk.Size/1GB,1)) ГБ"
            Uptime = $upStr
        }
    } catch {
        return @{ OS="Неизвестно"; CPU="Неизвестно"; RAM="Неизвестно"; Disk="Неизвестно"; Uptime="Неизвестно" }
    }
}

function Create-RestorePoint {
    Write-Log "Создание точки восстановления системы..."
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "PotatoPC Optimizer Backup" -RestorePointType "MODIFY_SETTINGS"
        Write-Log "Точка восстановления успешно создана!" -Color "Green"
        return $true
    } catch {
        Write-Log "Ошибка создания точки восстановления: $_" -Color "Red"
        return $false
    }
}

function Set-StartupApprovedState {
    param([string]$RegKey, [string]$ValueName, [bool]$Enable, [string]$ApprovedSubOverride = "")
    try {
        $isHKCU      = $RegKey -like "HKEY_CURRENT_USER*"
        $isRunOnce   = $RegKey -like "*RunOnce*"
        $approvedSub = if ($ApprovedSubOverride) { $ApprovedSubOverride }
                       elseif ($isRunOnce) {
                           'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\RunOnce'
                       } elseif ($RegKey -like '*WOW6432Node*') {
                           'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
                       } else {
                           'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
                       }
        $rootKey = if ($isHKCU) { [Microsoft.Win32.Registry]::CurrentUser }
                   else         { [Microsoft.Win32.Registry]::LocalMachine }
        $approvedKey = $rootKey.OpenSubKey($approvedSub, $true)
        if ($null -eq $approvedKey) {
            $approvedKey = $rootKey.CreateSubKey($approvedSub)
        }
        $existing = $approvedKey.GetValue($ValueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($existing -is [byte[]] -and $existing.Length -ge 4) {
            $data = [byte[]]$existing
        } else {
            $data = [byte[]]@(0x02,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)
        }
        $data[0] = if ($Enable) { [byte]0x02 } else { [byte]0x03 }
        $approvedKey.SetValue($ValueName, [byte[]]$data, [Microsoft.Win32.RegistryValueKind]::Binary)
        $approvedKey.Dispose()
        return $true
    } catch {
        Write-Log "StartupApproved для '$ValueName': $_" -Color "Red"
        return $false
    }
}

if (-not ("PSAsyncHelper" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
public static class PSAsyncHelper {
    public static Action MakeCompletion(PowerShell ps, IAsyncResult iar, Action<string> completion, Runspace bgRunspace, Runspace callerRunspace) {
        return () => {
            Exception err = null;
            try { ps.EndInvoke(iar); }
            catch (Exception e) { err = e; }
            try { ps.Dispose(); } catch {}
            try { if (bgRunspace != null) bgRunspace.Dispose(); } catch {}
            try { if (callerRunspace != null) { callerRunspace.SessionStateProxy.SetVariable("AsyncLastError", err == null ? null : err.Message); } } catch {}
            try { if (callerRunspace != null) { Runspace.DefaultRunspace = callerRunspace; } } catch {}
            if (completion != null) { try { completion(err == null ? null : err.Message); } catch {} }
        };
    }
    public static Action MakeRunAction(Action body, Runspace callerRunspace) {
        return () => {
            try { if (callerRunspace != null) Runspace.DefaultRunspace = callerRunspace; } catch {}
            if (body != null) { try { body(); } catch {} }
        };
    }
}
"@
}

$script:BgISS = $null
$script:BgConfigNames = @('ModuleDir','WorkFolder','RepoCacheFolder','LocalRepoRoot','ScriptsFolder','AppsJsonPath','AppsJsonUrl','ProtectRulesManifestUrl','ProtectRulesBaseUrl','RepoZipUrl','RepoZipSha256','LogPath','SettingsPath','UIStatePath','WindowsMajorVersion','CleanRulesPath','YaraEngineZipSha256','YaraEngineExeSha256','YaraRulesManifestSha256')

function Get-BgSessionState {
    # Снимок всех пользовательских функций один раз (после загрузки модулей).
    # Каждый фоновый ранспейс стартует с ним: общий ранспейс UI ни с кем не делится,
    # гонок подгрузки модулей между потоками больше нет.
    # При сбое снимка возвращаем $null — Start-Background запустит тело
    # в пустом ранспейсе, а ошибка уйдёт в лог (видимый), а не в тишину.
    if ($script:BgISS) { return $script:BgISS }
    try {
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        foreach ($fn in (Get-Command -CommandType Function)) {
            if ($fn.Source -ne '') { continue }
            if ([string]::IsNullOrWhiteSpace($fn.Name)) { continue }
            try {
                $entry = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry($fn.Name, $fn.ScriptBlock)
                $iss.Commands.Add($entry)
            } catch {}
        }
        $script:BgISS = $iss
        return $iss
    } catch {
        try { Write-Log ("Фон: не вышло снять функции: " + $_.Exception.Message) -Color "Yellow" } catch {}
        return $null
    }
}

function Start-Background {
    param([scriptblock]$ScriptBlock, [hashtable]$Variables = @{})
    # Всё тяжёлое предвычисляем здесь, в UI-потоке: объект ISS, init-скрипт,
    # исходник тела, живые ссылки. Пул-поток делает только .NET-обвязку
    # ранспейса (без единого cmdlet) и выполняет тело в полной изоляции.
    $iss = Get-BgSessionState
    $bodySrc = $ScriptBlock.ToString()
    $initLines = @()
    foreach ($n in $script:BgConfigNames) {
        try {
            $v = (Get-Variable -Name $n -Scope Script -ErrorAction Stop).Value
            if ($v -is [string]) { $initLines += ('$script:{0} = ''{1}''' -f $n, ($v -replace "'", "''")) }
            elseif ($v -is [int] -or $v -is [bool]) { $initLines += ('$script:{0} = {1}' -f $n, $v) }
        } catch {}
    }
    $initScript = ($initLines -join "`n")
    $liveVars = @{}
    try { if ($LogBox) { $liveVars['LogBox'] = $LogBox } } catch {}
    try { if ($LogBox -and $LogBox.Dispatcher) { $liveVars['bpDispatcher'] = $LogBox.Dispatcher } } catch {}
    try { if ($global:BgResults) { $liveVars['bgResults'] = $global:BgResults } } catch {}
    try { if ($global:BgLogQueue) { $liveVars['bgLogQueue'] = $global:BgLogQueue } } catch {}
    foreach ($kv in $Variables.GetEnumerator()) { $liveVars[$kv.Key] = $kv.Value }
    $logPathStr = [string]$script:LogPath
    $runner = {
        try {
            if ($iss) { $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss) }
            else { $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace() }
            $rs.ApartmentState = "STA"
            $rs.ThreadOptions = "ReuseThread"
            $rs.Open()
            try {
                foreach ($kv in $liveVars.GetEnumerator()) {
                    try { $rs.SessionStateProxy.SetVariable($kv.Key, $kv.Value) } catch {}
                }
                $ps = [System.Management.Automation.PowerShell]::Create()
                $ps.Runspace = $rs
                try {
                    if (-not [string]::IsNullOrWhiteSpace($initScript)) { [void]$ps.AddScript($initScript) }
                    [void]$ps.AddScript($bodySrc)
                    [void]$ps.Invoke()
                    foreach ($e in @($ps.Streams.Error)) {
                        # Ошибка фона — и в файл, и в UI-очередь: молчащих кнопок больше нет.
                        try {
                            $emsg = "[BG] " + $e.ToString()
                            $t = [DateTime]::Now.ToString("HH:mm:ss") + " " + $emsg + "`r`n"
                            [System.IO.File]::AppendAllText($logPathStr, $t)
                            try {
                                $q = $null
                                try { $q = $liveVars['bgLogQueue'] } catch {}
                                if ($q) {
                                    if ($q.Count -gt 5000) { try { $q.Dequeue() | Out-Null } catch {} }
                                    $q.Enqueue(@{ T = $emsg; C = 'Red' })
                                }
                            } catch {}
                        } catch {}
                    }
                } finally { try { $ps.Dispose() } catch {} }
            } finally { try { $rs.Dispose() } catch {} }
        } catch {
            try {
                $emsg = "[BG bootstrap] " + $_.Exception.Message
                $t = [DateTime]::Now.ToString("HH:mm:ss") + " " + $emsg + "`r`n"
                [System.IO.File]::AppendAllText($logPathStr, $t)
                try {
                    $q = $null
                    try { $q = $liveVars['bgLogQueue'] } catch {}
                    if ($q) {
                        if ($q.Count -gt 5000) { try { $q.Dequeue() | Out-Null } catch {} }
                        $q.Enqueue(@{ T = $emsg; C = 'Red' })
                    }
                } catch {}
            } catch {}
        }
    }.GetNewClosure()
    $callerRunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
    $action = [PSAsyncHelper]::MakeRunAction([Action]$runner, $callerRunspace)
    [System.Threading.Tasks.Task]::Run($action) | Out-Null
}

function Invoke-Async {
    param(
        [scriptblock]$ScriptBlock,
        [hashtable]$Variables = @{},
        [scriptblock]$OnComplete = $null
    )
    if (-not $script:LogState) { Set-LogExpanded -Expand $true }
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = "STA"
    $rs.ThreadOptions  = "ReuseThread"
    $rs.Open()
    if ($LogBox) { $rs.SessionStateProxy.SetVariable("LogBox", $LogBox) }
    try { if ($global:BgLogQueue) { $rs.SessionStateProxy.SetVariable("bgLogQueue", $global:BgLogQueue) } } catch {}
    try { if ($global:BgResults) { $rs.SessionStateProxy.SetVariable("bgResults", $global:BgResults) } } catch {}
    try { if ($script:LogPath) { $rs.SessionStateProxy.SetVariable("bgLogPath", [string]$script:LogPath) } } catch {}
    foreach ($kv in $Variables.GetEnumerator()) {
        $rs.SessionStateProxy.SetVariable($kv.Key, $kv.Value)
    }
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    $ps.AddScript($script:AsyncLogWriter) | Out-Null
    # инжект хелперов чтобы были доступны внутри Invoke-Async
    try {
        $retrySrc = ${function:Invoke-ScriptFileWithRetry}.ToString()
        $ps.AddScript("function Invoke-ScriptFileWithRetry {`n$retrySrc`n}") | Out-Null
        $timeoutSrc = ${function:Get-ScriptTimeout}.ToString()
        $ps.AddScript("function Get-ScriptTimeout {`n$timeoutSrc`n}") | Out-Null
        $wingetTrustSrc = ${function:Test-TrustedWingetPath}.ToString()
        $ps.AddScript("function Test-TrustedWingetPath {`n$wingetTrustSrc`n}") | Out-Null
        $wingetSrc = ${function:Get-WingetPath}.ToString()
        $ps.AddScript("function Get-WingetPath {`n$wingetSrc`n}") | Out-Null
        $onUISrc = ${function:Invoke-OnUI}.ToString()
        $ps.AddScript("function Invoke-OnUI {`n$onUISrc`n}") | Out-Null
        $bgResSrc = ${function:Set-BgResult}.ToString()
        $ps.AddScript("function Set-BgResult {`n$bgResSrc`n}") | Out-Null
        $setPrgSrc = ${function:Set-Progress}.ToString()
        $ps.AddScript("function Set-Progress {`n$setPrgSrc`n}") | Out-Null
        $clrPrgSrc = ${function:Clear-Progress}.ToString()
        $ps.AddScript("function Clear-Progress {`n$clrPrgSrc`n}") | Out-Null
    } catch {}
    # Хелперы вкладки Защита для фоновых сканирований.
    try {
        foreach ($hfn in @('Ensure-YaraEngine', 'Combine-YaraRules', 'Invoke-YaraEntry', 'Ensure-YaraRules', 'Read-ProcessOutput', 'Stop-ProcessTree', 'Invoke-WingetCommand', 'Get-RollbackFolder', 'Is-RollbackPath')) {
            try {
                $hsrc = (Get-Command $hfn -CommandType Function -ErrorAction Stop).ScriptBlock.ToString()
                $ps.AddScript("function $hfn {`n$hsrc`n}") | Out-Null
            } catch {}
        }
    } catch {}
    if ($LogBox) { try { $rs.SessionStateProxy.SetVariable("bpDispatcher", $LogBox.Dispatcher) } catch {} }
    $ps.AddScript($ScriptBlock) | Out-Null
    $iar = $ps.BeginInvoke()
    $callerRunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
    $completion = [Action]$OnComplete
    $completionWithError = [Action[string]]{
        param([string]$message)
        if (-not [string]::IsNullOrWhiteSpace($message)) {
            try { Write-Log ("Фоновая операция завершилась с ошибкой: " + $message) -Color "Red" } catch {}
        }
        if ($completion) { try { $completion.Invoke() } catch {} }
    }.GetNewClosure()
    $action = [PSAsyncHelper]::MakeCompletion($ps, $iar, $completionWithError, $rs, $callerRunspace)
    [System.Threading.Tasks.Task]::Run($action) | Out-Null
    # Handle для внешней остановки: Stop() тормозит конвейер, завершение подчистит ранспейс.
    # Остальные вызовы возвращаемое значение игнорируют — безопасно.
    $handlePs = $ps
    return [PSCustomObject]@{
        Stop = { try { $handlePs.Stop() } catch {} }.GetNewClosure()
    }
}

function Save-Settings {
    param([hashtable]$Settings)
    if (-not $script:SettingsPath) { return }
    try {
        $dir = Split-Path $script:SettingsPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $Settings | ConvertTo-Json -Compress | Out-File -FilePath $script:SettingsPath -Encoding UTF8 -Force
    } catch { Write-Log "Не удалось сохранить настройки: $_" -Color "Yellow" }
}

function Get-UIState {
    try {
        if ($script:UIStatePath -and (Test-Path $script:UIStatePath)) {
            return (Get-Content $script:UIStatePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop)
        }
    } catch {}
    return $null
}

function Save-UIState {
    try {
        if (-not $window) { return }
        $dir = Split-Path $script:UIStatePath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        @{
            Left        = $window.Left
            Top         = $window.Top
            Width       = $window.Width
            Height      = $window.Height
            State       = [string]$window.WindowState
            Tab         = $MainTabControl.SelectedIndex
            UiVersion   = 2
            LogExpanded = $script:LogState
            LogHeight   = $script:LogHeight
        } | ConvertTo-Json -Compress | Out-File -FilePath $script:UIStatePath -Encoding UTF8 -Force
    } catch {}
}

# ── Плавное сворачивание/разворачивание лога ──
if (-not ('PotatoPC.GridLengthAnimation' -as [type])) {
    try {
        Add-Type -ReferencedAssemblies @('PresentationFramework', 'PresentationCore', 'WindowsBase') -TypeDefinition @"
using System;
using System.Windows;
using System.Windows.Media.Animation;

namespace PotatoPC
{
    public class GridLengthAnimation : AnimationTimeline
    {
        public static readonly DependencyProperty FromProperty =
            DependencyProperty.Register("From", typeof(GridLength?), typeof(GridLengthAnimation));
        public static readonly DependencyProperty ToProperty =
            DependencyProperty.Register("To", typeof(GridLength?), typeof(GridLengthAnimation));

        public GridLength? From
        {
            get { return (GridLength?)GetValue(FromProperty); }
            set { SetValue(FromProperty, value); }
        }
        public GridLength? To
        {
            get { return (GridLength?)GetValue(ToProperty); }
            set { SetValue(ToProperty, value); }
        }

        public override Type TargetPropertyType
        {
            get { return typeof(GridLength); }
        }

        protected override Freezable CreateInstanceCore()
        {
            return new GridLengthAnimation();
        }

        public override object GetCurrentValue(object defaultOriginValue, object defaultDestinationValue, AnimationClock animationClock)
        {
            double fromVal = ((GridLength)defaultOriginValue).Value;
            double toVal   = ((GridLength)defaultDestinationValue).Value;
            if (From.HasValue) { fromVal = From.Value.Value; }
            if (To.HasValue)   { toVal   = To.Value.Value; }
            if (animationClock.CurrentProgress.HasValue)
            {
                double p = animationClock.CurrentProgress.Value;
                return new GridLength(fromVal + (toVal - fromVal) * p);
            }
            return new GridLength(toVal);
        }
    }
}
"@
    } catch {}
}

function Set-LogExpanded {
    param([bool]$Expand, [switch]$Instant)
    try {
        if (-not $logRow) { return }
        $script:LogState = $Expand
        if ($Expand) {
            $target = [double]$script:LogHeight
        } else {
            # свёрнутая высота = реальная высота тулбара консоли + запас
            $hdrNeed = 30.0
            try {
                $h = $LogHeaderBorder.ActualHeight
                if ($h -le 0) { $h = $LogHeaderBorder.DesiredSize.Height }
                if ($h -gt 0) { $hdrNeed = [Math]::Ceiling($h) }
            } catch {}
            try { $hdrNeed += $LogOuterBorder.BorderThickness.Top } catch {}
            $target = $hdrNeed + 10
            if ($target -lt 38) { $target = 38 }
        }
        $logSplitter.Visibility = if ($Expand) { "Visible" } else { "Collapsed" }
        try {
            $toggleIcon = Get-IconSource -Name $(if ($Expand) { "actions/go_down" } else { "actions/go_up" })
            if ($ToggleLogIcon -and $toggleIcon) { $ToggleLogIcon.Source = $toggleIcon }
            if ($ToggleLogText) { $ToggleLogText.Text = if ($Expand) { "Свернуть" } else { "Развернуть" } }
            else { $toggleLogBtn.Content = if ($Expand) { "▾ Свернуть" } else { "▴ Развернуть" } }
        } catch { try { $toggleLogBtn.Content = if ($Expand) { "▾ Свернуть" } else { "▴ Развернуть" } } catch {} }
        $from = $logRow.Height.Value
        if ([Math]::Abs($target - $from) -lt 1) { return }
        $heightProp = [System.Windows.Controls.RowDefinition]::HeightProperty
        if ($Instant) {
            try { $logRow.ApplyAnimationClock($heightProp, $null) } catch {}
            $logRow.SetValue($heightProp, [System.Windows.GridLength]::new($target))
            return
        }
        try {
            # базовое значение сразу = цель: после завершения часов значение останется верным
            $logRow.SetValue($heightProp, [System.Windows.GridLength]::new($target))
            $anim = New-Object PotatoPC.GridLengthAnimation
            $anim.From     = [System.Windows.GridLength]::new($from)
            $anim.To       = [System.Windows.GridLength]::new($target)
            $anim.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(160))
            $clock = $anim.CreateClock()
            $clock.Completed.Add({ $logRow.ApplyAnimationClock($heightProp, $null) }.GetNewClosure())
            $logRow.ApplyAnimationClock($heightProp, $clock)
        } catch {
            $logRow.SetValue($heightProp, [System.Windows.GridLength]::new($target))
        }
    } catch {}
}

# ── Hover-эффект карточек (сдвиг 2px) ──
function Add-CardFx {
    param([System.Windows.Controls.Border]$Card)
    try {
        $Card.RenderTransform = [System.Windows.Media.TranslateTransform]::new()
        $Card.Add_MouseEnter({
            param($s, $e)
            $a = [System.Windows.Media.Animation.DoubleAnimation]::new()
            $a.To = 2; $a.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(110))
            $s.RenderTransform.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $a)
        })
        $Card.Add_MouseLeave({
            param($s, $e)
            $a = [System.Windows.Media.Animation.DoubleAnimation]::new()
            $a.To = 0; $a.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(140))
            $s.RenderTransform.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $a)
        })
    } catch {}
}

function Load-Settings {
    if ($script:SettingsPath -and (Test-Path $script:SettingsPath)) {
        try { return (Get-Content $script:SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop) } catch {}
    }
    return $null
}

# Человеческое относительное время: "5 мин. назад", "вчера", "12.03.2024"
function Get-RelativeTime {
    param($Dt)
    try {
        if ($null -eq $Dt) { return "никогда" }
        $d = [DateTime]$Dt
        $span = (Get-Date) - $d
        if ($span.TotalMinutes -lt 1)  { return "только что" }
        if ($span.TotalMinutes -lt 60) { return ("{0} мин. назад" -f [int]$span.TotalMinutes) }
        if ($span.TotalHours -lt 24)   { return ("{0} ч. назад" -f [int]$span.TotalHours) }
        if ($span.TotalDays -lt 2)     { return "вчера" }
        if ($span.TotalDays -lt 30)    { return ("{0} дн. назад" -f [int]$span.TotalDays) }
        if ($span.TotalDays -lt 365)   { return ("{0} мес. назад" -f [int]($span.TotalDays / 30)) }
        return $d.ToString("dd.MM.yyyy")
    } catch { return "неизвестно" }
}

# Тёмный системный титлбар (Win10 20H1+). На старых сборках молча ничего не делает.
if (-not ('PotatoPC.Dwm' -as [type])) {
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PotatoPC_Dwm {
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
}
'@
    } catch {}
}

function Enable-DarkTitleBar {
    param($Window)
    try {
        $helper = [System.Windows.Interop.WindowInteropHelper]::new($Window)
        $hwnd = $helper.Handle
        if ($hwnd -eq [IntPtr]::Zero) { $hwnd = $helper.EnsureHandle() }
        $use = 1
        [PotatoPC_Dwm]::DwmSetWindowAttribute($hwnd, 20, [ref]$use, 4) | Out-Null
    } catch {}
}
