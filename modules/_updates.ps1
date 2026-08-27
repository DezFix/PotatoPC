$script:UpdateCheckboxes = @{}

function ConvertFrom-WingetUpgradeOutput {
    param([string]$RawOutput)
    $packages = @()
    if ([string]::IsNullOrWhiteSpace($RawOutput)) { return $packages }
    $lines = $RawOutput -split "`n" | Where-Object { $_ -match '\S' }
    $headerFound = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*-+\s*$') { $headerFound = $true; continue }
        if (-not $headerFound) { continue }
        $parts = $line -split '\s{2,}' | Where-Object { $_.Trim() -ne '' }
        if ($parts.Count -lt 4) { continue }
        $name       = $parts[0].Trim()
        $id         = $parts[1].Trim()
        $version    = $parts[2].Trim()
        $newVersion = $parts[3].Trim()
        if ($version -match '^(winget|msstore|Unknown|Name)$') { continue }
        if ($newVersion -match '^(winget|msstore|Unknown)$') { continue }
        if ($version -notmatch '\d' -or $newVersion -notmatch '\d') { continue }
        if ($id -match '^\d+[\.\d]+$') { continue }
        $packages += @{
            Name       = $name
            Id         = $id
            Version    = $version
            NewVersion = $newVersion
        }
    }
    return $packages
}

function Render-UpdatesPanel {
    param($Packages)
    if ($Packages.Count -eq 0) {
        $lbl = [System.Windows.Controls.TextBlock]::new()
        $lbl.Text = "✅ Все пакеты актуальны — обновлений нет."
        $lbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#50e050")
        $lbl.FontSize = 13; $lbl.TextAlignment = "Center"; $lbl.Margin = "0,60,0,0"
        $updatesPanel.Children.Add($lbl) | Out-Null
        $updateStatusText.Text = "✅ Обновлений нет"; Write-Log "✅ Обновлений нет"; return
    }
    $hdr = [System.Windows.Controls.Border]::new()
    $hdr.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#0e0e1e")
    $hdr.Padding = [System.Windows.Thickness]::new(12,5,12,5)
    $hdr.Margin = [System.Windows.Thickness]::new(0,0,0,4)
    $hg = [System.Windows.Controls.Grid]::new()
    $hw1 = [System.Windows.Controls.ColumnDefinition]::new(); $hw1.Width = [System.Windows.GridLength]::new(28)
    $hw2 = [System.Windows.Controls.ColumnDefinition]::new(); $hw2.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
    $hw3 = [System.Windows.Controls.ColumnDefinition]::new(); $hw3.Width = [System.Windows.GridLength]::Auto
    $hg.ColumnDefinitions.Add($hw1); $hg.ColumnDefinitions.Add($hw2); $hg.ColumnDefinitions.Add($hw3)
    $hn = [System.Windows.Controls.TextBlock]::new()
    $hn.Text = "ПРИЛОЖЕНИЕ"; $hn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#5050a0")
    $hn.FontSize = 10; $hn.FontWeight = "SemiBold"; $hn.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($hn, 1)
    $hv = [System.Windows.Controls.TextBlock]::new()
    $hv.Text = "ВЕРСИЯ → ДОСТУПНА"; $hv.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#5050a0")
    $hv.FontSize = 10; $hv.FontWeight = "SemiBold"; $hv.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($hv, 2)
    $hg.Children.Add($hn) | Out-Null; $hg.Children.Add($hv) | Out-Null
    $hdr.Child = $hg
    $updatesPanel.Children.Add($hdr) | Out-Null

    foreach ($pkg in $Packages) {
        $card = New-Card
        $g = [System.Windows.Controls.Grid]::new()
        $c1 = [System.Windows.Controls.ColumnDefinition]::new(); $c1.Width = [System.Windows.GridLength]::new(28)
        $c2 = [System.Windows.Controls.ColumnDefinition]::new(); $c2.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
        $c3 = [System.Windows.Controls.ColumnDefinition]::new(); $c3.Width = [System.Windows.GridLength]::Auto
        $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2); $g.ColumnDefinitions.Add($c3)
        $cb = [System.Windows.Controls.CheckBox]::new(); $cb.VerticalAlignment = "Center"; $cb.Tag = $pkg.Id
        $cb.Add_Checked({   Update-UpdateCount })
        $cb.Add_Unchecked({ Update-UpdateCount })
        [System.Windows.Controls.Grid]::SetColumn($cb, 0)
        $script:UpdateCheckboxes[$pkg.Id] = $cb
        $info = [System.Windows.Controls.StackPanel]::new(); $info.VerticalAlignment = "Center"
        $nm = [System.Windows.Controls.TextBlock]::new()
        $nm.Text = $pkg.Name; $nm.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#e0e0f4")
        $nm.FontSize = 12; $nm.FontWeight = "SemiBold"; $nm.TextTrimming = "CharacterEllipsis"
        $id = [System.Windows.Controls.TextBlock]::new()
        $id.Text = $pkg.Id; $id.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#9898c8")
        $id.FontSize = 10; $id.Margin = [System.Windows.Thickness]::new(0,1,0,0); $id.TextTrimming = "CharacterEllipsis"
        $info.Children.Add($nm) | Out-Null; $info.Children.Add($id) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($info, 1)
        $verStack = [System.Windows.Controls.StackPanel]::new()
        $verStack.Orientation = "Horizontal"; $verStack.VerticalAlignment = "Center"
        $vOld = [System.Windows.Controls.TextBlock]::new()
        $vOld.Text = $pkg.Version; $vOld.FontSize = 11
        $vOld.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#9898c8")
        $vArrow = [System.Windows.Controls.TextBlock]::new()
        $vArrow.Text = "  →  "; $vArrow.FontSize = 11
        $vArrow.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#5050a0")
        $vNew = [System.Windows.Controls.TextBlock]::new()
        $vNew.Text = $pkg.NewVersion; $vNew.FontSize = 11; $vNew.FontWeight = "SemiBold"
        $vNew.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#2ecc71")
        $verStack.Children.Add($vOld) | Out-Null
        $verStack.Children.Add($vArrow) | Out-Null
        $verStack.Children.Add($vNew) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($verStack, 2)
        $g.Children.Add($cb) | Out-Null; $g.Children.Add($info) | Out-Null; $g.Children.Add($verStack) | Out-Null
        $card.Child = $g
        Add-CardFx -Card $card
        $card.Add_MouseEnter({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#20203a") })
        $card.Add_MouseLeave({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e") })
        $updatesPanel.Children.Add($card) | Out-Null
    }
    $updateStatusText.Text = "Найдено обновлений: $($Packages.Count)"
    $updateCountText.Text = "Выбрано: 0"
    Write-Log "🔄 Найдено $($Packages.Count) обновлений"
}

function Update-UpdateCount {
    $count = @($script:UpdateCheckboxes.Values | Where-Object { $_.IsChecked }).Count
    if ($updateCountText) { $updateCountText.Text = "Выбрано: $count" }
}

function Build-UpdatesPanel {
    $updatesPanel.Children.Clear()
    $script:UpdateCheckboxes.Clear()
    $updateStatusText.Text = "Идёт проверка обновлений..."; $updateCountText.Text = ""
    Start-Background {
        try {
            $raw = winget upgrade --accept-source-agreements 2>&1 | Out-String
            $packages = ConvertFrom-WingetUpgradeOutput -RawOutput $raw
        } catch {
            $packages = @()
            Write-Log "Ошибка проверки обновлений: $_" -Color "Red"
        }
        try {
            $window.Dispatcher.Invoke([action]{ Render-UpdatesPanel -Packages $packages })
        } catch {}
    }
}

function Install-SelectedUpdates {
    $sel = $script:UpdateCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked }
    if (-not $sel) { Write-Log "⚠ Нет выбранных" -Color "Yellow"; return }
    $idList = @($sel | ForEach-Object { $_.Key })
    Write-Log "══ Обновление $($idList.Count) пакетов ══"
    Invoke-Async -ScriptBlock {
        $ok = 0; $fail = 0
        foreach ($id in $idList) {
            Write-Log "⬆ $id..."
            winget upgrade --id $id --silent --accept-source-agreements --accept-package-agreements 2>&1 |
                ForEach-Object { Write-Log "   $_" }
            if ($LASTEXITCODE -eq 0) { Write-Log "   ✓ Готово" -Color "Green"; $ok++ }
            else { Write-Log "   ✗ Ошибка (код $LASTEXITCODE)" -Color "Red"; $fail++ }
        }
        Write-Log "══ Обновление завершено: ✓$ok$(if($fail -gt 0){ `" ✗$fail`" }) ══"
    } -Variables @{ idList = $idList }
}