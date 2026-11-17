# PAGE: tweaks
# TITLE: Твики
# ICON: bolt
# ORDER: 20

$script:TwUi = $null
$script:PluginStatesStamp = $null

function Build-Page_tweaks {
    $ui = @{ Rows = @{}; Sections = @{}; Chips = @{}; Filter = 'all'; PresetChips = @{} }
    $ui.Search = New-TextInput -Placeholder 'Поиск по твикам' -Width 260
    $ui.Search.Add_TextChanged({ Update-TweakFilter })
    $reload = New-Button -Text 'Обновить' -Icon 'refresh' -ToolTip 'Перечитать папку scripts (например, после добавления плагина)' -OnClick { Initialize-TweakList -Reload }
    $ab = New-ActionBar
    $ui.Bar = $ab
    $ui.RpChk = New-CheckBox -Text 'Точка восстановления' -Checked $true -ToolTip 'Создать точку восстановления Windows перед изменениями'
    $ui.RebootChk = New-CheckBox -Text 'Перезагрузить после'
    $ui.ApplyBtn = New-Button -Text 'Применить' -Icon 'play' -Kind Primary -OnClick { Start-TweakApply }
    foreach ($x in @($ui.RpChk, $ui.RebootChk, $ui.ApplyBtn)) { $x.Margin = New-Thickness 22, 0, 0, 0; $x.VerticalAlignment = 'Center'; [void]$ab.Right.Children.Add($x) }
    $L = New-PageLayout -Title 'Твики' -Subtitle 'Каждый твик - отдельный скрипт-плагин. Отметьте нужные и примените.' -HeaderRight @($ui.Search, $reload) -ActionBar $ab.Root
    $ui.Body = $L.Body
    $ui.Scroll = $L.Scroll

    $ui.ChipPanel = New-Object System.Windows.Controls.WrapPanel
    [void]$L.Body.Children.Add($ui.ChipPanel)
    $pp = New-Object System.Windows.Controls.WrapPanel
    $pp.Margin = New-Thickness 0, 0, 0, 10
    $pl = New-Text -Text 'Отметить пресет:' -Size 13 -Color 'Muted' -Margin (0, 0, 10, 8)
    [void]$pp.Children.Add($pl)
    foreach ($k in @('potato', 'office', 'game')) {
        $b = New-Button -Text $script:PresetInfo[$k].Title -Kind Chip -Tag $k -OnClick { Select-TweakPreset -Preset $this.Tag }
        $ui.PresetChips[$k] = $b
        [void]$pp.Children.Add($b)
    }
    $none = New-Button -Text 'Снять всё' -Kind Chip -OnClick { Select-TweakPreset -Preset '' }
    [void]$pp.Children.Add($none)
    [void]$L.Body.Children.Add($pp)
    $ui.List = New-Stack
    [void]$L.Body.Children.Add($ui.List)

    $drop = New-Stack -Orientation Horizontal
    [void]$drop.Children.Add((New-Icon -Name 'plug' -Size 20 -Color 'Muted'))
    $dt = New-Text -Text ('Свои плагины: положите .ps1 с шапкой # NAME / # DESC / # TAGS в папку scripts\<раздел>\ - он появится здесь после «Обновить». Подробности - docs\PLUGINS.md.') -Size 13 -Color 'Muted' -Wrap -Margin (12, 0, 12, 0)
    $dt.MaxWidth = 620
    [void]$drop.Children.Add($dt)
    $of = New-Button -Text 'Открыть папку' -Kind Ghost -OnClick { Open-Path $ScriptsFolder }
    [void]$drop.Children.Add($of)
    $dc = New-Card -Child $drop -Padding (16, 12, 16, 12) -Margin (0, 0, 0, 16) -Background 'Bg'
    $dc.BorderBrush = Get-Brush '#3A404C'
    $dc.BorderThickness = New-Thickness 1.5
    [void]$L.Body.Children.Add($dc)

    $script:TwUi = $ui
    Initialize-TweakList
    return $L.Root
}

function Show-Page_tweaks {
    param($Arg)
    if ($Arg -and $Arg.Preset) { Select-TweakPreset -Preset $Arg.Preset }
    if ($Arg -and $Arg.Category) { Set-TweakFilter -Filter $Arg.Category }
    if (-not $script:PluginStatesStamp -or ((Get-Date) - $script:PluginStatesStamp).TotalMinutes -gt 2) { Update-TweakStates }
}

function Initialize-TweakList {
    param([switch]$Reload)
    $ui = $script:TwUi
    $checked = @{}
    foreach ($k in $ui.Rows.Keys) { if ($ui.Rows[$k].Check.IsChecked) { $checked[$k] = $true } }
    $plugins = @(Get-Plugins -Force:$Reload | Where-Object { -not $_.IsUndo })
    $ui.Plugins = $plugins
    $ui.Rows = @{}; $ui.Sections = @{}
    $ui.List.Children.Clear()
    $ui.ChipPanel.Children.Clear(); $ui.Chips = @{}
    $mk = {
        param($id, $text)
        $b = New-Button -Text $text -Kind Chip -Tag $id -OnClick { Set-TweakFilter -Filter $this.Tag }
        $script:TwUi.Chips[$id] = $b
        [void]$script:TwUi.ChipPanel.Children.Add($b)
    }
    & $mk 'all' ('Все  ' + $plugins.Count)
    $applied = Get-LastApplied
    foreach ($grp in @($plugins | Group-Object CatNum | Sort-Object Name)) {
        $first = $grp.Group[0]
        & $mk $grp.Name ($first.Category + '  ' + $grp.Count)
        $undo = @(Get-UndoPlugins -CatNum $grp.Name)
        $right = @()
        if ($undo.Count -gt 0) {
            $right += New-Button -Text 'Откатить раздел' -Icon 'undo' -Kind Ghost -Tag $grp.Name -OnClick { Start-TweakUndo -CatNum $this.Tag }
        }
        $sec = New-Section -Title $first.Category -Right $right
        foreach ($p in $grp.Group) {
            $chk = New-CheckBox -Checked ([bool]$checked[$p.Id]) -Tag $p.Id -OnChange { Update-TweakSelection }
            $iconName = if ($script:IconPaths.ContainsKey($p.Icon)) { $p.Icon } elseif ($script:CategoryIcons.ContainsKey($p.CatNum)) { $script:CategoryIcons[$p.CatNum] } else { 'plug' }
            $tile = New-IconTile -Icon $iconName -Color $(if ($p.Trusted) { 'Accent' } else { 'Info' })
            $left = New-Stack -Orientation Horizontal -Children @($chk, $tile)
            $tile.Margin = New-Thickness 12, 0, 0, 0
            $sub = $p.Desc
            if (-not $p.Applicable) { $sub = 'Только для Windows 11. ' + $sub }
            $main = New-TitleBlock -Title $p.Name -Sub $sub
            $main.Children[1].TextTrimming = 'CharacterEllipsis'
            $main.ToolTip = $p.Desc
            $status = New-Text -Text '' -Size 11 -Color 'Ok'
            if ($applied.ContainsKey($p.Id)) { $status.Text = '✓ применено ' + ([datetime]$applied[$p.Id]).ToString('dd.MM') }
            $right = @($status)
            if (-not $p.Trusted) { $right += New-Badge 'Сторонний плагин' 'info' }
            foreach ($pr in $p.Presets) { if ($script:PresetInfo.Contains($pr)) { $right += New-OutlineChip $script:PresetInfo[$pr].Title } }
            $right += New-RiskBadge $p.Risk
            $code = New-Button -Text '' -Icon 'term' -Kind Ghost -Tag $p.Path -ToolTip 'Показать код скрипта' -OnClick { Start-Process notepad.exe -ArgumentList ('"' + $this.Tag + '"') }
            $code.Content.Children[1].Visibility = 'Collapsed'
            $right += $code
            $row = New-Row -Left $left -Main $main -Right $right -Tag $p.Id
            if (-not $p.Applicable) { $chk.IsEnabled = $false; $row.Opacity = 0.55 }
            [void]$sec.Body.Children.Add($row)
            $ui.Rows[$p.Id] = @{ Check = $chk; Row = $row; Plugin = $p; Status = $status; Section = $grp.Name }
        }
        $ui.Sections[$grp.Name] = $sec.Root
        [void]$ui.List.Children.Add($sec.Root)
    }
    $third = @($plugins | Where-Object { -not $_.Trusted })
    if ($third.Count -gt 0) { & $mk 'third' ('Сторонние  ' + $third.Count) }
    if (-not $ui.Chips.ContainsKey($ui.Filter)) { $ui.Filter = 'all' }
    Set-TweakFilter -Filter $ui.Filter
    Update-TweakSelection
    if ($Reload) { Write-Log ('Плагинов найдено: ' + $plugins.Count + $(if ($third.Count) { ', из них сторонних: ' + $third.Count } else { '' })) ; Update-TweakStates }
}

function Set-TweakFilter {
    param([string]$Filter)
    $ui = $script:TwUi
    if (-not $ui.Chips.ContainsKey($Filter)) { $Filter = 'all' }
    $ui.Filter = $Filter
    foreach ($k in $ui.Chips.Keys) { Set-ChipActive -Button $ui.Chips[$k] -Active ($k -eq $Filter) }
    Update-TweakFilter
}

function Update-TweakFilter {
    $ui = $script:TwUi
    if (-not $ui) { return }
    $q = ([string]$ui.Search.Text).Trim().ToLowerInvariant()
    $visibleSec = @{}
    foreach ($r in $ui.Rows.Values) {
        $p = $r.Plugin
        $okCat = ($ui.Filter -eq 'all') -or ($ui.Filter -eq $p.CatNum) -or ($ui.Filter -eq 'third' -and -not $p.Trusted)
        $okQ = (-not $q) -or (($p.Name + ' ' + $p.Desc).ToLowerInvariant().Contains($q))
        $vis = $okCat -and $okQ
        $r.Row.Visibility = if ($vis) { 'Visible' } else { 'Collapsed' }
        if ($vis) { $visibleSec[$r.Section] = $true }
    }
    foreach ($k in $ui.Sections.Keys) { $ui.Sections[$k].Visibility = if ($visibleSec[$k]) { 'Visible' } else { 'Collapsed' } }
}

function Select-TweakPreset {
    param([string]$Preset)
    $ui = $script:TwUi
    $n = 0
    foreach ($r in $ui.Rows.Values) {
        $on = $Preset -and $r.Plugin.Applicable -and ($r.Plugin.Presets -contains $Preset)
        $r.Check.IsChecked = [bool]$on
        if ($on) { $n++ }
    }
    foreach ($k in $ui.PresetChips.Keys) { Set-ChipActive -Button $ui.PresetChips[$k] -Active ($k -eq $Preset) }
    if ($Preset) { Set-TweakFilter -Filter 'all'; Write-Log ('Пресет «' + $script:PresetInfo[$Preset].Title + '»: отмечено ' + $n + ' твиков. Проверьте список и нажмите «Применить».') }
    Update-TweakSelection
}

function Update-TweakSelection {
    $ui = $script:TwUi
    if (-not $ui -or -not $ui.Bar) { return }
    $sel = @($ui.Rows.Values | Where-Object { $_.Check.IsChecked })
    $careful = @($sel | Where-Object { $_.Plugin.Risk -ge 2 }).Count
    $t = $ui.Bar.Text
    $t.Inlines.Clear()
    $t.Inlines.Add((New-Object System.Windows.Documents.Bold (New-Object System.Windows.Documents.Run ([string]$sel.Count))))
    $run = New-Object System.Windows.Documents.Run (' выбрано' + $(if ($careful) { ' · осторожных: ' + $careful } else { '' }))
    $run.Foreground = Get-Brush 'Muted'
    $t.Inlines.Add($run)
    $ui.ApplyBtn.IsEnabled = ($sel.Count -gt 0) -and -not $ui.Running
}

function Update-TweakStates {
    $ui = $script:TwUi
    $plugins = @($ui.Plugins | Where-Object { $_.Check })
    if ($plugins.Count -eq 0) { return }
    $script:PluginStatesStamp = Get-Date
    Start-BgTask -Name 'Проверка твиков' -Silent -Vars @{ P = $plugins } -Script { Get-PluginStates -Plugins $P } -OnDone {
        param($states)
        if (-not $states) { return }
        $ui = $script:TwUi
        foreach ($id in $states.Keys) {
            $r = $ui.Rows[$id]
            if (-not $r) { continue }
            $v = $states[$id]
            if ($v -eq $true) { $r.Status.Text = '✓ применено'; $r.Status.Foreground = Get-Brush 'Ok' }
            elseif ($v -eq $false -and $r.Status.Text -like '✓*') { $r.Status.Text = 'сброшено'; $r.Status.Foreground = Get-Brush 'Muted'; $r.Status.ToolTip = 'Твик применялся раньше, но сейчас настройка другая (откат, обновление Windows или другая программа)' }
        }
    } | Out-Null
}

function Start-TweakApply {
    $ui = $script:TwUi
    $sel = @($ui.Rows.Values | Where-Object { $_.Check.IsChecked } | ForEach-Object { $_.Plugin } | Sort-Object CatNum, Num)
    if ($sel.Count -eq 0) { return }
    $third = @($sel | Where-Object { -not $_.Trusted })
    $msg = 'Применить ' + $sel.Count + ' твиков?' + "`n`n" + ((@($sel | ForEach-Object { '  • ' + $_.Name }) | Select-Object -First 25) -join "`n")
    if ($sel.Count -gt 25) { $msg += "`n  … и ещё " + ($sel.Count - 25) }
    if ($third.Count) { $msg += "`n`nСторонние плагины (не из поставки PotatoPC, выполняются от администратора):`n  • " + (($third | ForEach-Object { $_.Name }) -join "`n  • ") }
    $reboot = [bool]$ui.RebootChk.IsChecked
    if ($reboot) { $msg += "`n`nПосле выполнения компьютер перезагрузится (если не будет ошибок)." }
    if (-not (Show-Confirm -Message $msg -Title 'Применение твиков' -Warning:([bool]$third.Count))) { return }
    $ui.Running = $true
    Update-TweakSelection
    Start-BgTask -Name 'Применение твиков' -Vars @{ Sel = $sel; Rp = [bool]$ui.RpChk.IsChecked; Reboot = $reboot } -Script {
        $r = Invoke-PluginBatch -Plugins $Sel -RestorePoint $Rp -Title 'Применение твиков'
        if ($Reboot -and $r.Fail -eq 0 -and -not (Test-JobCancel)) { Request-Reboot -DelaySec 30 -Reason 'PotatoPC: твики применены' }
        return $r
    } -OnDone {
        param($r)
        $ui = $script:TwUi
        $ui.Running = $false
        foreach ($row in $ui.Rows.Values) { $row.Check.IsChecked = $false }
        Initialize-TweakList
        Update-TweakStates
        if ($r -and $r.Fail -gt 0) { Show-Info -Message ('Выполнено: ' + $r.Ok + ', с ошибкой: ' + $r.Fail + "`n" + ($r.Failed -join "`n") + "`n`nПодробности в журнале внизу окна.") -Title 'Твики' -Icon 'Warning' }
        elseif ($r) { Write-Log 'Часть изменений вступит в силу после перезахода в систему или перезагрузки.' }
    } | Out-Null
}

function Start-TweakUndo {
    param([string]$CatNum)
    $undo = @(Get-UndoPlugins -CatNum $CatNum)
    if ($undo.Count -eq 0) { return }
    $cat = @($script:TwUi.Plugins | Where-Object { $_.CatNum -eq $CatNum } | Select-Object -First 1).Category
    $msg = 'Вернуть настройки раздела «' + $cat + '» к заводским?' + "`n`n" + (($undo | ForEach-Object { '  • ' + $_.Name + "`n    " + $_.Desc }) -join "`n")
    if (-not (Show-Confirm -Message $msg -Title 'Откат' -Warning)) { return }
    Start-BgTask -Name ('Откат: ' + $cat) -Vars @{ U = $undo } -Script { Invoke-PluginBatch -Plugins $U -RestorePoint $false -Title 'Откат' } -OnDone {
        Initialize-TweakList
        Update-TweakStates
    } | Out-Null
}
