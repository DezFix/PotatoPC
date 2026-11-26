# PotatoPC v7 - оболочка окна и конструктор интерфейса.
# Только UI-поток. Страницы (pages\*.ps1) строят свои экраны из этих блоков.

$script:Clr = @{
    Bg = '#14161B'; Panel = '#1B1E25'; Card = '#20242C'; Line = '#2C313B'; Text = '#E8EAF0'; Muted = '#9AA3B2'
    Accent = '#F5B544'; AccentDim = '#2A2416'; OnAccent = '#1A1407'; Ok = '#4ADE80'; OkDim = '#123222'
    Warn = '#FBBF24'; WarnDim = '#33290F'; Bad = '#F87171'; BadDim = '#3A1A1A'; Info = '#7CC4FA'; InfoDim = '#13283A'; Hover = '#14FFFFFF'
}

# Значки: контуры 24x24 (stroke). Только линии и дуги - без заливки.
$script:IconPaths = @{
    home    = 'M3,11 L12,4 L21,11 M5,10 V20 H19 V10'
    bolt    = 'M13,2 L4,14 H11 L10,22 L19,10 H12 Z'
    broom   = 'M14,4 L20,10 M4,20 L11,13 M9,11 L13,15 L8,20 L3,19 L2,14 Z'
    power   = 'M12,3 V12 M6.4,6.4 A8,8 0 1 0 17.6,6.4'
    box     = 'M3,7 L12,3 L21,7 L12,11 Z M3,7 V17 L12,21 L21,17 V7 M12,11 V21'
    shield  = 'M12,3 L20,6 V12 C20,17 16.5,20 12,21 C7.5,20 4,17 4,12 V6 Z M9,12 L11,14 L15,10'
    undo    = 'M9,14 L4,9 L9,4 M4,9 H15 A5,5 0 0 1 15,19 H12'
    flag    = 'M5,21 V4 M5,4 H16 L14,8 L16,12 H5'
    folder  = 'M3,6 H9 L11,8 H21 V19 H3 Z'
    search  = 'M11,4 A7,7 0 1 1 11,18 A7,7 0 1 1 11,4 M20,20 L16,16'
    cpu     = 'M6,6 H18 V18 H6 Z M9,2 V6 M15,2 V6 M9,18 V22 M15,18 V22 M2,9 H6 M2,15 H6 M18,9 H22 M18,15 H22'
    mem     = 'M3,7 H21 V17 H3 Z M7,7 V17 M11,7 V17 M15,7 V17'
    disk    = 'M3,5 H21 V19 H3 Z M16,10.5 A1.5,1.5 0 1 1 16,13.5 A1.5,1.5 0 1 1 16,10.5'
    clock   = 'M12,3 A9,9 0 1 1 12,21 A9,9 0 1 1 12,3 M12,7 V12 L15,14'
    play    = 'M7,5 L19,12 L7,19 Z'
    check   = 'M5,12 L10,17 L19,7'
    eye     = 'M2,12 C4,8 7.5,5 12,5 C16.5,5 20,8 22,12 C20,16 16.5,19 12,19 C7.5,19 4,16 2,12 Z M12,9 A3,3 0 1 1 12,15 A3,3 0 1 1 12,9'
    lock    = 'M5,11 H19 V21 H5 Z M8,11 V7 A4,4 0 0 1 16,7 V11'
    plug    = 'M9,2 V7 M15,2 V7 M6,7 H18 V11 A6,6 0 0 1 6,11 Z M12,17 V22'
    term    = 'M3,4 H21 V20 H3 Z M7,9 L10,12 L7,15 M13,15 H17'
    trash   = 'M4,7 H20 M9,7 V4 H15 V7 M6,7 L7,20 H17 L18,7'
    warn    = 'M12,3 L22,21 H2 Z M12,10 V15 M12,18 V18.5'
    users   = 'M9,4.5 A3.5,3.5 0 1 1 9,11.5 A3.5,3.5 0 1 1 9,4.5 M2.5,20 A6.5,6.5 0 0 1 15.5,20 M16,4.5 A3.5,3.5 0 0 1 16,11.5 M18,14.5 A6.5,6.5 0 0 1 21.5,20'
    gauge   = 'M4,18 A8,8 0 1 1 20,18 M12,18 L16,12'
    key     = 'M8,11 A4,4 0 1 1 8,19 A4,4 0 1 1 8,11 M11,12 L20,3 M17,6 L20,9'
    battery = 'M2,7 H20 V17 H2 Z M22,11 V13 M5,10 H12 V14 H5 Z'
    gpu     = 'M2,6 H22 V18 H2 Z M9,9 A3,3 0 1 1 9,15 A3,3 0 1 1 9,9 M15,10 H19 M15,14 H19'
    plus    = 'M12,5 V19 M5,12 H19'
    save    = 'M5,3 H16 L19,6 V21 H5 Z M8,3 V8 H15 V3 M8,13 H16 V18 H8 Z'
    chip    = 'M7,7 H17 V17 H7 Z M10,3 V7 M14,3 V7 M10,17 V21 M14,17 V21 M3,10 H7 M3,14 H7 M17,10 H21 M17,14 H21'
    wrench  = 'M14.5,6.5 A4,4 0 0 0 19.5,11.5 L12,19 A2.1,2.1 0 0 1 9,16 L16.5,8.5 M14.5,6.5 L17,4'
    network = 'M9,3 H15 V8 H9 Z M3,16 H9 V21 H3 Z M15,16 H21 V21 H15 Z M12,8 V12 M6,16 V12 H18 V16'
    refresh = 'M20,11 A8,8 0 1 0 18,17 M20,4 V11 H13'
    wifi    = 'M2,9 A15,15 0 0 1 22,9 M5,12.5 A10,10 0 0 1 19,12.5 M8.5,16 A5,5 0 0 1 15.5,16 M12,19.5 V19.6'
    globe   = 'M12,3 A9,9 0 1 1 12,21 A9,9 0 1 1 12,3 M3,12 H21 M12,3 C9,6 9,18 12,21 C15,18 15,6 12,3'
    info    = 'M12,3 A9,9 0 1 1 12,21 A9,9 0 1 1 12,3 M12,11 V16 M12,8 V8.5'
    report  = 'M6,3 H15 L19,7 V21 H6 Z M9,12 H16 M9,16 H16 M9,8 H12'
    x       = 'M6,6 L18,18 M18,6 L6,18'
    history = 'M3,12 A9,9 0 1 0 6,5.3 M3,4 V9 H8 M12,7 V12 L15,14'
    chevR   = 'M9,6 L15,12 L9,18'
    chevD   = 'M6,9 L12,15 L18,9'
    file    = 'M6,3 H14 L19,8 V21 H6 Z M14,3 V8 H19'
    copy    = 'M8,8 H20 V20 H8 Z M4,16 V4 H16'
    ban     = 'M12,3 A9,9 0 1 1 12,21 A9,9 0 1 1 12,3 M5.6,5.6 L18.4,18.4'
    monitor = 'M3,4 H21 V16 H3 Z M8,20 H16 M12,16 V20'
    router  = 'M3,13 H21 V20 H3 Z M7,16.5 V16.6 M11,16.5 V16.6 M8.5,9.5 A5,5 0 0 1 15.5,9.5 M5.5,6.5 A9.5,9.5 0 0 1 18.5,6.5'
    building = 'M3,21 H21 M5,21 V9 L12,4 L19,9 V21 M10,21 V15 H14 V21'
}
$script:CategoryIcons = @{ '01' = 'bolt'; '02' = 'broom'; '03' = 'eye'; '05' = 'mem'; '08' = 'shield'; '09' = 'wrench' }

$script:BrushCache = @{}
function Get-Brush {
    param([string]$Color)
    if ($script:Clr.ContainsKey($Color)) { $Color = $script:Clr[$Color] }
    if (-not $script:BrushCache.ContainsKey($Color)) {
        $b = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($Color))
        $b.Freeze()
        $script:BrushCache[$Color] = $b
    }
    return $script:BrushCache[$Color]
}

function New-Thickness { param([double[]]$v) if ($v.Count -eq 1) { return New-Object System.Windows.Thickness $v[0] } ; if ($v.Count -eq 2) { return New-Object System.Windows.Thickness $v[0], $v[1], $v[0], $v[1] } ; return New-Object System.Windows.Thickness $v[0], $v[1], $v[2], $v[3] }

function New-Icon {
    param([string]$Name, [double]$Size = 18, [string]$Color = 'Muted', [double]$Stroke = 1.8)
    $data = $script:IconPaths[$Name]
    if (-not $data) { $data = $script:IconPaths['info'] }
    $p = New-Object System.Windows.Shapes.Path
    $p.Data = [System.Windows.Media.Geometry]::Parse($data)
    $p.Stroke = Get-Brush $Color
    $p.StrokeThickness = $Stroke
    $p.StrokeStartLineCap = 'Round'; $p.StrokeEndLineCap = 'Round'; $p.StrokeLineJoin = 'Round'
    $c = New-Object System.Windows.Controls.Canvas
    $c.Width = 24; $c.Height = 24
    [void]$c.Children.Add($p)
    $v = New-Object System.Windows.Controls.Viewbox
    $v.Width = $Size; $v.Height = $Size; $v.Child = $c
    $v.VerticalAlignment = 'Center'
    $v.SnapsToDevicePixels = $true
    return $v
}

function New-Text {
    param([string]$Text = '', [double]$Size = 14, [string]$Color = 'Text', [string]$Weight = 'Normal', [switch]$Wrap, $Margin = $null, [switch]$Mono)
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Text; $t.FontSize = $Size; $t.Foreground = Get-Brush $Color
    $t.FontWeight = [System.Windows.FontWeights]::$Weight
    if ($Wrap) { $t.TextWrapping = 'Wrap' } else { $t.TextTrimming = 'CharacterEllipsis' }
    if ($Mono) { $t.FontFamily = New-Object System.Windows.Media.FontFamily 'Cascadia Mono, Consolas' }
    if ($null -ne $Margin) { $t.Margin = New-Thickness $Margin }
    $t.VerticalAlignment = 'Center'
    return $t
}

function New-Stack {
    param([string]$Orientation = 'Vertical', $Margin = $null, [object[]]$Children = @())
    $s = New-Object System.Windows.Controls.StackPanel
    $s.Orientation = $Orientation
    if ($null -ne $Margin) { $s.Margin = New-Thickness $Margin }
    foreach ($c in $Children) { if ($null -ne $c) { [void]$s.Children.Add($c) } }
    return $s
}

function New-Button {
    # Kind: Primary | Secondary | Danger | Ghost | Small | SmallDanger | Chip
    param([string]$Text, [string]$Icon = '', [string]$Kind = 'Secondary', [scriptblock]$OnClick = $null, $Tag = $null, [string]$ToolTip = '')
    $b = New-Object System.Windows.Controls.Button
    $b.Style = $script:Window.FindResource('Btn' + $Kind)
    $fg = switch ($Kind) { 'Primary' { 'OnAccent' } 'Danger' { 'Bad' } 'SmallDanger' { 'Bad' } 'Ghost' { 'Accent' } default { 'Text' } }
    if ($Icon) {
        $sp = New-Stack -Orientation Horizontal
        [void]$sp.Children.Add((New-Icon -Name $Icon -Size 16 -Color $fg -Stroke 2))
        $t = New-Object System.Windows.Controls.TextBlock
        $t.Text = $Text; $t.Margin = New-Thickness 8, 0, 0, 0; $t.VerticalAlignment = 'Center'
        [void]$sp.Children.Add($t)
        $b.Content = $sp
    } else { $b.Content = $Text }
    if ($null -ne $Tag) { $b.Tag = $Tag }
    if ($ToolTip) { $b.ToolTip = $ToolTip }
    if ($OnClick) { $b.Add_Click($OnClick) }
    return $b
}

function Set-ButtonText {
    param($Button, [string]$Text)
    if ($Button.Content -is [System.Windows.Controls.StackPanel]) { $Button.Content.Children[1].Text = $Text } else { $Button.Content = $Text }
}

function Set-ChipActive {
    param($Button, [bool]$Active)
    if ($Active) {
        $Button.Background = Get-Brush 'Accent'; $Button.Foreground = Get-Brush 'OnAccent'; $Button.BorderThickness = New-Thickness 0; $Button.FontWeight = 'Bold'
    } else {
        $Button.ClearValue([System.Windows.Controls.Control]::BackgroundProperty)
        $Button.ClearValue([System.Windows.Controls.Control]::ForegroundProperty)
        $Button.ClearValue([System.Windows.Controls.Control]::BorderThicknessProperty)
        $Button.ClearValue([System.Windows.Controls.Control]::FontWeightProperty)
    }
}

function New-Card {
    param($Child = $null, $Padding = 18, $Margin = $null, [string]$Background = 'Card', [string]$Border = 'Line')
    $b = New-Object System.Windows.Controls.Border
    $b.Background = Get-Brush $Background; $b.BorderBrush = Get-Brush $Border
    $b.BorderThickness = New-Thickness 1
    $b.CornerRadius = New-Object System.Windows.CornerRadius 12
    $b.Padding = New-Thickness $Padding
    if ($null -ne $Margin) { $b.Margin = New-Thickness $Margin }
    if ($null -ne $Child) { $b.Child = $Child }
    return $b
}

function New-Section {
    # Карточка со строкой заголовка и списком строк. Возвращает @{ Root; Body; Header; Right }.
    param([string]$Title, $Right = $null, $Margin = (0, 0, 0, 16))
    $outer = New-Object System.Windows.Controls.Border
    $outer.Background = Get-Brush 'Card'; $outer.BorderBrush = Get-Brush 'Line'; $outer.BorderThickness = New-Thickness 1
    $outer.CornerRadius = New-Object System.Windows.CornerRadius 12
    $outer.Margin = New-Thickness $Margin
    $sp = New-Object System.Windows.Controls.StackPanel
    $g = New-Object System.Windows.Controls.Grid
    $g.Margin = New-Thickness 16, 10, 12, 10
    $g.MinHeight = 28
    [void]$g.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
    $cd = New-Object System.Windows.Controls.ColumnDefinition; $cd.Width = 'Auto'; [void]$g.ColumnDefinitions.Add($cd)
    $h = New-Text -Text $Title -Size 14 -Weight 'Bold'
    [void]$g.Children.Add($h)
    $rp = New-Stack -Orientation Horizontal
    [System.Windows.Controls.Grid]::SetColumn($rp, 1)
    if ($null -ne $Right) { foreach ($r in @($Right)) { [void]$rp.Children.Add($r) } }
    [void]$g.Children.Add($rp)
    [void]$sp.Children.Add($g)
    $body = New-Object System.Windows.Controls.StackPanel
    [void]$sp.Children.Add($body)
    $outer.Child = $sp
    return @{ Root = $outer; Body = $body; Header = $h; Right = $rp }
}

function New-Row {
    # Строка списка с разделителем сверху: [left] [main растягивается] [right...]
    param($Left = $null, $Main = $null, [object[]]$Right = @(), $Padding = (16, 11, 16, 11), $Tag = $null)
    $b = New-Object System.Windows.Controls.Border
    $b.BorderBrush = Get-Brush 'Line'; $b.BorderThickness = New-Thickness 0, 1, 0, 0
    $b.Padding = New-Thickness $Padding
    $b.MinHeight = 44
    if ($null -ne $Tag) { $b.Tag = $Tag }
    $g = New-Object System.Windows.Controls.Grid
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = 'Auto'
    $c1 = New-Object System.Windows.Controls.ColumnDefinition
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = 'Auto'
    [void]$g.ColumnDefinitions.Add($c0); [void]$g.ColumnDefinitions.Add($c1); [void]$g.ColumnDefinitions.Add($c2)
    if ($null -ne $Left) { $Left.Margin = New-Thickness 0, 0, 14, 0; $Left.VerticalAlignment = 'Center'; [void]$g.Children.Add($Left) }
    if ($null -ne $Main) { [System.Windows.Controls.Grid]::SetColumn($Main, 1); $Main.VerticalAlignment = 'Center'; [void]$g.Children.Add($Main) }
    $rp = New-Stack -Orientation Horizontal
    $rp.VerticalAlignment = 'Center'
    foreach ($r in $Right) { if ($null -ne $r) { $r.Margin = New-Thickness 8, 0, 0, 0; [void]$rp.Children.Add($r) } }
    [System.Windows.Controls.Grid]::SetColumn($rp, 2)
    [void]$g.Children.Add($rp)
    $b.Child = $g
    return $b
}

function New-TitleBlock {
    param([string]$Title, [string]$Sub = '', [string]$SubColor = 'Muted')
    $sp = New-Stack
    [void]$sp.Children.Add((New-Text -Text $Title -Size 14 -Weight 'SemiBold'))
    if ($Sub) { $s = New-Text -Text $Sub -Size 12 -Color $SubColor -Margin (0, 2, 0, 0); [void]$sp.Children.Add($s) }
    return $sp
}

function New-Badge {
    # Kind: ok | warn | bad | info | muted | accent
    param([string]$Text, [string]$Kind = 'muted')
    $map = @{ ok = @('Ok','OkDim'); warn = @('Warn','WarnDim'); bad = @('Bad','BadDim'); info = @('Info','InfoDim'); muted = @('Muted','#262A33'); accent = @('OnAccent','Accent') }
    $c = $map[$Kind]; if (-not $c) { $c = $map.muted }
    $b = New-Object System.Windows.Controls.Border
    $b.Background = Get-Brush $c[1]; $b.CornerRadius = New-Object System.Windows.CornerRadius 10
    $b.Padding = New-Thickness 9, 2, 9, 3; $b.VerticalAlignment = 'Center'
    $t = New-Text -Text $Text -Size 11 -Color $c[0] -Weight 'SemiBold'
    $b.Child = $t
    return $b
}

function New-RiskBadge {
    param([int]$Risk)
    switch ($Risk) { 1 { return New-Badge 'Безопасно' 'ok' } 3 { return New-Badge 'Рискованно' 'bad' } default { return New-Badge 'Осторожно' 'warn' } }
}

function New-OutlineChip {
    param([string]$Text)
    $b = New-Object System.Windows.Controls.Border
    $b.BorderBrush = Get-Brush 'Line'; $b.BorderThickness = New-Thickness 1
    $b.CornerRadius = New-Object System.Windows.CornerRadius 10; $b.Padding = New-Thickness 8, 1, 8, 2
    $b.VerticalAlignment = 'Center'
    $b.Child = New-Text -Text $Text -Size 11 -Color 'Muted'
    return $b
}

function New-CheckBox {
    param([string]$Text = '', [bool]$Checked = $false, $Tag = $null, [scriptblock]$OnChange = $null, [string]$ToolTip = '')
    $c = New-Object System.Windows.Controls.CheckBox
    $c.Style = $script:Window.FindResource('Check')
    if ($Text) { $c.Content = New-Text -Text $Text -Size 13 -Color 'Muted' }
    $c.IsChecked = $Checked
    if ($null -ne $Tag) { $c.Tag = $Tag }
    if ($ToolTip) { $c.ToolTip = $ToolTip }
    if ($OnChange) { $c.Add_Checked($OnChange); $c.Add_Unchecked($OnChange) }
    return $c
}

function New-Toggle {
    param([bool]$Checked = $false, $Tag = $null, [scriptblock]$OnClick = $null)
    $c = New-Object System.Windows.Controls.CheckBox
    $c.Style = $script:Window.FindResource('Toggle')
    $c.IsChecked = $Checked
    if ($null -ne $Tag) { $c.Tag = $Tag }
    if ($OnClick) { $c.Add_Click($OnClick) }
    return $c
}

function New-Radio {
    param([string]$Title, [string]$Sub = '', [string]$Group, [bool]$Checked = $false, $Tag = $null)
    $r = New-Object System.Windows.Controls.RadioButton
    $r.Style = $script:Window.FindResource('Radio')
    $r.GroupName = $Group; $r.IsChecked = $Checked
    $r.Content = New-TitleBlock -Title $Title -Sub $Sub
    $r.Margin = New-Thickness 0, 0, 0, 8
    if ($null -ne $Tag) { $r.Tag = $Tag }
    return $r
}

function New-TextInput {
    param([string]$Placeholder = '', [double]$Width = [double]::NaN, [string]$Text = '')
    $t = New-Object System.Windows.Controls.TextBox
    $t.Style = $script:Window.FindResource('Input')
    $t.Tag = $Placeholder; $t.Text = $Text
    if (-not [double]::IsNaN($Width)) { $t.Width = $Width }
    return $t
}

function New-PasswordInput {
    $p = New-Object System.Windows.Controls.PasswordBox
    $p.Style = $script:Window.FindResource('Password')
    return $p
}

function New-Field {
    param([string]$Label, $Control, $Margin = (0, 0, 0, 12))
    $sp = New-Stack -Margin $Margin
    [void]$sp.Children.Add((New-Text -Text $Label -Size 13 -Color 'Muted' -Margin (0, 0, 0, 6)))
    [void]$sp.Children.Add($Control)
    return $sp
}

function New-Grid {
    # Сетка из N равных колонок; элементы раскладываются по порядку.
    param([int]$Columns = 3, [object[]]$Items = @(), [double]$Gap = 14)
    $g = New-Object System.Windows.Controls.Primitives.UniformGrid
    $g.Columns = $Columns
    $g.Margin = New-Thickness 0, 0, (-1 * $Gap), 0
    foreach ($i in $Items) {
        if ($null -eq $i) { continue }
        $i.Margin = New-Thickness 0, 0, $Gap, $Gap
        [void]$g.Children.Add($i)
    }
    return $g
}

function New-StatCard {
    # Возвращает @{ Root; Value; Sub } - значения обновляются позже.
    param([string]$Icon = '', [string]$Label, [string]$Value = '…', [string]$Sub = '', [string]$ValueColor = 'Text')
    $sp = New-Stack
    $top = New-Stack -Orientation Horizontal
    if ($Icon) { [void]$top.Children.Add((New-Icon -Name $Icon -Size 16 -Color 'Muted')) }
    $lab = New-Text -Text $Label -Size 13 -Color 'Muted' -Margin $(if ($Icon) { (8, 0, 0, 0) } else { (0, 0, 0, 0) })
    [void]$top.Children.Add($lab)
    [void]$sp.Children.Add($top)
    $v = New-Text -Text $Value -Size 19 -Weight 'SemiBold' -Color $ValueColor -Margin (0, 8, 0, 0)
    [void]$sp.Children.Add($v)
    $s = New-Text -Text $Sub -Size 12 -Color 'Muted' -Margin (0, 3, 0, 0)
    [void]$sp.Children.Add($s)
    $card = New-Card -Child $sp -Padding 16
    return @{ Root = $card; Value = $v; Sub = $s; Label = $lab }
}

function New-Meter {
    param([double]$Height = 8)
    $g = New-Object System.Windows.Controls.Grid
    $g.Height = $Height
    $bg = New-Object System.Windows.Controls.Border
    $bg.Background = Get-Brush 'Panel'; $bg.CornerRadius = New-Object System.Windows.CornerRadius ($Height / 2)
    $fg = New-Object System.Windows.Controls.Border
    $fg.Background = Get-Brush 'Accent'; $fg.CornerRadius = New-Object System.Windows.CornerRadius ($Height / 2)
    $fg.HorizontalAlignment = 'Left'; $fg.Width = 0
    [void]$g.Children.Add($bg); [void]$g.Children.Add($fg)
    $g.Tag = @{ Fill = $fg; Value = 0.0 }
    $g.Add_SizeChanged({ try { $this.Tag.Fill.Width = [Math]::Max(0, $this.ActualWidth * $this.Tag.Value) } catch {} })
    return $g
}

function Set-Meter {
    param($Meter, [double]$Value, [string]$Color = 'Accent')
    $v = [Math]::Max(0, [Math]::Min(1, $Value))
    $Meter.Tag.Value = $v
    $Meter.Tag.Fill.Background = Get-Brush $Color
    $Meter.Tag.Fill.Width = [Math]::Max(0, $Meter.ActualWidth * $v)
}

function New-ScoreRing {
    param([double]$Size = 110, [double]$Thickness = 12)
    $g = New-Object System.Windows.Controls.Grid
    $g.Width = $Size; $g.Height = $Size
    $bg = New-Object System.Windows.Shapes.Ellipse
    $bg.Stroke = Get-Brush 'Line'; $bg.StrokeThickness = $Thickness
    $arc = New-Object System.Windows.Shapes.Path
    $arc.Stroke = Get-Brush 'Accent'; $arc.StrokeThickness = $Thickness
    $arc.StrokeStartLineCap = 'Round'; $arc.StrokeEndLineCap = 'Round'
    $sp = New-Stack; $sp.HorizontalAlignment = 'Center'; $sp.VerticalAlignment = 'Center'
    $num = New-Text -Text '—' -Size ($Size * 0.28) -Weight 'Bold'; $num.HorizontalAlignment = 'Center'
    $sub = New-Text -Text 'из 100' -Size 11 -Color 'Muted'; $sub.HorizontalAlignment = 'Center'
    [void]$sp.Children.Add($num); [void]$sp.Children.Add($sub)
    [void]$g.Children.Add($bg); [void]$g.Children.Add($arc); [void]$g.Children.Add($sp)
    $g.Tag = @{ Arc = $arc; Num = $num; Size = $Size; Thick = $Thickness }
    return $g
}

function Set-ScoreRing {
    param($Ring, [int]$Value, [string]$Color = '')
    $t = $Ring.Tag
    $v = [Math]::Max(0, [Math]::Min(100, $Value))
    $t.Num.Text = [string]$v
    if (-not $Color) { $Color = if ($v -ge 75) { 'Ok' } elseif ($v -ge 45) { 'Accent' } else { 'Bad' } }
    $t.Arc.Stroke = Get-Brush $Color
    $r = ($t.Size - $t.Thick) / 2; $c = $t.Size / 2
    if ($v -ge 100) { $v = 99.99 }
    $ang = (2 * [Math]::PI * $v / 100) - ([Math]::PI / 2)
    $x = $c + $r * [Math]::Cos($ang); $y = $c + $r * [Math]::Sin($ang)
    $large = if ($v -gt 50) { 1 } else { 0 }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($v -le 0) { $t.Arc.Data = $null; return }
    $t.Arc.Data = [System.Windows.Media.Geometry]::Parse(('M {0},{1} A {2},{2} 0 {3} 1 {4},{5}' -f $c.ToString($inv), ($c - $r).ToString($inv), $r.ToString($inv), $large, $x.ToString($inv), $y.ToString($inv)))
}

function New-AppIcon {
    # Цветной квадрат с буквой (если нет настоящего значка) или картинка из PNG-байтов.
    param([string]$Name, [byte[]]$Png = $null, [double]$Size = 36)
    $b = New-Object System.Windows.Controls.Border
    $b.Width = $Size; $b.Height = $Size; $b.CornerRadius = New-Object System.Windows.CornerRadius 9
    if ($Png -and (Set-AppIconPng -Icon $b -Png $Png)) { return $b }
    $palette = @('#60A5FA','#818CF8','#38BDF8','#F87171','#FBBF24','#4ADE80','#A78BFA','#F472B6','#FB923C','#2DD4BF')
    $h = 0; foreach ($ch in $Name.ToCharArray()) { $h = ($h * 31 + [int]$ch) % 1000 }
    $b.Background = Get-Brush $palette[$h % $palette.Count]
    $letter = if ($Name) { $Name.Substring(0, 1).ToUpper() } else { '?' }
    $t = New-Text -Text $letter -Size ($Size * 0.42) -Color '#14161B' -Weight 'Bold'
    $t.HorizontalAlignment = 'Center'
    $b.Child = $t
    return $b
}

function Set-AppIconPng {
    # Ставит настоящий значок (PNG-байты) в квадрат от New-AppIcon - можно и позже, когда значок догрузится.
    param($Icon, [byte[]]$Png)
    if (-not $Icon -or -not $Png -or $Png.Length -lt 8) { return $false }
    try {
        $ms = New-Object System.IO.MemoryStream (, $Png)
        $img = New-Object System.Windows.Media.Imaging.BitmapImage
        $img.BeginInit(); $img.StreamSource = $ms; $img.CacheOption = 'OnLoad'; $img.EndInit(); $img.Freeze()
        $im = New-Object System.Windows.Controls.Image
        $s = [double]$Icon.Width * 0.72
        $im.Source = $img; $im.Width = $s; $im.Height = $s
        [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($im, 'HighQuality')
        $Icon.Background = Get-Brush 'Panel'; $Icon.Child = $im
        return $true
    } catch { return $false }
}

function New-IconTile {
    param([string]$Icon, [string]$Color = 'Accent', [double]$Size = 36)
    $b = New-Object System.Windows.Controls.Border
    $b.Width = $Size; $b.Height = $Size; $b.CornerRadius = New-Object System.Windows.CornerRadius 9
    $b.Background = Get-Brush 'Panel'
    $i = New-Icon -Name $Icon -Size ($Size * 0.5) -Color $Color
    $i.HorizontalAlignment = 'Center'
    $b.Child = $i
    return $b
}

function New-Hint {
    # Пометка: значок + текст (kind: info | warn | bad | ok).
    param([string]$Text, [string]$Kind = 'info', $Margin = (0, 0, 0, 16))
    $map = @{ info = @('info', 'Muted', 'Card', 'Line'); warn = @('warn', 'Warn', 'WarnDim', '#5A4A1A'); bad = @('warn', 'Bad', 'BadDim', '#5A2626'); ok = @('shield', 'Ok', 'Card', 'Line') }
    $m = $map[$Kind]
    # DockPanel, а не горизонтальный StackPanel: в узком месте (окно, колонка) текст переносится.
    $g = New-Object System.Windows.Controls.DockPanel
    $ic = New-Icon -Name $m[0] -Size 18 -Color $m[1]; $ic.VerticalAlignment = 'Top'
    [System.Windows.Controls.DockPanel]::SetDock($ic, 'Left')
    [void]$g.Children.Add($ic)
    $t = New-Text -Text $Text -Size 13 -Color $(if ($Kind -eq 'info' -or $Kind -eq 'ok') { 'Muted' } else { $m[1] }) -Wrap -Margin (12, 0, 0, 0)
    $t.MaxWidth = 900; $t.HorizontalAlignment = 'Left'
    [void]$g.Children.Add($t)
    return (New-Card -Child $g -Padding (16, 12, 16, 12) -Margin $Margin -Background $m[2] -Border $m[3])
}

function New-ActionBar {
    # Нижняя панель страницы: текст слева, элементы справа.
    param([object[]]$Right = @())
    $b = New-Object System.Windows.Controls.Border
    $b.Background = Get-Brush 'Panel'; $b.BorderBrush = Get-Brush 'Line'; $b.BorderThickness = New-Thickness 1
    $b.CornerRadius = New-Object System.Windows.CornerRadius 12
    $b.Padding = New-Thickness 16, 10, 12, 10
    $b.Margin = New-Thickness 28, 0, 28, 16
    $g = New-Object System.Windows.Controls.DockPanel
    $rp = New-Stack -Orientation Horizontal
    [System.Windows.Controls.DockPanel]::SetDock($rp, 'Right')
    foreach ($r in $Right) { if ($null -ne $r) { $r.Margin = New-Thickness 14, 0, 0, 0; $r.VerticalAlignment = 'Center'; [void]$rp.Children.Add($r) } }
    [void]$g.Children.Add($rp)
    $txt = New-Text -Text '' -Size 14
    [void]$g.Children.Add($txt)
    $b.Child = $g
    return @{ Root = $b; Text = $txt; Right = $rp }
}

function New-PageLayout {
    <#
      Стандартный каркас страницы: заголовок, прокручиваемое тело, нижняя панель.
      Возвращает @{ Root; Body; HeaderRight; Title; Subtitle; Scroll }
    #>
    param([string]$Title, [string]$Subtitle = '', [object[]]$HeaderRight = @(), $ActionBar = $null)
    $root = New-Object System.Windows.Controls.Grid
    [void]$root.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
    $r2 = New-Object System.Windows.Controls.RowDefinition; $r2.Height = 'Auto'; [void]$root.RowDefinitions.Add($r2)
    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = 'Auto'
    $scroll.HorizontalScrollBarVisibility = 'Disabled'
    $body = New-Stack -Margin (28, 24, 28, 12)
    $hdr = New-Object System.Windows.Controls.DockPanel
    $hdr.Margin = New-Thickness 0, 0, 0, 20
    $hr = New-Stack -Orientation Horizontal
    $hr.VerticalAlignment = 'Center'
    [System.Windows.Controls.DockPanel]::SetDock($hr, 'Right')
    foreach ($x in $HeaderRight) { if ($null -ne $x) { $x.Margin = New-Thickness 10, 0, 0, 0; [void]$hr.Children.Add($x) } }
    [void]$hdr.Children.Add($hr)
    $ts = New-Stack
    $tt = New-Text -Text $Title -Size 26 -Weight 'Bold'
    $st = New-Text -Text $Subtitle -Size 14 -Color 'Muted' -Margin (0, 4, 0, 0) -Wrap
    [void]$ts.Children.Add($tt); [void]$ts.Children.Add($st)
    [void]$hdr.Children.Add($ts)
    [void]$body.Children.Add($hdr)
    $scroll.Content = $body
    [void]$root.Children.Add($scroll)
    if ($null -ne $ActionBar) {
        [System.Windows.Controls.Grid]::SetRow($ActionBar, 1)
        [void]$root.Children.Add($ActionBar)
    }
    return @{ Root = $root; Body = $body; HeaderRight = $hr; Title = $tt; Subtitle = $st; Scroll = $scroll }
}

function New-Placeholder {
    param([string]$Text = 'Загрузка…')
    $t = New-Text -Text $Text -Size 13 -Color 'Muted' -Margin (16, 14, 16, 14)
    return $t
}

function Show-Confirm {
    param([string]$Message, [string]$Title = 'PotatoPC', [switch]$Warning)
    $icon = if ($Warning) { 'Warning' } else { 'Question' }
    $r = [System.Windows.MessageBox]::Show($script:Window, $Message, $Title, 'YesNo', $icon)
    return ($r -eq 'Yes')
}

function Show-Info {
    param([string]$Message, [string]$Title = 'PotatoPC', [string]$Icon = 'Information')
    [void][System.Windows.MessageBox]::Show($script:Window, $Message, $Title, 'OK', $Icon)
}

function Show-FormDialog {
    <#
      Небольшое модальное окно в стиле приложения. $Build получает StackPanel
      для полей; $OnOk возвращает $true, чтобы закрыть окно. Возвращает $true при OK.
    #>
    param([string]$Title, [scriptblock]$Build, [scriptblock]$OnOk, [string]$OkText = 'Готово', [double]$Width = 420)
    $w = New-Object System.Windows.Window
    $w.Owner = $script:Window; $w.WindowStartupLocation = 'CenterOwner'
    $w.Width = $Width * $script:UiScale; $w.SizeToContent = 'Height'; $w.ResizeMode = 'NoResize'
    $w.Title = $Title; $w.Background = Get-Brush 'Bg'; $w.Foreground = Get-Brush 'Text'
    $w.FontFamily = $script:Window.FontFamily
    foreach ($k in $script:Window.Resources.MergedDictionaries) { [void]$w.Resources.MergedDictionaries.Add($k) }
    foreach ($key in $script:Window.Resources.Keys) { $w.Resources[$key] = $script:Window.Resources[$key] }
    $sp = New-Stack -Margin (22, 18, 22, 18)
    [void]$sp.Children.Add((New-Text -Text $Title -Size 18 -Weight 'Bold' -Margin (0, 0, 0, 14)))
    $fields = New-Stack
    # Высокие окна (много дисков, много программ) прокручиваются, а не уходят за край экрана.
    $sv = New-Object System.Windows.Controls.ScrollViewer
    $sv.VerticalScrollBarVisibility = 'Auto'; $sv.HorizontalScrollBarVisibility = 'Disabled'
    $sv.MaxHeight = [Math]::Max(320, [System.Windows.SystemParameters]::WorkArea.Height / $script:UiScale - 230)
    $sv.Content = $fields
    [void]$sp.Children.Add($sv)
    & $Build $fields
    $err = New-Text -Text '' -Size 12 -Color 'Bad' -Wrap -Margin (0, 0, 0, 8)
    [void]$sp.Children.Add($err)
    $btns = New-Stack -Orientation Horizontal
    $btns.HorizontalAlignment = 'Right'
    $script:DlgState = @{ Window = $w; OnOk = $OnOk; Fields = $fields; Err = $err; Result = $false; Ok = $null }
    $cancel = New-Button -Text 'Отмена' -OnClick { $script:DlgState.Window.Close() }
    $ok = New-Button -Text $OkText -Kind Primary -OnClick {
        try {
            $r = & $script:DlgState.OnOk $script:DlgState.Fields
            if ($r -is [string]) { $script:DlgState.Err.Text = $r; return }
            if ($r) { $script:DlgState.Result = $true; $script:DlgState.Window.Close() }
        } catch { $script:DlgState.Err.Text = $_.Exception.Message }
    }
    $ok.Margin = New-Thickness 10, 0, 0, 0
    $script:DlgState.Ok = $ok
    [void]$btns.Children.Add($cancel); [void]$btns.Children.Add($ok)
    [void]$sp.Children.Add($btns)
    Add-UiScale $sp
    $w.Content = $sp
    try { Enable-DarkTitleBar -Target $w } catch {}
    [void]$w.ShowDialog()
    return $script:DlgState.Result
}

function Show-ActionMenu {
    <#
      Тёмное меню под кнопкой «⋯». Items: @{ Text; Tag; OnClick; Danger; Checked; Separator }.
    #>
    param($Anchor, [object[]]$Items, [switch]$AtMouse)
    $cm = New-Object System.Windows.Controls.ContextMenu
    $cm.Style = $script:Window.FindResource('Menu')
    foreach ($i in $Items) {
        if ($i.Separator) { $s = New-Object System.Windows.Controls.Separator; $s.Style = $script:Window.FindResource('MenuSep'); [void]$cm.Items.Add($s); continue }
        $mi = New-Object System.Windows.Controls.MenuItem
        $mi.Style = $script:Window.FindResource('MenuItem')
        $mi.Header = [string]$i.Text
        if ($i.Danger) { $mi.Foreground = Get-Brush 'Bad' }
        if ($i.Disabled) { $mi.IsEnabled = $false }
        if ($null -ne $i.Checked) { $mi.IsCheckable = $true; $mi.IsChecked = [bool]$i.Checked }
        $mi.Tag = $i.Tag
        if ($i.OnClick) { $mi.Add_Click($i.OnClick) }
        [void]$cm.Items.Add($mi)
    }
    Add-UiScale $cm
    $cm.PlacementTarget = $Anchor
    $cm.Placement = if ($AtMouse) { 'MousePoint' } else { 'Bottom' }
    # Пока меню открыто, живые списки (например «Кто сейчас в сети») не перерисовываются.
    $script:ActionMenuOpen = $true
    $cm.Add_Closed({ $script:ActionMenuOpen = $false })
    $cm.IsOpen = $true
}

function Open-Path {
    param([string]$Path)
    try { Start-Process -FilePath $Path } catch { Write-Log ('Не удалось открыть: ' + $Path) 'warn' }
}

# --- Оболочка ---

function Import-Shell {
    $theme = [System.IO.File]::ReadAllText((Join-Path $AssetsFolder 'Theme.xaml'), [System.Text.Encoding]::UTF8)
    $shell = [System.IO.File]::ReadAllText((Join-Path $AssetsFolder 'Shell.xaml'), [System.Text.Encoding]::UTF8)
    $a = $theme.IndexOf('>', $theme.IndexOf('<ResourceDictionary')) + 1
    $b = $theme.LastIndexOf('</ResourceDictionary>')
    $inner = $theme.Substring($a, $b - $a)
    $shell = $shell.Replace('<WindowChrome.WindowChrome>', '<Window.Resources><ResourceDictionary>' + $inner + '</ResourceDictionary></Window.Resources><WindowChrome.WindowChrome>')
    $w = [System.Windows.Markup.XamlReader]::Parse($shell)
    return $w
}

function Enable-DarkTitleBar {
    param($Target)
    try {
        if (-not ('PotatoPC.Dwm' -as [type])) {
            Add-Type -Namespace 'PotatoPC' -Name 'Dwm' -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(System.IntPtr h, int a, ref int v, int s);'
        }
        $h = (New-Object System.Windows.Interop.WindowInteropHelper $Target).EnsureHandle()
        $v = 1
        [void][PotatoPC.Dwm]::DwmSetWindowAttribute($h, 20, [ref]$v, 4)
    } catch {}
}

# --- Масштаб окна ---
# Всё содержимое окна рисуется через LayoutTransform, поэтому на маленьких
# экранах (ноутбуки 1366×768, 125–150 % в Windows) окно целиком становится меньше.

$script:UiBaseW = 1240; $script:UiBaseH = 800      # размер окна при 100 %
$script:UiMinW = 980;   $script:UiMinH = 620
$script:UiScale = 1.0
$script:UiScaleAuto = $true
$script:UiScaleSteps = @(0.7, 0.75, 0.8, 0.85, 0.9, 1.0, 1.1, 1.25)

function Get-AutoUiScale {
    # Самый крупный шаг, при котором окно занимает не больше ~90 % рабочей области.
    $wa = [System.Windows.SystemParameters]::WorkArea
    $fit = [Math]::Min(($wa.Width * 0.92) / $script:UiBaseW, ($wa.Height * 0.9) / $script:UiBaseH)
    $best = $script:UiScaleSteps[0]
    foreach ($s in $script:UiScaleSteps) { if ($s -le 1.0 -and $s -le $fit) { $best = $s } }
    return $best
}

function Add-UiScale {
    # Для отдельных окон и всплывающих меню: они не наследуют масштаб главного окна.
    param($Element)
    if ($Element -and [Math]::Abs($script:UiScale - 1.0) -gt 0.001) {
        $Element.LayoutTransform = New-Object System.Windows.Media.ScaleTransform $script:UiScale, $script:UiScale
    }
}

function Set-UiScale {
    param([double]$Scale = 1.0, [switch]$Auto, [switch]$KeepSize)
    $w = $script:Window
    if ($Auto) { $Scale = Get-AutoUiScale }
    $Scale = [Math]::Max(0.6, [Math]::Min(1.5, $Scale))
    $old = $script:UiScale
    $script:UiScale = $Scale
    $script:UiScaleAuto = [bool]$Auto
    $content = $w.FindName('RootBorder').Child
    $content.LayoutTransform = if ([Math]::Abs($Scale - 1.0) -lt 0.001) { [System.Windows.Media.Transform]::Identity } else { New-Object System.Windows.Media.ScaleTransform $Scale, $Scale }
    try { [System.Windows.Shell.WindowChrome]::GetWindowChrome($w).CaptionHeight = 36 * $Scale } catch {}
    $wa = [System.Windows.SystemParameters]::WorkArea
    $w.MinWidth = [Math]::Min($script:UiMinW * $Scale, $wa.Width)
    $w.MinHeight = [Math]::Min($script:UiMinH * $Scale, $wa.Height)
    $w.FindName('ScaleText').Text = ([string][int][Math]::Round($Scale * 100)) + '%'
    if ($KeepSize -or $w.WindowState -ne 'Normal') { return }
    # Окно меняет размер вместе с масштабом, центр остаётся на месте и окно не уходит за экран.
    $loaded = $w.IsLoaded
    if ($loaded) {
        $cx = $w.Left + $w.ActualWidth / 2; $cy = $w.Top + $w.ActualHeight / 2
        $nw = $w.ActualWidth * $Scale / $old; $nh = $w.ActualHeight * $Scale / $old
    } else {
        $nw = $script:UiBaseW * $Scale; $nh = $script:UiBaseH * $Scale
    }
    $nw = [Math]::Max($w.MinWidth, [Math]::Min($nw, $wa.Width))
    $nh = [Math]::Max($w.MinHeight, [Math]::Min($nh, $wa.Height))
    $w.Width = $nw; $w.Height = $nh
    if ($loaded) {
        $w.Left = [Math]::Max($wa.Left, [Math]::Min($cx - $nw / 2, $wa.Right - $nw))
        $w.Top = [Math]::Max($wa.Top, [Math]::Min($cy - $nh / 2, $wa.Bottom - $nh))
    }
}

function Step-UiScale {
    param([int]$Dir)
    $steps = $script:UiScaleSteps
    $i = 0
    for ($k = 0; $k -lt $steps.Count; $k++) { if ([Math]::Abs($steps[$k] - $script:UiScale) -lt 0.001 -or $steps[$k] -lt $script:UiScale) { $i = $k } }
    $j = [Math]::Max(0, [Math]::Min($steps.Count - 1, $i + $Dir))
    if ($j -ne $i -or -not ([Math]::Abs($steps[$i] - $script:UiScale) -lt 0.001)) { Set-UiScale -Scale $steps[$j] }
}

function Show-UiScaleMenu {
    $auto = Get-AutoUiScale
    $items = @(@{ Text = 'По размеру экрана (' + [int][Math]::Round($auto * 100) + '%)'; Tag = 'auto'; Checked = $script:UiScaleAuto
                  OnClick = { Set-UiScale -Auto } }
               @{ Separator = $true })
    foreach ($s in $script:UiScaleSteps) {
        $items += @{ Text = ([string][int][Math]::Round($s * 100)) + '%'; Tag = $s
                     Checked = (-not $script:UiScaleAuto -and [Math]::Abs($s - $script:UiScale) -lt 0.001)
                     OnClick = { Set-UiScale -Scale ([double]$this.Tag) } }
    }
    Show-ActionMenu -Anchor $script:Window.FindName('ScaleBtn') -Items $items
}

$script:Pages = [ordered]@{}
$script:NavButtons = @{}
$script:CurrentPage = ''

function Register-Pages {
    # Ищет pages\*.ps1 с шапкой «# PAGE: id». Сами файлы подключает menu.ps1.
    $list = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $PagesFolder -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $h = Read-PluginHeader -Path $f.FullName
        if (-not $h['PAGE']) { continue }
        $order = 500; if ([string]$h['ORDER'] -match '^\d+$') { $order = [int]$h['ORDER'] }
        $list += [pscustomobject]@{
            Id = ([string]$h['PAGE']).Trim(); Title = [string]$h['TITLE']; Icon = [string]$h['ICON']
            Order = $order; Nav = $(if ($h['NAV']) { [string]$h['NAV'] } else { 'main' }); File = $f.FullName
            Built = $false; View = $null
        }
    }
    foreach ($p in ($list | Sort-Object Order)) { $script:Pages[$p.Id] = $p }
}

function Initialize-Nav {
    $nav = $script:Window.FindName('NavPanel')
    $foot = $script:Window.FindName('FooterPanel')
    foreach ($p in $script:Pages.Values) {
        $sp = New-Stack -Orientation Horizontal
        $ic = New-Icon -Name $p.Icon -Size 18 -Color 'Muted'
        [void]$sp.Children.Add($ic)
        $t = New-Object System.Windows.Controls.TextBlock
        $t.Text = $p.Title; $t.Margin = New-Thickness 12, 0, 0, 0; $t.VerticalAlignment = 'Center'
        [void]$sp.Children.Add($t)
        $b = New-Object System.Windows.Controls.Button
        $b.Style = $script:Window.FindResource('BtnNav')
        $b.Content = $sp; $b.Tag = $p.Id
        $b.Add_Click({ Show-Page -Id $this.Tag })
        if ($p.Nav -eq 'footer') { $b.MinHeight = 36; $b.FontSize = 13; [void]$foot.Children.Add($b) } else { [void]$nav.Children.Add($b) }
        $script:NavButtons[$p.Id] = @{ Button = $b; Icon = $ic }
    }
    $rp = New-Object System.Windows.Controls.Button
    $rp.Style = $script:Window.FindResource('BtnNav'); $rp.MinHeight = 36; $rp.FontSize = 13
    $sp = New-Stack -Orientation Horizontal
    [void]$sp.Children.Add((New-Icon -Name 'flag' -Size 17 -Color 'Muted'))
    $t = New-Object System.Windows.Controls.TextBlock; $t.Text = 'Точка восстановления'; $t.Margin = New-Thickness 12, 0, 0, 0; $t.VerticalAlignment = 'Center'
    [void]$sp.Children.Add($t)
    $rp.Content = $sp
    $rp.ToolTip = 'Создать точку восстановления Windows сейчас'
    $rp.Add_Click({
        Start-BgTask -Name 'Точка восстановления' -Script { New-RestorePoint -Description 'PotatoPC: вручную' } | Out-Null
    })
    [void]$foot.Children.Add($rp)
}

function Show-Page {
    param([string]$Id, $Arg = $null)
    if (-not $script:Pages.Contains($Id)) { return }
    $p = $script:Pages[$Id]
    if (-not $p.Built) {
        try {
            $fn = 'Build-Page_' + $Id
            $p.View = & $fn
            $p.Built = $true
        } catch {
            Write-Log ('Страница «' + $p.Title + '» не открылась: ' + $_.Exception.Message) 'err'
            $p.View = New-Text -Text ('Ошибка: ' + $_.Exception.Message) -Color 'Bad' -Wrap -Margin (28, 28, 28, 28)
        }
    }
    foreach ($k in $script:NavButtons.Keys) {
        $nb = $script:NavButtons[$k]
        $active = ($k -eq $Id)
        $nb.Button.Background = if ($active) { Get-Brush 'Card' } else { [System.Windows.Media.Brushes]::Transparent }
        $nb.Button.Foreground = if ($active) { Get-Brush 'Text' } else { Get-Brush 'Muted' }
        $nb.Button.FontWeight = if ($active) { 'SemiBold' } else { 'Normal' }
        try { $nb.Icon.Child.Children[0].Stroke = if ($active) { Get-Brush 'Accent' } else { Get-Brush 'Muted' } } catch {}
    }
    $script:Window.FindName('PageHost').Child = $p.View
    $script:Window.FindName('CaptionText').Text = 'PotatoPC · ' + $p.Title
    $script:CurrentPage = $Id
    $fnShow = 'Show-Page_' + $Id
    if (Get-Command $fnShow -ErrorAction SilentlyContinue) {
        try { & $fnShow $Arg } catch { Write-Log ('Страница «' + $p.Title + '»: ' + $_.Exception.Message) 'err' }
    }
}

function Add-LogLine {
    param($Item)
    $box = $script:LogBox
    if (-not $box) { return }
    if ($box.LineCount -gt 3000) { $box.Text = ($box.Text -split "`n" | Select-Object -Last 2000) -join "`n" }
    $box.AppendText($Item.Text + "`n")
    if ($script:LogPanel.Visibility -eq 'Visible') { $box.ScrollToEnd() }
    $script:LogLast.Text = $Item.Raw
    $script:LogLast.Foreground = switch ($Item.Level) { 'ok' { Get-Brush 'Ok' } 'warn' { Get-Brush 'Warn' } 'err' { Get-Brush 'Bad' } default { Get-Brush 'Muted' } }
    if ($Item.Level -eq 'err' -and $script:LogPanel.Visibility -ne 'Visible') { Set-LogVisible $true }
}

function Set-LogVisible {
    param([bool]$Visible)
    $script:LogPanel.Visibility = if ($Visible) { 'Visible' } else { 'Collapsed' }
    $script:Window.FindName('LogToggleBtn').Content = if ($Visible) { 'Журнал ▾' } else { 'Журнал ▴' }
    if ($Visible) { $script:LogBox.ScrollToEnd() }
}

function Update-BusyIndicator {
    $running = @(Get-RunningTasks)
    $bar = $script:Window.FindName('BusyBar')
    $stop = $script:Window.FindName('StopTaskBtn')
    if ($running.Count -gt 0) {
        $bar.Visibility = 'Visible'
        $stop.Visibility = 'Visible'
        $stop.ToolTip = 'Остановить: ' + (($running | ForEach-Object { $_.Name }) -join ', ')
    } else {
        $bar.Visibility = 'Hidden'
        $stop.Visibility = 'Collapsed'
    }
}

function Initialize-ShellEvents {
    $w = $script:Window
    $script:LogBox = $w.FindName('LogBox')
    $script:LogPanel = $w.FindName('LogPanel')
    $script:LogLast = $w.FindName('LogLastText')
    $w.FindName('VersionText').Text = 'v' + $AppVersion + ' · ' + $WinInfo.Name + $(if ($PortableMode) { ' · портативно' } else { '' })
    $w.FindName('MinBtn').Add_Click({ $script:Window.WindowState = 'Minimized' })
    $w.FindName('MaxBtn').Add_Click({ if ($script:Window.WindowState -eq 'Maximized') { $script:Window.WindowState = 'Normal' } else { $script:Window.WindowState = 'Maximized' } })
    $w.FindName('CloseBtn').Add_Click({ $script:Window.Close() })
    $w.FindName('ScaleBtn').Add_Click({ Show-UiScaleMenu })
    # Ctrl + колесо мыши, Ctrl +/-, Ctrl + 0 (по размеру экрана).
    $w.Add_PreviewMouseWheel({
        param($s, $e)
        if ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) {
            Step-UiScale $(if ($e.Delta -gt 0) { 1 } else { -1 }); $e.Handled = $true
        }
    })
    $w.Add_PreviewKeyDown({
        param($s, $e)
        if (-not ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) { return }
        switch ([string]$e.Key) {
            { $_ -in 'OemPlus', 'Add' } { Step-UiScale 1; $e.Handled = $true }
            { $_ -in 'OemMinus', 'Subtract' } { Step-UiScale -1; $e.Handled = $true }
            { $_ -in 'D0', 'NumPad0' } { Set-UiScale -Auto; $e.Handled = $true }
        }
    })
    $w.Add_StateChanged({
        # WindowStyle=None в развёрнутом виде вылезает за край экрана на ~7 px.
        $rb = $script:Window.FindName('RootBorder')
        $rb.Margin = if ($script:Window.WindowState -eq 'Maximized') { New-Thickness 7 } else { New-Thickness 0 }
        $script:Window.FindName('MaxIcon').Data = [System.Windows.Media.Geometry]::Parse($(if ($script:Window.WindowState -eq 'Maximized') { 'M2.5,0.5 H9.5 V7.5 M0.5,2.5 H7.5 V9.5 H0.5 Z' } else { 'M0.5,0.5 H9.5 V9.5 H0.5 Z' }))
    })
    $w.FindName('LogToggleBtn').Add_Click({ Set-LogVisible ($script:LogPanel.Visibility -ne 'Visible') })
    $w.FindName('LogCopyBtn').Add_Click({ try { [System.Windows.Clipboard]::SetText($script:LogBox.Text) } catch {} })
    $w.FindName('LogOpenBtn').Add_Click({ Open-Path $LogPath })
    $w.FindName('LogClearBtn').Add_Click({ $script:LogBox.Clear() })
    $w.FindName('StopTaskBtn').Add_Click({
        foreach ($j in @(Get-RunningTasks)) { Stop-BgTask $j }
        Write-Log 'Остановка запрошена…' 'warn'
    })
    $script:PollTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:PollTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:PollTimer.Add_Tick({ try { Invoke-BgPoll } catch {} })
    $script:PollTimer.Start()
}
