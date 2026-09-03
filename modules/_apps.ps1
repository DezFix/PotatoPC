$script:AppCheckboxes = @{}

function Load-Apps {
    $fallback = [PSCustomObject]@{
        "Утилиты" = @(
            @{ Name="7-Zip"; Id="7zip.7zip"; Description="Бесплатный архиватор." }
            @{ Name="Notepad++"; Id="Notepad++.Notepad++"; Description="Текстовый редактор." }
        )
        "Медиа" = @(@{ Name="VLC"; Id="VideoLAN.VLC"; Description="Универсальный медиаплеер." })
    }
    if (Test-Path $script:AppsJsonPath) {
        try {
            $j = Get-Content $script:AppsJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.ManualCategories) {
                $n = @($j.ManualCategories.PSObject.Properties).Count
                Write-Log "apps.json: $n категорий"
                return $j
            }
        } catch {
            Write-Log "Ошибка apps.json, резервный список." -Color "Yellow"
        }
    }
    return [PSCustomObject]@{ ManualCategories = $fallback; Presets = @{} }
}

function Update-AppsCount {
    $sel   = @($script:AppCheckboxes.Values | Where-Object { $_.IsChecked }).Count
    $total = $script:AppCheckboxes.Count
    if ($AppCountText) { $AppCountText.Text = "Выбрано: $sel из $total" }
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
            if (-not $app -or [string]::IsNullOrWhiteSpace([string]$app.Id)) { continue }
            $card=New-Card
            $stk=[System.Windows.Controls.StackPanel]::new(); $stk.VerticalAlignment="Center"
            $cb=[System.Windows.Controls.CheckBox]::new(); $cb.Content=$app.Name; $cb.Tag=$app.Id
            $cb.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#c8c8e0"); $cb.FontSize=13; $cb.FontWeight="Medium"
            $cb.Add_Checked({ Update-AppsCount }); $cb.Add_Unchecked({ Update-AppsCount })
            $script:AppCheckboxes[$app.Id]=$cb
            $desc=[System.Windows.Controls.TextBlock]::new(); $desc.Text=[string]$app.Description
            $desc.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#c4c4ee"); $desc.FontSize=11; $desc.Margin=[System.Windows.Thickness]::new(28,2,0,0); $desc.TextWrapping="Wrap"
            $stk.Children.Add($cb) | Out-Null; $stk.Children.Add($desc) | Out-Null
            $card.Child=$stk
            Add-CardFx -Card $card
            $appsPanel.Children.Add($card) | Out-Null
        }
    }
    Update-AppsCount
}

function Select-Preset {
    param($presetName)
    $appsData = Load-Apps
    $presetList = $null
    if ($appsData.Presets -is [hashtable]) {
        if ($appsData.Presets.ContainsKey($presetName)) { $presetList = $appsData.Presets[$presetName] }
    } else {
        $prop = $appsData.Presets.PSObject.Properties[$presetName]
        if ($prop) { $presetList = $prop.Value }
    }
    if ($null -eq $presetList) { Write-Log "Пресет '$presetName' не найден" -Color "Yellow"; return }
    foreach ($cb in $script:AppCheckboxes.Values) { $cb.IsChecked = $false }
    foreach ($entry in $presetList) {
        $matched = $null
        if ($script:AppCheckboxes.ContainsKey($entry)) {
            $matched = $script:AppCheckboxes[$entry]
        } else {
            foreach ($kv in $script:AppCheckboxes.GetEnumerator()) {
                if ($kv.Value.Content -eq $entry) { $matched = $kv.Value; break }
            }
        }
        if ($matched) { $matched.IsChecked = $true }
        else { Write-Log "Пресет '$presetName': приложение '$entry' не найдено в списке" -Color "Yellow" }
    }
    Update-AppsCount
    Write-Log "Пресет $presetName применён" -Color "Green"
}
