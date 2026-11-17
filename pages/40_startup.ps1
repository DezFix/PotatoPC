# PAGE: startup
# TITLE: Автозагрузка
# ICON: power
# ORDER: 40

$script:StUi = $null

function Build-Page_startup {
    $ui = @{ Rows = @{}; Filter = 'all'; Chips = @{} }
    $ui.RecBtn = New-Button -Text 'Выключить рекомендованные' -Icon 'power' -Kind Primary -OnClick { Disable-RecommendedStartup }
    $ui.RecBtn.IsEnabled = $false
    $refresh = New-Button -Text 'Обновить' -Icon 'refresh' -OnClick { Update-StartupPage }
    $L = New-PageLayout -Title 'Автозагрузка' -Subtitle 'Что запускается вместе с Windows' -HeaderRight @($refresh, $ui.RecBtn)
    $ui.On = New-StatCard -Label 'Включено' -Value '…'
    $ui.Boot = New-StatCard -Label 'Время загрузки (последняя)' -Value '…'
    $ui.Gain = New-StatCard -Label 'Можно выиграть' -Value '…' -ValueColor 'Ok'
    [void]$L.Body.Children.Add((New-Grid -Columns 3 -Items @($ui.On.Root, $ui.Boot.Root, $ui.Gain.Root)))
    $ui.ChipPanel = New-Object System.Windows.Controls.WrapPanel
    [void]$L.Body.Children.Add($ui.ChipPanel)
    $ui.Search = New-TextInput -Placeholder 'Поиск' -Width 220
    $ui.Search.Add_TextChanged({ Update-StartupFilter })
    $L.HeaderRight.Children.Insert(0, $ui.Search)
    $ui.Search.Margin = New-Thickness 0
    $ui.Section = New-Section -Title 'Программы, задачи и службы' -Right @((New-Text -Text 'Выключение не удаляет программу - включить можно в любой момент' -Size 12 -Color 'Muted'))
    [void]$ui.Section.Body.Children.Add((New-Placeholder))
    [void]$L.Body.Children.Add($ui.Section.Root)
    [void]$L.Body.Children.Add((New-Hint -Text '«Сильно / средне / слабо» - оценка по известным программам и размеру файла, а не точный замер. Системные элементы (драйверы, антивирус) помечены замком: их лучше не трогать.'))
    $script:StUi = $ui
    return $L.Root
}

function Show-Page_startup {
    param($Arg)
    if (-not $script:StUi.Loaded) { Update-StartupPage }
}

function Update-StartupPage {
    $ui = $script:StUi
    if ($ui.Busy) { return }
    $ui.Busy = $true
    Start-BgTask -Name 'Чтение автозагрузки' -Script {
        return @{ Items = @(Get-StartupItems -WithIcons -IncludeServices); Boot = (Get-BootTimeSec) }
    } -OnDone {
        param($r, $err)
        $script:StUi.Busy = $false
        if (-not $r) { Write-Log ('Автозагрузка не прочиталась: ' + $err) 'err'; return }
        $script:StUi.Loaded = Get-Date
        Set-StartupItems -Items $r.Items -Boot $r.Boot
    } | Out-Null
}

function Set-StartupItems {
    param($Items, [double]$Boot = -1)
    $ui = $script:StUi
    $ui.Items = @($Items)
    if ($Boot -ge 0) { $ui.BootSec = $Boot }
    $ui.Rows = @{}
    $body = $ui.Section.Body
    $body.Children.Clear()
    $order = @{ 'reg' = 0; 'folder' = 0; 'task' = 1; 'service' = 2 }
    foreach ($it in @($ui.Items | Sort-Object @{ E = { -not $_.Enabled } }, @{ E = { -not $_.Recommend } }, @{ E = { - $_.Impact } }, @{ E = { $order[$_.Kind] } }, @{ E = { $_.Name } })) {
        $kind = switch ($it.Kind) { 'task' { 'Задача планировщика' } 'service' { 'Служба' } default { $it.Source } }
        $sub = $(if ($it.Publisher) { $it.Publisher + ' · ' } else { '' }) + $kind
        $main = New-TitleBlock -Title $it.Name -Sub $sub
        $main.ToolTip = $it.Command
        $right = @()
        if ($it.Never) {
            $lk = New-Stack -Orientation Horizontal -Children @((New-Icon -Name 'lock' -Size 13 -Color 'Muted'), (New-Text -Text 'Системное - не трогать' -Size 11 -Color 'Muted' -Margin (4, 0, 0, 0)))
            $right += $lk
        } elseif ($it.Recommend -and $it.Enabled) {
            $rk = New-Stack -Orientation Horizontal -Children @((New-Icon -Name 'warn' -Size 13 -Color 'Accent'), (New-Text -Text 'Рекомендуем выключить' -Size 11 -Color 'Accent' -Margin (4, 0, 0, 0)))
            $right += $rk
        }
        $right += switch ($it.Impact) { 3 { New-Badge 'Сильно тормозит' 'bad' } 2 { New-Badge 'Средне' 'warn' } default { New-Badge 'Слабо' 'ok' } }
        $tg = New-Toggle -Checked ([bool]$it.Enabled) -Tag $it.Id -OnClick { Switch-StartupItem -Id $this.Tag -Enable ([bool]$this.IsChecked) }
        $right += $tg
        $row = New-Row -Left (New-AppIcon -Name $it.Name -Png $it.Icon) -Main $main -Right $right
        if (-not $it.Enabled) { $row.Opacity = 0.6 }
        [void]$body.Children.Add($row)
        $ui.Rows[$it.Id] = @{ Row = $row; Item = $it; Toggle = $tg }
    }
    Update-StartupStats
    Update-StartupChips
    Update-StartupFilter
}

function Update-StartupStats {
    $ui = $script:StUi
    $en = @($ui.Items | Where-Object { $_.Enabled })
    $rec = @($en | Where-Object { $_.Recommend -and -not $_.Never })
    $ui.On.Value.Text = [string]$en.Count
    $ui.On.Sub.Text = 'из ' + $ui.Items.Count
    $ui.Boot.Value.Text = if ($ui.BootSec -gt 0) { Format-Duration $ui.BootSec } else { 'нет данных' }
    $ui.Boot.Value.Foreground = if ($ui.BootSec -gt 60) { Get-Brush 'Warn' } else { Get-Brush 'Text' }
    $ui.Boot.Sub.Text = 'по журналу Windows'
    $gain = 0; foreach ($r in $rec) { $gain += switch ($r.Impact) { 3 { 8 } 2 { 4 } default { 1.5 } } }
    $ui.Gain.Value.Text = if ($gain -gt 0) { '≈ ' + [int]$gain + ' с' } else { 'уже хорошо' }
    $ui.Gain.Sub.Text = if ($rec.Count) { 'если выключить ' + $rec.Count + ' рекомендованных' } else { '' }
    Set-ButtonText -Button $ui.RecBtn -Text ('Выключить рекомендованные (' + $rec.Count + ')')
    $ui.RecBtn.IsEnabled = ($rec.Count -gt 0)
}

function Update-StartupChips {
    $ui = $script:StUi
    $ui.ChipPanel.Children.Clear(); $ui.Chips = @{}
    $defs = @(
        @('all', 'Все', { $true }), @('on', 'Включены', { $_.Enabled }), @('rec', 'Рекомендуем выключить', { $_.Recommend -and $_.Enabled -and -not $_.Never }),
        @('app', 'Программы', { $_.Kind -eq 'reg' -or $_.Kind -eq 'folder' }), @('task', 'Задачи', { $_.Kind -eq 'task' }), @('service', 'Службы', { $_.Kind -eq 'service' })
    )
    $ui.ChipDefs = @{}
    foreach ($d in $defs) {
        $n = @($ui.Items | Where-Object $d[2]).Count
        $b = New-Button -Text ($d[1] + '  ' + $n) -Kind Chip -Tag $d[0] -OnClick { $script:StUi.Filter = $this.Tag; Update-StartupChips; Update-StartupFilter }
        Set-ChipActive -Button $b -Active ($ui.Filter -eq $d[0])
        [void]$ui.ChipPanel.Children.Add($b)
        $ui.ChipDefs[$d[0]] = $d[2]
    }
}

function Update-StartupFilter {
    $ui = $script:StUi
    if (-not $ui.ChipDefs) { return }
    $f = $ui.ChipDefs[$ui.Filter]
    $q = ([string]$ui.Search.Text).Trim().ToLowerInvariant()
    foreach ($r in $ui.Rows.Values) {
        $ok = @($r.Item | Where-Object $f).Count -gt 0
        if ($ok -and $q) { $ok = (($r.Item.Name + ' ' + $r.Item.Publisher).ToLowerInvariant().Contains($q)) }
        $r.Row.Visibility = if ($ok) { 'Visible' } else { 'Collapsed' }
    }
}

function Switch-StartupItem {
    param([string]$Id, [bool]$Enable)
    $r = $script:StUi.Rows[$Id]
    if (-not $r) { return }
    $it = $r.Item
    if (-not $Enable -and $it.Never) {
        if (-not (Show-Confirm -Message ('«' + $it.Name + '» похоже на системный компонент (драйвер, антивирус, устройство ввода). Выключить всё равно?') -Warning)) { $r.Toggle.IsChecked = $true; return }
    }
    try {
        Set-StartupItemEnabled -Item $it -Enable $Enable
        $it.Enabled = $Enable
        $r.Row.Opacity = if ($Enable) { 1 } else { 0.6 }
        Write-Log (($(if ($Enable) { 'Включено: ' } else { 'Выключено: ' })) + $it.Name) 'ok'
        Update-StartupStats
        Update-StartupChips
    } catch {
        $r.Toggle.IsChecked = -not $Enable
        Write-Log ('Не удалось переключить «' + $it.Name + '»: ' + $_.Exception.Message) 'err'
    }
}

function Disable-RecommendedStartup {
    $ui = $script:StUi
    $rec = @($ui.Items | Where-Object { $_.Enabled -and $_.Recommend -and -not $_.Never })
    if ($rec.Count -eq 0) { return }
    $msg = "Выключить из автозагрузки:`n  • " + (($rec | ForEach-Object { $_.Name }) -join "`n  • ") + "`n`nПрограммы останутся установлены и будут запускаться, когда вы их откроете."
    if (-not (Show-Confirm -Message $msg -Title 'Автозагрузка')) { return }
    foreach ($it in $rec) { Switch-StartupItem -Id $it.Id -Enable $false; $ui.Rows[$it.Id].Toggle.IsChecked = $false }
}
