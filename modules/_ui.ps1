# Общие UI-хелперы — биндинг контролов + фабрики карточек

function Initialize-Controls {
    param([System.Windows.Window]$Window)
    $map = @{
        LogBox              = "LogOutput"
        ScriptsPanel        = "ScriptsPanel"
        AppsPanel           = "AppsPanel"
        SysPanel            = "SysPanel"
        UpdatesPanel        = "UpdatesPanel"
        DiagPanel           = "DiagPanel"
        ScriptsFolderText   = "ScriptsFolderText"
        SelectedCountText   = "SelectedCountText"
        RunScriptsBtn       = "RunScriptsBtn"
        RebootAfterChk      = "RebootAfterScriptsChk"
        SelectAllBtn        = "SelectAllBtn"
        DeselectAllBtn      = "DeselectAllBtn"
        RefreshBtn          = "RefreshBtn"
        OpenFolderBtn       = "OpenFolderBtn"
        ClearLogBtn         = "ClearLogBtn"
        CopyLogBtn          = "CopyLogBtn"
        ToggleLogBtn        = "ToggleLogBtn"
        LogSplitter         = "LogSplitter"
        LogRow              = "LogRow"
        LogOuterBorder      = "LogOuterBorder"
        LogHeaderBorder     = "LogHeaderBorder"
        MainTabControl      = "MainTabControl"
        InstallAppsBtn      = "InstallAppsBtn"
        SelectAllAppsBtn    = "SelectAllAppsBtn"
        DeselectAllAppsBtn  = "DeselectAllAppsBtn"
        AppCountText        = "AppCountText"
        RestorePointBtn     = "RestorePointBtn"
        PresetOfficeBtn     = "PresetOfficeBtn"
        PresetGamesBtn      = "PresetGamesBtn"
        SelectRecommendedBtn= "SelectRecommendedBtn"
        CheckUpdatesBtn     = "CheckUpdatesBtn"
        SelectAllUpdatesBtn = "SelectAllUpdatesBtn"
        DeselectAllUpdatesBtn="DeselectAllUpdatesBtn"
        InstallUpdatesBtn   = "InstallUpdatesBtn"
        UpdateStatusText    = "UpdateStatusText"
        UpdateCountText     = "UpdateCountText"
        StartupAppsPanel    = "StartupAppsPanel"
        RefreshStartupBtn   = "RefreshStartupBtn"
        DisableStartupBtn   = "DisableStartupBtn"
        EnableStartupBtn    = "EnableStartupBtn"
        SelectAllStartupBtn = "SelectAllStartupBtn"
        DeselectAllStartupBtn="DeselectAllStartupBtn"
        StartupFilterAllBtn = "StartupFilterAllBtn"
        StartupFilterAppBtn = "StartupFilterAppBtn"
        StartupFilterTaskBtn= "StartupFilterTaskBtn"
        StartupCountText    = "StartupCountText"
        StartupSelectedText = "StartupSelectedText"
        StartupSearchBox    = "StartupSearchBox"
        StartupSearchHint   = "StartupSearchHint"
        StartupSearchClear  = "StartupSearchClear"
        UsersPanel          = "UsersPanel"
        RefreshUsersBtn     = "RefreshUsersBtn"
        AddUserBtn          = "AddUserBtn"
        ScriptSearchBox     = "ScriptSearchBox"
        ScriptSearchHint    = "ScriptSearchHint"
        ScriptSearchClear   = "ScriptSearchClear"
        AppSearchBox        = "AppSearchBox"
        AppSearchHint       = "AppSearchHint"
        AppSearchClear      = "AppSearchClear"
        ToolsBtn            = "ToolsBtn"
        AdminBtn            = "AdminBtn"
        UninstallAppsPanel  = "UninstallAppsPanel"
        RefreshUninstallBtn = "RefreshUninstallBtn"
        UninstallSelectedBtn= "UninstallSelectedBtn"
        BcuUninstallBtn     = "BcuUninstallBtn"
        SelectAllUninstallBtn  = "SelectAllUninstallBtn"
        DeselectAllUninstallBtn="DeselectAllUninstallBtn"
        UninstallFilterAllBtn  = "UninstallFilterAllBtn"
        UninstallFilterWin32Btn= "UninstallFilterWin32Btn"
        UninstallFilterStoreBtn= "UninstallFilterStoreBtn"
        UninstallCountText  = "UninstallCountText"
        UninstallSelectedText="UninstallSelectedText"
        UninstallSearchBox  = "UninstallSearchBox"
        UninstallSearchHint = "UninstallSearchHint"
        UninstallSearchClear= "UninstallSearchClear"
        QuietUninstallChk   = "QuietUninstallChk"
        CleanLeftoversChk   = "CleanLeftoversChk"
    }
    foreach ($kv in $map.GetEnumerator()) {
        Set-Variable -Name $kv.Key -Value $Window.FindName($kv.Value) -Scope Global
    }
}

function New-Card {
    param(
        [switch]$Dimmed,
        [switch]$Recommended,
        [switch]$Incompatible,
        [System.Windows.Thickness]$Padding,
        [switch]$Large
    )
    $card = [System.Windows.Controls.Border]::new()
    $card.CornerRadius = if ($Large) { $script:Theme.CornerCardLarge } else { $script:Theme.CornerCard }
    $card.Margin       = $script:Theme.MarginCard
    $card.Padding      = if ($Padding) { $Padding } else { $script:Theme.PadCard }
    if ($Incompatible) {
        $card.Background     = Get-ThemeBrush "#141420"
        $card.BorderBrush    = Get-ThemeBrush "#2a1a2a"
        $card.BorderThickness= $script:Theme.BorderAccentR
        $card.Opacity        = 0.55
    } elseif ($Recommended) {
        $card.Background     = $script:Theme.CardBg
        $card.BorderBrush    = Get-ThemeBrush "#d4a017"
        $card.BorderThickness= $script:Theme.BorderAccentR
    } elseif ($Dimmed) {
        $card.Background     = $script:Theme.CardBgDim
        $card.BorderBrush    = $script:Theme.CardBorderDim
        $card.BorderThickness= $script:Theme.BorderBottom
        $card.Opacity        = 0.6
    } else {
        $card.Background     = $script:Theme.CardBg
        $card.BorderBrush    = $script:Theme.CardBorder
        $card.BorderThickness= $script:Theme.BorderBottom
    }
    return $card
}

function New-CategoryHeader {
    param([string]$Title, [string]$Kind = "default")
    $b = [System.Windows.Controls.Border]::new()
    $b.Margin          = [System.Windows.Thickness]::new(0,10,0,4)
    $b.Padding         = [System.Windows.Thickness]::new(0,0,0,4)
    $b.BorderBrush     = $script:Theme.CardBorder
    $b.BorderThickness = $script:Theme.BorderBottom
    $t = [System.Windows.Controls.TextBlock]::new()
    $t.Text       = $Title.ToUpper()
    $t.Foreground = $script:Theme.Accent
    $t.FontSize   = 11
    $t.FontWeight = "SemiBold"
    $b.Child = $t
    return $b
}

function New-TagBadge {
    param([int]$Tag)
    $b = [System.Windows.Controls.Border]::new()
    $b.CornerRadius = $script:Theme.CornerTag
    $b.Padding      = $script:Theme.PadTag
    $b.Margin       = [System.Windows.Thickness]::new(7,0,0,0)
    $b.VerticalAlignment = "Center"
    $b.BorderThickness   = $script:Theme.BorderThin
    $txt = [System.Windows.Controls.TextBlock]::new()
    $txt.FontSize   = 10
    $txt.FontWeight = "SemiBold"
    switch ($Tag) {
        1 { $b.Background= $script:Theme.SuccessBg; $b.BorderBrush=$script:Theme.SuccessBorder; $txt.Text="● безопасно";  $txt.Foreground=$script:Theme.SuccessFg }
        2 { $b.Background= $script:Theme.WarnBg;    $b.BorderBrush=$script:Theme.WarnBorder;    $txt.Text="● осторожно"; $txt.Foreground=$script:Theme.WarnFg }
        3 { $b.Background= $script:Theme.DangerBg;  $b.BorderBrush=$script:Theme.DangerBorder;  $txt.Text="● опасно";    $txt.Foreground=$script:Theme.DangerFg }
    }
    $b.Child = $txt
    return $b
}
