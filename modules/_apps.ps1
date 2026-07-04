$script:AppCheckboxes = @{}

function Load-Apps {
    $fallback = @{
        "Утилиты" = @(
            @{ Name="7-Zip"; Id="7zip.7zip"; Description="Бесплатный архиватор." }
            @{ Name="Notepad++"; Id="Notepad++.Notepad++"; Description="Текстовый редактор." }
        )
        "Медиа" = @(@{ Name="VLC"; Id="VideoLAN.VLC"; Description="Универсальный медиаплеер." })
    }
    if (Test-Path $script:AppsJsonPath) {
        try {
            $j = Get-Content $script:AppsJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            Write-Log "✓ apps.json: $($j.ManualCategories.PSObject.Properties.Name.Count) категорий"
            return $j
        } catch { Write-Log "⚠ Ошибка apps.json, резервный список." -Color "Yellow" }
    }
    return [PSCustomObject]@{ ManualCategories = $fallback; Presets = @{} }
}

function Build-AppsPanel {
    $appsPanel.Children.Clear()
    $script:AppCheckboxes = @{}
    $appsData = Load-Apps
    foreach ($category in $appsData.ManualCategories.PSObject.Properties) {
        $h = [System.Windows.Controls.Border]::new()
        $h.Margin=[System.Windows.Thickness]::new(0,16,0,6); $h.Padding=[System.Windows.Thickness]::new(0,0,0,6)
        $h.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFrom("#1e1e38"); $h.BorderThickness=[System.Windows.Thickness]::new(0,0,0,1)
        $t=[System.Windows.Controls.TextBlock]::new(); $t.Text=$category.Name.ToUpper()
        $t.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#6c63ff"); $t.FontSize=11; $t.FontWeight="SemiBold"
        $h.Child=$t; $appsPanel.Children.Add($h) | Out-Null
        foreach ($app in $category.Value) {
            $card=[System.Windows.Controls.Border]::new()
            $card.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e")
            $card.CornerRadius=[System.Windows.CornerRadius]::new(6); $card.Margin=[System.Windows.Thickness]::new(0,2,0,2); $card.Padding=[System.Windows.Thickness]::new(12,8,12,8)
            $stk=[System.Windows.Controls.StackPanel]::new(); $stk.VerticalAlignment="Center"
            $cb=[System.Windows.Controls.CheckBox]::new(); $cb.Content=$app.Name; $cb.Tag=$app.Id
            $cb.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#c8c8e0"); $cb.FontSize=13; $cb.FontWeight="Medium"
            $script:AppCheckboxes[$app.Id]=$cb
            $desc=[System.Windows.Controls.TextBlock]::new(); $desc.Text=$app.Description
            $desc.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#c4c4ee"); $desc.FontSize=11; $desc.Margin=[System.Windows.Thickness]::new(28,2,0,0); $desc.TextWrapping="Wrap"
            $stk.Children.Add($cb) | Out-Null; $stk.Children.Add($desc) | Out-Null
            $card.Child=$stk
            $card.Add_MouseEnter({ $this.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#20203a") })
            $card.Add_MouseLeave({ $this.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e") })
            $appsPanel.Children.Add($card) | Out-Null
        }
    }
}

function Select-Preset($presetName) {
    $appsData = Load-Apps
    if (-not $appsData.Presets.$presetName) { Write-Log "⚠ Пресет '$presetName' не найден" -Color "Yellow"; return }
    foreach ($cb in $script:AppCheckboxes.Values) { $cb.IsChecked = $false }
    foreach ($id in $appsData.Presets.$presetName) {
        if ($script:AppCheckboxes.ContainsKey($id)) { $script:AppCheckboxes[$id].IsChecked = $true }
    }
    Write-Log "✓ Пресет $presetName применён" -Color "Green"
}
