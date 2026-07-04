# ═══ Поиск в модулях ═══
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

# ═══ Поиск в приложениях ═══
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

# ═══ Кнопки вкладок ═══
$runScriptsBtn.Add_Click({ Run-SelectedScripts })
$selectAllBtn.Add_Click({
    foreach ($cb in $script:ScriptCheckboxes.Values) { if ($cb.IsEnabled) { $cb.IsChecked=$true } }
    Update-SelectedCount
})
$deselectAllBtn.Add_Click({ foreach($cb in $script:ScriptCheckboxes.Values){$cb.IsChecked=$false}; Update-SelectedCount })
$selectRecommendedBtn.Add_Click({ Select-RecommendedScripts })

$refreshBtn.Add_Click({
    Download-Repo -Force
    $scriptsFolderText.Text = $script:ScriptsFolder
    Build-ScriptsPanel
    Write-Log "✓ Список скриптов обновлён"
})
$openFolderBtn.Add_Click({
    if (-not (Test-Path $script:ScriptsFolder)) { New-Item -ItemType Directory -Path $script:ScriptsFolder -Force | Out-Null }
    Start-Process explorer.exe $script:ScriptsFolder
})

$clearLogBtn.Add_Click({ $script:LogBox.Clear() })
$copyLogBtn.Add_Click({ [System.Windows.Clipboard]::SetText($script:LogBox.Text); Write-Log "✓ Лог скопирован" -Color "Green" })
$restorePointBtn.Add_Click({ Create-RestorePoint })
$refreshStartupBtn.Add_Click({ Build-StartupPanel })
$refreshUsersBtn.Add_Click({ Build-UsersPanel })
$addUserBtn.Add_Click({ Show-CreateUserDialog })

# ═══ Автозагрузка: кнопки ═══
$disableStartupBtn.Add_Click({
    $total = 0
    $sel = @($script:StartupCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked })
    foreach ($kv in $sel) {
        $tag = $kv.Value.Tag
        if ($tag.Location -like "Папка*") {
            try {
                $src = $tag.Command
                $dst = $src + ".disabled"
                Rename-Item -Path $src -NewName $dst -Force -ErrorAction Stop
                Write-Log "⏸ Отключено (папка): $($tag.Name)" -Color "Green"; $total++
            } catch { Write-Log "✗ $($tag.Name): $_" -Color "Red" }
        } else {
            $ok = Set-StartupApprovedState -RegKey $tag.RegKey -ValueName $tag.Name -Enable $false
            if ($ok) { Write-Log "⏸ Отключено: $($tag.Name)" -Color "Green"; $total++ }
        }
    }
    foreach ($kv in @($script:TaskCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked })) {
        $tag = $kv.Value.Tag
        try {
            Disable-ScheduledTask -TaskName $tag.Name -TaskPath $tag.Path -ErrorAction Stop | Out-Null
            Write-Log "⏸ Задача отключена: $($tag.Name)" -Color "Green"; $total++
        } catch { Write-Log "✗ $($tag.Name): $_" -Color "Red" }
    }
    if ($total -gt 0) { Write-Log "Отключено: $total элементов"; Build-StartupPanel }
    else { Write-Log "⚠ Нет выбранных элементов" -Color "Yellow" }
})

$enableStartupBtn.Add_Click({
    $total = 0
    $sel = @($script:StartupCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked })
    foreach ($kv in $sel) {
        $tag = $kv.Value.Tag
        if ($tag.Location -like "Папка*") {
            try {
                $src = $tag.Command
                $dst = $src -replace '\.disabled$', ''
                if ($src -ne $dst) { Rename-Item -Path $src -NewName $dst -Force -ErrorAction Stop }
                Write-Log "▶ Включено (папка): $($tag.Name)" -Color "Green"; $total++
            } catch { Write-Log "✗ $($tag.Name): $_" -Color "Red" }
        } else {
            $ok = Set-StartupApprovedState -RegKey $tag.RegKey -ValueName $tag.Name -Enable $true
            if ($ok) { Write-Log "▶ Включено: $($tag.Name)" -Color "Green"; $total++ }
        }
    }
    foreach ($kv in @($script:TaskCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked })) {
        $tag = $kv.Value.Tag
        try {
            Enable-ScheduledTask -TaskName $tag.Name -TaskPath $tag.Path -ErrorAction Stop | Out-Null
            Write-Log "▶ Задача включена: $($tag.Name)" -Color "Green"; $total++
        } catch { Write-Log "✗ $($tag.Name): $_" -Color "Red" }
    }
    if ($total -gt 0) { Write-Log "Включено: $total элементов"; Build-StartupPanel }
    else { Write-Log "⚠ Нет выбранных элементов" -Color "Yellow" }
})

$selectAllStartupBtn.Add_Click({
    foreach ($cb in $script:StartupCheckboxes.Values) { $cb.IsChecked = $true }
    foreach ($cb in $script:TaskCheckboxes.Values)    { $cb.IsChecked = $true }
    Update-StartupSelectedCount
})
$deselectAllStartupBtn.Add_Click({
    foreach ($cb in $script:StartupCheckboxes.Values) { $cb.IsChecked = $false }
    foreach ($cb in $script:TaskCheckboxes.Values)    { $cb.IsChecked = $false }
    Update-StartupSelectedCount
})

$startupFilterAllBtn.Add_Click({
    $script:StartupFilter = "All"
    $startupFilterAllBtn.Style  = $window.FindResource("BtnPrimary")
    $startupFilterAppBtn.Style  = $window.FindResource("BtnSecondary")
    $startupFilterTaskBtn.Style = $window.FindResource("BtnSecondary")
    Apply-StartupFilter
})
$startupFilterAppBtn.Add_Click({
    $script:StartupFilter = "Apps"
    $startupFilterAllBtn.Style  = $window.FindResource("BtnSecondary")
    $startupFilterAppBtn.Style  = $window.FindResource("BtnPrimary")
    $startupFilterTaskBtn.Style = $window.FindResource("BtnSecondary")
    Apply-StartupFilter
})
$startupFilterTaskBtn.Add_Click({
    $script:StartupFilter = "Tasks"
    $startupFilterAllBtn.Style  = $window.FindResource("BtnSecondary")
    $startupFilterAppBtn.Style  = $window.FindResource("BtnSecondary")
    $startupFilterTaskBtn.Style = $window.FindResource("BtnPrimary")
    Apply-StartupFilter
})

$startupSearchBox.Add_TextChanged({
    $q = $startupSearchBox.Text.Trim()
    $startupSearchHint.Visibility  = if ($q -eq "") { "Visible" } else { "Collapsed" }
    $startupSearchClear.Visibility = if ($q -eq "") { "Collapsed" } else { "Visible" }
    Apply-StartupFilter
})
$startupSearchClear.Add_Click({ $startupSearchBox.Text = "" })

$ToolsBtn.Add_Click({ Start-Process control.exe })
$AdminBtn.Add_Click({ Start-Process compmgmt.msc })
$presetOfficeBtn.Add_Click({ Select-Preset "Office-pack" })
$presetGamesBtn.Add_Click({ Select-Preset "Games-pack" })

$installAppsBtn.Add_Click({
    $sel = $script:AppCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked }
    if (-not $sel) { Write-Log "⚠ Нет выбранных приложений" -Color "Yellow"; return }
    $idList = @($sel | ForEach-Object { $_.Key })
    Write-Log "══ Установка $($idList.Count) приложений ══"
    Invoke-Async -ScriptBlock {
        function Write-Log($msg, $color = "Default") {
            $time = (Get-Date).ToString("HH:mm:ss")
            $line = "[$time] $msg"
            $LogBox.Dispatcher.Invoke([action]{ $LogBox.AppendText("$line`n"); $LogBox.ScrollToEnd() })
            $c = switch($color){"Green"{"Green"}"Red"{"Red"}"Yellow"{"Yellow"}default{"White"}}
            Write-Host $line -ForegroundColor $c
        }
        foreach ($id in $idList) {
            Write-Log "⏳ Установка: $id..."
            winget install --id $id --silent --accept-source-agreements --accept-package-agreements 2>&1 |
                ForEach-Object { Write-Log "   $_" }
            Write-Log "✓ $id установлена" -Color "Green"
        }
        Write-Log "══ Установка завершена ══"
    } -Variables @{ idList = $idList }
})
$selectAllAppsBtn.Add_Click({ foreach($cb in $script:AppCheckboxes.Values){$cb.IsChecked=$true} })
$deselectAllAppsBtn.Add_Click({ foreach($cb in $script:AppCheckboxes.Values){$cb.IsChecked=$false} })

# ═══ Кнопки обновлений ═══
$checkUpdatesBtn.Add_Click({ $updatesPanel.Children.Clear(); $script:UpdateCheckboxes.Clear(); Build-UpdatesPanel })
$selectAllUpdatesBtn.Add_Click({ foreach($cb in $script:UpdateCheckboxes.Values){$cb.IsChecked=$true}; $updateCountText.Text="Выбрано: $($script:UpdateCheckboxes.Count)" })
$deselectAllUpdatesBtn.Add_Click({ foreach($cb in $script:UpdateCheckboxes.Values){$cb.IsChecked=$false}; $updateCountText.Text="Выбрано: 0" })
$installUpdatesBtn.Add_Click({ Install-SelectedUpdates })

# ═══ Окно загружено — финальная инициализация ═══
$window.Add_Loaded({
    $scriptsFolderText.Text = $script:ScriptsFolder
    Write-Log "PotatoPC Optimizer v4.0 запущен"
    Write-Log "Система: $((Get-SystemInfo).OS)"
    Write-Log "Windows $($script:WindowsMajorVersion) обнаружена"
    Write-Log "Рабочая папка: $($script:WorkFolder)"
    Initialize-PotatoPC
    Build-ScriptsPanel
    Build-AppsPanel
    Build-SysPanel
    Build-DiagPanel
    Build-StartupPanel
    Build-UsersPanel
    Write-Log "✓ Готов к работе." -Color "Green"
    $restoreResult=[System.Windows.MessageBox]::Show(
        "Рекомендуется создать точку восстановления системы перед внесением изменений.`n`nСоздать точку восстановления сейчас?",
        "PotatoPC Optimizer",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question)
    if ($restoreResult -eq "Yes") { Create-RestorePoint }
})

$window.ShowDialog() | Out-Null
