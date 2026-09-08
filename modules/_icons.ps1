# Иконки Papirus (GNU GPL 3.0) из assets/icons — замена эмодзи в UI.
# Лог и консоль намеренно остаются текстовыми: моноширинный TextBox не умеет
# встроенные картинки, а глифы ✓✗●▶⚠ — символы шрифта Consolas/Segoe UI,
# а не эмодзи. Атрибуция: assets/icons/ICONS.md

function Get-IconDir {
    if ($script:IconDir -and (Test-Path $script:IconDir)) { return $script:IconDir }
    $cands = @()
    try { if ($script:ScriptsFolder) { $cands += (Join-Path (Split-Path $script:ScriptsFolder -Parent) 'assets\icons') } } catch {}
    try { if ($script:ModuleDir)     { $cands += (Join-Path (Split-Path $script:ModuleDir -Parent) 'assets\icons') } } catch {}
    foreach ($c in $cands) {
        if ($c -and (Test-Path $c)) { $script:IconDir = $c; return $c }
    }
    return $null
}

$script:_iconSrcCache = @{}

function Get-IconSource {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    $key = $Name.Trim().ToLowerInvariant().Replace('/', '\')
    if ($script:_iconSrcCache.ContainsKey($key)) { return $script:_iconSrcCache[$key] }
    $src = $null
    try {
        $dir = Get-IconDir
        if ($dir) {
            $file = Join-Path $dir ($key + '.png')
            if (Test-Path $file) {
                $bi = [System.Windows.Media.Imaging.BitmapImage]::new()
                $bi.BeginInit()
                $bi.UriSource = [System.Uri]::new($file)
                $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $bi.EndInit()
                try { $bi.Freeze() } catch {}
                $src = $bi
            }
        }
    } catch {}
    $script:_iconSrcCache[$key] = $src
    return $src
}

function Get-IconImage {
    param([string]$Name, [int]$Size = 16)
    $src = Get-IconSource -Name $Name
    if ($null -eq $src) { return $null }
    try {
        $img = [System.Windows.Controls.Image]::new()
        $img.Source = $src
        $img.Width = $Size; $img.Height = $Size
        $img.Stretch = [System.Windows.Media.Stretch]::Uniform
        $img.VerticalAlignment = 'Center'
        return $img
    } catch { return $null }
}

# Маппинг ICON-заголовков скриптов (эмодзи -> слот иконки).
# Ключи и вход нормализуются от VS16/ZWJ, поэтому форма заголовка не важна.
$script:EmojiIconMap = @{
    '📄' = 'mimetypes/doc_generic'
    '🤖' = 'mimetypes/robot'
    '🎤' = 'devices/mic'
    '🗑' = 'places/trash'
    '📂' = 'places/folder_open'
    '📦' = 'mimetypes/nav_apps'
    '📜' = 'mimetypes/doc_generic'
    '📝' = 'actions/doc_new'
    '🚫' = 'status/privacy'
    '📌' = 'actions/location'
    '🪟' = 'devices/computer'
    '🕵' = 'status/privacy'
    '🖱' = 'devices/mouse'
    '🌙' = 'status/night'
    '🖥' = 'devices/display'
    '🔬' = 'apps/nav_diag'
    '🛡' = 'status/password'
    '↩' = 'actions/undo'
    '⚡' = 'actions/power'
    '🎮' = 'apps/games'
    '⌨' = 'devices/keyboard'
    '🌐' = 'devices/network'
    '⚙' = 'actions/admin_gear'
}

function Get-ScriptIconName {
    param([string]$Emoji)
    if ([string]::IsNullOrWhiteSpace($Emoji)) { return 'mimetypes/script_default' }
    $clean = ($Emoji -replace '️', '').Trim()
    if ($script:EmojiIconMap.ContainsKey($clean)) { return $script:EmojiIconMap[$clean] }
    return 'mimetypes/script_default'
}

# Заголовок секции с иконкой (для панелей, строящихся в коде)
function New-SectionHeader {
    param([string]$Title, [string]$Icon = '', [string]$Color = '#6c63ff')
    $b = [System.Windows.Controls.Border]::new()
    $b.Margin = [System.Windows.Thickness]::new(0,8,0,4)
    $b.Padding = [System.Windows.Thickness]::new(0,0,0,6)
    $b.BorderBrush = $script:Theme.CardBorder
    $b.BorderThickness = $script:Theme.BorderBottom
    $row = [System.Windows.Controls.StackPanel]::new()
    $row.Orientation = 'Horizontal'; $row.VerticalAlignment = 'Center'
    if ($Icon) {
        $img = Get-IconImage -Name $Icon -Size 13
        if ($img) { $img.Margin = [System.Windows.Thickness]::new(0,0,7,0); $row.Children.Add($img) | Out-Null }
    }
    $t = [System.Windows.Controls.TextBlock]::new()
    $t.Text = $Title.ToUpper()
    try { $t.Foreground = $script:Theme.Accent } catch { $t.Foreground = Get-ThemeBrush $Color }
    $t.FontSize = 10; $t.FontWeight = 'SemiBold'; $t.VerticalAlignment = 'Center'
    $row.Children.Add($t) | Out-Null
    $b.Child = $row
    return $b
}

# Кнопка с иконкой+текстом (для кнопок, строящихся в коде)
function New-IconButtonContent {
    param([string]$Text, [string]$Icon = '', [int]$Size = 12)
    $row = [System.Windows.Controls.StackPanel]::new()
    $row.Orientation = 'Horizontal'; $row.VerticalAlignment = 'Center'
    if ($Icon) {
        $img = Get-IconImage -Name $Icon -Size $Size
        if ($img) { $img.Margin = [System.Windows.Thickness]::new(0,0,6,0); $row.Children.Add($img) | Out-Null }
    }
    $t = [System.Windows.Controls.TextBlock]::new()
    $t.Text = $Text; $t.VerticalAlignment = 'Center'
    $row.Children.Add($t) | Out-Null
    return $row
}

# Расставляет PNG-иконки по именованным Image в window.xaml.
# Null-safe: со старым XAML просто ничего не делает.
function Initialize-WindowIcons {
    $pairs = @(
        @('LogoIcon', 'apps/logo'), @('NavModulesIcon', 'apps/nav_modules'),
        @('NavStartupIcon', 'actions/nav_startup'), @('NavUsersIcon', 'apps/nav_users'),
        @('NavAppsIcon', 'mimetypes/nav_apps'), @('NavUpdatesIcon', 'apps/nav_updates'),
        @('NavDiagIcon', 'apps/nav_diag'), @('NavSysIcon', 'devices/nav_sys'),
        @('ModulesFolderIcon', 'places/folder_open'), @('OpenFolderIcon', 'places/folder_open'),
        @('RefreshIcon', 'actions/refresh'), @('ScriptSearchIcon', 'actions/search'),
        @('StartupSearchIcon', 'actions/search'), @('AppSearchIcon', 'actions/search'),
        @('RestorePointIcon', 'actions/restore'), @('ToolsIcon', 'apps/tools'),
        @('AdminIcon', 'actions/admin_gear'), @('PresetsIcon', 'actions/power'),
        @('PresetOfficeIcon', 'apps/office'), @('PresetGamesIcon', 'apps/games'),
        @('StartupFilterAllIcon', 'actions/select_all'), @('StartupFilterAppIcon', 'mimetypes/nav_apps'),
        @('StartupFilterTaskIcon', 'actions/calendar'), @('CheckUpdatesIcon', 'actions/search'),
        @('InstallAppsIcon', 'mimetypes/nav_apps'), @('InstallUpdatesIcon', 'actions/go_up'),
        @('UsersHeaderIcon', 'apps/nav_users'), @('DiagHeaderIcon', 'status/info'),
        @('CopyLogIcon', 'actions/copy'), @('ClearLogIcon', 'places/trash'),
        @('ToggleLogIcon', 'actions/go_down'),
        @('RefreshStartupIcon', 'actions/refresh'), @('AddUserIcon', 'apps/nav_users'),
        @('RefreshUsersIcon', 'actions/refresh')
    )
    foreach ($p in $pairs) {
        try {
            $ctl = Get-Variable -Name $p[0] -Scope Global -ValueOnly -ErrorAction SilentlyContinue
            if ($null -eq $ctl) { continue }
            $src = Get-IconSource -Name $p[1]
            if ($src) { $ctl.Source = $src }
        } catch {}
    }
}
