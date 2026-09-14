# Поисковые фильтры — вынесено из _events.ps1
# Требует: $scriptSearchBox, $scriptSearchHint, $scriptSearchClear, $scriptsPanel,
#           $appSearchBox, $appSearchHint, $appSearchClear, $appsPanel,
#           $startupSearchBox, $startupSearchHint, $startupSearchClear, Apply-StartupFilter
# Все привязки null-safe: отсутствующие контролы подменены пустышкой
# (Protect-Controls в _events.ps1), старый XAML файл не роняет.

if ($scriptSearchBox) { $scriptSearchBox.Add_TextChanged({
    $q=$scriptSearchBox.Text.Trim().ToLower()
    try { $scriptSearchHint.Visibility  = if($q -eq ""){"Visible"}else{"Collapsed"} } catch {}
    try { $scriptSearchClear.Visibility = if($q -eq ""){"Collapsed"}else{"Visible"} } catch {}
    # Два прохода за один: фильтруем карточки и прячем заголовки разделов без совпадений
    # (например, при поиске раздел "02 Очистка" без хитов скрывается целиком).
    $lastHeader = $null
    $visibleInSection = 0
    foreach ($child in $scriptsPanel.Children) {
        if ($child -is [System.Windows.Controls.Border]) {
            $grid=$child.Child
            if ($grid -is [System.Windows.Controls.Grid] -and $grid.ColumnDefinitions.Count -ge 3) {
                # Карточка скрипта
                $child.Visibility="Visible"
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
                else { $visibleInSection++ }
            } else {
                # Заголовок раздела: подводим итог предыдущего
                if ($lastHeader -ne $null -and $q -ne "" -and $visibleInSection -eq 0) { $lastHeader.Visibility = "Collapsed" }
                $lastHeader = $child
                $child.Visibility = "Visible"
                $visibleInSection = 0
            }
        }
    }
    if ($lastHeader -ne $null -and $q -ne "" -and $visibleInSection -eq 0) { $lastHeader.Visibility = "Collapsed" }
})}
if ($scriptSearchClear) { $scriptSearchClear.Add_Click({ $scriptSearchBox.Text="" }) }

if ($appSearchBox) { $appSearchBox.Add_TextChanged({
    $q=$appSearchBox.Text.Trim().ToLower()
    try { $appSearchHint.Visibility  = if($q -eq ""){"Visible"}else{"Collapsed"} } catch {}
    try { $appSearchClear.Visibility = if($q -eq ""){"Collapsed"}else{"Visible"} } catch {}
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
})}
if ($appSearchClear) { $appSearchClear.Add_Click({ $appSearchBox.Text="" }) }

if ($startupSearchBox) { $startupSearchBox.Add_TextChanged({
    $q = $startupSearchBox.Text.Trim()
    try { $startupSearchHint.Visibility  = if ($q -eq "") { "Visible" } else { "Collapsed" } } catch {}
    try { $startupSearchClear.Visibility = if ($q -eq "") { "Collapsed" } else { "Visible" } } catch {}
    Apply-StartupFilter
})}
if ($startupSearchClear) { $startupSearchClear.Add_Click({ $startupSearchBox.Text = "" }) }
