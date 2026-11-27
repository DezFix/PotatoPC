# PAGE: history
# TITLE: История и откаты
# ICON: history
# ORDER: 95
# NAV: footer

$script:HiUi = $null
$script:HistoryIcons = @{ plugin = 'bolt'; clean = 'broom'; startup = 'power'; app = 'box'; drivers = 'chip'; users = 'users'; protect = 'shield'; service = 'wrench'; maintenance = 'clock'; test = 'gauge'; report = 'report'; restore = 'flag'; optimize = 'play'; network = 'network'; uninstall = 'trash'; firewall = 'ban' }

function Build-Page_history {
    $ui = @{}
    $rp = New-Button -Text 'Создать точку восстановления' -Icon 'flag' -OnClick { Start-BgTask -Name 'Точка восстановления' -Script { New-RestorePoint -Description 'PotatoPC: вручную' } -OnDone { Update-RestorePoints } | Out-Null }
    $rs = New-Button -Text 'Восстановление системы' -Kind Ghost -OnClick { Start-Process (Join-Path $env:WINDIR 'System32\rstrui.exe') }
    $L = New-PageLayout -Title 'История и откаты' -Subtitle 'Что и когда менял PotatoPC, как вернуть всё назад' -HeaderRight @($rs, (New-Button -Text 'Обновить' -Icon 'refresh' -OnClick { Show-Page_history }), $rp)
    $ui.Points = New-Section -Title 'Точки восстановления Windows'
    [void]$L.Body.Children.Add($ui.Points.Root)
    $ui.Undo = New-Section -Title 'Откаты по разделам'
    [void]$L.Body.Children.Add($ui.Undo.Root)
    $rep = New-Button -Text 'Отчёт о проделанной работе' -Kind Ghost -OnClick {
        $f = Join-Path $ReportFolder 'test-last.json'
        if (-not (Test-Path -LiteralPath $f)) { Show-Info 'Отчёт строится вместе с результатами теста. Откройте «Тест ПК» и запустите тест - в отчёт попадут и выполненные работы.'; return }
        try { $t = Get-Content -LiteralPath $f -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop; $file = New-MasterReport -Test $t; Open-Path $file } catch { Write-Log ('Отчёт: ' + $_.Exception.Message) 'err' }
    }
    $ui.Log = New-Section -Title 'Журнал действий' -Right @($rep)
    [void]$L.Body.Children.Add($ui.Log.Root)
    $script:HiUi = $ui
    return $L.Root
}

function Show-Page_history {
    param($Arg)
    $ui = $script:HiUi
    # Откаты
    $ui.Undo.Body.Children.Clear()
    # Одна строка на раздел: все откаты его твиков разом. Откатить отдельный
    # твик можно кнопкой у самого твика на странице «Твики».
    $cats = @{}
    foreach ($p in @(Get-Plugins | Where-Object { -not $_.IsUndo })) { $cats[$p.CatNum] = $p.Category }
    $all = @(Get-UndoPlugins)
    foreach ($num in @($all | ForEach-Object { $_.UndoFor } | Where-Object { $_ } | Sort-Object -Unique)) {
        $list = @($all | Where-Object { $_.UndoFor -contains $num })
        $cat = if ($cats[$num]) { $cats[$num] } else { $num }
        $sub = 'Откатов: ' + $list.Count + '. ' + ((@($list | ForEach-Object { $_.Name -replace '^Откат:\s*', '' }) | Select-Object -First 4) -join '; ') + $(if ($list.Count -gt 4) { '…' } else { '' })
        $b = New-Button -Text 'Откатить раздел' -Icon 'undo' -Kind Small -Tag @{ Cat = $cat; List = $list } -OnClick {
            $t = $this.Tag
            $msg = 'Вернуть настройки раздела «' + $t.Cat + '» к заводским?' + "`n`n" + (($t.List | ForEach-Object { '  • ' + $_.Name }) -join "`n")
            if (-not (Show-Confirm -Message $msg -Title 'Откат' -Warning)) { return }
            Start-BgTask -Name ('Откат: ' + $t.Cat) -Vars @{ P = $t.List } -Script { Invoke-PluginBatch -Plugins @($P) -RestorePoint $true -Title 'Откат' } -OnDone { Show-Page_history } | Out-Null
        }
        [void]$ui.Undo.Body.Children.Add((New-Row -Left (New-IconTile -Icon 'undo' -Color 'Info') -Main (New-TitleBlock -Title ('Раздел «' + $cat + '»') -Sub $sub) -Right @($b)))
    }
    # Журнал
    $ui.Log.Body.Children.Clear()
    $h = @(Get-History -Last 300)
    $ui.Log.Header.Text = 'Журнал действий · ' + $h.Count
    if ($h.Count -eq 0) { [void]$ui.Log.Body.Children.Add((New-Placeholder 'PotatoPC пока ничего не менял на этом компьютере.')) }
    $lastDay = ''
    foreach ($x in ($h | Select-Object -First 150)) {
        $t = [datetime]$x.Time
        $day = $t.ToString('dd MMMM yyyy')
        if ($day -ne $lastDay) {
            [void]$ui.Log.Body.Children.Add((New-Text -Text $day -Size 12 -Color 'Muted' -Weight 'SemiBold' -Margin (16, 12, 16, 4)))
            $lastDay = $day
        }
        $icon = $script:HistoryIcons[[string]$x.Kind]; if (-not $icon) { $icon = 'info' }
        $ok = $x.Result -eq 'ok'
        $right = @((New-Text -Text $t.ToString('HH:mm') -Size 12 -Color 'Muted'))
        if (-not $ok) { $right = @((New-Badge 'ошибка' 'bad')) + $right }
        # Исправления реестра и остатки программ сохраняют копию - их можно откатить
        if ($ok -and $x.Ref -and [string]$x.Kind -in @('registry', 'uninstall', 'users') -and [string]$x.Name -notlike 'Откат*' -and (Test-Path -LiteralPath ([string]$x.Ref) -PathType Container)) {
            if (@(Get-ChildItem -LiteralPath ([string]$x.Ref) -Include '*.reg', 'tasks.json' -Recurse -ErrorAction SilentlyContinue).Count) {
                $rb = New-Button -Text 'Откатить' -Icon 'undo' -Kind Small -Tag ([string]$x.Ref) -OnClick {
                    if (-not (Show-Confirm -Message ('Вернуть ключи реестра (и задачи) из копии?' + "`n`n" + $this.Tag) -Title 'Откат' -Warning)) { return }
                    Start-BgTask -Name 'Откат реестра' -Vars @{ F = $this.Tag } -Script { Restore-RegistryBackup -Folder $F } -OnDone { Show-Page_history } | Out-Null
                }
                $right = @($rb) + $right
            }
        }
        # Запрет доступа в интернет (страница «Сеть») снимается одной кнопкой, пока правило ещё есть
        if ($ok -and [string]$x.Kind -eq 'firewall' -and $x.Ref -and (Get-NetFirewallRule -Name ([string]$x.Ref) -ErrorAction SilentlyContinue)) {
            $fb = New-Button -Text 'Разрешить снова' -Icon 'undo' -Kind Small -Tag ([string]$x.Ref) -OnClick {
                $id = [string]$this.Tag
                Start-BgTask -Name 'Снятие запрета' -Vars @{ Id = $id } -Script { Remove-NetAppBlock -Id $Id } -OnDone { Show-Page_history } | Out-Null
            }
            $right = @($fb) + $right
        }
        $main = New-Text -Text ([string]$x.Name) -Size 13
        if ($x.Detail) { $main.ToolTip = [string]$x.Detail }
        [void]$ui.Log.Body.Children.Add((New-Row -Left (New-Icon -Name $icon -Size 16 -Color $(if ($ok) { 'Muted' } else { 'Bad' })) -Main $main -Right $right -Padding (16, 6, 16, 6)))
    }
    Update-RestorePoints
}

function Update-RestorePoints {
    $ui = $script:HiUi
    $ui.Points.Body.Children.Clear()
    [void]$ui.Points.Body.Children.Add((New-Placeholder))
    Start-BgTask -Name 'Точки восстановления' -Silent -Script {
        $pts = @()
        try { $pts = @(Get-ComputerRestorePoint -ErrorAction Stop | Sort-Object SequenceNumber -Descending | Select-Object -First 8 | ForEach-Object { @{ Desc = [string]$_.Description; Time = $_.ConvertToDateTime($_.CreationTime) } }) } catch {}
        $disabled = $false
        try { $v = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore' -Name DisableSR -ErrorAction Stop; $disabled = ($v.DisableSR -eq 1) } catch {}
        return @{ Points = $pts; Disabled = $disabled }
    } -OnDone {
        param($r)
        $ui = $script:HiUi
        $ui.Points.Body.Children.Clear()
        if (-not $r) { return }
        if ($r.Points.Count -eq 0) {
            $en = New-Button -Text 'Включить защиту системы' -Kind Small -OnClick {
                Start-BgTask -Name 'Защита системы' -Script {
                    Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction Stop
                    [void](Invoke-ProcessLive -FilePath (Join-Path $env:WINDIR 'System32\vssadmin.exe') -Arguments ('resize shadowstorage /for=' + $env:SystemDrive + ' /on=' + $env:SystemDrive + ' /maxsize=5%') -TimeoutSec 60 -Quiet)
                    Write-Log ('Защита системы включена для ' + $env:SystemDrive + ' (до 5% диска)') 'ok'
                    Add-History -Kind 'restore' -Name 'Включена защита системы'
                    [void](New-RestorePoint -Description 'PotatoPC: первая точка')
                } -OnDone { Update-RestorePoints } | Out-Null
            }
            $msg = if ($r.Disabled) { 'Защита системы запрещена политикой - точки восстановления не создаются.' } else { 'Точек восстановления нет. Скорее всего, защита системы выключена - без неё откатить Windows целиком не получится.' }
            [void]$ui.Points.Body.Children.Add((New-Row -Left (New-Icon -Name 'warn' -Size 18 -Color 'Warn') -Main (New-Text -Text $msg -Size 13 -Wrap) -Right @($en)))
            return
        }
        foreach ($p in $r.Points) {
            [void]$ui.Points.Body.Children.Add((New-Row -Left (New-Icon -Name 'flag' -Size 16 -Color 'Muted') -Main (New-Text -Text $p.Desc -Size 13) -Right @((New-Text -Text $p.Time.ToString('dd.MM.yyyy HH:mm') -Size 12 -Color 'Muted')) -Padding (16, 6, 16, 6)))
        }
    } | Out-Null
}

# --- Окно «Точки восстановления» (кнопка внизу боковой панели) ---

function Show-RestoreMenu {
    param($Anchor)
    Show-ActionMenu -Anchor $Anchor -Items @(
        @{ Text = 'Создать точку сейчас'; OnClick = { Start-BgTask -Name 'Точка восстановления' -Script { New-RestorePoint -Description 'PotatoPC: вручную' } -OnDone { if ($script:HiUi) { Update-RestorePoints } } | Out-Null } }
        @{ Text = 'Все точки и откат Windows…'; OnClick = { Show-RestorePointsDialog } }
    )
}

function Get-RestorePointKind {
    param([int]$Type)
    switch ($Type) { 0 { 'установка программы' } 1 { 'удаление программы' } 10 { 'установка драйвера' } 12 { 'изменение настроек' } 13 { 'отменённая операция' } default { 'системная' } }
}

function Show-RestorePointsDialog {
    $w = New-Object System.Windows.Window
    $w.Owner = $script:Window; $w.WindowStartupLocation = 'CenterOwner'
    $w.Width = 560 * $script:UiScale; $w.SizeToContent = 'Height'; $w.ResizeMode = 'NoResize'
    $w.Title = 'Точки восстановления'; $w.Background = Get-Brush 'Bg'; $w.Foreground = Get-Brush 'Text'
    $w.FontFamily = $script:Window.FontFamily
    foreach ($k in $script:Window.Resources.MergedDictionaries) { [void]$w.Resources.MergedDictionaries.Add($k) }
    foreach ($key in $script:Window.Resources.Keys) { $w.Resources[$key] = $script:Window.Resources[$key] }
    $sp = New-Stack -Margin (22, 18, 22, 18)
    [void]$sp.Children.Add((New-Text -Text 'Точки восстановления Windows' -Size 18 -Weight 'Bold' -Margin (0, 0, 0, 6)))
    [void]$sp.Children.Add((New-Text -Text 'Откат возвращает системные файлы, драйверы, реестр и программы к состоянию на дату точки. Документы, фото и загрузки не трогаются. Компьютер перезагрузится.' -Size 12 -Color 'Muted' -Wrap -Margin (0, 0, 0, 12)))
    $card = New-Object System.Windows.Controls.Border
    $card.Background = Get-Brush 'Card'; $card.BorderBrush = Get-Brush 'Line'; $card.BorderThickness = New-Thickness 1
    $card.CornerRadius = New-Object System.Windows.CornerRadius 10
    $list = New-Stack
    $sv = New-Object System.Windows.Controls.ScrollViewer
    $sv.VerticalScrollBarVisibility = 'Auto'; $sv.HorizontalScrollBarVisibility = 'Disabled'
    $sv.MaxHeight = [Math]::Max(300, [System.Windows.SystemParameters]::WorkArea.Height / $script:UiScale - 300)
    $sv.Content = $list
    $card.Child = $sv
    [void]$sp.Children.Add($card)
    [void]$list.Children.Add((New-Text -Text 'Загружаю список точек…' -Size 13 -Color 'Muted' -Margin (16, 14, 16, 14)))
    $create = New-Button -Text 'Создать точку' -Icon 'flag' -OnClick {
        $this.IsEnabled = $false
        Start-BgTask -Name 'Точка восстановления' -Script { New-RestorePoint -Description 'PotatoPC: вручную' } -OnDone { Update-RestoreDialogList; if ($script:HiUi) { Update-RestorePoints } } | Out-Null
    }
    $rstrui = New-Button -Text 'Восстановление Windows' -Kind Ghost -OnClick { Start-Process (Join-Path $env:WINDIR 'System32\rstrui.exe') }
    $rstrui.Margin = New-Thickness 10, 0, 0, 0
    $close = New-Button -Text 'Закрыть' -OnClick { $script:RpDlg.Window.Close() }
    $bar = New-Object System.Windows.Controls.DockPanel
    $bar.LastChildFill = $false
    $bar.Margin = New-Thickness 0, 14, 0, 0
    [System.Windows.Controls.DockPanel]::SetDock($close, 'Right')
    [void]$bar.Children.Add($close)
    [void]$bar.Children.Add($create)
    [void]$bar.Children.Add($rstrui)
    [void]$sp.Children.Add($bar)
    $script:RpDlg = @{ Window = $w; List = $list; Create = $create }
    Add-UiScale $sp
    $w.Content = $sp
    try { Enable-DarkTitleBar -Target $w } catch {}
    $w.Add_ContentRendered({ Update-RestoreDialogList })
    [void]$w.ShowDialog()
    $script:RpDlg = $null
}

function Add-RestoreDialogRows {
    # UI-поток: заполняет список окна. $R = @{ Points; Disabled }.
    param($R)
    $d = $script:RpDlg
    if (-not $d) { return }
    $d.Create.IsEnabled = $true
    $d.List.Children.Clear()
    if (-not $R -or @($R.Points).Count -eq 0) {
        $msg = if ($R -and $R.Disabled) { 'Защита системы запрещена политикой - точки восстановления не создаются.' } else { 'Точек восстановления нет. Нажмите «Создать точку». Если не получится - защита системы выключена, включить её можно на странице «История и откаты».' }
        $row = New-Row -Left (New-Icon -Name 'warn' -Size 18 -Color 'Warn') -Main (New-Text -Text $msg -Size 13 -Wrap)
        $row.BorderThickness = New-Thickness 0
        [void]$d.List.Children.Add($row)
        return
    }
    $first = $true
    foreach ($p in $R.Points) {
        $mine = $p.Desc -like 'PotatoPC*'
        $sub = $p.Time.ToString('dd.MM.yyyy HH:mm') + ' · ' + (Get-RestorePointKind $p.Type) + $(if ($first) { ' · самая новая' } else { '' })
        $b = New-Button -Text 'Откатить' -Kind Small -Tag $p -OnClick { Invoke-RestoreToPoint -Point $this.Tag }
        $row = New-Row -Left (New-Icon -Name 'flag' -Size 16 -Color $(if ($mine) { 'Accent' } else { 'Muted' })) -Main (New-TitleBlock -Title $p.Desc -Sub $sub) -Right @($b) -Padding (16, 8, 16, 8)
        if ($first) { $row.BorderThickness = New-Thickness 0 }
        [void]$d.List.Children.Add($row)
        $first = $false
    }
}

function Update-RestoreDialogList {
    if (-not $script:RpDlg) { return }
    Start-BgTask -Name 'Точки восстановления' -Silent -Script {
        $pts = @()
        try { $pts = @(Get-ComputerRestorePoint -ErrorAction Stop | Sort-Object SequenceNumber -Descending | ForEach-Object { @{ Seq = [int]$_.SequenceNumber; Desc = [string]$_.Description; Type = [int]$_.RestorePointType; Time = $_.ConvertToDateTime($_.CreationTime) } }) } catch {}
        $disabled = $false
        try { $v = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore' -Name DisableSR -ErrorAction Stop; $disabled = ($v.DisableSR -eq 1) } catch {}
        return @{ Points = $pts; Disabled = $disabled }
    } -OnDone { param($r) Add-RestoreDialogRows -R $r } | Out-Null
}

function Invoke-RestoreToPoint {
    param($Point)
    $when = $Point.Time.ToString('dd.MM.yyyy HH:mm')
    $msg = 'Откатить Windows к точке «' + $Point.Desc + '» от ' + $when + "?`n`n" +
           "Компьютер СРАЗУ перезагрузится - сохраните открытые документы.`n" +
           'Программы и драйверы, установленные после ' + $when + ", пропадут, а удалённые после этой даты вернутся. Документы, фото и загрузки не трогаются.`n`n" +
           'Если результат не понравится, откат можно отменить: перед ним Windows сама создаёт новую точку.'
    if (-not (Show-Confirm -Message $msg -Title 'Откат Windows' -Warning)) { return }
    Add-History -Kind 'restore' -Name ('Откат Windows к точке: ' + $Point.Desc + ' (' + $when + ')')
    Write-Log ('Откат Windows к точке «' + $Point.Desc + '» - компьютер перезагрузится') 'warn'
    Start-BgTask -Name 'Откат Windows' -Vars @{ Seq = $Point.Seq } -Script {
        try { Restore-Computer -RestorePoint $Seq -Confirm:$false -ErrorAction Stop; return $true }
        catch { Write-Log ('Откат не запустился: ' + $_.Exception.Message + '. Попробуйте кнопку «Восстановление Windows».') 'err'; return $false }
    } | Out-Null
}
