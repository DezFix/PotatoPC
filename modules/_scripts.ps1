$script:ScriptCheckboxes = @{}
$script:RollbackCheckboxes = @{}
$script:BatchRunning = $false
$script:BatchControl = $null
$script:BatchHandle  = $null
$script:RunBtnSaved  = $false
$script:RunBtnContent = $null
$script:RunBtnStyle   = $null
$script:RollbackBatchRunning = $false
$script:RollbackBatchControl = $null
$script:RollbackBatchHandle = $null
$script:RollbackRunBtnSaved = $false
$script:RollbackRunBtnContent = $null
$script:RollbackRunBtnStyle = $null
$script:RollbackFolderName = "09 Откат"
$script:RollbackFolder = ""
try { $script:RollbackFolder = Join-Path $script:ScriptsFolder $script:RollbackFolderName } catch {}

function Get-RollbackFolder {
    param(
        [string]$ScriptsFolder = $script:ScriptsFolder,
        [string]$FolderName = $script:RollbackFolderName
    )
    if ([string]::IsNullOrWhiteSpace($FolderName)) { $FolderName = "09 Откат" }
    try {
        if ([System.IO.Path]::IsPathRooted($FolderName)) {
            return [System.IO.Path]::GetFullPath($FolderName)
        }
        if ([string]::IsNullOrWhiteSpace($ScriptsFolder)) { return "" }
        return [System.IO.Path]::GetFullPath((Join-Path -Path $ScriptsFolder -ChildPath $FolderName))
    } catch {
        return ""
    }
}

function Is-RollbackPath {
    param(
        [Parameter(Position = 0)]
        [string]$Path,
        [Parameter(Position = 1)]
        [string]$ScriptsFolder = $script:ScriptsFolder,
        [Parameter(Position = 2)]
        [string]$FolderName = $script:RollbackFolderName
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $folder = Get-RollbackFolder -ScriptsFolder $ScriptsFolder -FolderName $FolderName
    if ([string]::IsNullOrWhiteSpace($folder)) { return $false }
    try {
        if (-not [System.IO.Path]::IsPathRooted($Path)) {
            if ([string]::IsNullOrWhiteSpace($ScriptsFolder)) {
                $Path = [System.IO.Path]::GetFullPath($Path)
            } else {
                $Path = Join-Path -Path $ScriptsFolder -ChildPath $Path
            }
        }
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        $fullFolder = [System.IO.Path]::GetFullPath($folder).TrimEnd([char[]]@('\','/'))
        $prefix = $fullFolder + [System.IO.Path]::DirectorySeparatorChar
        $inside = $fullPath.Equals($fullFolder, [System.StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
        if (-not $inside) { return $false }
        $folderItem = $null
        try { $folderItem = Get-Item -LiteralPath $fullFolder -Force -ErrorAction Stop } catch { return $false }
        if ($null -eq $folderItem -or -not $folderItem.PSIsContainer -or (($folderItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) { return $false }
        $folderProbe = $fullFolder
        $scriptsRoot = [System.IO.Path]::GetFullPath($ScriptsFolder).TrimEnd([char[]]@('\','/'))
        while (-not [string]::IsNullOrEmpty($folderProbe) -and -not $folderProbe.Equals($scriptsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            try { $folderPart = Get-Item -LiteralPath $folderProbe -Force -ErrorAction Stop } catch { return $false }
            if (($folderPart.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
            $folderParent = [System.IO.Path]::GetDirectoryName($folderProbe)
            if ([string]::IsNullOrEmpty($folderParent) -or $folderParent -eq $folderProbe) { break }
            $folderProbe = $folderParent
        }
        $item = $null
        try { $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop } catch { return $false }
        if ($null -eq $item -or $item.PSIsContainer -or (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) { return $false }
        $probe = $fullPath
        while (-not [string]::IsNullOrEmpty($probe) -and -not $probe.Equals($fullFolder, [System.StringComparison]::OrdinalIgnoreCase)) {
            try { $part = Get-Item -LiteralPath $probe -Force -ErrorAction Stop } catch { return $false }
            if (($part.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
            $parent = [System.IO.Path]::GetDirectoryName($probe)
            if ([string]::IsNullOrEmpty($parent) -or $parent -eq $probe) { break }
            $probe = $parent
        }
        return $true
    } catch {
        return $false
    }
}

function Get-RollbackScriptPaths {
    param(
        [string]$ScriptsFolder = $script:ScriptsFolder,
        [string]$FolderName = $script:RollbackFolderName
    )
    $folder = Get-RollbackFolder -ScriptsFolder $ScriptsFolder -FolderName $FolderName
    if ([string]::IsNullOrWhiteSpace($folder) -or -not (Test-Path -LiteralPath $folder -PathType Container)) { return @() }
    try {
        return @(Get-ChildItem -LiteralPath $folder -Filter "*.ps1" -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { Is-RollbackPath -Path $_.FullName -ScriptsFolder $ScriptsFolder -FolderName $FolderName } |
            Sort-Object FullName |
            ForEach-Object { $_.FullName })
    } catch {
        return @()
    }
}

function Reset-RunButton {
    try {
        if ($script:RunBtnSaved) {
            $runScriptsBtn.Content = $script:RunBtnContent
            $runScriptsBtn.Style = $script:RunBtnStyle
        }
    } catch {}
    $script:BatchRunning = $false
    $script:BatchHandle = $null
}

function Stop-SelectedScripts {
    if (-not $script:BatchRunning) { Reset-RunButton; return }
    try { if ($script:BatchControl) { $script:BatchControl.Abort = $true } } catch {}
    try {
        $pidToKill = 0
        try { $pidToKill = [int]$script:BatchControl.ChildPid } catch {}
        if ($pidToKill -gt 0) {
            Write-Log "Останавливаю дерево процессов PID $pidToKill..." -Color Yellow
            Stop-ProcessTree -TargetPid $pidToKill
        }
    } catch {}
    try { if ($script:BatchHandle -and $script:BatchHandle.Stop) { & $script:BatchHandle.Stop } } catch {}
    try { $runScriptsBtn.Content = '⏳ Остановка...' } catch {}
    Write-Log "Остановка запрошена, жду завершения..." -Color Yellow
}

function Read-ScriptHeader {
    param([string]$Path)
    try {
        $text = [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
    } catch {
        try { $text = [System.IO.File]::ReadAllText($Path) } catch { $text = "" }
    }
    return $text.Split([string[]]@("`r`n", "`n"), [System.StringSplitOptions]::None) | Select-Object -First 20
}

function Load-Scripts {
    $result = @()
    $files = Get-ChildItem -Path $script:ScriptsFolder -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue | Sort-Object Name | Where-Object { -not (Is-RollbackPath -Path $_.FullName) }
    foreach ($file in $files) {
        $parentName = $file.Directory.Name
        $category = if ($parentName -ne (Split-Path $script:ScriptsFolder -Leaf)) { $parentName } else { "Другое" }
        $num = 0
        if ($file.BaseName -match '^(\d{2})_') { $num = [int]$Matches[1] }
        $meta = @{
            Name        = ($file.BaseName -replace '^\d{2}_', '')
            Num         = $num
            Desc        = ""
            Category    = $category
            Icon        = "📄"
            Presets     = @()
            Tag         = 0
            Win11Only   = $false
            Path        = $file.FullName
        }
        foreach ($line in (Read-ScriptHeader -Path $file.FullName)) {
            if ($line -match '^#\s*NAME:\s*(.+)')        { $meta.Name        = $Matches[1].Trim() }
            if ($line -match '^#\s*DESC:\s*(.+)')        { $meta.Desc        = $Matches[1].Trim() }
            if ($line -match '^#\s*ICON:\s*(.+)')        { $meta.Icon        = $Matches[1].Trim() }
            if ($line -match '^#\s*PRESET:\s*(.+)')      { $meta.Presets     = @($Matches[1].Split(',') | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ -ne '' }) }
            if ($line -match '^#\s*TAGS:\s*(\d)')        { $meta.Tag         = [int]$Matches[1].Trim() }
            if ($line -match '^#\s*TAGS:.*win11')        { $meta.Win11Only   = $true }
        }
        $result += $meta
    }
    return $result
}

function Load-RollbackScripts {
    param(
        [string]$ScriptsFolder = $script:ScriptsFolder,
        [string]$FolderName = $script:RollbackFolderName
    )
    $result = @()
    foreach ($path in @(Get-RollbackScriptPaths -ScriptsFolder $ScriptsFolder -FolderName $FolderName)) {
        try { $file = Get-Item -LiteralPath $path -ErrorAction Stop } catch { continue }
        $num = 0
        if ($file.BaseName -match '^(\d{2})_') { $num = [int]$Matches[1] }
        $meta = @{
            Name        = ($file.BaseName -replace '^\d{2}_', '')
            Num         = $num
            Desc        = ""
            Category    = "Откат"
            Icon        = "↩️"
            Presets     = @()
            Tag         = 0
            Win11Only   = $false
            Path        = $file.FullName
            IsRollback  = $true
        }
        foreach ($line in (Read-ScriptHeader -Path $file.FullName)) {
            if ($line -match '^#\s*NAME:\s*(.+)')        { $meta.Name        = $Matches[1].Trim() }
            if ($line -match '^#\s*DESC:\s*(.+)')        { $meta.Desc        = $Matches[1].Trim() }
            if ($line -match '^#\s*ICON:\s*(.+)')        { $meta.Icon        = $Matches[1].Trim() }
            if ($line -match '^#\s*PRESET:\s*(.+)')      { $meta.Presets     = @($Matches[1].Split(',') | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ -ne '' }) }
            if ($line -match '^#\s*TAGS:\s*(\d)')        { $meta.Tag         = [int]$Matches[1].Trim() }
            if ($line -match '^#\s*TAGS:.*win11')        { $meta.Win11Only   = $true }
        }
        $result += $meta
    }
    return @($result)
}

function Update-SelectedCount {
    $count = @($script:ScriptCheckboxes.Values | Where-Object { $_.IsChecked }).Count
    $total = $script:ScriptCheckboxes.Count
    if ($selectedCountText) { $selectedCountText.Text = "Выбрано: $count из $total" }
    try { Update-HeaderCount } catch {}
}

# Чипы пресетов на карточке: видно, куда входит скрипт (цвета как у кнопок пресетов).
$script:PresetBadgeStyle = @{
    potato = @{ T = "POTATO"; Fg = "#FBBF24"; Bg = "#2A2300"; Bd = "#6B5B00" }
    office = @{ T = "ОФИС";   Fg = "#7DD3FC"; Bg = "#0C2E44"; Bd = "#1a5aaa" }
    game   = @{ T = "ИГРЫ";   Fg = "#F472B6"; Bg = "#4A1830"; Bd = "#8a2a52" }
}

function New-PresetBadge {
    param([string]$Preset)
    $key = ([string]$Preset).ToLower().Trim()
    if (-not $script:PresetBadgeStyle.ContainsKey($key)) { return $null }
    $st = $script:PresetBadgeStyle[$key]
    try {
        $b = [System.Windows.Controls.Border]::new()
        $b.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $b.Padding = [System.Windows.Thickness]::new(5,1,5,1)
        $b.Margin  = [System.Windows.Thickness]::new(7,0,0,0)
        $b.VerticalAlignment = "Center"
        $b.BorderThickness = [System.Windows.Thickness]::new(1)
        $b.Background  = [Windows.Media.BrushConverter]::new().ConvertFrom($st.Bg)
        $b.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom($st.Bd)
        $t = [System.Windows.Controls.TextBlock]::new()
        $t.Text = $st.T; $t.FontSize = 10; $t.FontWeight = "SemiBold"
        $t.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom($st.Fg)
        $b.Child = $t
        return $b
    } catch { return $null }
}

function Build-ScriptsPanel {
    if ($null -eq $scriptsPanel) { [Console]::WriteLine('PotatoPC: этот файл — часть приложения. Запускай menu.ps1'); return }
    $scriptsPanel.Children.Clear()
    $script:ScriptCheckboxes.Clear()
    $scripts = Load-Scripts
    if ($scripts.Count -eq 0) {
        $emptyWrap = [System.Windows.Controls.StackPanel]::new()
        $emptyWrap.HorizontalAlignment = "Center"; $emptyWrap.Margin = "0,60,0,0"
        $emptyImg = Get-IconImage -Name 'places/folder_open' -Size 32
        if ($emptyImg) {
            $emptyImg.HorizontalAlignment = "Center"
            $emptyImg.Margin = [System.Windows.Thickness]::new(0,0,0,10)
            $emptyWrap.Children.Add($emptyImg) | Out-Null
        }
        $empty = [System.Windows.Controls.TextBlock]::new()
        $empty.Text = "Папка скриптов пуста.`nПапка: $($script:ScriptsFolder)"
        $empty.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#a8a8d0")
        $empty.FontSize = 13; $empty.TextAlignment = "Center"
        $emptyWrap.Children.Add($empty) | Out-Null
        $scriptsPanel.Children.Add($emptyWrap) | Out-Null
        Update-SelectedCount; return
    }
    $grouped = $scripts | Group-Object { $_.Category } | Sort-Object Name
    foreach ($group in $grouped) {
        $catBorder = New-CategoryHeader -Title $group.Name
        $scriptsPanel.Children.Add($catBorder) | Out-Null
        foreach ($script_item in $group.Group) {
            $isWin11Incompatible = $script_item.Win11Only -and ($script:WindowsMajorVersion -lt 11)
            $card = New-Card -Large -Incompatible:$isWin11Incompatible
            Add-CardFx -Card $card
            $grid = [System.Windows.Controls.Grid]::new()
            $col1 = [System.Windows.Controls.ColumnDefinition]::new(); $col1.Width = [System.Windows.GridLength]::new(32)
            $col2 = [System.Windows.Controls.ColumnDefinition]::new(); $col2.Width = [System.Windows.GridLength]::Auto
            $col3 = [System.Windows.Controls.ColumnDefinition]::new(); $col3.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
            $col4 = [System.Windows.Controls.ColumnDefinition]::new(); $col4.Width = [System.Windows.GridLength]::Auto
            $grid.ColumnDefinitions.Add($col1); $grid.ColumnDefinitions.Add($col2)
            $grid.ColumnDefinitions.Add($col3); $grid.ColumnDefinitions.Add($col4)
            $cb = [System.Windows.Controls.CheckBox]::new()
            $cb.VerticalAlignment = "Center"
            $cb.Tag = $script_item.Path
            if ($isWin11Incompatible) {
                $cb.IsEnabled = $false
            } else {
                $cb.Add_Checked({ Update-SelectedCount })
                $cb.Add_Unchecked({ Update-SelectedCount })
            }
            [System.Windows.Controls.Grid]::SetColumn($cb, 0)
            $script:ScriptCheckboxes[$script_item.Path] = $cb
            $iconImg = Get-IconImage -Name (Get-ScriptIconName -Emoji $script_item.Icon) -Size 22
            if ($null -eq $iconImg) {
                $iconImg = [System.Windows.Controls.TextBlock]::new()
                $iconImg.Text = $script_item.Icon
                $iconImg.FontSize = 16; $iconImg.VerticalAlignment = "Center"
            }
            $iconImg.Margin = [System.Windows.Thickness]::new(0,0,8,0)
            $iconImg.VerticalAlignment = "Center"
            [System.Windows.Controls.Grid]::SetColumn($iconImg, 1)
            $textStack = [System.Windows.Controls.StackPanel]::new()
            $textStack.VerticalAlignment = "Center"
            $nameRow = [System.Windows.Controls.StackPanel]::new()
            $nameRow.Orientation = "Horizontal"; $nameRow.VerticalAlignment = "Center"
            $nameText = [System.Windows.Controls.TextBlock]::new()
            # Номер скрипта из имени файла (NN_name.ps1): "02 04" = раздел 02, скрипт 04.
            $nameText.Text = if ($script_item.Num -gt 0) { ("{0:D2} · {1}" -f $script_item.Num, $script_item.Name) } else { $script_item.Name }
            $nameText.FontSize = 12; $nameText.FontWeight = "Medium"
            $nameText.VerticalAlignment = "Center"
            $nameColor = if ($isWin11Incompatible) { "#505060" } else { "#e0e0f4" }
            $nameText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom($nameColor)
            $nameRow.Children.Add($nameText) | Out-Null
            if ($script_item.Win11Only) {
                $w11b = [System.Windows.Controls.Border]::new()
                $w11b.CornerRadius = [System.Windows.CornerRadius]::new(4)
                $w11b.Padding = [System.Windows.Thickness]::new(5,1,5,1)
                $w11b.Margin  = [System.Windows.Thickness]::new(7,0,0,0)
                $w11b.VerticalAlignment = "Center"
                $w11b.BorderThickness = [System.Windows.Thickness]::new(1)
                if ($isWin11Incompatible) {
                    $w11b.Background  = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a0a0a")
                    $w11b.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#4a2222")
                } else {
                    $w11b.Background  = [Windows.Media.BrushConverter]::new().ConvertFrom("#0a1a2e")
                    $w11b.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a5aaa")
                }
                $w11t = [System.Windows.Controls.TextBlock]::new()
                $w11t.FontSize = 10; $w11t.FontWeight = "SemiBold"
                $w11t.Text = if ($isWin11Incompatible) { "⊘ Только Win 11" } else { "⊞ Win 11" }
                $w11t.Foreground = if ($isWin11Incompatible) {
                    [Windows.Media.BrushConverter]::new().ConvertFrom("#7a3030")
                } else {
                    [Windows.Media.BrushConverter]::new().ConvertFrom("#4a9eff")
                }
                $w11b.Child = $w11t
                $nameRow.Children.Add($w11b) | Out-Null
            }
            if (-not $isWin11Incompatible -and $script_item.Tag -in 1,2,3) {
                $tagBorder = New-TagBadge -Tag $script_item.Tag
                $nameRow.Children.Add($tagBorder) | Out-Null
            }
            if (-not $isWin11Incompatible) {
                foreach ($pp in @($script_item.Presets)) {
                    $pb = New-PresetBadge -Preset $pp
                    if ($pb) { $nameRow.Children.Add($pb) | Out-Null }
                }
            }
            $textStack.Children.Add($nameRow) | Out-Null
            $descText = [System.Windows.Controls.TextBlock]::new()
            if ($isWin11Incompatible) {
                $descText.Text = "Требуется Windows 11 — недоступно на вашей системе"
                $descText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#7a5a5a")
            } else {
                $descText.Text = if ($script_item.Desc) { $script_item.Desc } else { $script_item.Path | Split-Path -Leaf }
                $descText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#c4c4ee")
            }
            $descText.FontSize = 11; $descText.Margin = [System.Windows.Thickness]::new(0,2,0,0)
            $descText.TextWrapping = "Wrap"
            $textStack.Children.Add($descText) | Out-Null
            [System.Windows.Controls.Grid]::SetColumn($textStack, 2)
            $runOneBtn = [System.Windows.Controls.Button]::new()
            $runOneBtn.Content = "▶"
            $runOneBtn.ToolTip = "Запустить только этот скрипт"
            $runOneBtn.Cursor = [System.Windows.Input.Cursors]::Hand
            $runOneBtn.BorderThickness = [System.Windows.Thickness]::new(0)
            $runOneBtn.Width = 30; $runOneBtn.Height = 30; $runOneBtn.FontSize = 12
            $runOneBtn.VerticalAlignment = "Center"
            $runOneBtn.Margin = [System.Windows.Thickness]::new(8,0,0,0)
            $runOneBtn.Tag = $script_item.Path
            if ($isWin11Incompatible) {
                $runOneBtn.IsEnabled = $false
                $runOneBtn.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a28")
                $runOneBtn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#505068")
            } else {
                $runOneBtn.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#2d2d35")
                $runOneBtn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#6c63ff")
                $runOneBtn.Add_Click({
                    $scriptPath = $this.Tag
                    $miss = @(Test-ScriptsExist -Paths @($scriptPath))
                    if ($miss.Count -gt 0) {
                        Write-Log ("✗ Файл пропал с диска: " + (Split-Path $scriptPath -Leaf)) -Color "Red"
                        Repair-ScriptsCache
                        return
                    }
                    Write-Log "══ Запуск: $(Split-Path $scriptPath -Leaf) ══"
                    Start-Background {
                        try {
                            $ok = Invoke-ScriptFileWithRetry -FilePath $scriptPath -MaxAttempts 2 -TimeoutSec (Get-ScriptTimeout $scriptPath)
                            if ($ok) { Write-Log "✓ Выполнено успешно" -Color "Green" }
                            else { Write-Log "✗ Завершился с ошибкой (см. лог)" -Color Yellow }
                        } catch {
                            Write-Log "✗ КРИТИЧНО: $_" -Color Red
                            Write-Log "Скипаю. Проблемный скрипт: $scriptPath" -Color Red
                        }
                    } -Variables @{ scriptPath = $scriptPath }
                })
            }
            [System.Windows.Controls.Grid]::SetColumn($runOneBtn, 3)
            $grid.Children.Add($cb) | Out-Null
            $grid.Children.Add($iconImg) | Out-Null
            $grid.Children.Add($textStack) | Out-Null
            $grid.Children.Add($runOneBtn) | Out-Null
            $card.Child = $grid
            if (-not $isWin11Incompatible) {
                $card.Add_MouseEnter({ $this.Background = $script:Theme.CardBgHover })
                $card.Add_MouseLeave({ $this.Background = $script:Theme.CardBg })
            }
            $scriptsPanel.Children.Add($card) | Out-Null
        }
    }
    Update-SelectedCount
    $win11Count = @($scripts | Where-Object { $_.Win11Only }).Count
    Write-Log "Загружено скриптов: $($scripts.Count)$(if($win11Count -gt 0){" (только Win11: $win11Count, ОС: Windows $($script:WindowsMajorVersion))"})"
}

function Get-RollbackControl {
    param([Parameter(Mandatory = $true)][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    $control = $null
    try { $control = Get-Variable -Name $Name -Scope Global -ValueOnly -ErrorAction Stop } catch {}
    if ($null -eq $control) {
        try { $control = Get-Variable -Name $Name -Scope Script -ValueOnly -ErrorAction Stop } catch {}
    }
    if ($null -eq $control) {
        try { $control = Get-Variable -Name $Name -Scope 1 -ValueOnly -ErrorAction Stop } catch {}
    }
    if ($null -eq $control -and $Name -match '^[a-z]') {
        $pascalName = $Name.Substring(0, 1).ToUpperInvariant() + $Name.Substring(1)
        try {
            $win = Get-Variable -Name 'window' -Scope Global -ValueOnly -ErrorAction Stop
            if (-not $win) { $win = Get-Variable -Name 'window' -Scope Script -ValueOnly -ErrorAction Stop }
            if ($win) { $control = $win.FindName($pascalName) }
        } catch {}
    }
    return $control
}

function Update-RollbackSelectedCount {
    $count = @($script:RollbackCheckboxes.Values | Where-Object { $_.IsChecked }).Count
    $total = $script:RollbackCheckboxes.Count
    $countText = Get-RollbackControl -Name 'rollbackCountText'
    if ($countText) {
        try { $countText.Text = "Выбрано: $count из $total" } catch {}
    }
    try { Update-HeaderCount } catch {}
}

function Build-RollbackPanel {
    $panel = Get-RollbackControl -Name 'rollbackPanel'
    if ($null -eq $panel) { return }
    try { $panel.Children.Clear() } catch { return }
    $script:RollbackCheckboxes = @{}
    $rollbackItems = @(Load-RollbackScripts)
    $folderText = Get-RollbackControl -Name 'rollbackFolderText'
    if ($folderText) {
        try { $folderText.Text = Get-RollbackFolder } catch {}
    }
    if ($rollbackItems.Count -eq 0) {
        $emptyWrap = [System.Windows.Controls.StackPanel]::new()
        $emptyWrap.HorizontalAlignment = "Center"
        $emptyWrap.Margin = [System.Windows.Thickness]::new(0,60,0,0)
        $emptyImg = $null
        try { $emptyImg = Get-IconImage -Name 'places/folder_open' -Size 32 } catch {}
        if ($emptyImg) {
            $emptyImg.HorizontalAlignment = "Center"
            $emptyImg.Margin = [System.Windows.Thickness]::new(0,0,0,10)
            $emptyWrap.Children.Add($emptyImg) | Out-Null
        }
        $emptyText = [System.Windows.Controls.TextBlock]::new()
        $emptyText.Text = "Папка отката пуста.`nПапка: $(Get-RollbackFolder)"
        $emptyText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#a8a8d0")
        $emptyText.FontSize = 13
        $emptyText.TextAlignment = "Center"
        $emptyWrap.Children.Add($emptyText) | Out-Null
        try { $panel.Children.Add($emptyWrap) | Out-Null } catch {}
        Update-RollbackSelectedCount
        return
    }
    $osMajor = 10
    try { $osMajor = [int]$script:WindowsMajorVersion } catch {}
    $groups = @($rollbackItems | Group-Object -Property Category | Sort-Object -Property Name)
    foreach ($group in $groups) {
        $header = $null
        try { $header = New-CategoryHeader -Title ([string]$group.Name) } catch {}
        if ($null -eq $header) { continue }
        try { $panel.Children.Add($header) | Out-Null } catch { continue }
        foreach ($rollbackItem in @($group.Group)) {
            $isWin11Incompatible = ([bool]$rollbackItem.Win11Only -and ($osMajor -lt 11))
            $card = $null
            try { $card = New-Card -Large -Incompatible:$isWin11Incompatible } catch {}
            if ($null -eq $card) {
                try { $card = [System.Windows.Controls.Border]::new() } catch { continue }
            }
            if (-not $isWin11Incompatible) {
                try { Add-CardFx -Card $card } catch {}
            }
            $grid = [System.Windows.Controls.Grid]::new()
            $col1 = [System.Windows.Controls.ColumnDefinition]::new(); $col1.Width = [System.Windows.GridLength]::new(32)
            $col2 = [System.Windows.Controls.ColumnDefinition]::new(); $col2.Width = [System.Windows.GridLength]::new([System.Windows.GridUnitType]::Auto)
            $col3 = [System.Windows.Controls.ColumnDefinition]::new(); $col3.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $col4 = [System.Windows.Controls.ColumnDefinition]::new(); $col4.Width = [System.Windows.GridLength]::new([System.Windows.GridUnitType]::Auto)
            $grid.ColumnDefinitions.Add($col1) | Out-Null
            $grid.ColumnDefinitions.Add($col2) | Out-Null
            $grid.ColumnDefinitions.Add($col3) | Out-Null
            $grid.ColumnDefinitions.Add($col4) | Out-Null
            $checkBox = [System.Windows.Controls.CheckBox]::new()
            $checkBox.VerticalAlignment = "Center"
            $checkBox.Tag = [string]$rollbackItem.Path
            if ($isWin11Incompatible) {
                $checkBox.IsEnabled = $false
            } else {
                $checkBox.Add_Checked({ Update-RollbackSelectedCount })
                $checkBox.Add_Unchecked({ Update-RollbackSelectedCount })
            }
            [System.Windows.Controls.Grid]::SetColumn($checkBox, 0)
            $script:RollbackCheckboxes[[string]$rollbackItem.Path] = $checkBox
            $iconImage = $null
            try { $iconImage = Get-IconImage -Name (Get-ScriptIconName -Emoji $rollbackItem.Icon) -Size 22 } catch {}
            if ($null -eq $iconImage) {
                $iconImage = [System.Windows.Controls.TextBlock]::new()
                $iconImage.Text = $rollbackItem.Icon
                $iconImage.FontSize = 16
                $iconImage.VerticalAlignment = "Center"
            }
            $iconImage.Margin = [System.Windows.Thickness]::new(0,0,8,0)
            $iconImage.VerticalAlignment = "Center"
            [System.Windows.Controls.Grid]::SetColumn($iconImage, 1)
            $textStack = [System.Windows.Controls.StackPanel]::new()
            $textStack.VerticalAlignment = "Center"
            $nameText = [System.Windows.Controls.TextBlock]::new()
            $nameText.Text = if ($rollbackItem.Num -gt 0) { ("{0:D2} · {1}" -f $rollbackItem.Num, $rollbackItem.Name) } else { $rollbackItem.Name }
            $nameText.FontSize = 12
            $nameText.FontWeight = "Medium"
            $nameText.VerticalAlignment = "Center"
            $nameColor = if ($isWin11Incompatible) { "#505060" } else { "#e0e0f4" }
            try { $nameText.Foreground = Get-ThemeBrush $nameColor } catch { $nameText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom($nameColor) }
            $textStack.Children.Add($nameText) | Out-Null
            $descText = [System.Windows.Controls.TextBlock]::new()
            if ($isWin11Incompatible) {
                $descText.Text = "Требуется Windows 11 — недоступно на вашей системе"
                try { $descText.Foreground = Get-ThemeBrush "#7a5a5a" } catch { $descText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#7a5a5a") }
            } else {
                $descText.Text = if ($rollbackItem.Desc) { $rollbackItem.Desc } else { $rollbackItem.Path | Split-Path -Leaf }
                try { $descText.Foreground = Get-ThemeBrush "#c4c4ee" } catch { $descText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#c4c4ee") }
            }
            $descText.FontSize = 11
            $descText.Margin = [System.Windows.Thickness]::new(0,2,0,0)
            $descText.TextWrapping = "Wrap"
            $textStack.Children.Add($descText) | Out-Null
            [System.Windows.Controls.Grid]::SetColumn($textStack, 2)
            $runOneButton = [System.Windows.Controls.Button]::new()
            $runOneButton.Content = "▶"
            $runOneButton.ToolTip = "Запустить только этот откат"
            $runOneButton.Cursor = [System.Windows.Input.Cursors]::Hand
            $runOneButton.BorderThickness = [System.Windows.Thickness]::new(0)
            $runOneButton.Width = 30
            $runOneButton.Height = 30
            $runOneButton.FontSize = 12
            $runOneButton.VerticalAlignment = "Center"
            $runOneButton.Margin = [System.Windows.Thickness]::new(8,0,0,0)
            $runOneButton.Tag = [string]$rollbackItem.Path
            if ($isWin11Incompatible) {
                $runOneButton.IsEnabled = $false
                try {
                    $runOneButton.Background = Get-ThemeBrush "#1a1a28"
                    $runOneButton.Foreground = Get-ThemeBrush "#505068"
                } catch {}
            } else {
                try {
                    $runOneButton.Background = Get-ThemeBrush "#2d2d35"
                    $runOneButton.Foreground = Get-ThemeBrush "#6c63ff"
                } catch {
                    $runOneButton.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#2d2d35")
                    $runOneButton.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#6c63ff")
                }
                $runOneButton.Add_Click({
                    $rollbackPath = [string]$this.Tag
                    try { Run-SelectedRollbackScripts -Paths @($rollbackPath) } catch { try { Write-Log ("Ошибка запуска отката: " + $_) -Color "Red" } catch {} }
                })
            }
            [System.Windows.Controls.Grid]::SetColumn($runOneButton, 3)
            $grid.Children.Add($checkBox) | Out-Null
            $grid.Children.Add($iconImage) | Out-Null
            $grid.Children.Add($textStack) | Out-Null
            $grid.Children.Add($runOneButton) | Out-Null
            $card.Child = $grid
            try { $panel.Children.Add($card) | Out-Null } catch {}
        }
    }
    Update-RollbackSelectedCount
}

function Test-ScriptsExist {
    # Возвращает список пропавших .ps1 (съел антивирус, битый кэш, чистка TEMP).
    param([string[]]$Paths)
    $miss = @()
    foreach ($p in @($Paths)) {
        try { if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { $miss += $p } } catch { $miss += $p }
    }
    return @($miss)
}

function Repair-ScriptsCache {
    # Докачка репозитория в фоне + перестройка панелей через шину.
    Write-Log "Файлы скриптов пропали с диска — качаю заново..." -Color "Yellow"
    Write-Log "Если пропадают снова — глянь карантин Defender (свежая система их ест)." -Color "Yellow"
    Start-Background {
        $ok = $false
        try { $ok = [bool](Download-Repo) }
        catch { Write-Log ("Не вышло докачать: " + $_) -Color "Red" }
        if ($ok) {
            Set-BgResult -Key 'paths' -Value @{ ScriptsFolder = $script:ScriptsFolder; AppsJsonPath = $script:AppsJsonPath }
            Set-BgResult -Key 'rebuildScripts' -Value $true
        } else { Set-BgResult -Key 'initError' -Value 'Репозиторий не обновлён' }
    }
}

function Select-AllRollbackScripts {
    foreach ($checkBox in @($script:RollbackCheckboxes.Values)) {
        try {
            if ($checkBox.IsEnabled) { $checkBox.IsChecked = $true }
        } catch {}
    }
    Update-RollbackSelectedCount
}

function Deselect-AllRollbackScripts {
    foreach ($checkBox in @($script:RollbackCheckboxes.Values)) {
        try { $checkBox.IsChecked = $false } catch {}
    }
    Update-RollbackSelectedCount
}

function Reset-RollbackRunButton {
    $runButton = Get-RollbackControl -Name 'runRollbackBtn'
    try {
        if ($runButton -and $script:RollbackRunBtnSaved) {
            $runButton.Content = $script:RollbackRunBtnContent
            $runButton.Style = $script:RollbackRunBtnStyle
        }
    } catch {}
    $script:RollbackBatchRunning = $false
    $script:RollbackBatchControl = $null
    $script:RollbackBatchHandle = $null
}

function Stop-SelectedRollbackScripts {
    if (-not $script:RollbackBatchRunning) {
        Reset-RollbackRunButton
        return $false
    }
    try { if ($script:RollbackBatchControl) { $script:RollbackBatchControl.Abort = $true } } catch {}
    try {
        $rollbackProcessId = 0
        try { $rollbackProcessId = [int]$script:RollbackBatchControl.ChildPid } catch {}
        if ($rollbackProcessId -gt 0) {
            Write-Log "Останавливаю дерево процессов отката PID $rollbackProcessId..." -Color Yellow
            Stop-ProcessTree -TargetPid $rollbackProcessId
        }
    } catch {}
    try {
        if ($script:RollbackBatchHandle -and $script:RollbackBatchHandle.Stop) {
            & $script:RollbackBatchHandle.Stop | Out-Null
        }
    } catch {}
    Write-Log "Остановка отката запрошена, жду завершения..." -Color Yellow
    return $true
}

function Get-RollbackConfirmationMessage {
    param([string[]]$Paths)
    $items = @($Paths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $names = @()
    foreach ($path in $items) {
        try { $names += (Split-Path -Path ([string]$path) -Leaf) } catch { $names += [string]$path }
    }
    $list = if ($names.Count -gt 0) { $names -join "`n" } else { "(нет)" }
    return ("Будет последовательно выполнено откатов: $($items.Count).`n`n" + $list + "`n`nОткат изменит системные настройки. Продолжить?")
}

function Confirm-RollbackRun {
    param([string[]]$Paths)
    try {
        $result = [System.Windows.MessageBox]::Show(
            (Get-RollbackConfirmationMessage -Paths $Paths),
            "PotatoPC: откат",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning)
        return ($result -eq [System.Windows.MessageBoxResult]::Yes)
    } catch {
        try { Write-Log ("Не удалось запросить подтверждение отката: " + $_) -Color "Red" } catch {}
        return $false
    }
}

function Run-SelectedRollbackScripts {
    param([string[]]$Paths)
    if ($script:RollbackBatchRunning) {
        Stop-SelectedRollbackScripts | Out-Null
        return $false
    }
    if ($script:BatchRunning) {
        try { Write-Log "Дождитесь завершения обычных скриптов перед откатом." -Color "Yellow" } catch {}
        return $false
    }
    $rawPaths = @()
    if ($PSBoundParameters.ContainsKey('Paths')) {
        $rawPaths = @($Paths)
    } else {
        $selected = @($script:RollbackCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked })
        $rawPaths = @($selected | ForEach-Object { $_.Key })
    }
    $pathsList = @()
    foreach ($path in $rawPaths) {
        if ([string]::IsNullOrWhiteSpace([string]$path)) { continue }
        $path = [string]$path
        if ($pathsList -notcontains $path) { $pathsList += $path }
    }
    if ($pathsList.Count -eq 0) {
        try { Write-Log "⚠ Нет выбранных rollback-скриптов" -Color "Yellow" } catch {}
        return $false
    }
    $invalid = @($pathsList | Where-Object { -not (Is-RollbackPath -Path $_) })
    if ($invalid.Count -gt 0) {
        try { Write-Log "✗ Отказ: выбран путь вне папки отката." -Color "Red" } catch {}
        return $false
    }
    $miss = @(Test-ScriptsExist -Paths $pathsList)
    if ($miss.Count -gt 0) {
        try { Write-Log ("✗ Нет файлов отката: " + $miss.Count + " (напр. " + (Split-Path $miss[0] -Leaf) + ")") -Color "Red" } catch {}
        return $false
    }
    if (-not (Confirm-RollbackRun -Paths $pathsList)) { return $false }
    $script:RollbackBatchControl = [hashtable]::Synchronized(@{ Abort = $false; ChildPid = 0 })
    $script:RollbackBatchRunning = $true
    $runButton = Get-RollbackControl -Name 'runRollbackBtn'
    if ($runButton) {
        try {
            if (-not $script:RollbackRunBtnSaved) {
                $script:RollbackRunBtnContent = $runButton.Content
                $script:RollbackRunBtnStyle = $runButton.Style
                $script:RollbackRunBtnSaved = $true
            }
            $runButton.Content = "⏹ Стоп"
            try {
                $win = Get-Variable -Name 'window' -Scope Global -ValueOnly -ErrorAction Stop
                if ($win) { $runButton.Style = $win.FindResource("BtnDanger") }
            } catch {}
        } catch {}
    }
    try { Write-Log "══════════════════════════════════════" } catch {}
    try { Write-Log "▶ Запуск $($pathsList.Count) rollback-скриптов..." -Color "Cyan" } catch {}
    try { Write-Log "══════════════════════════════════════" } catch {}
    try {
        $script:RollbackBatchHandle = Invoke-Async -ScriptBlock {
            $ok = 0
            $fail = 0
            $stoppedByUser = $false
            $total = @($pathsList).Count
            $idx = 0
            try {
                foreach ($rollbackPath in $pathsList) {
                    if ($batchControl.Abort) {
                        $stoppedByUser = $true
                        break
                    }
                    $idx++
                    try { Set-Progress ([double]$idx / [double]([Math]::Max(1, $total))) } catch {}
                     try {
                         if (-not (Is-RollbackPath -Path $rollbackPath -ScriptsFolder $ScriptsFolder -FolderName $FolderName)) { throw 'Путь отката изменился или стал небезопасным' }
                         Write-Log "── $(Split-Path $rollbackPath -Leaf)"
                         $result = Invoke-ScriptFileWithRetry -FilePath $rollbackPath -MaxAttempts 2 -TimeoutSec (Get-ScriptTimeout $rollbackPath) -Control $batchControl
                        if ($result) {
                            Write-Log "   ✓ Готово" -Color "Green"
                            $ok++
                        } else {
                            Write-Log "   ✗ Ошибка (код выхода)" -Color "Yellow"
                            $fail++
                        }
                    } catch {
                        if ("$_" -like "*STOPPED_BY_USER*") {
                            $stoppedByUser = $true
                            $fail++
                            Write-Log "⏹ Остановлено пользователем: $(Split-Path $rollbackPath -Leaf)" -Color "Yellow"
                            break
                        }
                        $fail++
                        Write-Log "   ⚠ Скипаю: $_" -Color "Yellow"
                    }
                }
                Write-Log "══════════════════════════════════════"
                if ($stoppedByUser) {
                    Write-Log "⏹ Откат остановлен пользователем. Выполнено: ✓$ok ✗$fail" -Color "Yellow"
                } else {
                    $tail = ""
                    if ($fail -gt 0) { $tail += " ✗$fail ошибок" }
                    Write-Log "Откат завершён: ✓$ok$tail" -Color "Green"
                }
                Write-Log "══════════════════════════════════════"
            } finally {
                try { Clear-Progress } catch {}
            }
        } -Variables @{ pathsList = $pathsList; batchControl = $script:RollbackBatchControl; ScriptsFolder = $script:ScriptsFolder; FolderName = $script:RollbackFolderName } -OnComplete {
            try { Invoke-OnUI { Reset-RollbackRunButton } } catch { try { Reset-RollbackRunButton } catch {} }
        }
        return $true
    } catch {
        try { Write-Log ("✗ Не удалось запустить откат: " + $_) -Color "Red" } catch {}
        Reset-RollbackRunButton
        return $false
    }
}

function Run-SelectedScripts {
    if ($script:BatchRunning) { Stop-SelectedScripts; return }
    if ($script:RollbackBatchRunning) { try { Write-Log 'Дождитесь завершения отката перед запуском обычных скриптов.' -Color 'Yellow' } catch {}; return }
    $selected = $script:ScriptCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked }
    if (-not $selected) { Write-Log "⚠ Нет выбранных скриптов" -Color "Yellow"; return }
    $pathsList = @($selected | ForEach-Object { $_.Key })
    $miss = @(Test-ScriptsExist -Paths $pathsList)
    if ($miss.Count -gt 0) {
        Write-Log ("✗ Нет файлов на диске: " + $miss.Count + " (напр. " + (Split-Path $miss[0] -Leaf) + ")") -Color "Red"
        Repair-ScriptsCache
        return
    }
    $reboot    = [bool]($rebootAfterChk.IsChecked -eq $true)
    if ($reboot) {
        $names = @($pathsList | ForEach-Object { Split-Path $_ -Leaf })
        $answer = [System.Windows.MessageBox]::Show(
            ("После выполнения " + $names.Count + " скриптов будет выполнена перезагрузка:`n" + ($names -join "`n") + "`n`nПродолжить?"),
            "PotatoPC: перезагрузка",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning)
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
    }
    $count     = $pathsList.Count
    if (-not $script:RunBtnSaved) {
        try {
            $script:RunBtnContent = $runScriptsBtn.Content
            $script:RunBtnStyle = $runScriptsBtn.Style
            $script:RunBtnSaved = $true
        } catch {}
    }
    $script:BatchControl = [hashtable]::Synchronized(@{ Abort = $false; ChildPid = 0 })
    $script:BatchRunning = $true
    try {
        $runScriptsBtn.Content = "⏹ Стоп"
        $runScriptsBtn.Style = $window.FindResource("BtnDanger")
    } catch {}
    Write-Log "══════════════════════════════════════"
    Write-Log "▶ Запуск $count скриптов..."
    Write-Log "══════════════════════════════════════"
    $script:BatchHandle = Invoke-Async -ScriptBlock {
        $ok=0; $fail=0; $skipped=@(); $stoppedByUser=$false
        $total=@($pathsList).Count; $idx=0
        try {
        foreach ($scriptPath in $pathsList) {
            Write-Log "── $(Split-Path $scriptPath -Leaf)"
            $idx++; Set-Progress ([double]$idx / [double]([Math]::Max(1, $total)))
            try {
                $res = Invoke-ScriptFileWithRetry -FilePath $scriptPath -MaxAttempts 2 -TimeoutSec (Get-ScriptTimeout $scriptPath) -Control $batchControl
                if ($res) { Write-Log "   ✓ Готово" -Color "Green"; $ok++ }
                else { Write-Log "   ✗ Ошибка (код выхода)" -Color Yellow; $fail++ }
            } catch {
                if ("$_" -like "*STOPPED_BY_USER*") {
                    $stoppedByUser=$true; $fail++
                    Write-Log "⏹ Остановлено пользователем: $(Split-Path $scriptPath -Leaf)" -Color Yellow
                    break
                }
                $fail++
                $skipped += (Split-Path $scriptPath -Leaf)
                Write-Log "   ⚠ Скипаю после неудачных попыток: $_" -Color Yellow
                Write-Log "   Иду к следующему скрипту..." -Color Yellow
            }
        }
        Write-Log "══════════════════════════════════════"
        if ($stoppedByUser) {
            Write-Log "⏹ Выполнение остановлено пользователем. Выполнено: ✓$ok ✗$fail" -Color Yellow
        } else {
            $tail = ""
            if ($fail -gt 0) { $tail += " ✗$fail ошибок" }
            if ($skipped.Count -gt 0) { $tail += " ⏭скип: " + ($skipped -join ", ") }
            Write-Log "Завершено: ✓$ok$tail" -Color Green
        }
        Write-Log "══════════════════════════════════════"
        if (-not $stoppedByUser -and $reboot) {
            if ($fail -eq 0) {
                Write-Log "Перезагрузка через 10 секунд..."
                Start-Sleep 10
                Restart-Computer -Force
            } else {
                try {
                    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                    $note = Join-Path ([Environment]::GetFolderPath('Desktop')) ("PotatoPC-failures-" + $stamp + ".txt")
                    $head = @("PotatoPC: выполнение завершилось с ошибками: $fail", "Время: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
                    if ($skipped.Count -gt 0) { $head += ("Скипнуты: " + ($skipped -join ", ")) }
                    $tailLines = @()
                    try {
                        $lp = $null; try { $lp = $bgLogPath } catch {}
                        if ($lp -and (Test-Path -LiteralPath $lp)) {
                            $all = [System.IO.File]::ReadAllLines($lp)
                            if ($all.Count -gt 200) { $tailLines = $all[($all.Count - 200)..($all.Count - 1)] } else { $tailLines = $all }
                        }
                    } catch {}
                    ([string[]]$head + @('', '--- хвост лога ---', '') + [string[]]$tailLines) | Out-File -FilePath $note -Encoding UTF8 -Force
                    Write-Log ("Ошибки: перезагрузка отменена, отчёт: " + $note) -Color "Yellow"
                } catch { Write-Log ("Не удалось сохранить отчёт: " + $_) -Color "Yellow" }
            }
        }
        } finally { Clear-Progress }
    } -Variables @{ pathsList=$pathsList; reboot=$reboot; batchControl=$script:BatchControl } -OnComplete {
        Invoke-OnUI { Reset-RunButton }
    }
}

$script:PresetTitles = @{ potato = "Potato (слабый ПК)"; office = "Офис"; game = "Игры" }

function Select-ScriptPreset {
    param([string]$Preset)
    $key = $Preset.ToLower().Trim()
    $title = if ($script:PresetTitles.ContainsKey($key)) { $script:PresetTitles[$key] } else { $Preset }
    foreach ($cb in $script:ScriptCheckboxes.Values) { $cb.IsChecked = $false }
    $scripts = Load-Scripts; $n = 0; $skip = 0
    foreach ($s in $scripts) {
        if ($s.Win11Only -and $script:WindowsMajorVersion -lt 11) {
            if ($s.Presets -contains $key) { $skip++ }
            continue
        }
        if (($s.Presets -contains $key) -and $script:ScriptCheckboxes.ContainsKey($s.Path)) {
            $script:ScriptCheckboxes[$s.Path].IsChecked = $true; $n++
        }
    }
    $msg = "✓ Пресет '$title': выбрано $n скриптов"
    if ($skip -gt 0) { $msg += " (пропущено только для Win11: $skip)" }
    Write-Log $msg -Color "Green"
    Update-SelectedCount
}