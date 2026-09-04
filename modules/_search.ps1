# Поисковые фильтры — вынесено из _events.ps1
# Требует: $scriptSearchBox, $scriptSearchHint, $scriptSearchClear, $scriptsPanel,
#           $appSearchBox, $appSearchHint, $appSearchClear, $appsPanel,
#           $startupSearchBox, $startupSearchHint, $startupSearchClear, Apply-StartupFilter

$scriptSearchBox.Add_TextChanged({
    $q=$scriptSearchBox.Text.Trim().ToLower()
    $scriptSearchHint.Visibility  = if($q -eq ""){"Visible"}else{"Collapsed"}
    $scriptSearchClear.Visibility = if($q -eq ""){"Collapsed"}else{"Visible"}
    foreach ($child in $scriptsPanel.Children) {
        if ($child -is [System.Windows.Controls.Border]) {
            $child.Visibility="Visible"
            $grid=$child.Child
            if ($grid -is [System.Windows.Controls.Grid] -and $grid.ColumnDefinitions.Count -ge 3) {
                $nameVal=""; $descVal=""
                foreach ($el in $grid.Children) {
                    if ($el -is [System.Windows.Controls.StackPanel]) {
                        foreach ($tb in $el.Children) {
                            if ($tb -is [System.Windows.Controls.TextBlock]) {
                                if ($nameVal -eq ""){$nameVal=$tb.Text.ToLower()} else {$descVal=$tb.Text.ToLower()}
                            }
                        }
                    }
                }
                if ($q -ne "" -and ($nameVal -notlike "*$q*") -and ($descVal -notlike "*$q*")) { $child.Visibility="Collapsed" }
            }
        }
    }
})
$scriptSearchClear.Add_Click({ $scriptSearchBox.Text="" })

$appSearchBox.Add_TextChanged({
    $q=$appSearchBox.Text.Trim().ToLower()
    $appSearchHint.Visibility  = if($q -eq ""){"Visible"}else{"Collapsed"}
    $appSearchClear.Visibility = if($q -eq ""){"Collapsed"}else{"Visible"}
    foreach ($child in $appsPanel.Children) {
        if ($child -is [System.Windows.Controls.Border]) {
            $inner=$child.Child
            if ($inner -is [System.Windows.Controls.StackPanel]) {
                $nameVal=""; $descVal=""
                foreach ($el in $inner.Children) {
                    if ($el -is [System.Windows.Controls.CheckBox]) { $nameVal=$el.Content.ToString().ToLower() }
                    if ($el -is [System.Windows.Controls.TextBlock]) { $descVal=$el.Text.ToLower() }
                }
                $child.Visibility = if ($q -ne "" -and ($nameVal -notlike "*$q*") -and ($descVal -notlike "*$q*")){"Collapsed"}else{"Visible"}
            } else { $child.Visibility="Visible" }
        }
    }
})
$appSearchClear.Add_Click({ $appSearchBox.Text="" })

$startupSearchBox.Add_TextChanged({
    $q = $startupSearchBox.Text.Trim()
    $startupSearchHint.Visibility  = if ($q -eq "") { "Visible" } else { "Collapsed" }
    $startupSearchClear.Visibility = if ($q -eq "") { "Collapsed" } else { "Visible" }
    Apply-StartupFilter
})
$startupSearchClear.Add_Click({ $startupSearchBox.Text = "" })
