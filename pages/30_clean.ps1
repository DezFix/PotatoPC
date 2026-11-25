# PAGE: clean
# TITLE: Очистка
# ICON: broom
# ORDER: 30

$script:CleanUi = $null
$script:CleanGroupColors = @('#F5B544', '#E08A3C', '#7CC4FA', '#A78BFA', '#4ADE80', '#F472B6', '#94A3B8')

function Get-CleanCatalog {
    # Плоский список пунктов из cleaner\rules.json.
    $out = @()
    try {
        $j = Get-Content -LiteralPath $CleanRulesPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $gi = 0
        foreach ($g in @($j.Groups)) {
            foreach ($i in @($g.Items)) {
                $id = [string]$g.Name + '/' + [string]$i.Name
                $safe = (($g.Name -eq 'Система' -and $i.Name -notmatch 'Дамп' -and -not $i.Confirm) -or ($g.Name -eq 'Браузеры')) -and -not $i.Action
                $out += [pscustomobject]@{
                    Id = $id; Group = [string]$g.Name; GroupIndex = $gi; Name = [string]$i.Name; Desc = [string]$i.Desc
                    Paths = @($i.Paths); Action = [string]$i.Action; Special = [string]$i.Special
                    Confirm = [bool]$i.Confirm; MinAgeDays = [int]$i.MinAgeDays; ChildSubdir = [string]$i.ChildSubdir
                    Safe = $safe; Bytes = [long]-1
                }
            }
            $gi++
        }
    } catch { Write-Log ('Не прочитан cleaner\rules.json: ' + $_.Exception.Message) 'err' }
    return $out
}

function Measure-RecycleBin {
    $sum = 0L
    try {
        $sh = New-Object -ComObject Shell.Application
        foreach ($it in $sh.NameSpace(10).Items()) { try { $sum += [long]$it.ExtendedProperty('Size') } catch {} }
    } catch {}
    return $sum
}

function Measure-CleanItems {
    # Фон. Заполняет Bytes у каждого пункта.
    param($Items)
    $list = @($Items)
    $i = 0
    foreach ($it in $list) {
        $i++
        Set-JobProgress ($i / [Math]::Max(1, $list.Count)) $it.Name
        if (Test-JobCancel) { break }
        try {
            if ($it.Action) { $it.Bytes = -1; continue }
            if ($it.Special -eq 'recyclebin') { $it.Bytes = Measure-RecycleBin; continue }
            $res = @(Resolve-CleanPaths -Paths $it.Paths -ChildSubdir $it.ChildSubdir)
            $it.Bytes = if ($res.Count -gt 0) { [long](Measure-CleanPaths -Resolved $res -MinAgeDays $it.MinAgeDays) } else { 0L }
        } catch { $it.Bytes = 0 }
    }
    return $list
}

function Invoke-CleanItems {
    # Фон. Удаляет выбранное, пишет отчёт об удалённом.
    param($Items)
    $list = @($Items)
    Write-Log ('Очистка: ' + $list.Count + ' пунктов') 'head'
    Reset-CleanRemovedReport
    Clear-CleanSkipped
    $errors = 0
    $i = 0
    foreach ($it in $list) {
        if (Test-JobCancel) { Write-Log 'Остановлено пользователем' 'warn'; break }
        $i++
        Set-JobProgress ($i / [Math]::Max(1, $list.Count)) $it.Name
        try {
            if ($it.Action) {
                foreach ($l in (Invoke-CleanAction -Name $it.Action)) { Write-Log ('   ' + $l) }
                continue
            }
            if ($it.Special -eq 'recyclebin') {
                Clear-RecycleBin -Force -ErrorAction SilentlyContinue
                Write-Log '   Корзина очищена'
                continue
            }
            $before = (Get-CleanRemovedReport).Bytes
            $res = @(Resolve-CleanPaths -Paths $it.Paths -ChildSubdir $it.ChildSubdir)
            if ($res.Count -eq 0) { continue }
            $errors += [int](Clear-CleanPaths -Resolved $res -MinAgeDays $it.MinAgeDays)
            $got = (Get-CleanRemovedReport).Bytes - $before
            if ($got -gt 0) { Write-Log ('   ' + $it.Name + ': ' + (Format-Size $got)) }
        } catch { $errors++; Write-Log ('   ' + $it.Name + ': ' + $_.Exception.Message) 'warn' }
    }
    $rep = Get-CleanRemovedReport
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    try {
        $file = Join-Path $ReportFolder ('clean-' + $stamp + '.log')
        $lines = @('PotatoPC: очистка ' + (Get-Date), ('Удалено файлов: ' + $rep.Count + ', объём: ' + (Format-Size $rep.Bytes)), '', 'Первые 200 путей:') + @($rep.Items)
        $skipped = @(Get-CleanSkippedReport)
        if ($skipped.Count) { $lines += @('', 'Пропущено (защита или занято другой программой):') + @($skipped | Select-Object -First 300) }
        [System.IO.File]::WriteAllLines($file, [string[]]$lines, [System.Text.Encoding]::UTF8)
        Write-Log ('Список удалённого: ' + $file)
    } catch {}
    Write-Log ('Освобождено: ' + (Format-Size $rep.Bytes) + ' (' + $rep.Count + ' файлов)' + $(if ($errors -gt 0) { '; часть файлов занята программами - закройте их и повторите' } else { '' })) 'ok'
    Add-History -Kind 'clean' -Name ('Очистка: освобождено ' + (Format-Size $rep.Bytes)) -Detail (($list | ForEach-Object { $_.Name }) -join ', ')
    return @{ Bytes = $rep.Bytes; Count = $rep.Count; Errors = $errors }
}

function Build-Page_clean {
    $ui = @{ Rows = @{}; Items = @(); Mode = 'junk' }
    $script:CleanUi = $ui
    $scan = New-Button -Text 'Сканировать' -Icon 'search' -OnClick { Start-CleanScan }
    $ui.ScanBtn = $scan
    $ab = New-ActionBar
    $ui.Bar = $ab
    $ui.CleanBtn = New-Button -Text 'Очистить' -Icon 'trash' -Kind Primary -OnClick { Start-CleanRun }
    $ui.CleanBtn.IsEnabled = $false
    [void]$ab.Right.Children.Add($ui.CleanBtn)
    # Кнопки режима «Что занимает место» живут в той же нижней панели.
    $ui.SpGo = New-Button -Text '' -Kind Secondary -OnClick { Invoke-SpaceGo }
    $ui.SpCopy = New-Button -Text 'Копировать путь' -Icon 'copy' -Kind Secondary -OnClick {
        $n = $script:CleanUi.SpSel
        if ($n) { try { [System.Windows.Clipboard]::SetText([string]$n.Path); Write-Log ('Путь скопирован: ' + $n.Path) 'ok' } catch {} }
    }
    $ui.SpOpen = New-Button -Text 'Открыть в Проводнике' -Icon 'folder' -Kind Primary -OnClick { Open-SpaceSelected }
    foreach ($b in @($ui.SpGo, $ui.SpCopy, $ui.SpOpen)) { $b.Visibility = 'Collapsed'; [void]$ab.Right.Children.Add($b) }
    $L = New-PageLayout -Title 'Очистка' -Subtitle 'Временные файлы, кэши и мусор программ' -HeaderRight @($scan) -ActionBar $ab.Root
    $ui.Subtitle = $L.Subtitle

    # Переключатель: мусор / что занимает место
    $modes = New-Object System.Windows.Controls.WrapPanel
    $modes.Margin = New-Thickness 0, 0, 0, 8
    $ui.ModeBtns = @{}
    foreach ($m in @(@('junk', 'Мусор'), @('space', 'Что занимает место'))) {
        $b = New-Button -Text $m[1] -Kind Chip -Tag $m[0] -OnClick { Set-CleanMode -Mode ([string]$this.Tag) }
        $ui.ModeBtns[$m[0]] = $b
        [void]$modes.Children.Add($b)
    }
    Set-ChipActive -Button $ui.ModeBtns['junk'] -Active $true
    [void]$L.Body.Children.Add($modes)
    $ui.JunkView = New-Stack
    $ui.SpaceView = New-SpaceView
    $ui.SpaceView.Visibility = 'Collapsed'
    [void]$L.Body.Children.Add($ui.JunkView)
    [void]$L.Body.Children.Add($ui.SpaceView)
    $L = @{ Root = $L.Root; Body = $ui.JunkView }

    $sum = New-Stack
    $top = New-Object System.Windows.Controls.DockPanel
    $ui.After = New-Text -Text '' -Size 13 -Color 'Muted'
    $ui.After.VerticalAlignment = 'Bottom'
    [System.Windows.Controls.DockPanel]::SetDock($ui.After, 'Right')
    [void]$top.Children.Add($ui.After)
    $ts = New-Stack
    [void]$ts.Children.Add((New-Text -Text 'Можно освободить' -Size 13 -Color 'Muted'))
    $ui.Total = New-Text -Text '…' -Size 38 -Weight 'Bold' -Color 'Accent'
    [void]$ts.Children.Add($ui.Total)
    [void]$top.Children.Add($ts)
    [void]$sum.Children.Add($top)
    $ui.BarGrid = New-Object System.Windows.Controls.Grid
    $ui.BarGrid.Height = 10; $ui.BarGrid.Margin = New-Thickness 0, 14, 0, 0
    [void]$sum.Children.Add($ui.BarGrid)
    $ui.Legend = New-Object System.Windows.Controls.WrapPanel
    $ui.Legend.Margin = New-Thickness 0, 10, 0, 0
    [void]$sum.Children.Add($ui.Legend)
    [void]$L.Body.Children.Add((New-Card -Child $sum -Margin (0, 0, 0, 16)))

    $ui.Groups = New-Stack
    [void]$ui.Groups.Children.Add((New-Placeholder 'Нажмите «Сканировать».'))
    [void]$L.Body.Children.Add($ui.Groups)
    [void]$L.Body.Children.Add((New-Hint -Text 'Файлы удаляются навсегда, минуя корзину. Папки пользователя (Документы, Рабочий стол, Загрузки) и сам PotatoPC защищены. Список удалённого сохраняется в отчёт.' -Kind 'bad'))
    $script:CleanUi = $ui
    return $L.Root
}

function Show-Page_clean {
    param($Arg)
    if ($Arg -eq 'space') { Set-CleanMode -Mode 'space'; return }
    if ($script:CleanUi.Mode -eq 'junk' -and -not $script:CleanUi.Scanned) { Start-CleanScan }
}

function Set-CleanMode {
    param([string]$Mode)
    $ui = $script:CleanUi
    $ui.Mode = $Mode
    foreach ($k in $ui.ModeBtns.Keys) { Set-ChipActive -Button $ui.ModeBtns[$k] -Active ($k -eq $Mode) }
    $junk = ($Mode -eq 'junk')
    $ui.JunkView.Visibility = if ($junk) { 'Visible' } else { 'Collapsed' }
    $ui.SpaceView.Visibility = if ($junk) { 'Collapsed' } else { 'Visible' }
    $ui.ScanBtn.Visibility = if ($junk) { 'Visible' } else { 'Collapsed' }
    $ui.CleanBtn.Visibility = if ($junk) { 'Visible' } else { 'Collapsed' }
    if ($junk) {
        $ui.Subtitle.Text = 'Временные файлы, кэши и мусор программ'
        foreach ($b in @($ui.SpGo, $ui.SpCopy, $ui.SpOpen)) { $b.Visibility = 'Collapsed' }
        Update-CleanSelection
        if (-not $ui.Scanned) { Start-CleanScan }
    } else {
        $ui.Subtitle.Text = 'Какие папки и файлы занимают диск - деревом, по убыванию размера'
        Update-SpaceBar
        if (-not $ui.SpRoot -and -not $ui.SpBusy) { Start-SpaceScan }
    }
}

function Start-CleanScan {
    $ui = $script:CleanUi
    if ($ui.Busy) { return }
    $ui.Busy = $true
    $ui.CleanBtn.IsEnabled = $false
    $ui.Total.Text = '…'
    $ui.Subtitle.Text = 'Сканирую…'
    Start-BgTask -Name 'Сканирование мусора' -Script {
        $items = Get-CleanCatalog
        $items = Measure-CleanItems -Items $items
        $free = 0.0
        try { $free = [double](Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $env:SystemDrive + "'") -ErrorAction Stop).FreeSpace } catch {}
        return @{ Items = $items; Free = $free }
    } -OnDone {
        param($r, $err)
        $script:CleanUi.Busy = $false
        if (-not $r) { Write-Log ('Сканирование не удалось: ' + $err) 'err'; return }
        $script:CleanUi.Scanned = $true
        $script:CleanUi.Free = $r.Free
        Set-CleanItems -Items $r.Items
    } | Out-Null
}

function Set-CleanItems {
    param($Items)
    $ui = $script:CleanUi
    $ui.Items = @($Items)
    $ui.Rows = @{}
    $ui.Groups.Children.Clear()
    $ui.Subtitle.Text = 'Сканирование завершено в ' + (Get-Date).ToString('HH:mm')
    $browsersOpen = @(Get-Process -Name chrome, msedge, firefox, opera, browser, brave -ErrorAction SilentlyContinue).Count -gt 0
    if ($browsersOpen) {
        [void]$ui.Groups.Children.Add((New-Hint -Text 'Открыт браузер - часть его кэша занята и не удалится. Закройте браузер перед очисткой, чтобы освободить больше.' -Kind 'warn'))
    }
    foreach ($grp in @($ui.Items | Group-Object Group)) {
        $sel = New-Button -Text 'Выбрать всё' -Kind Ghost -Tag $grp.Name -OnClick {
            $g = [string]$this.Tag
            $all = @($script:CleanUi.Rows.Values | Where-Object { $_.Item.Group -eq $g -and $_.Check.IsEnabled })
            $state = -not (@($all | Where-Object { -not $_.Check.IsChecked }).Count -eq 0)
            foreach ($r in $all) { $r.Check.IsChecked = $state }
        }
        $gsum = 0L; foreach ($x in $grp.Group) { if ($x.Bytes -gt 0) { $gsum += $x.Bytes } }
        $sec = New-Section -Title ($grp.Name + $(if ($gsum -gt 0) { '  ·  ' + (Format-Size $gsum) } else { '' })) -Right @($sel)
        foreach ($it in @($grp.Group | Sort-Object { - $_.Bytes })) {
            $has = ($it.Bytes -gt 0) -or [bool]$it.Action
            $chk = New-CheckBox -Checked ($has -and ($it.Safe -or ($it.Bytes -gt 50MB -and -not $it.Confirm))) -Tag $it.Id -OnChange { Update-CleanSelection }
            $chk.IsEnabled = $has
            $size = if ($it.Action) { New-Text -Text 'действие' -Size 12 -Color 'Muted' } else { New-Text -Text $(if ($it.Bytes -gt 0) { Format-Size $it.Bytes } else { 'пусто' }) -Size 14 -Weight 'Bold' -Color $(if ($it.Bytes -gt 0) { 'Text' } else { 'Muted' }) }
            $size.Width = 80; $size.TextAlignment = 'Right'
            $badge = if ($it.Confirm) { New-Badge 'Осторожно' 'warn' } else { $null }
            $row = New-Row -Left $chk -Main (New-TitleBlock -Title $it.Name -Sub $it.Desc) -Right @($badge, $size)
            if (-not $has) { $row.Opacity = 0.55 }
            [void]$sec.Body.Children.Add($row)
            $ui.Rows[$it.Id] = @{ Check = $chk; Item = $it }
        }
        [void]$ui.Groups.Children.Add($sec.Root)
    }
    Update-CleanSelection
}

function Update-CleanSelection {
    $ui = $script:CleanUi
    $sel = @($ui.Rows.Values | Where-Object { $_.Check.IsChecked })
    $bytes = 0L; foreach ($r in $sel) { if ($r.Item.Bytes -gt 0) { $bytes += $r.Item.Bytes } }
    $ui.Total.Text = Format-Size $bytes
    if ($bytes -le 0) { $ui.Total.Text = '0' }
    if ($ui.Free) { $ui.After.Text = 'После очистки на ' + $env:SystemDrive + ' будет ' + (Format-Size ($ui.Free + $bytes)) + ' свободно' }
    if ($ui.Mode -eq 'junk') {
        $ui.Bar.Text.Inlines.Clear()
        $ui.Bar.Text.Inlines.Add((New-Object System.Windows.Documents.Bold (New-Object System.Windows.Documents.Run ([string]$sel.Count))))
        $ui.Bar.Text.Inlines.Add((New-Object System.Windows.Documents.Run (' выбрано · ' + (Format-Size $bytes))))
    }
    $ui.CleanBtn.IsEnabled = ($sel.Count -gt 0)
    # Полоса по группам
    $ui.BarGrid.Children.Clear(); $ui.BarGrid.ColumnDefinitions.Clear(); $ui.Legend.Children.Clear()
    $byGroup = [ordered]@{}
    foreach ($r in $sel) { if ($r.Item.Bytes -gt 0) { $byGroup[$r.Item.Group] = [long]$byGroup[$r.Item.Group] + $r.Item.Bytes; $byGroup[$r.Item.Group + '#i'] = $r.Item.GroupIndex } }
    $col = 0
    foreach ($k in @($byGroup.Keys | Where-Object { $_ -notlike '*#i' })) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = New-Object System.Windows.GridLength ([double]$byGroup[$k]), 'Star'
        [void]$ui.BarGrid.ColumnDefinitions.Add($cd)
        $color = $script:CleanGroupColors[[int]$byGroup[$k + '#i'] % $script:CleanGroupColors.Count]
        $seg = New-Object System.Windows.Controls.Border
        $seg.Background = Get-Brush $color; $seg.Margin = New-Thickness 0, 0, 2, 0
        $seg.CornerRadius = New-Object System.Windows.CornerRadius 3
        [System.Windows.Controls.Grid]::SetColumn($seg, $col); $col++
        [void]$ui.BarGrid.Children.Add($seg)
        $lg = New-Stack -Orientation Horizontal -Margin (0, 0, 18, 0)
        $dot = New-Object System.Windows.Shapes.Ellipse; $dot.Width = 8; $dot.Height = 8; $dot.Fill = Get-Brush $color
        [void]$lg.Children.Add($dot)
        [void]$lg.Children.Add((New-Text -Text ($k + ' ' + (Format-Size $byGroup[$k])) -Size 12 -Color 'Muted' -Margin (6, 0, 0, 0)))
        [void]$ui.Legend.Children.Add($lg)
    }
}

function Start-CleanRun {
    $ui = $script:CleanUi
    $sel = @($ui.Rows.Values | Where-Object { $_.Check.IsChecked } | ForEach-Object { $_.Item })
    if ($sel.Count -eq 0) { return }
    $risky = @($sel | Where-Object { $_.Confirm })
    $msg = 'Удалить навсегда (' + $sel.Count + ' пунктов)?'
    if ($risky.Count) { $msg += "`n`nВнимание, эти кэши разработчика скачаются заново при следующей сборке:`n  • " + (($risky | ForEach-Object { $_.Name }) -join "`n  • ") }
    if (-not (Show-Confirm -Message $msg -Title 'Очистка' -Warning)) { return }
    $ui.CleanBtn.IsEnabled = $false
    Start-BgTask -Name 'Очистка' -Vars @{ Sel = $sel } -Script { Invoke-CleanItems -Items $Sel } -OnDone {
        param($r)
        if ($r) { Show-Info -Message ('Освобождено: ' + (Format-Size $r.Bytes) + '.') -Title 'Очистка' }
        $script:CleanUi.Scanned = $false
        Start-CleanScan
    } | Out-Null
}

# ---------- Что занимает место (дерево папок, как WinDirStat) ----------

$script:SpaceMaxKids = 150

function Initialize-PotatoDisk {
    if ('PotatoDisk' -as [type]) { return $true }
    try { Add-Type -TypeDefinition ([System.IO.File]::ReadAllText((Join-Path $AssetsFolder 'PotatoDisk.cs'), [System.Text.Encoding]::UTF8)) -ErrorAction Stop; return $true }
    catch { Write-Log ('Модуль обхода диска не загрузился: ' + $_.Exception.Message) 'err'; return $false }
}

function Get-SpaceDrives {
    $out = @()
    foreach ($d in @([System.IO.DriveInfo]::GetDrives())) {
        try {
            if ($d.DriveType -ne 'Fixed' -or -not $d.IsReady) { continue }
            $label = $d.Name.TrimEnd('\')
            if ($d.VolumeLabel) { $label += ' ' + $d.VolumeLabel }
            $out += @{ Root = $d.Name; Label = $label; Total = [double]$d.TotalSize; Free = [double]$d.TotalFreeSpace }
        } catch {}
    }
    return $out
}

function Get-SpaceHint {
    # Подсказка к папке или файлу: что это и где это безопасно почистить.
    # Kind: ok (можно чистить) | warn (осторожно) | mute (справка). Go: куда ведёт кнопка в нижней панели.
    param($Node)
    $p = [string]$Node.Path
    $n = [string]$Node.Name
    $win = $env:WINDIR.TrimEnd('\')
    if ($Node.IsRest) { return $null }
    if ($Node.Denied) { return @{ Text = 'нет доступа'; Kind = 'mute'; Go = '' } }
    if ($p -match '(?i)\\AppData\\Local\\Temp$' -or $p -ieq ($win + '\Temp')) { return @{ Text = 'временные файлы - можно чистить'; Kind = 'ok'; Go = 'junk' } }
    if ($p -match '(?i)\\(Cache|Code Cache|GPUCache)$' -and $p -match '(?i)\\User Data\\|\\Mozilla\\|\\Opera') { return @{ Text = 'кэш браузера - можно чистить'; Kind = 'ok'; Go = 'junk' } }
    if ($p -match '(?i)\\(NVIDIA\\DXCache|NVIDIA\\GLCache|D3DSCache|AMD\\DxCache)$') { return @{ Text = 'кэш шейдеров - можно чистить'; Kind = 'ok'; Go = 'junk' } }
    if ($p -ieq ($win + '\SoftwareDistribution\Download')) { return @{ Text = 'скачанные обновления - можно чистить'; Kind = 'ok'; Go = 'junk' } }
    if ($p -match '(?i)^[A-Z]:\\\$Recycle\.Bin$') { return @{ Text = 'корзина - можно очистить'; Kind = 'ok'; Go = 'junk' } }
    if ($p -match '(?i)\\CrashDumps$' -or $p -ieq ($win + '\MEMORY.DMP') -or $p -ieq ($win + '\Minidump')) { return @{ Text = 'отчёты о сбоях - можно чистить'; Kind = 'ok'; Go = 'junk' } }
    if ($p -ieq ($win + '\WinSxS')) { return @{ Text = 'компоненты Windows - сжимаются в «Твиках»'; Kind = 'warn'; Go = 'tweaks' } }
    if (-not $Node.IsDir -and $n -ieq 'hiberfil.sys') { return @{ Text = 'гибернация - можно отключить в «Твиках»'; Kind = 'warn'; Go = 'tweaks' } }
    if (-not $Node.IsDir -and ($n -ieq 'pagefile.sys' -or $n -ieq 'swapfile.sys')) { return @{ Text = 'файл подкачки Windows'; Kind = 'mute'; Go = '' } }
    if ($p -match '(?i)\\steamapps\\common$') { return @{ Text = 'игры Steam - удалять через Steam'; Kind = 'warn'; Go = '' } }
    if ($p -match '(?i)^[A-Z]:\\Program Files( \(x86\))?$') { return @{ Text = 'программы - удалять через «Удаление программ»'; Kind = 'warn'; Go = 'uninstall' } }
    if ($p -ieq $win -or $p -match '(?i)^[A-Z]:\\(System Volume Information|Recovery)$') { return @{ Text = 'система - не трогать'; Kind = 'mute'; Go = '' } }
    if ($p -match '(?i)^[A-Z]:\\Users\\[^\\]+\\Downloads$') { return @{ Text = 'загрузки - проверьте старые установщики'; Kind = 'warn'; Go = '' } }
    if ($p -match '(?i)\\Telegram Desktop\\tdata\\user_data$') { return @{ Text = 'кэш Telegram - чистится в настройках Telegram'; Kind = 'warn'; Go = '' } }
    if (-not $Node.IsDir -and $n -match '(?i)\.(iso|msi|exe|zip|rar|7z)$' -and $p -match '(?i)\\Downloads\\') { return @{ Text = 'установщик или архив'; Kind = 'warn'; Go = '' } }
    return $null
}

function New-SpaceGrid {
    $g = New-Object System.Windows.Controls.Grid
    foreach ($w in @(0, 150, 46, 90, 90)) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        if ($w -eq 0) { $cd.Width = New-Object System.Windows.GridLength 1, 'Star' } else { $cd.Width = New-Object System.Windows.GridLength $w }
        [void]$g.ColumnDefinitions.Add($cd)
    }
    return $g
}

function New-SpaceView {
    $ui = $script:CleanUi
    $sp = New-Stack
    # Диски + кнопка
    $top = New-Object System.Windows.Controls.DockPanel
    $top.Margin = New-Thickness 0, 0, 0, 6
    $btn = New-Button -Text 'Сканировать' -Icon 'search' -Kind Primary -OnClick {
        if ($script:CleanUi.SpBusy) { if ('PotatoDisk' -as [type]) { [PotatoDisk]::Cancel = $true } } else { Start-SpaceScan }
    }
    $btn.VerticalAlignment = 'Top'
    [System.Windows.Controls.DockPanel]::SetDock($btn, 'Right')
    [void]$top.Children.Add($btn)
    $drv = New-Object System.Windows.Controls.WrapPanel
    [void]$top.Children.Add($drv)
    [void]$sp.Children.Add($top)
    $status = New-Text -Text '' -Size 12 -Color 'Muted' -Wrap -Margin (2, 0, 0, 12)
    [void]$sp.Children.Add($status)
    # Дерево
    $sec = New-Section -Title 'Папки и файлы'
    $hdr = New-SpaceGrid
    $hdr.Margin = New-Thickness 16, 0, 16, 6
    $cols = @('Имя', 'Доля от папки выше', '', 'Размер', 'Файлов')
    for ($i = 0; $i -lt $cols.Count; $i++) {
        $t = New-Text -Text $cols[$i] -Size 12 -Color 'Muted'
        if ($i -ge 3) { $t.TextAlignment = 'Right' }
        [System.Windows.Controls.Grid]::SetColumn($t, $i)
        [void]$hdr.Children.Add($t)
    }
    [void]$sec.Body.Children.Add($hdr)
    $tree = New-Stack
    $tree.Margin = New-Thickness 0, 0, 0, 8
    [void]$tree.Children.Add((New-Placeholder 'Выберите диск и нажмите «Сканировать».'))
    [void]$sec.Body.Children.Add($tree)
    [void]$sp.Children.Add($sec.Root)
    [void]$sp.Children.Add((New-Hint -Text 'Правая кнопка мыши по строке - меню: открыть, свойства, командная строка, пересканировать, удалить в корзину или навсегда. Папки Windows, корни дисков и профилей удалить нельзя. Цвет подсказки: зелёный - можно чистить, жёлтый - осторожно, серый - не трогать.' -Kind 'info'))
    $ui.SpScanBtn = $btn
    $ui.SpDrives = $drv
    $ui.SpStatus = $status
    $ui.SpTree = $tree
    if (-not $ui.SpDrive) { $ui.SpDrive = $env:SystemDrive + '\' }
    Update-SpaceDrives
    return $sp
}

function Update-SpaceDrives {
    $ui = $script:CleanUi
    $ui.SpDrives.Children.Clear()
    foreach ($d in @(Get-SpaceDrives)) {
        $b = New-Button -Kind Chip -Tag $d.Root -OnClick {
            if ($script:CleanUi.SpBusy) { return }
            $script:CleanUi.SpDrive = [string]$this.Tag
            Update-SpaceDrives
            Start-SpaceScan
        }
        $b.Padding = New-Thickness 14, 8, 14, 8
        $b.HorizontalContentAlignment = 'Stretch'
        $st = New-Stack
        $st.Width = 230
        $row = New-Object System.Windows.Controls.DockPanel
        $free = New-Text -Text ('свободно ' + (Format-Size $d.Free) + ' из ' + (Format-Size $d.Total)) -Size 11 -Color 'Muted'
        [System.Windows.Controls.DockPanel]::SetDock($free, 'Right')
        [void]$row.Children.Add($free)
        [void]$row.Children.Add((New-Text -Text $d.Label -Size 13 -Weight 'SemiBold' -Margin (0, 0, 8, 0)))
        [void]$st.Children.Add($row)
        $m = New-Meter -Height 6
        $m.Margin = New-Thickness 0, 7, 0, 0
        $used = if ($d.Total -gt 0) { 1 - $d.Free / $d.Total } else { 0 }
        Set-Meter -Meter $m -Value $used -Color $(if ($used -ge 0.9) { 'Bad' } elseif ($used -ge 0.75) { 'Warn' } else { 'Accent' })
        [void]$st.Children.Add($m)
        $b.Content = $st
        if ($d.Root -ieq $ui.SpDrive) { $b.BorderBrush = Get-Brush 'Accent'; $b.BorderThickness = New-Thickness 1.5 }
        [void]$ui.SpDrives.Children.Add($b)
    }
}

function Start-SpaceScan {
    $ui = $script:CleanUi
    if ($ui.SpBusy) { return }
    if (-not (Initialize-PotatoDisk)) { return }
    $ui.SpBusy = $true
    $ui.SpRoot = $null
    $ui.SpSel = $null
    $ui.SpSelRow = $null
    $ui.SpSelHint = $null
    Update-SpaceBar
    Set-ButtonText -Button $ui.SpScanBtn -Text 'Остановить'
    $ui.SpTree.Children.Clear()
    [void]$ui.SpTree.Children.Add((New-Placeholder ('Сканирую ' + $ui.SpDrive + ' - на большом диске это займёт от 20 секунд до пары минут.')))
    $ui.SpStatus.Text = ''
    [PotatoDisk]::Cancel = $false
    $ui.SpStart = Get-Date
    $ui.SpTimer = New-Object System.Windows.Threading.DispatcherTimer
    $ui.SpTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $ui.SpTimer.Add_Tick({
        $ui = $script:CleanUi
        $cur = [string][PotatoDisk]::Current
        if ($cur.Length -gt 90) { $cur = $cur.Substring(0, 40) + '…' + $cur.Substring($cur.Length - 45) }
        $ui.SpStatus.Text = 'Просмотрено ' + ('{0:N0}' -f [PotatoDisk]::FilesSeen) + ' файлов · ' + (Format-Size ([double][PotatoDisk]::BytesSeen)) + '  ·  ' + $cur
    })
    $ui.SpTimer.Start()
    Write-Log ('Что занимает место: сканирую ' + $ui.SpDrive) 'head'
    Start-BgTask -Name 'Что занимает место' -Vars @{ Root = $ui.SpDrive } -Script {
        $n = [PotatoDisk]::Scan($Root)
        return @{ Node = $n; Cancelled = [bool][PotatoDisk]::Cancel }
    } -OnDone {
        param($r, $err)
        $ui = $script:CleanUi
        try { $ui.SpTimer.Stop() } catch {}
        $ui.SpBusy = $false
        Set-ButtonText -Button $ui.SpScanBtn -Text 'Сканировать'
        $ui.SpTree.Children.Clear()
        Update-SpaceDrives
        if (-not $r -or -not $r.Node) {
            [void]$ui.SpTree.Children.Add((New-Placeholder 'Сканирование не удалось - подробности в журнале.'))
            $ui.SpStatus.Text = ''
            if ($err) { Write-Log ('Сканирование диска: ' + $err) 'err' }
            Update-SpaceBar
            return
        }
        if ($r.Cancelled) {
            [void]$ui.SpTree.Children.Add((New-Placeholder 'Остановлено. Нажмите «Сканировать», чтобы начать заново.'))
            $ui.SpStatus.Text = ''
            Update-SpaceBar
            return
        }
        $ui.SpRoot = $r.Node
        $sec = [Math]::Round(((Get-Date) - $ui.SpStart).TotalSeconds)
        $txt = ('{0:N0}' -f $r.Node.Files) + ' файлов, ' + (Format-Size ([double]$r.Node.Size)) + ', за ' + (Format-Duration $sec)
        try {
            $d = New-Object System.IO.DriveInfo ($ui.SpDrive)
            $gap = ([double]$d.TotalSize - [double]$d.TotalFreeSpace) - [double]$r.Node.Size
            if ($gap -gt 1GB) { $txt += '. Ещё ' + (Format-Size $gap) + ' занято служебными данными Windows (теневые копии, метаданные диска) - в дереве их не видно.' }
        } catch {}
        $ui.SpStatus.Text = $txt
        Write-Log ('Что занимает место: ' + $txt) 'ok'
        $row = New-SpaceRow -Node $r.Node -Depth 0 -ParentSize 0
        [void]$ui.SpTree.Children.Add($row)
        Switch-SpaceRow -Row $row
        Select-SpaceRow -Row $row
    } | Out-Null
}

function New-SpaceRow {
    param($Node, [int]$Depth, [double]$ParentSize, $ParentRow = $null)
    $hasKids = $Node.IsDir -and @($Node.Kids).Count -gt 0
    $b = New-Object System.Windows.Controls.Border
    $b.Padding = New-Thickness 16, 0, 16, 0
    $b.MinHeight = 32
    $b.Background = [System.Windows.Media.Brushes]::Transparent
    $b.Cursor = 'Hand'
    $g = New-SpaceGrid
    # Имя: отступ, стрелка, значок, название, подсказка
    $name = New-Stack -Orientation Horizontal
    $name.Margin = New-Thickness ($Depth * 18), 0, 8, 0
    $name.ClipToBounds = $true
    $chev = New-Icon -Name 'chevR' -Size 14 -Color 'Muted' -Stroke 2.2
    $chev.Margin = New-Thickness 0, 0, 6, 0
    if (-not $hasKids) { $chev.Visibility = 'Hidden' }
    [void]$name.Children.Add($chev)
    $isFolder = $Node.IsDir -and -not $Node.IsRest
    [void]$name.Children.Add((New-Icon -Name $(if ($isFolder) { 'folder' } else { 'file' }) -Size 16 -Color $(if ($isFolder) { 'Accent' } else { 'Muted' })))
    [void]$name.Children.Add((New-Text -Text ([string]$Node.Name) -Size 13 -Weight $(if ($Depth -eq 0) { 'Bold' } else { 'Normal' }) -Color $(if ($Node.IsRest) { 'Muted' } else { 'Text' }) -Margin (8, 0, 0, 0)))
    $hint = Get-SpaceHint -Node $Node
    if ($hint) {
        [void]$name.Children.Add((New-Text -Text $hint.Text -Size 12 -Color $(switch ($hint.Kind) { 'ok' { 'Ok' } 'warn' { 'Warn' } default { 'Muted' } }) -Margin (10, 0, 0, 0)))
    }
    [void]$g.Children.Add($name)
    # Доля от папки выше, размер, число файлов
    $share = if ($ParentSize -gt 0) { [double]$Node.Size / $ParentSize } else { 1.0 }
    $m = New-Meter -Height 8
    $m.VerticalAlignment = 'Center'
    Set-Meter -Meter $m -Value $share -Color $(if ($Depth -eq 0) { 'Accent' } else { '#B98A35' })
    [System.Windows.Controls.Grid]::SetColumn($m, 1); [void]$g.Children.Add($m)
    $pt = New-Text -Text ([string][Math]::Round($share * 100) + '%') -Size 12 -Color 'Muted'
    $pt.TextAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetColumn($pt, 2); [void]$g.Children.Add($pt)
    $st = New-Text -Text (Format-Size ([double]$Node.Size)) -Size 13 -Weight 'SemiBold'
    $st.TextAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetColumn($st, 3); [void]$g.Children.Add($st)
    $ft = New-Text -Text $(if ($isFolder -or $Node.IsRest) { '{0:N0}' -f [long]$Node.Files } else { '—' }) -Size 12 -Color 'Muted'
    $ft.TextAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetColumn($ft, 4); [void]$g.Children.Add($ft)
    $b.Child = $g
    $b.ToolTip = [string]$Node.Path
    $b.Tag = @{ Node = $Node; Depth = $Depth; Open = $false; HasKids = $hasKids; Chev = $chev; Hint = $hint; ParentRow = $ParentRow; Meter = $m; Pct = $pt; SizeT = $st; FilesT = $ft }
    $b.Add_MouseEnter({ if ($this -ne $script:CleanUi.SpSelRow) { $this.Background = Get-Brush 'Hover' } })
    $b.Add_MouseLeave({ if ($this -ne $script:CleanUi.SpSelRow) { $this.Background = [System.Windows.Media.Brushes]::Transparent } })
    $b.Add_MouseLeftButtonUp({
        Select-SpaceRow -Row $this
        if ($this.Tag.HasKids) { Switch-SpaceRow -Row $this }
    })
    $b.Add_MouseRightButtonUp({
        Select-SpaceRow -Row $this
        Show-SpaceMenu -Row $this
        $_.Handled = $true
    })
    return $b
}

function Switch-SpaceRow {
    # Раскрыть или свернуть папку: дочерние строки вставляются сразу под ней.
    param($Row)
    $ui = $script:CleanUi
    $t = $Row.Tag
    $list = $ui.SpTree.Children
    $idx = $list.IndexOf($Row)
    if ($idx -lt 0) { return }
    if ($t.Open) {
        while ($idx + 1 -lt $list.Count -and $list[$idx + 1].Tag.Depth -gt $t.Depth) { $list.RemoveAt($idx + 1) }
        $t.Open = $false
        $t.Chev.Child.Children[0].Data = [System.Windows.Media.Geometry]::Parse($script:IconPaths['chevR'])
        return
    }
    $kids = @($t.Node.Kids)
    $pos = $idx + 1
    $shown = 0
    foreach ($k in $kids) {
        if ($shown -ge $script:SpaceMaxKids) { break }
        $list.Insert($pos, (New-SpaceRow -Node $k -Depth ($t.Depth + 1) -ParentSize ([double]$t.Node.Size) -ParentRow $Row))
        $pos++; $shown++
    }
    if ($kids.Count -gt $shown) {
        $restSize = 0.0; for ($i = $shown; $i -lt $kids.Count; $i++) { $restSize += [double]$kids[$i].Size }
        $mb = New-Object System.Windows.Controls.Border
        $mb.MinHeight = 28
        $mb.Padding = New-Thickness (16 + ($t.Depth + 1) * 18 + 20), 0, 16, 0
        $mb.Child = New-Text -Text ('… и ещё ' + ($kids.Count - $shown) + ' элементов, ' + (Format-Size $restSize) + ' - откройте папку в Проводнике') -Size 12 -Color 'Muted'
        $mb.Tag = @{ Depth = $t.Depth + 1 }
        $list.Insert($pos, $mb)
    }
    $t.Open = $true
    $t.Chev.Child.Children[0].Data = [System.Windows.Media.Geometry]::Parse($script:IconPaths['chevD'])
}

function Select-SpaceRow {
    param($Row)
    $ui = $script:CleanUi
    if ($ui.SpSelRow -and $ui.SpSelRow -ne $Row) { $ui.SpSelRow.Background = [System.Windows.Media.Brushes]::Transparent }
    $ui.SpSelRow = $Row
    $Row.Background = Get-Brush 'AccentDim'
    $ui.SpSel = $Row.Tag.Node
    $ui.SpSelHint = $Row.Tag.Hint
    Update-SpaceBar
}

function Update-SpaceBar {
    $ui = $script:CleanUi
    if ($ui.Mode -ne 'space') { return }
    $ui.Bar.Text.Inlines.Clear()
    $n = $ui.SpSel
    if (-not $n) {
        $ui.Bar.Text.Inlines.Add((New-Object System.Windows.Documents.Run $(if ($ui.SpBusy) { 'Сканирую…' } else { 'Нажмите на папку, чтобы раскрыть её' })))
        foreach ($b in @($ui.SpGo, $ui.SpCopy, $ui.SpOpen)) { $b.Visibility = 'Collapsed' }
        return
    }
    $ui.Bar.Text.Inlines.Add((New-Object System.Windows.Documents.Bold (New-Object System.Windows.Documents.Run (Format-Size ([double]$n.Size)))))
    $ui.Bar.Text.Inlines.Add((New-Object System.Windows.Documents.Run ('  ·  ' + [string]$n.Path)))
    $ui.Bar.Text.ToolTip = [string]$n.Path
    $ui.SpCopy.Visibility = 'Visible'
    $ui.SpOpen.Visibility = 'Visible'
    $go = if ($ui.SpSelHint) { [string]$ui.SpSelHint.Go } else { '' }
    $ui.SpGo.Tag = $go
    switch ($go) {
        'junk' { Set-ButtonText -Button $ui.SpGo -Text 'Почистить в «Мусоре»'; $ui.SpGo.Visibility = 'Visible' }
        'tweaks' { Set-ButtonText -Button $ui.SpGo -Text 'Открыть «Твики»'; $ui.SpGo.Visibility = 'Visible' }
        'uninstall' { Set-ButtonText -Button $ui.SpGo -Text 'Открыть «Удаление программ»'; $ui.SpGo.Visibility = 'Visible' }
        default { $ui.SpGo.Visibility = 'Collapsed' }
    }
}

function Invoke-SpaceGo {
    switch ([string]$script:CleanUi.SpGo.Tag) {
        'junk' { Set-CleanMode -Mode 'junk' }
        'tweaks' { Show-Page -Id 'tweaks' }
        'uninstall' { Show-Page -Id 'uninstall' }
    }
}

function Open-SpaceSelected {
    $n = $script:CleanUi.SpSel
    if (-not $n) { return }
    $p = [string]$n.Path
    try {
        if ($n.IsDir -or $n.IsRest) { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $p + '"') }
        else { Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"' + $p + '"') }
    } catch { Write-Log ('Не удалось открыть: ' + $p) 'warn' }
}

# --- Меню по правой кнопке (как в WinDirStat) ---

function Test-SpaceDeleteBlocked {
    # Причина, по которой путь нельзя удалить из дерева, или '' - можно.
    param($Node)
    if ($Node.IsRest) { return 'это сводная строка, а не файл' }
    $p = ([string]$Node.Path).TrimEnd('\')
    $n = [string]$Node.Name
    if ($p -match '^[A-Za-z]:$') { return 'это корень диска' }
    $win = $env:WINDIR.TrimEnd('\')
    if ($p -ieq $win -or $p.StartsWith($win + '\', [StringComparison]::OrdinalIgnoreCase)) { return 'это папка Windows' }
    if ($p -match '(?i)^[A-Z]:\\(\$Recycle\.Bin|System Volume Information|Recovery|Boot|EFI|Config\.Msi|Documents and Settings)(\\|$)') { return 'это служебная папка Windows' }
    if (-not $Node.IsDir -and $n -match '(?i)^(pagefile|hiberfil|swapfile)\.sys$|^(bootmgr|BOOTNXT|BOOTSECT\.BAK)$') { return 'это системный файл Windows (гибернацию отключают в «Твиках»)' }
    $exact = @()
    foreach ($x in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432, $env:ProgramData, $env:PUBLIC, (Split-Path $env:PUBLIC -Parent), $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA, (Split-Path $env:LOCALAPPDATA -Parent))) {
        if ($x) { $exact += $x.TrimEnd('\') }
    }
    foreach ($x in $exact) { if ($p -ieq $x) { return 'это системная папка, удалять можно только её содержимое' } }
    # Корни чужих профилей и их AppData, стандартные папки пользователя (Документы, Загрузки...)
    if ($p -match '(?i)^[A-Z]:\\Users\\[^\\]+(\\AppData(\\(Local|Roaming|LocalLow))?)?$') { return 'это папка профиля, удалять можно только её содержимое' }
    if ($p -match '(?i)^[A-Z]:\\Users\\[^\\]+\\(Desktop|Documents|Downloads|Pictures|Videos|Music|Favorites|Links|Contacts|Saved Games|Searches|OneDrive|3D Objects)$') { return 'это стандартная папка пользователя, удалять можно только её содержимое' }
    # Сам PotatoPC
    foreach ($x in @($AppRoot, $DataRoot)) {
        if ($x -and ($p -ieq $x.TrimEnd('\') -or $p.StartsWith($x.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or $x.StartsWith($p + '\', [StringComparison]::OrdinalIgnoreCase))) { return 'здесь лежит сам PotatoPC' }
    }
    return ''
}

function Show-SpaceMenu {
    param($Row)
    $n = $Row.Tag.Node
    $isFolder = $n.IsDir -and -not $n.IsRest
    $items = @()
    $items += @{ Text = $(if ($isFolder -or $n.IsRest) { 'Открыть папку' } else { 'Открыть файл' }); Tag = $n; OnClick = {
        $x = $this.Tag
        try { if ($x.IsDir -or $x.IsRest) { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $x.Path + '"') } else { Start-Process -FilePath $x.Path } } catch { Write-Log ('Не удалось открыть: ' + $x.Path + ' - ' + $_.Exception.Message) 'warn' }
    } }
    if (-not $n.IsRest) {
        $items += @{ Text = 'Показать в Проводнике'; Tag = $n; OnClick = { Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"' + $this.Tag.Path + '"') } }
    }
    $items += @{ Text = 'Копировать путь'; Tag = $n; OnClick = { try { [System.Windows.Clipboard]::SetText([string]$this.Tag.Path); Write-Log ('Путь скопирован: ' + $this.Tag.Path) 'ok' } catch {} } }
    if (-not $n.IsRest -and $Row.Tag.Depth -gt 0) {
        $items += @{ Text = 'Свойства'; Tag = $n; OnClick = { Show-SpaceProperties -Path ([string]$this.Tag.Path) } }
    }
    $items += @{ Text = 'Командная строка здесь'; Tag = $n; OnClick = {
        $x = $this.Tag
        $dir = if ($x.IsDir -or $x.IsRest) { [string]$x.Path } else { Split-Path ([string]$x.Path) -Parent }
        Start-Process -FilePath 'cmd.exe' -WorkingDirectory $dir
    } }
    if ($isFolder) {
        $items += @{ Text = 'Пересканировать папку'; Tag = $Row; OnClick = { Update-SpaceFolder -Row $this.Tag } }
    }
    if ($Row.Tag.Hint -and $Row.Tag.Hint.Go) {
        $go = [string]$Row.Tag.Hint.Go
        $items += @{ Text = $(switch ($go) { 'junk' { 'Почистить в «Мусоре»' } 'tweaks' { 'Открыть «Твики»' } default { 'Открыть «Удаление программ»' } }); Tag = $go; OnClick = {
            $script:CleanUi.SpGo.Tag = [string]$this.Tag; Invoke-SpaceGo
        } }
    }
    $items += @{ Separator = $true }
    $why = Test-SpaceDeleteBlocked -Node $n
    if ($why) {
        $items += @{ Text = 'Удалить нельзя: ' + $why; Disabled = $true }
    } else {
        $items += @{ Text = 'Удалить в корзину'; Tag = $Row; OnClick = { Remove-SpaceItem -Row $this.Tag } }
        $items += @{ Text = 'Удалить навсегда…'; Tag = $Row; Danger = $true; OnClick = { Remove-SpaceItem -Row $this.Tag -Permanent } }
    }
    Show-ActionMenu -Anchor $Row -Items $items -AtMouse
}

function Show-SpaceProperties {
    # Стандартное окно «Свойства» Проводника.
    param([string]$Path)
    try {
        $sh = New-Object -ComObject Shell.Application
        $dir = $sh.NameSpace((Split-Path $Path -Parent))
        $it = $dir.ParseName((Split-Path $Path -Leaf))
        $it.InvokeVerb('properties')
    } catch { Write-Log ('Не удалось открыть свойства: ' + $_.Exception.Message) 'warn' }
}

function Remove-SpaceItem {
    param($Row, [switch]$Permanent)
    $ui = $script:CleanUi
    if ($ui.SpBusy -or $ui.SpDeleting) { Show-Info 'Дождитесь окончания текущей операции.'; return }
    $n = $Row.Tag.Node
    $why = Test-SpaceDeleteBlocked -Node $n
    if ($why) { Show-Info ('Удалить нельзя: ' + $why + '.'); return }
    $what = if ($n.IsDir) { 'папку' } else { 'файл' }
    $size = Format-Size ([double]$n.Size)
    $extra = ''
    if ([string]$n.Path -match '(?i)^[A-Z]:\\Program Files') { $extra = "`n`nЭто папка программы. Программы правильнее удалять через «Удаление программ» - иначе останутся записи в реестре и ярлыки." }
    if ($n.IsDir) { $extra += "`n`nВнутри: " + ('{0:N0}' -f [long]$n.Files) + ' файлов.' }
    if ($Permanent) {
        $msg = 'Удалить ' + $what + ' НАВСЕГДА, минуя корзину?' + "`n`n" + $n.Path + "`n" + $size + $extra + "`n`nВосстановить потом будет нельзя."
    } else {
        $msg = 'Переместить ' + $what + ' в корзину?' + "`n`n" + $n.Path + "`n" + $size + $extra + "`n`nМесто освободится после очистки корзины. Если " + $what + ' не поместится в корзину, Windows спросит, удалить ли навсегда.'
    }
    if (-not (Show-Confirm -Message $msg -Title $(if ($Permanent) { 'Удалить навсегда' } else { 'Удалить в корзину' }) -Warning)) { return }
    if (-not (Initialize-PotatoDisk)) { return }
    $ui.SpDeleting = $true
    $ui.SpStatus.Text = 'Удаляю ' + $n.Path + ' …'
    Write-Log ($(if ($Permanent) { 'Удаляю навсегда: ' } else { 'В корзину: ' }) + $n.Path + ' (' + $size + ')') 'head'
    Start-BgTask -Name 'Удаление' -Context $Row -Vars @{ P = [string]$n.Path; Perm = [bool]$Permanent; Size = $size } -Script {
        $r = @{ Code = 0; Failed = 0 }
        if ($Perm) { [PotatoDisk]::DeleteTree($P); $r.Failed = [long][PotatoDisk]::DelFailed }
        else { $r.Code = [PotatoDisk]::Recycle($P) }
        $r.Exists = Test-Path -LiteralPath $P
        $verb = if ($Perm) { 'Удалено навсегда' } else { 'Удалено в корзину' }
        if (-not $r.Exists) {
            Write-Log ($verb + ': ' + $P) 'ok'
            Add-History -Kind 'clean' -Name ($verb + ': ' + $P + ' (' + $Size + ')')
        } elseif ($r.Code -eq -1) {
            Write-Log ('Удаление отменено: ' + $P) 'warn'
        } else {
            Write-Log ('Удалено не всё - часть файлов занята программами или защищена: ' + $P + $(if ($r.Failed) { ' (не удалось: ' + $r.Failed + ')' } else { '' })) 'warn'
            Add-History -Kind 'clean' -Name ($verb + ' частично: ' + $P) -Result 'error'
        }
        return $r
    } -OnDone {
        param($r, $err, $job)
        $ui = $script:CleanUi
        $ui.SpDeleting = $false
        $row = $job.Context
        $ui.SpStatus.Text = ''
        Update-SpaceDrives
        if ($r -and -not $r.Exists) { Remove-SpaceRow -Row $row }
        elseif ($r -and $r.Code -ne -1) { Update-SpaceFolder -Row $row }
    } | Out-Null
}

function Set-SpaceRowNumbers {
    # Перерисовать размер, число файлов и долю строки после изменения узла.
    param($Row)
    $t = $Row.Tag
    $n = $t.Node
    $t.SizeT.Text = Format-Size ([double]$n.Size)
    if ($n.IsDir -or $n.IsRest) { $t.FilesT.Text = '{0:N0}' -f [long]$n.Files }
    $ps = if ($t.ParentRow) { [double]$t.ParentRow.Tag.Node.Size } else { 0 }
    $share = if ($ps -gt 0) { [double]$n.Size / $ps } else { 1.0 }
    $t.Pct.Text = [string][Math]::Round($share * 100) + '%'
    Set-Meter -Meter $t.Meter -Value $share -Color $(if ($t.Depth -eq 0) { 'Accent' } else { '#B98A35' })
}

function Update-SpaceAncestors {
    # Вычесть изменение размера из всех папок выше и обновить их строки.
    param($Row, [double]$DeltaSize, [double]$DeltaFiles)
    $r = $Row.Tag.ParentRow
    while ($r) {
        $r.Tag.Node.Size = [long]([double]$r.Tag.Node.Size + $DeltaSize)
        $r.Tag.Node.Files = [long]([double]$r.Tag.Node.Files + $DeltaFiles)
        $r = $r.Tag.ParentRow
    }
    # Доли соседних строк тоже поменялись - перерисовать все видимые строки (их сотни, это быстро).
    foreach ($x in @($script:CleanUi.SpTree.Children)) { if ($x.Tag -and $x.Tag.Node) { Set-SpaceRowNumbers -Row $x } }
}

function Remove-SpaceRow {
    # Файл или папка удалены: убрать строку (и раскрытое под ней) и пересчитать папки выше.
    param($Row)
    $ui = $script:CleanUi
    $t = $Row.Tag
    $list = $ui.SpTree.Children
    $idx = $list.IndexOf($Row)
    if ($idx -ge 0) {
        while ($idx + 1 -lt $list.Count -and $list[$idx + 1].Tag.Depth -gt $t.Depth) { $list.RemoveAt($idx + 1) }
        $list.RemoveAt($idx)
    }
    if ($t.ParentRow) { [void]$t.ParentRow.Tag.Node.Kids.Remove($t.Node) }
    Update-SpaceAncestors -Row $Row -DeltaSize (-[double]$t.Node.Size) -DeltaFiles (-[double]$t.Node.Files)
    if ($ui.SpSelRow -eq $Row) {
        if ($t.ParentRow) { Select-SpaceRow -Row $t.ParentRow } else { $ui.SpSel = $null; $ui.SpSelRow = $null; Update-SpaceBar }
    }
}

function Update-SpaceFolder {
    # Пересканировать одну папку и подставить новый результат в дерево.
    param($Row)
    $ui = $script:CleanUi
    if ($ui.SpBusy) { return }
    if (-not (Initialize-PotatoDisk)) { return }
    $n = $Row.Tag.Node
    if (-not $n.IsDir) {
        # Файл: просто перечитать размер (или убрать, если его уже нет)
        if (-not (Test-Path -LiteralPath $n.Path)) { Remove-SpaceRow -Row $Row; return }
        $new = [double](Get-Item -LiteralPath $n.Path -Force).Length
        $d = $new - [double]$n.Size
        $n.Size = [long]$new
        Set-SpaceRowNumbers -Row $Row
        Update-SpaceAncestors -Row $Row -DeltaSize $d -DeltaFiles 0
        return
    }
    $ui.SpBusy = $true
    $ui.SpStatus.Text = 'Пересканирую ' + $n.Path + ' …'
    Start-BgTask -Name 'Пересканирование папки' -Silent -Context $Row -Vars @{ P = [string]$n.Path } -Script {
        if (-not (Test-Path -LiteralPath $P)) { return @{ Gone = $true } }
        return @{ Gone = $false; Node = [PotatoDisk]::Scan($P) }
    } -OnDone {
        param($r, $err, $job)
        $ui = $script:CleanUi
        $ui.SpBusy = $false
        $ui.SpStatus.Text = ''
        $row = $job.Context
        if (-not $r) { return }
        if ($r.Gone) { Remove-SpaceRow -Row $row; return }
        $t = $row.Tag
        $old = $t.Node
        $dS = [double]$r.Node.Size - [double]$old.Size
        $dF = [double]$r.Node.Files - [double]$old.Files
        $old.Kids = $r.Node.Kids; $old.Size = $r.Node.Size; $old.Files = $r.Node.Files; $old.Denied = $r.Node.Denied
        $wasOpen = $t.Open
        if ($wasOpen) { Switch-SpaceRow -Row $row }
        $t.HasKids = @($old.Kids).Count -gt 0
        $t.Chev.Visibility = if ($t.HasKids) { 'Visible' } else { 'Hidden' }
        Set-SpaceRowNumbers -Row $row
        Update-SpaceAncestors -Row $row -DeltaSize $dS -DeltaFiles $dF
        if ($wasOpen -and $t.HasKids) { Switch-SpaceRow -Row $row }
        Update-SpaceBar
    } | Out-Null
}
