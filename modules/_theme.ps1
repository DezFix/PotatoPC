# Централизованная тема — цвета, кисти, Thickness/CornerRadius
# Заменяет десятки строк BrushConverter::ConvertFrom по коду

$script:Theme = @{}

# helper — кэширует SolidColorBrush и сразу Freeze для потокобезопасности
$script:_brushCache = @{}
function Get-ThemeBrush {
    param([string]$Hex)
    if (-not $script:_brushCache.ContainsKey($Hex)) {
        $b = [Windows.Media.BrushConverter]::new().ConvertFrom($Hex)
        try { $b.Freeze() } catch {}
        $script:_brushCache[$Hex] = $b
    }
    return $script:_brushCache[$Hex]
}

# палитра
$script:Theme.CardBg          = Get-ThemeBrush "#1a1a2e"
$script:Theme.CardBgHover     = Get-ThemeBrush "#20203a"
$script:Theme.CardBorder      = Get-ThemeBrush "#1e1e38"
$script:Theme.CardBgDim       = Get-ThemeBrush "#111118"
$script:Theme.CardBorderDim   = Get-ThemeBrush "#1a1a25"
$script:Theme.Accent          = Get-ThemeBrush "#6c63ff"
$script:Theme.AccentBgBtn     = Get-ThemeBrush "#6c63ff"
$script:Theme.TextPrimary     = Get-ThemeBrush "#e0e0f4"
$script:Theme.TextSecondary   = Get-ThemeBrush "#c4c4ee"
$script:Theme.TextMuted       = Get-ThemeBrush "#9898b8"
$script:Theme.TextHeader      = Get-ThemeBrush "#5050a0"
$script:Theme.SuccessBg       = Get-ThemeBrush "#0d2d1a"
$script:Theme.SuccessBorder   = Get-ThemeBrush "#1a6b35"
$script:Theme.SuccessFg       = Get-ThemeBrush "#2ecc71"
$script:Theme.WarnBg          = Get-ThemeBrush "#2d2200"
$script:Theme.WarnBorder      = Get-ThemeBrush "#a07800"
$script:Theme.WarnFg          = Get-ThemeBrush "#f0c040"
$script:Theme.DangerBg        = Get-ThemeBrush "#2d0d0d"
$script:Theme.DangerBorder    = Get-ThemeBrush "#6b1a1a"
$script:Theme.DangerFg        = Get-ThemeBrush "#e74c3c"

# частые Thickness / CornerRadius — синглтоны
$script:Theme.PadCard         = [System.Windows.Thickness]::new(10,6,10,6)
$script:Theme.PadCardSys      = [System.Windows.Thickness]::new(12,9,12,9)
$script:Theme.PadTag          = [System.Windows.Thickness]::new(5,1,5,1)
$script:Theme.PadBadge        = [System.Windows.Thickness]::new(5,2,5,2)
$script:Theme.MarginCard      = [System.Windows.Thickness]::new(0,2,0,2)
$script:Theme.MarginCardSys   = [System.Windows.Thickness]::new(0,3,0,3)
$script:Theme.BorderThin      = [System.Windows.Thickness]::new(1)
$script:Theme.BorderAccentR   = [System.Windows.Thickness]::new(0,0,3,0)
$script:Theme.BorderBottom    = [System.Windows.Thickness]::new(0,0,0,1)
$script:Theme.CornerCard      = [System.Windows.CornerRadius]::new(7)
$script:Theme.CornerCardLarge = [System.Windows.CornerRadius]::new(8)
$script:Theme.CornerTag       = [System.Windows.CornerRadius]::new(4)
