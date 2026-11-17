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
        $j = Get-Content -LiteralPath $CleanRulesPath -Raw -Encoding UTF8 | ConvertFrom-Json
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
    $ui = @{ Rows = @{}; Items = @() }
    $scan = New-Button -Text 'Сканировать' -Icon 'search' -OnClick { Start-CleanScan }
    $ab = New-ActionBar
    $ui.Bar = $ab
    $ui.CleanBtn = New-Button -Text 'Очистить' -Icon 'trash' -Kind Primary -OnClick { Start-CleanRun }
    $ui.CleanBtn.IsEnabled = $false
    [void]$ab.Right.Children.Add($ui.CleanBtn)
    $L = New-PageLayout -Title 'Очистка' -Subtitle 'Временные файлы, кэши и мусор программ' -HeaderRight @($scan) -ActionBar $ab.Root
    $ui.Subtitle = $L.Subtitle

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
    if (-not $script:CleanUi.Scanned) { Start-CleanScan }
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
        try { $free = [double](Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $env:SystemDrive + "'")).FreeSpace } catch {}
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
    $ui.Bar.Text.Inlines.Clear()
    $ui.Bar.Text.Inlines.Add((New-Object System.Windows.Documents.Bold (New-Object System.Windows.Documents.Run ([string]$sel.Count))))
    $ui.Bar.Text.Inlines.Add((New-Object System.Windows.Documents.Run (' выбрано · ' + (Format-Size $bytes))))
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
