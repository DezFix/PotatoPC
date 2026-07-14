$script:ScriptCheckboxes = @{}

function Load-Scripts {
    $result = @()
    $files = Get-ChildItem -Path $script:ScriptsFolder -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue | Sort-Object Name
    foreach ($file in $files) {
        $parentName = $file.Directory.Name
        $category = if ($parentName -ne (Split-Path $script:ScriptsFolder -Leaf)) { $parentName } else { "Другое" }
        $meta = @{
            Name        = $file.BaseName
            Desc        = ""
            Category    = $category
            Icon        = "📄"
            Recommended = $false
            Tag         = 0
            Win11Only   = $false
            Path        = $file.FullName
        }
        $lines = Get-Content $file.FullName -TotalCount 15 -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            if ($line -match '^#\s*NAME:\s*(.+)')        { $meta.Name        = $Matches[1].Trim() }
            if ($line -match '^#\s*DESC:\s*(.+)')        { $meta.Desc        = $Matches[1].Trim() }
            if ($line -match '^#\s*ICON:\s*(.+)')        { $meta.Icon        = $Matches[1].Trim() }
            if ($line -match '^#\s*RECOMMENDED:\s*true') { $meta.Recommended = $true }
            if ($line -match '^#\s*TAGS:\s*(\d)')        { $meta.Tag         = [int]$Matches[1].Trim() }
            if ($line -match '^#\s*WIN11:\s*true')       { $meta.Win11Only   = $true }
            if ($line -match '^#\s*TAGS:.*win11')        { $meta.Win11Only   = $true }
        }
        $result += $meta
    }
    return $result
}

function Update-SelectedCount {
    $count = ($script:ScriptCheckboxes.Values | Where-Object { $_.IsChecked }).Count
    $total = $script:ScriptCheckboxes.Count
    $selectedCountText.Text = "Выбрано: $count из $total скриптов"
}

function Build-ScriptsPanel {
    $scriptsPanel.Children.Clear()
    $script:ScriptCheckboxes.Clear()
    $scripts = Load-Scripts
    if ($scripts.Count -eq 0) {
        $empty = [System.Windows.Controls.TextBlock]::new()
        $empty.Text = "📂 Папка скриптов пуста.`nПапка: $($script:ScriptsFolder)"
        $empty.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#a8a8d0")
        $empty.FontSize = 13; $empty.TextAlignment = "Center"; $empty.Margin = "0,60,0,0"
        $scriptsPanel.Children.Add($empty) | Out-Null
        Update-SelectedCount; return
    }
    $grouped = $scripts | Group-Object { $_.Category } | Sort-Object Name
    foreach ($group in $grouped) {
        $catBorder = [System.Windows.Controls.Border]::new()
        $catBorder.Margin = [System.Windows.Thickness]::new(0,16,0,6)
        $catBorder.Padding = [System.Windows.Thickness]::new(0,0,0,6)
        $catBorder.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#1e1e38")
        $catBorder.BorderThickness = [System.Windows.Thickness]::new(0,0,0,1)
        $catText = [System.Windows.Controls.TextBlock]::new()
        $catText.Text = $group.Name.ToUpper()
        $catText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#6c63ff")
        $catText.FontSize = 11; $catText.FontWeight = "SemiBold"
        $catBorder.Child = $catText
        $scriptsPanel.Children.Add($catBorder) | Out-Null
        foreach ($script_item in $group.Group) {
            $isWin11Incompatible = $script_item.Win11Only -and ($script:WindowsMajorVersion -lt 11)
            $card = [System.Windows.Controls.Border]::new()
            $card.CornerRadius = [System.Windows.CornerRadius]::new(8)
            $card.Margin = [System.Windows.Thickness]::new(0,3,0,3)
            $card.Padding = [System.Windows.Thickness]::new(14,10,14,10)
            if ($isWin11Incompatible) {
                $card.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#141420")
                $card.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#2a1a2a")
                $card.BorderThickness = [System.Windows.Thickness]::new(0,0,3,0)
                $card.Opacity = 0.55
            } elseif ($script_item.Recommended) {
                $card.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e")
                $card.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#d4a017")
                $card.BorderThickness = [System.Windows.Thickness]::new(0,0,3,0)
            } else {
                $card.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e")
            }
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
            $icon = [System.Windows.Controls.TextBlock]::new()
            $icon.Text = $script_item.Icon
            $icon.FontSize = 18; $icon.VerticalAlignment = "Center"; $icon.Margin = [System.Windows.Thickness]::new(0,0,12,0)
            [System.Windows.Controls.Grid]::SetColumn($icon, 1)
            $textStack = [System.Windows.Controls.StackPanel]::new()
            $textStack.VerticalAlignment = "Center"
            $nameRow = [System.Windows.Controls.StackPanel]::new()
            $nameRow.Orientation = "Horizontal"; $nameRow.VerticalAlignment = "Center"
            $nameText = [System.Windows.Controls.TextBlock]::new()
            $nameText.Text = $script_item.Name; $nameText.FontSize = 13; $nameText.FontWeight = "Medium"
            $nameText.VerticalAlignment = "Center"
            $nameColor = if ($isWin11Incompatible) { "#505060" } elseif ($script_item.Recommended) { "#d4a017" } else { "#e0e0f4" }
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
                $tagBorder = [System.Windows.Controls.Border]::new()
                $tagBorder.CornerRadius = [System.Windows.CornerRadius]::new(4)
                $tagBorder.Padding = [System.Windows.Thickness]::new(5,1,5,1)
                $tagBorder.Margin  = [System.Windows.Thickness]::new(7,0,0,0)
                $tagBorder.VerticalAlignment = "Center"
                $tagBorder.BorderThickness = [System.Windows.Thickness]::new(1)
                $tagTxt = [System.Windows.Controls.TextBlock]::new()
                $tagTxt.FontSize = 10; $tagTxt.FontWeight = "SemiBold"
                switch ($script_item.Tag) {
                    1 { $tagBorder.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#0d2d1a"); $tagBorder.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFrom("#1a6b35"); $tagTxt.Text="● безопасно"; $tagTxt.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#2ecc71") }
                    2 { $tagBorder.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#2d2200"); $tagBorder.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFrom("#a07800"); $tagTxt.Text="● осторожно"; $tagTxt.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#f0c040") }
                    3 { $tagBorder.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#2d0d0d"); $tagBorder.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFrom("#8b1a1a"); $tagTxt.Text="● опасно"; $tagTxt.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#e74c3c") }
                }
                $tagBorder.Child = $tagTxt
                $nameRow.Children.Add($tagBorder) | Out-Null
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
            $descText.TextTrimming = "CharacterEllipsis"
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
                $runOneBtn.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#2a2a4a")
                $runOneBtn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#6c63ff")
                $runOneBtn.Add_Click({
                    $scriptPath = $this.Tag
                    Write-Log "══ Запуск: $(Split-Path $scriptPath -Leaf) ══"
                    [System.Threading.Tasks.Task]::Run([Action]{
                        try {
                            & $scriptPath 2>&1 | ForEach-Object { Write-Log "  $_" }
                            Write-Log "✓ Выполнено успешно" -Color "Green"
                        } catch {
                            Write-Log "✗ Ошибка: $_" -Color "Red"
                        }
                    }) | Out-Null
                })
            }
            [System.Windows.Controls.Grid]::SetColumn($runOneBtn, 3)
            $grid.Children.Add($cb) | Out-Null
            $grid.Children.Add($icon) | Out-Null
            $grid.Children.Add($textStack) | Out-Null
            $grid.Children.Add($runOneBtn) | Out-Null
            $card.Child = $grid
            if (-not $isWin11Incompatible) {
                $card.Add_MouseEnter({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#20203a") })
                $card.Add_MouseLeave({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e") })
            }
            $scriptsPanel.Children.Add($card) | Out-Null
        }
    }
    Update-SelectedCount
    $win11Count = @($scripts | Where-Object { $_.Win11Only }).Count
    Write-Log "Загружено скриптов: $($scripts.Count)$(if($win11Count -gt 0){" (только Win11: $win11Count, ОС: Windows $($script:WindowsMajorVersion))"})"
}

function Run-SelectedScripts {
    $selected = $script:ScriptCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked }
    if (-not $selected) { Write-Log "⚠ Нет выбранных скриптов" -Color "Yellow"; return }
    $pathsList = @($selected | ForEach-Object { $_.Key })
    $reboot    = $rebootAfterChk.IsChecked
    $count     = $pathsList.Count
    Write-Log "══════════════════════════════════════"
    Write-Log "▶ Запуск $count скриптов..."
    Write-Log "══════════════════════════════════════"
    Invoke-Async -ScriptBlock {
        function Write-Log($msg, $color = "Default") {
            $time = (Get-Date).ToString("HH:mm:ss")
            $line = "[$time] $msg"
            $LogBox.Dispatcher.Invoke([action]{ $LogBox.AppendText("$line`n"); $LogBox.ScrollToEnd() })
            $c = switch($color){"Green"{"Green"}"Red"{"Red"}"Yellow"{"Yellow"}default{"White"}}
            Write-Host $line -ForegroundColor $c
        }
        $ok=0; $fail=0
        foreach ($scriptPath in $pathsList) {
            Write-Log "── $(Split-Path $scriptPath -Leaf)"
            try {
                & $scriptPath 2>&1 | ForEach-Object { Write-Log "   $_" }
                Write-Log "   ✓ Готово" -Color "Green"; $ok++
            } catch {
                Write-Log "   ✗ Ошибка: $_" -Color "Red"; $fail++
            }
        }
        Write-Log "══════════════════════════════════════"
        Write-Log "Завершено: ✓$ok$(if($fail -gt 0){ " ✗$fail ошибок" })"
        Write-Log "══════════════════════════════════════"
        if ($reboot) { Write-Log "🔄 Перезагрузка через 10 секунд..."; Start-Sleep 10; Restart-Computer -Force }
    } -Variables @{ pathsList=$pathsList; reboot=$reboot }
}

function Select-RecommendedScripts {
    $scripts = Load-Scripts; $n = 0
    foreach ($s in $scripts) {
        if ($s.Win11Only -and $script:WindowsMajorVersion -lt 11) { continue }
        if ($s.Recommended -and $script:ScriptCheckboxes.ContainsKey($s.Path)) {
            $script:ScriptCheckboxes[$s.Path].IsChecked = $true; $n++
        }
    }
    Write-Log "✓ Выбрано $n рекомендованных скриптов" -Color "Green"
    Update-SelectedCount
}
