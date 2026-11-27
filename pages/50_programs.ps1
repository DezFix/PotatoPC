# PAGE: programs
# TITLE: Программы
# ICON: box
# ORDER: 50

$script:PgUi = $null

function Build-Page_programs {
    $ui = @{ Tab = 'install'; Checks = @{}; UpdChecks = @{}; Installed = @{}; Tabs = @{}; IconTargets = (New-Object System.Collections.ArrayList); IconData = $null }
    $script:PgUi = $ui
    $ui.Search = New-TextInput -Placeholder 'Найти программу' -Width 260
    $ui.Search.Add_TextChanged({ Update-ProgramFilter })
    $ui.Search.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { Start-WingetSearch } })
    $ab = New-ActionBar
    $ui.Bar = $ab
    $ui.ActBtn = New-Button -Text 'Установить' -Icon 'plus' -Kind Primary -OnClick { Start-ProgramAction }
    [void]$ab.Right.Children.Add($ui.ActBtn)
    $refresh = New-Button -Text 'Обновить' -Icon 'refresh' -ToolTip 'Перечитать установленные программы и обновления' -OnClick { $script:PgUi.UpdLoaded = $false; Update-ProgramInstalled }
    $L = New-PageLayout -Title 'Программы' -Subtitle 'Установка и обновление через winget - без сайтов, рекламы и галочек «установить заодно»' -HeaderRight @($ui.Search, $refresh) -ActionBar $ab.Root

    $tabs = New-Stack -Orientation Horizontal -Margin (0, 0, 0, 18)
    foreach ($t in @(@('install', 'Установить'), @('updates', 'Обновления'))) {
        $b = New-Object System.Windows.Controls.Button
        $b.Style = $script:Window.FindResource('BtnGhost')
        $b.Tag = $t[0]; $b.Content = $t[1]; $b.FontSize = 14; $b.MinHeight = 40
        $b.BorderThickness = New-Thickness 0, 0, 0, 2
        $b.Margin = New-Thickness 0, 0, 18, 0
        $b.Add_Click({ Set-ProgramTab -Tab $this.Tag })
        [void]$tabs.Children.Add($b)
        $ui.Tabs[$t[0]] = $b
    }
    $toUn = New-Button -Text 'Удаление программ →' -Kind Ghost -OnClick { Show-Page -Id 'uninstall' }
    $toUn.VerticalAlignment = 'Center'
    [void]$tabs.Children.Add($toUn)
    [void]$L.Body.Children.Add($tabs)

    # Нет winget - предлагаем поставить его прямо отсюда.
    $mt = New-Text -Text 'winget не найден - без него не работают установка и обновление программ. PotatoPC может поставить его сам: с официального GitHub Microsoft, с проверкой подписи.' -Size 13 -Color 'Warn' -Wrap -Margin (12, 0, 16, 0)
    $mt.MaxWidth = 640
    $ui.WgBtn = New-Button -Text 'Установить winget' -Icon 'plus' -Kind Primary -OnClick { Start-WingetSetup }
    $ms = New-Object System.Windows.Controls.DockPanel
    [System.Windows.Controls.DockPanel]::SetDock($ui.WgBtn, 'Right')
    [void]$ms.Children.Add($ui.WgBtn)
    $mi = New-Icon -Name 'warn' -Size 20 -Color 'Warn'
    [System.Windows.Controls.DockPanel]::SetDock($mi, 'Left')
    [void]$ms.Children.Add($mi)
    [void]$ms.Children.Add($mt)
    $ui.Missing = New-Card -Child $ms -Padding (16, 12, 12, 12) -Margin (0, 0, 0, 16) -Background 'WarnDim' -Border '#5A4A1A'
    $ui.Missing.Visibility = 'Collapsed'
    [void]$L.Body.Children.Add($ui.Missing)

    # Вкладка «Установить»
    $ui.InstallPane = New-Stack
    $cat = Get-AppCatalog
    $ui.Catalog = $cat
    $ui.Workshop = @{}
    $ui.WorkshopPanel = New-WorkshopSection
    [void]$ui.InstallPane.Children.Add($ui.WorkshopPanel)
    $ui.CatPanels = @()
    foreach ($cname in $cat.Categories.Keys) {
        $hdr = New-Text -Text $cname.ToUpper() -Size 12 -Color 'Muted' -Weight 'SemiBold' -Margin (0, 4, 0, 10)
        $tiles = @()
        foreach ($a in $cat.Categories[$cname]) {
            $tiles += New-ProgramTile -App $a
        }
        $grid = New-Grid -Columns 3 -Items $tiles -Gap 10
        $panel = New-Stack -Children @($hdr, $grid)
        [void]$ui.InstallPane.Children.Add($panel)
        $ui.CatPanels += @{ Panel = $panel; Grid = $grid }
    }
    $ui.SearchPane = New-Section -Title 'Найдено в winget'
    $ui.SearchPane.Root.Visibility = 'Collapsed'
    [void]$ui.InstallPane.Children.Add($ui.SearchPane.Root)
    $ui.SearchBtn = New-Button -Text 'Искать в каталоге winget' -Icon 'search' -Kind Ghost -OnClick { Start-WingetSearch }
    $ui.SearchBtn.HorizontalAlignment = 'Left'
    [void]$ui.InstallPane.Children.Add($ui.SearchBtn)
    [void]$L.Body.Children.Add($ui.InstallPane)

    # Вкладка «Обновления»
    $ui.UpdPane = New-Section -Title 'Доступные обновления'
    $ui.UpdPane.Root.Visibility = 'Collapsed'
    [void]$L.Body.Children.Add($ui.UpdPane.Root)
    # Вкладка «Установленные»
    $ui.InstPane = New-Section -Title 'Установленные программы (известные winget)'
    $ui.InstPane.Root.Visibility = 'Collapsed'
    [void]$L.Body.Children.Add($ui.InstPane.Root)

    $script:PgUi = $ui
    Set-ProgramTab -Tab 'install'
    return $L.Root
}

function New-ProgramTile {
    param($App, [switch]$Search)
    $chk = New-CheckBox -Tag $App.Id -OnChange { Update-ProgramSelection }
    $sp = New-Stack
    [void]$sp.Children.Add((New-Text -Text $App.Name -Size 14 -Weight 'SemiBold'))
    [void]$sp.Children.Add((New-Text -Text $App.Id -Size 11 -Color 'Muted' -Mono))
    $state = New-Text -Text '' -Size 11 -Color 'Ok'
    $g = New-Object System.Windows.Controls.DockPanel
    $ic = New-AppIcon -Name $App.Name -Size 34
    $ic.Margin = New-Thickness 0, 0, 12, 0
    [System.Windows.Controls.DockPanel]::SetDock($ic, 'Left')
    $rp = New-Stack -Orientation Horizontal -Children @($state, $chk)
    $rp.VerticalAlignment = 'Center'
    $state.Margin = New-Thickness 0, 0, 8, 0
    [System.Windows.Controls.DockPanel]::SetDock($rp, 'Right')
    [void]$g.Children.Add($ic); [void]$g.Children.Add($rp); [void]$g.Children.Add($sp)
    $card = New-Card -Child $g -Padding (12, 10, 12, 10) -Background 'Panel'
    $card.ToolTip = $App.Desc
    $card.Cursor = 'Hand'
    $card.Tag = $chk
    $card.Add_MouseLeftButtonUp({ if ($this.Tag.IsEnabled) { $this.Tag.IsChecked = -not $this.Tag.IsChecked } })
    $script:PgUi.Checks[$App.Id] = @{ Check = $chk; State = $state; App = $App; Card = $card }
    Register-ProgramIcon -Icon $ic -Id $App.Id -Name $App.Name
    return $card
}

function Set-ProgramTab {
    param([string]$Tab)
    $ui = $script:PgUi
    $ui.Tab = $Tab
    foreach ($k in $ui.Tabs.Keys) {
        $b = $ui.Tabs[$k]
        $on = ($k -eq $Tab)
        $b.BorderBrush = if ($on) { Get-Brush 'Accent' } else { [System.Windows.Media.Brushes]::Transparent }
        $b.Foreground = if ($on) { Get-Brush 'Text' } else { Get-Brush 'Muted' }
    }
    $ui.InstallPane.Visibility = if ($Tab -eq 'install') { 'Visible' } else { 'Collapsed' }
    $ui.UpdPane.Root.Visibility = if ($Tab -eq 'updates') { 'Visible' } else { 'Collapsed' }
    $ui.InstPane.Root.Visibility = if ($Tab -eq 'installed') { 'Visible' } else { 'Collapsed' }
    $ui.Search.Visibility = if ($Tab -eq 'install') { 'Visible' } else { 'Collapsed' }
    $ui.Bar.Root.Visibility = if ($Tab -eq 'installed') { 'Collapsed' } else { 'Visible' }
    if ($Tab -eq 'updates' -and -not $ui.UpdLoaded) { Update-ProgramUpdates }
    Update-ProgramSelection
}

function Show-Page_programs {
    param($Arg)
    # Программу могли удалить и мимо PotatoPC (Параметры Windows) - список старше минуты перечитываем.
    $ui = $script:PgUi
    if (-not $ui.InstLoaded -or -not $ui.InstAt -or ((Get-Date) - $ui.InstAt).TotalSeconds -gt 60) { Update-ProgramInstalled }
    if (-not $script:PgUi.IconsStarted) { Start-ProgramIcons }
    Update-WorkshopState
}

# --- «Мастерская Potato»: свои установщики (core\Workshop.ps1) ---

function New-WorkshopSection {
    $ui = $script:PgUi
    $hdr = New-Object System.Windows.Controls.TextBlock
    $hdr.FontSize = 16; $hdr.FontWeight = 'Bold'; $hdr.Foreground = Get-Brush 'Text'; $hdr.VerticalAlignment = 'Bottom'
    $hdr.Inlines.Add((New-Object System.Windows.Documents.Run 'Мастерская '))
    $acc = New-Object System.Windows.Documents.Run 'Potato'; $acc.Foreground = Get-Brush 'Accent'
    $hdr.Inlines.Add($acc)
    $sub = New-Text -Text 'наши установщики - для того, что winget не умеет ставить правильно' -Size 12 -Color 'Muted' -Margin (10, 0, 0, 2)
    $sub.VerticalAlignment = 'Bottom'
    $top = New-Stack -Orientation Horizontal -Margin (0, 0, 0, 10) -Children @($hdr, $sub)

    # Сетка 3 колонки: карточка занимает две, в конце - место под будущие установщики.
    $g = New-Object System.Windows.Controls.Grid
    foreach ($i in 1..3) { [void]$g.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition)) }
    $row = 0; $col = 0
    $cells = @()
    foreach ($it in (Get-WorkshopItems)) {
        if ($col + 2 -gt 3) { $row++; $col = 0 }
        $cells += @{ El = (New-WorkshopCard -Item $it); Row = $row; Col = $col; Span = 2 }
        $col += 2
    }
    if ($col -ge 3) { $row++; $col = 0 }
    $ph = New-Object System.Windows.Controls.Grid
    $ph.MinHeight = 76
    $rect = New-Object System.Windows.Shapes.Rectangle
    $rect.Stroke = Get-Brush 'Line'; $rect.StrokeThickness = 1; $rect.RadiusX = 12; $rect.RadiusY = 12
    $rect.StrokeDashArray = New-Object System.Windows.Media.DoubleCollection (, [double[]]@(4, 3))
    $pt = New-Text -Text 'Здесь будут другие наши установщики' -Size 12 -Color 'Muted' -Wrap
    $pt.HorizontalAlignment = 'Center'; $pt.TextAlignment = 'Center'; $pt.Margin = New-Thickness 12
    [void]$ph.Children.Add($rect); [void]$ph.Children.Add($pt)
    $cells += @{ El = $ph; Row = $row; Col = $col; Span = (3 - $col) }
    foreach ($i in 0..$row) { [void]$g.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition)) }
    foreach ($c in $cells) {
        [System.Windows.Controls.Grid]::SetRow($c.El, $c.Row)
        [System.Windows.Controls.Grid]::SetColumn($c.El, $c.Col)
        [System.Windows.Controls.Grid]::SetColumnSpan($c.El, $c.Span)
        $c.El.Margin = New-Thickness 0, 0, $(if ($c.Col + $c.Span -lt 3) { 10 } else { 0 }), 10
        [void]$g.Children.Add($c.El)
    }
    return (New-Stack -Margin (0, 0, 0, 14) -Children @($top, $g))
}

function New-WorkshopCard {
    param($Item)
    $ui = $script:PgUi
    $ic = New-AppIcon -Name $Item.Name -Size 44
    $ic.Margin = New-Thickness 0, 0, 16, 0
    [System.Windows.Controls.DockPanel]::SetDock($ic, 'Left')
    Register-ProgramIcon -Icon $ic -Id $Item.Id -Name $Item.Name
    $state = New-Text -Text $Item.Size -Size 12 -Color 'Muted' -Margin (0, 0, 16, 0)
    $btn = New-Button -Text 'Настроить и установить' -Kind Primary -Tag $Item.Id -OnClick { Start-WorkshopItem -Id ([string]$this.Tag) }
    $rp = New-Stack -Orientation Horizontal -Children @($state, $btn)
    $rp.VerticalAlignment = 'Center'
    [System.Windows.Controls.DockPanel]::SetDock($rp, 'Right')
    $title = New-Stack -Orientation Horizontal -Children @((New-Text -Text $Item.Name -Size 16 -Weight 'SemiBold'))
    if ($Item.Badge) { $bd = New-Badge $Item.Badge 'info'; $bd.Margin = New-Thickness 10, 0, 0, 0; [void]$title.Children.Add($bd) }
    $main = New-Stack -Children @($title, (New-Text -Text $Item.Desc -Size 12 -Color 'Muted' -Wrap -Margin (0, 4, 0, 0)))
    $main.VerticalAlignment = 'Center'
    $dp = New-Object System.Windows.Controls.DockPanel
    [void]$dp.Children.Add($ic); [void]$dp.Children.Add($rp); [void]$dp.Children.Add($main)
    $card = New-Card -Child $dp -Padding (16, 14, 16, 14) -Background 'Card' -Border '#5A4A1A'
    $ui.Workshop[$Item.Id] = @{ Card = $card; State = $state; Btn = $btn; Item = $Item; Busy = $false }
    return $card
}

function Start-WorkshopItem {
    param([string]$Id)
    switch ($Id) {
        'potato.office' { Show-OfficeSetup }
    }
}

function Update-WorkshopState {
    # Что из «Мастерской» уже стоит (реестр - быстро, но в фоне, чтобы не тормозить вкладку).
    Start-BgTask -Name 'Мастерская: что установлено' -Silent -Script { return @{ Office = (Get-OfficeState) } } -OnDone {
        param($r)
        $ui = $script:PgUi
        if (-not $r -or -not $ui -or -not $ui.Workshop.ContainsKey('potato.office')) { return }
        $w = $ui.Workshop['potato.office']
        if ($w.Busy) { return }
        $st = $r.Office
        if ($st -and $st.C2R) {
            $w.State.Text = 'Установлено: ' + ((@($st.Products) | ForEach-Object { Get-OfficeProductTitle $_ }) -join ', ')
            $w.State.Foreground = Get-Brush 'Ok'
        } else {
            $w.State.Text = $w.Item.Size
            $w.State.Foreground = Get-Brush 'Muted'
        }
    } | Out-Null
}

function Show-OfficeSetup {
    $ui = $script:PgUi
    if ($ui.Workshop['potato.office'].Busy) { return }
    $is64 = [Environment]::Is64BitOperatingSystem
    $script:OfcDlg = @{ Edition = 'std2024'; Bits = $(if ($is64) { '64' } else { '32' }); Is64 = $is64; St = (Get-OfficeState); Cards = @{}; Langs = @(); Apps = @{}; Key = $null; BitBtns = @{}; Opt = $null }
    $ok = Show-FormDialog -Title 'Установка Microsoft Office' -Width 740 -OkText 'Установить Office' -Build {
        param($f)
        $d = $script:OfcDlg
        [void]$f.Children.Add((New-Text -Text 'Скачивается с серверов Microsoft (officecdn.microsoft.com). После установки временные файлы удаляются.' -Size 12 -Color 'Muted' -Wrap -Margin (0, 0, 0, 4)))

        [void]$f.Children.Add((New-Text -Text 'РЕДАКЦИЯ' -Size 12 -Color 'Muted' -Weight 'SemiBold' -Margin (0, 14, 0, 8)))
        $eds = @()
        $all = Get-OfficeEditions
        foreach ($k in $all.Keys) {
            $e = $all[$k]
            $r = New-Object System.Windows.Controls.RadioButton
            $r.Style = $script:Window.FindResource('Radio')
            $r.GroupName = 'ofced'; $r.Tag = $k; $r.IsChecked = ($k -eq $d.Edition)
            $r.Content = New-Stack -Children @((New-Text -Text $e.Title -Size 14 -Weight 'SemiBold'), (New-Text -Text $e.Sub -Size 12 -Color 'Muted' -Wrap -Margin (0, 3, 0, 0)))
            $r.Add_Checked({ $script:OfcDlg.Edition = [string]$this.Tag; Update-OfficeDialog })
            # Стиль Radio сам рисует карточку и подсвечивает выбранную.
            $d.Cards[$k] = $r
            $eds += $r
        }
        [void]$f.Children.Add((New-Grid -Columns 3 -Items $eds -Gap 10))

        [void]$f.Children.Add((New-Text -Text 'ЯЗЫКИ' -Size 12 -Color 'Muted' -Weight 'SemiBold' -Margin (0, 6, 0, 8)))
        $os = Get-OsOfficeLanguage
        $names = Get-OfficeLanguages
        $order = @(); if ($os) { $order += $os }; foreach ($c in $names.Keys) { if ($order -notcontains $c) { $order += $c } }
        $ls = New-Stack -Orientation Horizontal
        foreach ($c in $order) {
            $on = ($c -eq $os) -or ($c -eq 'en-us') -or (-not $os -and $c -eq 'ru-ru')
            $cb = New-CheckBox -Text ($names[$c] + $(if ($c -eq $os) { ' · как в Windows' } else { '' })) -Checked $on -Tag $c
            $cb.Margin = New-Thickness 0, 0, 22, 0
            $d.Langs += $cb
            [void]$ls.Children.Add($cb)
        }
        [void]$f.Children.Add($ls)
        [void]$f.Children.Add((New-Text -Text 'Первый отмеченный язык будет языком интерфейса, остальные - для проверки орфографии.' -Size 12 -Color 'Muted' -Wrap -Margin (0, 8, 0, 0)))

        [void]$f.Children.Add((New-Text -Text 'ПРИЛОЖЕНИЯ' -Size 12 -Color 'Muted' -Weight 'SemiBold' -Margin (0, 16, 0, 8)))
        $apps = @()
        $an = Get-OfficeApps
        foreach ($a in $an.Keys) {
            $cb = New-CheckBox -Text $an[$a] -Checked ($a -in @('Word', 'Excel', 'PowerPoint', 'Outlook')) -Tag $a
            $d.Apps[$a] = $cb
            $apps += (New-Card -Child $cb -Padding (12, 8, 12, 8) -Background 'Panel')
        }
        [void]$f.Children.Add((New-Grid -Columns 3 -Items $apps -Gap 8))

        $kg = New-Object System.Windows.Controls.Grid
        [void]$kg.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
        $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = 'Auto'; [void]$kg.ColumnDefinitions.Add($c2)
        $d.Key = New-TextInput -Placeholder 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX'
        $d.KeyField = New-Field -Label 'Ключ продукта · необязательно' -Control $d.Key -Margin (0, 0, 16, 0)
        [void]$kg.Children.Add($d.KeyField)
        $bs = New-Stack -Orientation Horizontal
        foreach ($b in @('64', '32')) {
            $bb = New-Button -Text ($b + ' бит') -Kind Chip -Tag $b -OnClick { $script:OfcDlg.Bits = [string]$this.Tag; Update-OfficeDialog }
            $bb.Margin = New-Thickness 0, 0, 6, 0
            if ($b -eq '64' -and -not $d.Is64) { $bb.IsEnabled = $false }
            $d.BitBtns[$b] = $bb
            [void]$bs.Children.Add($bb)
        }
        $bf = New-Field -Label 'Разрядность' -Control $bs -Margin (0, 0, 0, 0)
        $bf.VerticalAlignment = 'Bottom'
        [System.Windows.Controls.Grid]::SetColumn($bf, 1)
        [void]$kg.Children.Add($bf)
        $kg.Margin = New-Thickness 0, 8, 0, 0
        [void]$f.Children.Add($kg)
        $d.KeyHint = New-Text -Text '' -Size 12 -Color 'Muted' -Wrap -Margin (0, 8, 0, 12)
        [void]$f.Children.Add($d.KeyHint)

        $d.Warn = New-Hint -Text '' -Kind 'warn' -Margin (0, 0, 0, 8)
        $d.Info = New-Hint -Text '' -Kind 'info' -Margin (0, 0, 0, 8)
        [void]$f.Children.Add($d.Warn); [void]$f.Children.Add($d.Info)
        [void]$f.Children.Add((New-Text -Text '≈ 3 ГБ скачивания · 15-30 минут' -Size 12 -Color 'Muted' -Margin (0, 4, 0, 4)))
        Update-OfficeDialog
    } -OnOk {
        param($f)
        $d = $script:OfcDlg
        $langs = @($d.Langs | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag })
        if ($langs.Count -eq 0) { return 'Выберите хотя бы один язык.' }
        $apps = @($d.Apps.Keys | Where-Object { $d.Apps[$_].IsChecked -and $d.Apps[$_].IsEnabled })
        if ($apps.Count -eq 0) { return 'Выберите хотя бы одно приложение.' }
        $ed = (Get-OfficeEditions)[$d.Edition]
        $key = ''
        if ($ed.Key) {
            $key = ([string]$d.Key.Text).Trim().ToUpperInvariant() -replace '\s', ''
            if ($key -and -not (Test-OfficeKey $key)) { return 'Ключ должен выглядеть так: XXXXX-XXXXX-XXXXX-XXXXX-XXXXX.' }
        }
        $d.Opt = @{ Edition = $d.Edition; Langs = $langs; Apps = $apps; Key = $key; Bits = $d.Bits }
        return $true
    }
    if ($ok -and $script:OfcDlg.Opt) { Start-OfficeInstall -Opt $script:OfcDlg.Opt }
}

function Update-OfficeDialog {
    $d = $script:OfcDlg
    if (-not $d -or -not $d.KeyHint) { return }
    $ed = (Get-OfficeEditions)[$d.Edition]
    foreach ($b in $d.BitBtns.Keys) { Set-ChipActive -Button $d.BitBtns[$b] -Active ($b -eq $d.Bits) }
    $acc = $d.Apps['Access']
    $acc.IsEnabled = [bool]$ed.Access
    if (-not $ed.Access) { $acc.IsChecked = $false }
    $acc.ToolTip = if ($ed.Access) { $null } else { 'Access есть только в Pro Plus и Microsoft 365' }
    $d.KeyField.IsEnabled = [bool]$ed.Key
    $d.KeyField.Opacity = if ($ed.Key) { 1.0 } else { 0.45 }
    $d.KeyHint.Text = if ($ed.Key) { 'Без ключа Office установится и попросит активацию при первом запуске.' } else { 'Microsoft 365 активируется входом в аккаунт Microsoft с подпиской - ключ не нужен.' }
    $st = $d.St
    $warn = @(); $info = ''
    if (@($st.Msi).Count) { $warn += ('Найден ' + (@($st.Msi) -join ', ') + '.') }
    if ($st.C2R) {
        $t = (@($st.Products) | ForEach-Object { Get-OfficeProductTitle $_ }) -join ', '
        if (@($st.Products) -contains $ed.Product) { $info = 'Уже установлен ' + $t + '. Установка изменит языки и состав приложений.' }
        else { $warn += ('Установлен ' + $t + '.') }
    }
    $d.Warn.Visibility = if ($warn.Count) { 'Visible' } else { 'Collapsed' }
    if ($warn.Count) { $d.Warn.Child.Children[1].Text = (($warn -join ' ') + ' Перед установкой он будет удалён - две версии Office вместе не работают. Документы и настройки не пострадают.') }
    $d.Info.Visibility = if ($info) { 'Visible' } else { 'Collapsed' }
    if ($info) { $d.Info.Child.Children[1].Text = $info }
}

function Start-OfficeInstall {
    param([hashtable]$Opt)
    $w = $script:PgUi.Workshop['potato.office']
    $w.Busy = $true
    $w.Btn.IsEnabled = $false
    Set-ButtonText -Button $w.Btn -Text 'Устанавливается…'
    $w.State.Text = 'Скачивание и установка, 15-30 минут'
    $w.State.Foreground = Get-Brush 'Accent'
    Start-BgTask -Name 'Установка Microsoft Office' -Vars @{ Opt = $Opt } -Script { Install-OfficeOdt -Opt $Opt } -OnDone {
        param($r)
        $w = $script:PgUi.Workshop['potato.office']
        $w.Busy = $false
        $w.Btn.IsEnabled = $true
        Set-ButtonText -Button $w.Btn -Text 'Настроить и установить'
        Update-WorkshopState
        if ($script:UnUi) { $script:UnUi.Loaded = $false }
        if ($r -and $r.Ok) { Show-Info ($r.Title + ' установлен.') }
        elseif ($r -and $r.Why -ne 'отменено') { Show-Info -Message ("Office не установился:`n" + $r.Why + "`n`nПодробности в журнале.") -Icon 'Warning' }
    } | Out-Null
}

function Start-ProgramIcons {
    # Настоящие значки вместо квадратов с буквой: каталог - с сайта программы (один раз, потом из data\icons),
    # остальное - из exe установленных программ.
    $ui = $script:PgUi
    $ui.IconsStarted = $true
    $apps = @()
    foreach ($cn in $ui.Catalog.Categories.Keys) { foreach ($a in $ui.Catalog.Categories[$cn]) { $apps += @{ Id = $a.Id; Site = $a.Site } } }
    foreach ($a in (Get-WorkshopItems)) { $apps += @{ Id = $a.Id; Site = $a.Site } }
    Start-BgTask -Name 'Значки программ' -Silent -Vars @{ Apps = $apps } -Script {
        $byName = @{}; $byId = @{}
        try { $byName = Get-ProgramIconIndex } catch {}
        try { $byId = Get-CatalogIcons -Apps $Apps } catch {}
        return @{ ById = $byId; ByName = $byName }
    } -OnDone {
        param($r)
        $ui = $script:PgUi
        if (-not $r) { $ui.IconsStarted = $false; return }
        $ui.IconData = $r
        foreach ($t in @($ui.IconTargets)) { Set-ProgramIcon -Target $t }
    } | Out-Null
}

function Register-ProgramIcon {
    param($Icon, [string]$Id, [string]$Name)
    $ui = $script:PgUi
    $t = @{ Icon = $Icon; Id = $Id; Name = $Name }
    [void]$ui.IconTargets.Add($t)
    if ($ui.IconData) { Set-ProgramIcon -Target $t }
}

function Set-ProgramIcon {
    param($Target)
    $d = $script:PgUi.IconData
    if (-not $d) { return }
    $png = $null
    if ($Target.Id -and $d.ById -and $d.ById.ContainsKey($Target.Id)) { $png = $d.ById[$Target.Id] }
    if (-not $png -and $d.ByName) { $png = Find-ProgramIconByName -Index $d.ByName -Names @($Target.Name, $Target.Id, (([string]$Target.Id) -split '\.')[-1]) }
    if ($png) { [void](Set-AppIconPng -Icon $Target.Icon -Png $png) }
}

function Update-ProgramInstalled {
    $ui = $script:PgUi
    $ui.InstLoaded = $true
    $ui.InstAt = Get-Date
    $ui.InstPane.Body.Children.Clear()
    [void]$ui.InstPane.Body.Children.Add((New-Placeholder 'Спрашиваю winget…'))
    Start-BgTask -Name 'Список программ' -Script { $r = Get-WingetInstalled; if ($null -eq $r) { return @{ Missing = $true } }; return @{ List = @($r) } } -OnDone {
        param($r)
        $ui = $script:PgUi
        $ui.InstPane.Body.Children.Clear()
        Clear-ProgramIconTargets -Kind 'inst'
        if (-not $r -or $r.Missing) { $ui.Missing.Visibility = 'Visible'; $ui.InstLoaded = $false; return }
        $ui.Installed = @{}
        foreach ($p in $r.List) { $ui.Installed[$p.Id] = $p.Version }
        foreach ($k in $ui.Checks.Keys) {
            $c = $ui.Checks[$k]
            if ($ui.Installed.ContainsKey($k)) { $c.State.Text = 'Установлено'; $c.Check.IsChecked = $false; $c.Check.IsEnabled = $false; $c.Check.Visibility = 'Collapsed' }
            elseif ($c.State.Text -eq 'Установлено') {
                # Программу удалили (здесь, на «Удалении программ» или в Windows) - карточку снова можно отметить.
                $c.State.Text = ''; $c.Check.IsEnabled = $true; $c.Check.Visibility = 'Visible'
            }
        }
        $names = @{}
        foreach ($cn in $ui.Catalog.Categories.Keys) { foreach ($a in $ui.Catalog.Categories[$cn]) { $names[$a.Id] = $a.Name } }
        foreach ($p in @($r.List | Sort-Object { if ($names[$_.Id]) { $names[$_.Id] } else { $_.Id } })) {
            $nm = if ($names[$p.Id]) { $names[$p.Id] } else { ($p.Id -split '\.')[-1] }
            $un = New-Button -Text 'Удалить' -Kind SmallDanger -Tag $p.Id -OnClick {
                $id = [string]$this.Tag
                if (-not (Show-Confirm -Message ('Удалить программу ' + $id + '?') -Warning)) { return }
                Start-BgTask -Name ('Удаление ' + $id) -Vars @{ Id = $id } -Script { Install-WingetPackages -Ids @($Id) -Mode uninstall } -OnDone { Update-ProgramInstalled; if ($script:UnUi) { $script:UnUi.Loaded = $false } } | Out-Null
            }
            $ic = New-AppIcon -Name $nm -Size 32
            Register-ProgramIcon -Icon $ic -Id $p.Id -Name $nm
            $ic.Tag = 'inst'
            $row = New-Row -Left $ic -Main (New-TitleBlock -Title $nm -Sub ($p.Id + '  ·  ' + $p.Version)) -Right @($un) -Padding (16, 8, 12, 8)
            [void]$ui.InstPane.Body.Children.Add($row)
        }
        $ui.InstPane.Header.Text = 'Установленные программы (известные winget) · ' + $r.List.Count
        if (-not $ui.UpdLoaded) { Update-ProgramUpdates }
    } | Out-Null
}

function Update-ProgramUpdates {
    $ui = $script:PgUi
    $ui.UpdLoaded = $true
    $ui.UpdPane.Body.Children.Clear()
    [void]$ui.UpdPane.Body.Children.Add((New-Placeholder 'Проверяю обновления…'))
    Start-BgTask -Name 'Проверка обновлений программ' -Script { $r = Get-WingetUpgrades; if ($null -eq $r) { return @{ Missing = $true } }; return @{ List = @($r) } } -OnDone {
        param($r)
        $ui = $script:PgUi
        $ui.UpdPane.Body.Children.Clear()
        $ui.UpdChecks = @{}
        Clear-ProgramIconTargets -Kind 'upd'
        if (-not $r -or $r.Missing) { $ui.Missing.Visibility = 'Visible'; $ui.UpdLoaded = $false; return }
        # Office обновляется сам (Click-to-Run) - winget по нему только путается в версиях.
        $r.List = @($r.List | Where-Object { $_.Id -notlike 'Microsoft.Office*' })
        if ($r.List.Count -eq 0) { [void]$ui.UpdPane.Body.Children.Add((New-Placeholder 'Все программы, которые знает winget, обновлены.')) }
        foreach ($u in $r.List) {
            $chk = New-CheckBox -Checked $true -Tag $u.Id -OnChange { Update-ProgramSelection }
            $ver = New-Text -Text ($u.Version + '  →  ' + $u.Available) -Size 12 -Color 'Muted' -Mono
            $ic = New-AppIcon -Name $u.Name -Size 30
            $ic.Tag = 'upd'
            Register-ProgramIcon -Icon $ic -Id $u.Id -Name $u.Name
            $row = New-Row -Left $chk -Main (New-Stack -Orientation Horizontal -Children @($ic, (New-TitleBlock -Title $u.Name -Sub $u.Id))) -Right @($ver) -Padding (16, 8, 16, 8)
            $row.Child.Children[1].Children[1].Margin = New-Thickness 12, 0, 0, 0
            [void]$ui.UpdPane.Body.Children.Add($row)
            $ui.UpdChecks[$u.Id] = $chk
        }
        $ui.UpdPane.Header.Text = 'Доступные обновления · ' + $r.List.Count
        Set-ButtonText -Button $ui.Tabs['updates'] -Text ('Обновления · ' + $r.List.Count)
        Update-ProgramSelection
    } | Out-Null
}

function Clear-ProgramIconTargets {
    # Строки списка пересоздаются - старые квадраты больше не нужны.
    param([string]$Kind)
    $ui = $script:PgUi
    foreach ($t in @($ui.IconTargets)) { if ([string]$t.Icon.Tag -eq $Kind) { $ui.IconTargets.Remove($t) } }
}

function Update-ProgramFilter {
    $ui = $script:PgUi
    $q = ([string]$ui.Search.Text).Trim().ToLowerInvariant()
    foreach ($c in $ui.Checks.Values) {
        if ($c.Search) { continue }
        $ok = (-not $q) -or (($c.App.Name + ' ' + $c.App.Id + ' ' + $c.App.Desc).ToLowerInvariant().Contains($q))
        $c.Card.Visibility = if ($ok) { 'Visible' } else { 'Collapsed' }
    }
    foreach ($p in $ui.CatPanels) {
        $any = $false
        foreach ($ch in $p.Grid.Children) { if ($ch.Visibility -eq 'Visible') { $any = $true; break } }
        $p.Panel.Visibility = if ($any) { 'Visible' } else { 'Collapsed' }
    }
    Set-ButtonText -Button $ui.SearchBtn -Text $(if ($q) { 'Искать «' + $ui.Search.Text.Trim() + '» в каталоге winget (Enter)' } else { 'Искать в каталоге winget' })
}

function Start-WingetSearch {
    $ui = $script:PgUi
    $q = ([string]$ui.Search.Text).Trim()
    if ($q.Length -lt 2) { return }
    $ui.SearchPane.Root.Visibility = 'Visible'
    $ui.SearchPane.Body.Children.Clear()
    [void]$ui.SearchPane.Body.Children.Add((New-Placeholder ('Ищу «' + $q + '»…')))
    Start-BgTask -Name 'Поиск в winget' -Vars @{ Q = $q } -Script { $r = Search-Winget -Query $Q; if ($null -eq $r) { return @{ Missing = $true } }; return @{ List = @($r) } } -OnDone {
        param($r)
        $ui = $script:PgUi
        $ui.SearchPane.Body.Children.Clear()
        Clear-ProgramIconTargets -Kind 'search'
        if (-not $r -or $r.Missing) { $ui.Missing.Visibility = 'Visible'; return }
        if ($r.List.Count -eq 0) { [void]$ui.SearchPane.Body.Children.Add((New-Placeholder 'Ничего не нашлось.')); return }
        foreach ($a in $r.List) {
            if ($ui.Checks.ContainsKey($a.Id) -and -not $ui.Checks[$a.Id].Search) { continue }
            $chk = New-CheckBox -Tag $a.Id -OnChange { Update-ProgramSelection }
            $inst = if ($ui.Installed.ContainsKey($a.Id)) { New-Badge 'Установлено' 'ok' } else { $null }
            if ($inst) { $chk.IsEnabled = $false }
            $ic = New-AppIcon -Name $a.Name -Size 30
            $ic.Tag = 'search'
            Register-ProgramIcon -Icon $ic -Id $a.Id -Name $a.Name
            $tb = New-TitleBlock -Title $a.Name -Sub ($a.Id + '  ·  ' + $a.Version)
            $tb.Margin = New-Thickness 12, 0, 0, 0
            $row = New-Row -Left $chk -Main (New-Stack -Orientation Horizontal -Children @($ic, $tb)) -Right @($inst) -Padding (16, 8, 16, 8)
            [void]$ui.SearchPane.Body.Children.Add($row)
            $ui.Checks[$a.Id] = @{ Check = $chk; State = (New-Text ''); App = @{ Name = $a.Name; Id = $a.Id; Desc = '' }; Card = $row; Search = $true }
        }
    } | Out-Null
}

function Update-ProgramSelection {
    $ui = $script:PgUi
    if (-not $ui -or -not $ui.Bar) { return }
    $t = $ui.Bar.Text
    $t.Inlines.Clear()
    if ($ui.Tab -eq 'updates') {
        $n = @($ui.UpdChecks.Values | Where-Object { $_.IsChecked }).Count
        $t.Inlines.Add((New-Object System.Windows.Documents.Bold (New-Object System.Windows.Documents.Run ([string]$n))))
        $t.Inlines.Add((New-Object System.Windows.Documents.Run ' выбрано для обновления'))
        Set-ButtonText -Button $ui.ActBtn -Text 'Обновить'
        $ui.ActBtn.IsEnabled = ($n -gt 0)
    } else {
        $n = @($ui.Checks.Values | Where-Object { $_.Check.IsChecked }).Count
        $t.Inlines.Add((New-Object System.Windows.Documents.Bold (New-Object System.Windows.Documents.Run ([string]$n))))
        $r = New-Object System.Windows.Documents.Run ' выбрано · тихая установка через winget'
        $r.Foreground = Get-Brush 'Muted'
        $t.Inlines.Add($r)
        Set-ButtonText -Button $ui.ActBtn -Text 'Установить'
        $ui.ActBtn.IsEnabled = ($n -gt 0)
    }
}

function Start-ProgramAction {
    $ui = $script:PgUi
    if ($ui.Tab -eq 'updates') {
        $ids = @($ui.UpdChecks.Keys | Where-Object { $ui.UpdChecks[$_].IsChecked })
        $mode = 'upgrade'
    } else {
        $ids = @($ui.Checks.Keys | Where-Object { $ui.Checks[$_].Check.IsChecked })
        $mode = 'install'
    }
    if ($ids.Count -eq 0) { return }
    $verb = if ($mode -eq 'install') { 'Установить' } else { 'Обновить' }
    if (-not (Show-Confirm -Message ($verb + ' (' + $ids.Count + "):`n  • " + ($ids -join "`n  • ")) -Title 'Программы')) { return }
    $ui.ActBtn.IsEnabled = $false
    Start-BgTask -Name ($verb + ' программы') -Vars @{ Ids = $ids; Mode = $mode } -Script { Install-WingetPackages -Ids $Ids -Mode $Mode } -OnDone {
        param($r)
        $ui = $script:PgUi
        foreach ($c in $ui.Checks.Values) { $c.Check.IsChecked = $false }
        if ($r -and $r.Fail.Count) { Show-Info -Message ("Не получилось:`n" + ($r.Fail -join "`n") + "`n`nПодробности в журнале.") -Icon 'Warning' }
        $ui.UpdLoaded = $false
        Update-ProgramInstalled
        if ($script:UnUi) { $script:UnUi.Loaded = $false }
    } | Out-Null
}

function Start-WingetSetup {
    $ui = $script:PgUi
    if (-not (Show-Confirm -Message ('Установить winget (App Installer)?' + "`n`n" + 'Сначала PotatoPC попробует включить уже встроенный в Windows установщик. Если его нет - скачает около 300 МБ с официального GitHub Microsoft (microsoft/winget-cli) и проверит цифровую подпись перед установкой.') -Title 'winget')) { return }
    $ui.WgBtn.IsEnabled = $false
    Set-ButtonText -Button $ui.WgBtn -Text 'Устанавливаю…'
    Start-BgTask -Name 'Установка winget' -Script { Install-WingetClient } -OnDone {
        param($ok)
        $ui = $script:PgUi
        $ui.WgBtn.IsEnabled = $true
        Set-ButtonText -Button $ui.WgBtn -Text 'Установить winget'
        if ($ok) {
            $ui.Missing.Visibility = 'Collapsed'
            $ui.InstLoaded = $false; $ui.UpdLoaded = $false
            Update-ProgramInstalled
            Show-Info 'winget установлен - установка и обновление программ доступны.'
        } else {
            if (Show-Confirm -Message ('Автоматически поставить не получилось (подробности в журнале).' + "`n`n" + 'Открыть страницу «Установщик приложений» в Microsoft Store?') -Title 'winget') { Open-Path 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1' }
        }
    } | Out-Null
}
