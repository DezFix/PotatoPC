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
    if ($cat.Kits.Count -gt 0) {
        [void]$ui.InstallPane.Children.Add((New-Text -Text 'Наборы' -Size 16 -Weight 'SemiBold' -Margin (0, 0, 0, 12)))
        $kits = @()
        foreach ($k in $cat.Kits) {
            $b = New-Object System.Windows.Controls.Button
            $b.Style = $script:Window.FindResource('BtnSecondary')
            $b.HorizontalContentAlignment = 'Stretch'; $b.Padding = New-Thickness 16, 12, 16, 12
            $b.Tag = $k
            $sp = New-Stack
            [void]$sp.Children.Add((New-Text -Text $k.Name -Size 15 -Weight 'Bold'))
            $d = New-Text -Text $k.Desc -Size 12 -Color 'Muted' -Wrap -Margin (0, 4, 0, 4); $d.FontWeight = 'Normal'
            [void]$sp.Children.Add($d)
            [void]$sp.Children.Add((New-Text -Text ([string]@($k.Ids).Count + ' программ') -Size 12 -Color 'Accent' -Weight 'SemiBold'))
            $b.Content = $sp
            $b.Add_Click({ foreach ($id in @($this.Tag.Ids)) { if ($script:PgUi.Checks.ContainsKey($id) -and $script:PgUi.Checks[$id].Check.IsEnabled) { $script:PgUi.Checks[$id].Check.IsChecked = $true } }; Update-ProgramSelection })
            $kits += $b
        }
        [void]$ui.InstallPane.Children.Add((New-Grid -Columns 3 -Items $kits))
    }
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
    if (-not $script:PgUi.InstLoaded) { Update-ProgramInstalled }
    if (-not $script:PgUi.IconsStarted) { Start-ProgramIcons }
}

function Start-ProgramIcons {
    # Настоящие значки вместо квадратов с буквой: каталог - с сайта программы (один раз, потом из data\icons),
    # остальное - из exe установленных программ.
    $ui = $script:PgUi
    $ui.IconsStarted = $true
    $apps = @()
    foreach ($cn in $ui.Catalog.Categories.Keys) { foreach ($a in $ui.Catalog.Categories[$cn]) { $apps += @{ Id = $a.Id; Site = $a.Site } } }
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
