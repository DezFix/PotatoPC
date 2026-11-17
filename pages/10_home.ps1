# PAGE: home
# TITLE: Главная
# ICON: home
# ORDER: 10

$script:HomeUi = $null
$script:PresetInfo = [ordered]@{
    potato = @{ Title = 'Слабый ПК'; Desc = 'Максимум разгрузки: фон, эффекты, телеметрия, гибернация' }
    office = @{ Title = 'Офис'; Desc = 'Умеренно: без игровых твиков и агрессивной чистки' }
    game   = @{ Title = 'Игры'; Desc = 'Игровые приоритеты, план «Высокая производительность», без записи игр' }
}

function Build-Page_home {
    $ui = @{}
    $refresh = New-Button -Text 'Обновить' -Icon 'refresh' -OnClick { Update-HomeData -Force }
    $L = New-PageLayout -Title 'Главная' -Subtitle 'Коротко о системе и быстрые действия' -HeaderRight @($refresh)

    $ui.Cpu = New-StatCard -Icon 'cpu' -Label 'Процессор'
    $ui.Ram = New-StatCard -Icon 'mem' -Label 'Память'
    $ui.Disk = New-StatCard -Icon 'disk' -Label ('Диск ' + $env:SystemDrive)
    $ui.Up = New-StatCard -Icon 'clock' -Label 'Без перезагрузки'
    [void]$L.Body.Children.Add((New-Grid -Columns 4 -Items @($ui.Cpu.Root, $ui.Ram.Root, $ui.Disk.Root, $ui.Up.Root)))

    # Оценка
    $scoreSp = New-Stack
    $top = New-Object System.Windows.Controls.DockPanel
    $ui.Ring = New-ScoreRing -Size 104
    $ui.Ring.Margin = New-Thickness 0, 0, 20, 0
    [System.Windows.Controls.DockPanel]::SetDock($ui.Ring, 'Left')
    [void]$top.Children.Add($ui.Ring)
    $tsp = New-Stack; $tsp.VerticalAlignment = 'Center'
    $ui.ScoreTitle = New-Text -Text 'Проверяю систему…' -Size 20 -Weight 'Bold'
    $ui.ScoreText = New-Text -Text 'Это займёт несколько секунд.' -Size 14 -Color 'Muted' -Wrap -Margin (0, 6, 0, 0)
    [void]$tsp.Children.Add($ui.ScoreTitle); [void]$tsp.Children.Add($ui.ScoreText)
    [void]$top.Children.Add($tsp)
    [void]$scoreSp.Children.Add($top)
    $ui.Meters = @{}
    $mg = New-Object System.Windows.Controls.Primitives.UniformGrid
    $mg.Columns = 2; $mg.Margin = New-Thickness 0, 18, -20, 0
    foreach ($a in @(@('speed','Скорость'), @('clean','Чистота диска'), @('privacy','Приватность'), @('security','Безопасность'))) {
        $cell = New-Stack -Margin (0, 0, 20, 12)
        $hd = New-Object System.Windows.Controls.DockPanel
        $val = New-Text -Text '—' -Size 12 -Weight 'Bold'
        [System.Windows.Controls.DockPanel]::SetDock($val, 'Right')
        [void]$hd.Children.Add($val)
        [void]$hd.Children.Add((New-Text -Text $a[1] -Size 12 -Color 'Muted'))
        $m = New-Meter -Height 6; $m.Margin = New-Thickness 0, 6, 0, 0
        [void]$cell.Children.Add($hd); [void]$cell.Children.Add($m)
        [void]$mg.Children.Add($cell)
        $ui.Meters[$a[0]] = @{ Meter = $m; Value = $val }
    }
    [void]$scoreSp.Children.Add($mg)
    $btns = New-Stack -Orientation Horizontal -Margin (0, 6, 0, 0)
    $ui.OptBtn = New-Button -Text 'Оптимизировать' -Icon 'play' -Kind Primary -OnClick { Start-HomeOptimize }
    $ui.OptBtn.IsEnabled = $false
    $prev = New-Button -Text 'Что изменится' -Icon 'eye' -OnClick { Show-HomeOptimizePlan | Out-Null }
    $prev.Margin = New-Thickness 10, 0, 0, 0
    [void]$btns.Children.Add($ui.OptBtn); [void]$btns.Children.Add($prev)
    [void]$scoreSp.Children.Add($btns)
    $scoreCard = New-Card -Child $scoreSp

    $ui.Checks = New-Section -Title 'Проверка' -Margin (0, 0, 0, 0)
    [void]$ui.Checks.Body.Children.Add((New-Placeholder))

    $g = New-Object System.Windows.Controls.Grid
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength 1, 'Star'
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength 1, 'Star'
    [void]$g.ColumnDefinitions.Add($c1); [void]$g.ColumnDefinitions.Add($c2)
    $scoreCard.Margin = New-Thickness 0, 0, 8, 0
    $ui.Checks.Root.Margin = New-Thickness 8, 0, 0, 0
    [System.Windows.Controls.Grid]::SetColumn($ui.Checks.Root, 1)
    [void]$g.Children.Add($scoreCard); [void]$g.Children.Add($ui.Checks.Root)
    $g.Margin = New-Thickness 0, 0, 0, 16
    [void]$L.Body.Children.Add($g)

    # До / после
    $snapBtn = New-Button -Text 'Сделать замер' -Kind Ghost -OnClick { Start-HomeSnapshot }
    $ui.Compare = New-Section -Title 'До и после оптимизации' -Right @($snapBtn)
    [void]$ui.Compare.Body.Children.Add((New-Placeholder 'Замеров пока нет. «Оптимизировать» сделает замер «до» автоматически, а после перезагрузки здесь появится сравнение.'))
    [void]$L.Body.Children.Add($ui.Compare.Root)

    # Пресеты
    [void]$L.Body.Children.Add((New-Text -Text 'Пресеты' -Size 16 -Weight 'SemiBold' -Margin (0, 4, 0, 12)))
    $ui.PresetCards = @{}
    $cards = @()
    foreach ($k in $script:PresetInfo.Keys) {
        $info = $script:PresetInfo[$k]
        $b = New-Object System.Windows.Controls.Button
        $b.Style = $script:Window.FindResource('BtnSecondary')
        $b.HorizontalContentAlignment = 'Stretch'; $b.VerticalContentAlignment = 'Stretch'
        $b.Padding = New-Thickness 16, 14, 16, 14
        $b.Tag = $k
        $sp = New-Stack
        $hd = New-Object System.Windows.Controls.DockPanel
        $badge = New-Badge -Text 'Подходит вам' -Kind 'accent'
        $badge.Visibility = 'Collapsed'
        [System.Windows.Controls.DockPanel]::SetDock($badge, 'Right')
        [void]$hd.Children.Add($badge)
        [void]$hd.Children.Add((New-Text -Text $info.Title -Size 16 -Weight 'Bold'))
        [void]$sp.Children.Add($hd)
        $d = New-Text -Text $info.Desc -Size 13 -Color 'Muted' -Wrap -Margin (0, 8, 0, 8)
        $d.FontWeight = 'Normal'
        [void]$sp.Children.Add($d)
        $cnt = New-Text -Text '' -Size 12 -Color 'Accent' -Weight 'SemiBold'
        [void]$sp.Children.Add($cnt)
        $b.Content = $sp
        $b.Add_Click({ Show-Page -Id 'tweaks' -Arg @{ Preset = $this.Tag } })
        $ui.PresetCards[$k] = @{ Button = $b; Badge = $badge; Count = $cnt }
        $cards += $b
    }
    [void]$L.Body.Children.Add((New-Grid -Columns 3 -Items $cards))
    $script:HomeUi = $ui
    return $L.Root
}

function Show-Page_home {
    param($Arg)
    if (-not $script:HomeUi.Loaded -or ((Get-Date) - $script:HomeUi.Loaded).TotalMinutes -gt 3) { Update-HomeData }
}

function Update-HomeData {
    param([switch]$Force)
    if ($script:HomeUi.Busy) { return }
    $script:HomeUi.Busy = $true
    Start-BgTask -Name 'Проверка системы' -Script {
        $sum = Get-SystemSummary
        $st = Get-StartupItems
        $checks = Get-HealthChecks -Summary $sum -StartupItems $st
        $score = Get-HealthScore -Checks $checks
        $snap = Get-MetricSnapshot -Label 'now' -StartupItems $st
        $base = Get-BaselineSnapshot
        $plugins = @(Get-Plugins -Force | Where-Object { -not $_.IsUndo -and $_.Applicable })
        $counts = @{}
        foreach ($k in @('potato', 'office', 'game')) { $counts[$k] = @($plugins | Where-Object { $_.Presets -contains $k }).Count }
        return @{ Sum = $sum; Checks = $checks; Score = $score; Snap = $snap; Base = $base; Preset = (Get-RecommendedPreset $sum); Counts = $counts }
    } -OnDone {
        param($r, $err)
        $script:HomeUi.Busy = $false
        if (-not $r) { Write-Log ('Проверка системы не удалась: ' + $err) 'err'; return }
        Set-HomeData $r
    } | Out-Null
}

function Set-HomeData {
    param($r)
    $ui = $script:HomeUi
    $ui.Loaded = Get-Date
    $ui.Data = $r
    $s = $r.Sum
    $ui.Cpu.Value.Text = if ($s.Cpu) { $s.Cpu } else { '—' }
    $ui.Cpu.Value.ToolTip = $s.Cpu
    $ui.Cpu.Sub.Text = ('{0} ядер / {1} потоков · загрузка {2}%' -f $s.Cores, $s.Threads, $s.CpuLoad)
    if ($s.RamTotal -gt 0) {
        $ui.Ram.Value.Text = ('{0} / {1}' -f (Format-Size ($s.RamTotal - $s.RamFree)), (Format-Size $s.RamTotal))
        $ui.Ram.Sub.Text = ('занято {0}%' -f [int](100 * (1 - $s.RamFree / $s.RamTotal)))
    }
    $ui.Disk.Value.Text = (Format-Size $s.Disk.Free) + ' свободно'
    $ui.Disk.Sub.Text = 'из ' + (Format-Size $s.Disk.Total) + ', ' + $s.Disk.Media
    $ui.Up.Value.Text = Format-Duration $s.Uptime
    $ui.Up.Sub.Text = if ($s.Uptime -gt 3 * 86400) { 'рекомендуем перезагрузить' } else { 'норма' }

    $sc = $r.Score
    Set-ScoreRing -Ring $ui.Ring -Value $sc.total
    $problems = @($r.Checks | Where-Object { $_.Level -ne 'ok' })
    if ($sc.total -ge 80) { $ui.ScoreTitle.Text = 'Всё хорошо' }
    elseif ($sc.total -ge 50) { $ui.ScoreTitle.Text = 'Есть что улучшить' }
    else { $ui.ScoreTitle.Text = 'Системе нужна помощь' }
    $pi = $script:PresetInfo[$r.Preset]
    $ui.ScoreText.Text = 'Проблем: ' + $problems.Count + '. «Оптимизировать» применит пресет «' + $pi.Title + '» и почистит мусор, предварительно создав точку восстановления.'
    foreach ($k in $ui.Meters.Keys) {
        $v = [int]$sc[$k]
        $col = if ($v -ge 75) { 'Ok' } elseif ($v -ge 45) { 'Warn' } else { 'Bad' }
        Set-Meter -Meter $ui.Meters[$k].Meter -Value ($v / 100) -Color $col
        $ui.Meters[$k].Value.Text = [string]$v
        $ui.Meters[$k].Value.Foreground = Get-Brush $col
    }
    $ui.OptBtn.IsEnabled = $true

    $ui.Checks.Body.Children.Clear()
    $order = @{ bad = 0; warn = 1; ok = 2 }
    foreach ($c in @($r.Checks | Sort-Object { $order[$_.Level] } | Select-Object -First 7)) {
        $col = switch ($c.Level) { 'ok' { 'Ok' } 'warn' { 'Warn' } default { 'Bad' } }
        $icon = if ($c.Level -eq 'ok') { 'check' } else { 'warn' }
        $fix = $null
        if ($c.Level -ne 'ok' -and $c.Fix) {
            $fix = New-Button -Text 'Исправить' -Kind Ghost -Tag $c.Fix -OnClick {
                $f = [string]$this.Tag
                if ($f -like 'tweaks:*') { Show-Page -Id 'tweaks' -Arg @{ Category = $f.Substring(7) } } else { Show-Page -Id $f }
            }
        }
        $row = New-Row -Left (New-Icon -Name $icon -Size 18 -Color $col) -Main (New-TitleBlock -Title $c.Title -Sub $c.Detail) -Right @($fix) -Padding (16, 8, 12, 8)
        [void]$ui.Checks.Body.Children.Add($row)
    }

    foreach ($k in $ui.PresetCards.Keys) {
        $pc = $ui.PresetCards[$k]
        $pc.Count.Text = [string]$r.Counts[$k] + ' твиков'
        $rec = ($k -eq $r.Preset)
        $pc.Badge.Visibility = if ($rec) { 'Visible' } else { 'Collapsed' }
        $pc.Button.BorderBrush = if ($rec) { Get-Brush 'Accent' } else { Get-Brush 'Line' }
        $pc.Button.Background = if ($rec) { Get-Brush 'AccentDim' } else { Get-Brush 'Card' }
    }
    Set-HomeCompare -Base $r.Base -Now $r.Snap
}

function Set-HomeCompare {
    param($Base, $Now)
    $body = $script:HomeUi.Compare.Body
    if (-not $Base) { return }
    $body.Children.Clear()
    $when = try { ([datetime]$Base.Time).ToString('dd.MM.yyyy HH:mm') } catch { '' }
    $rows = @(
        @{ N = 'Время загрузки Windows'; B = $Base.BootSec; A = $Now.BootSec; F = { param($v) if ($v -lt 0) { '—' } else { Format-Duration $v } }; Less = $true },
        @{ N = 'Занято памяти'; B = $Base.RamUsed; A = $Now.RamUsed; F = { param($v) Format-Size $v }; Less = $true },
        @{ N = 'Процессов запущено'; B = $Base.Processes; A = $Now.Processes; F = { param($v) [string]$v }; Less = $true },
        @{ N = 'Программ в автозагрузке'; B = $Base.Startup; A = $Now.Startup; F = { param($v) [string]$v }; Less = $true },
        @{ N = ('Свободно на ' + $env:SystemDrive); B = $Base.FreeSys; A = $Now.FreeSys; F = { param($v) Format-Size $v }; Less = $false }
    )
    $hdr = New-Row -Main (New-Text -Text ('Метрика  ·  «до» от ' + $when) -Size 12 -Color 'Muted') -Right @((New-Text -Text 'До' -Size 12 -Color 'Muted'), (New-Text -Text 'Сейчас' -Size 12 -Color 'Muted')) -Padding (16, 6, 16, 6)
    [void]$body.Children.Add($hdr)
    foreach ($x in $rows) {
        $b = [double]$x.B; $a = [double]$x.A
        $better = if ($x.Less) { $a -lt $b } else { $a -gt $b }
        $col = if ($a -eq $b -or $b -le 0 -or $a -lt 0) { 'Text' } elseif ($better) { 'Ok' } else { 'Warn' }
        $bt = New-Text -Text (& $x.F $b) -Size 13 -Color 'Muted'; $bt.Width = 110; $bt.TextAlignment = 'Right'
        $at = New-Text -Text (& $x.F $a) -Size 13 -Weight 'SemiBold' -Color $col; $at.Width = 110; $at.TextAlignment = 'Right'
        [void]$body.Children.Add((New-Row -Main (New-Text -Text $x.N -Size 13) -Right @($bt, $at) -Padding (16, 6, 16, 6)))
    }
    $note = New-Text -Text 'Время загрузки обновляется после перезагрузки. «Занято памяти» честно сравнивать сразу после включения ПК.' -Size 12 -Color 'Muted' -Wrap -Margin (16, 8, 16, 12)
    [void]$body.Children.Add($note)
}

function Start-HomeSnapshot {
    Start-BgTask -Name 'Замер системы' -Script {
        $s = Get-MetricSnapshot -Label 'before'
        Save-MetricSnapshot $s
        Write-Log 'Замер сохранён как точка «до». После изменений сравнение появится на Главной.' 'ok'
        return $s
    } -OnDone { param($r) if ($r) { Update-HomeData -Force } } | Out-Null
}

function Get-HomeOptimizePlan {
    $preset = if ($script:HomeUi.Data) { $script:HomeUi.Data.Preset } else { 'potato' }
    $plugins = @(Get-Plugins | Where-Object { -not $_.IsUndo -and $_.Applicable -and ($_.Presets -contains $preset) -and $_.Trusted })
    return @{ Preset = $preset; Plugins = $plugins }
}

function Show-HomeOptimizePlan {
    param([switch]$Ask)
    $plan = Get-HomeOptimizePlan
    $pi = $script:PresetInfo[$plan.Preset]
    $lines = @($plan.Plugins | ForEach-Object { '  • ' + $_.Name + $(if ($_.Risk -ge 2) { '  (осторожно)' } else { '' }) })
    $msg = "Пресет «" + $pi.Title + "»:`n" + ($lines -join "`n") + "`n`nПлюс очистка мусора: временные файлы, кэш обновлений, отчёты об ошибках, кэши браузеров.`n`nПеред изменениями: замер «до» и точка восстановления. Откатить любой раздел можно на странице «История»."
    if ($Ask) { return (Show-Confirm -Message ($msg + "`n`nНачать?") -Title 'Оптимизация') }
    Show-Info -Message $msg -Title 'Что изменится'
    return $true
}

function Start-HomeOptimize {
    if (-not (Show-HomeOptimizePlan -Ask)) { return }
    $plan = Get-HomeOptimizePlan
    $script:HomeUi.OptBtn.IsEnabled = $false
    Start-BgTask -Name 'Оптимизация' -Vars @{ Plan = $plan } -Script {
        Write-Log 'Замер «до»...'
        $snap = Get-MetricSnapshot -Label 'before'
        Save-MetricSnapshot $snap
        $r = Invoke-PluginBatch -Plugins $Plan.Plugins -RestorePoint $true -Title 'Оптимизация'
        if (-not (Test-JobCancel)) {
            $items = @(Get-CleanCatalog | Where-Object { $_.Safe })
            Invoke-CleanItems -Items $items | Out-Null
        }
        Add-History -Kind 'optimize' -Name ('Оптимизация, пресет ' + $Plan.Preset) -Detail ('твиков: ' + $r.Ok + ', ошибок: ' + $r.Fail)
        return $r
    } -OnDone {
        param($r)
        $script:HomeUi.OptBtn.IsEnabled = $true
        $script:PluginStatesStamp = $null
        Update-HomeData -Force
        if ($r) {
            Show-Info -Message ('Готово. Твиков применено: ' + $r.Ok + $(if ($r.Fail -gt 0) { ', с ошибкой: ' + $r.Fail + ' (подробности в журнале)' } else { '' }) + ".`n`nПерезагрузите компьютер, чтобы изменения вступили в силу. После перезагрузки на Главной появится сравнение «до/после».") -Title 'Оптимизация'
        }
    } | Out-Null
}
