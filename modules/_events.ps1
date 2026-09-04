# ═══ Сворачивание/разворачивание лога ═══
$toggleLogBtn.Add_Click({ Set-LogExpanded -Expand (-not $script:LogState) })

# поиск вынесен в _search.ps1

# ═══ Кнопки вкладок ═══
$runScriptsBtn.Add_Click({
    if (-not (Get-Command Run-SelectedScripts -ErrorAction SilentlyContinue)) {
        Write-Log "ОШИБКА: модуль _scripts.ps1 не загружен. Удали $env:TEMP\PotatoPC и перезапусти." -Color Red
        return
    }
    Run-SelectedScripts
})
$selectAllBtn.Add_Click({
    foreach ($cb in $script:ScriptCheckboxes.Values) { if ($cb.IsEnabled) { $cb.IsChecked=$true } }
    Update-SelectedCount
})
$deselectAllBtn.Add_Click({ foreach($cb in $script:ScriptCheckboxes.Values){$cb.IsChecked=$false}; Update-SelectedCount })
$selectRecommendedBtn.Add_Click({
    if (-not (Get-Command Select-RecommendedScripts -ErrorAction SilentlyContinue)) {
        Write-Log "ОШИБКА: модуль _scripts.ps1 не загружен. Удали $env:TEMP\PotatoPC и перезапусти." -Color Red
        return
    }
    Select-RecommendedScripts
})

$refreshBtn.Add_Click({
    $refreshBtn.IsEnabled = $false
    Write-Log "Обновление списка скриптов..."
    Start-Background {
        try {
            Download-Repo -Force
            Set-BgResult -Key 'paths' -Value @{ ScriptsFolder = $script:ScriptsFolder; AppsJsonPath = $script:AppsJsonPath }
        } catch {
            Write-Log "Ошибка обновления: $_" -Color "Red"
        } finally {
            Set-BgResult -Key 'rebuildScripts' -Value $true
        }
    }
})
$openFolderBtn.Add_Click({
    if (-not (Test-Path $script:ScriptsFolder)) { New-Item -ItemType Directory -Path $script:ScriptsFolder -Force | Out-Null }
    Start-Process explorer.exe $script:ScriptsFolder
})

$clearLogBtn.Add_Click({ $LogBox.Clear() })
$copyLogBtn.Add_Click({
    try {
        [System.Windows.Clipboard]::SetText($LogBox.Text)
        Write-Log "✓ Лог скопирован" -Color "Green"
    } catch {
        Write-Log "Не удалось скопировать лог: $_" -Color "Yellow"
    }
})
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
                Rename-Item -LiteralPath $src -NewName ([System.IO.Path]::GetFileName($src + ".disabled")) -Force -ErrorAction Stop
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
                if ($src -ne $dst) { Rename-Item -LiteralPath $src -NewName ([System.IO.Path]::GetFileName($dst)) -Force -ErrorAction Stop }
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

# startup-поиск — в _search.ps1

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
        $wg = Get-WingetPath
        $ok = 0; $fail = 0
        foreach ($id in $idList) {
            Write-Log "⏳ Установка: $id..."
            & $wg install --id $id --silent --accept-source-agreements --accept-package-agreements 2>&1 |
                ForEach-Object { Write-Log "   $_" }
            if ($LASTEXITCODE -eq 0) { Write-Log "✓ $id установлена" -Color "Green"; $ok++ }
            else { Write-Log "✗ ${id}: ошибка (код $LASTEXITCODE)" -Color "Red"; $fail++ }
        }
        Write-Log "══ Установка завершена: ✓$ok$(if($fail -gt 0){ `" ✗$fail`" }) ══"
    } -Variables @{ idList = $idList }
})
$selectAllAppsBtn.Add_Click({ foreach($cb in $script:AppCheckboxes.Values){$cb.IsChecked=$true}; Update-AppsCount })
$deselectAllAppsBtn.Add_Click({ foreach($cb in $script:AppCheckboxes.Values){$cb.IsChecked=$false}; Update-AppsCount })

# ═══ Кнопки удаления ═══
$refreshUninstallBtn.Add_Click({ Build-UninstallPanel })
$uninstallSelectedBtn.Add_Click({ Uninstall-SelectedNative })
$bcuUninstallBtn.Add_Click({ Uninstall-SelectedViaBcu })
$selectAllUninstallBtn.Add_Click({
    foreach ($cb in $script:UninstallCheckboxes.Values) { $cb.IsChecked = $true }
    Update-UninstallCounts
})
$deselectAllUninstallBtn.Add_Click({
    foreach ($cb in $script:UninstallCheckboxes.Values) { $cb.IsChecked = $false }
    Update-UninstallCounts
})
$uninstallFilterAllBtn.Add_Click({
    $script:UninstallFilter = "All"
    $uninstallFilterAllBtn.Style   = $window.FindResource("BtnPrimary")
    $uninstallFilterWin32Btn.Style = $window.FindResource("BtnSecondary")
    $uninstallFilterStoreBtn.Style = $window.FindResource("BtnSecondary")
    Apply-UninstallFilter
})
$uninstallFilterWin32Btn.Add_Click({
    $script:UninstallFilter = "Win32"
    $uninstallFilterAllBtn.Style   = $window.FindResource("BtnSecondary")
    $uninstallFilterWin32Btn.Style = $window.FindResource("BtnPrimary")
    $uninstallFilterStoreBtn.Style = $window.FindResource("BtnSecondary")
    Apply-UninstallFilter
})
$uninstallFilterStoreBtn.Add_Click({
    $script:UninstallFilter = "Store"
    $uninstallFilterAllBtn.Style   = $window.FindResource("BtnSecondary")
    $uninstallFilterWin32Btn.Style = $window.FindResource("BtnSecondary")
    $uninstallFilterStoreBtn.Style = $window.FindResource("BtnPrimary")
    Apply-UninstallFilter
})

# ═══ Кнопки обновлений ═══
$checkUpdatesBtn.Add_Click({ $updatesPanel.Children.Clear(); $script:UpdateCheckboxes.Clear(); Build-UpdatesPanel })
$selectAllUpdatesBtn.Add_Click({ foreach($cb in $script:UpdateCheckboxes.Values){$cb.IsChecked=$true}; Update-UpdateCount })
$deselectAllUpdatesBtn.Add_Click({ foreach($cb in $script:UpdateCheckboxes.Values){$cb.IsChecked=$false}; Update-UpdateCount })
$installUpdatesBtn.Add_Click({ Install-SelectedUpdates })

# ═══ Очередь фон->UI: таймер забирает готовые результаты из шины ═══
function Test-BgQueue {
    if (-not $script:PanelsBuilt) {
        if (Get-BgResult -Key 'init') {
            $script:PanelsBuilt = $true
            $p = Get-BgResult -Key 'paths'
            if ($p) {
                if ($p.ScriptsFolder) { $script:ScriptsFolder = $p.ScriptsFolder }
                if ($p.AppsJsonPath)  { $script:AppsJsonPath = $p.AppsJsonPath }
            }
            $scriptsFolderText.Text = $script:ScriptsFolder
            Build-ScriptsPanel
            Build-AppsPanel
            Build-SysPanel
            Build-DiagPanel
            Build-StartupPanel
            Build-UsersPanel
            Build-UninstallPanel
            Write-Log "✓ Готов к работе." -Color "Green"
            $restoreResult=[System.Windows.MessageBox]::Show(
                "Рекомендуется создать точку восстановления системы перед внесением изменений.`n`nСоздать точку восстановления сейчас?",
                "PotatoPC Optimizer",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Question)
            if ($restoreResult -eq "Yes") { Start-Background { Create-RestorePoint } }
        }
        return
    }
    $u = Get-BgResult -Key 'uninstall'
    if ($u -and -not $u.Consumed) {
        $u.Consumed = $true
        if ($u.Gen -eq $script:UninstallPanelGen) {
            $script:UninstallApps = @($u.Data)
            Render-UninstallPanel -Apps $script:UninstallApps
        }
    }
    $s = Get-BgResult -Key 'startup'
    if ($s -and -not $s.Consumed) {
        $s.Consumed = $true
        if ($s.Gen -eq $script:StartupPanelGen) {
            Render-StartupPanel -Data $s.Data
        }
    }
    $up = Get-BgResult -Key 'updates'
    if ($up -and -not $up.Consumed) {
        $up.Consumed = $true
        if ($up.Error) { Write-Log "Ошибка проверки обновлений: $($up.Error)" -Color "Red" }
        Render-UpdatesPanel -Packages @($up.Data)
    }
    if (Get-BgResult -Key 'rebuildScripts') {
        Set-BgResult -Key 'rebuildScripts' -Value $null
        $p = Get-BgResult -Key 'paths'
        if ($p) {
            if ($p.ScriptsFolder) { $script:ScriptsFolder = $p.ScriptsFolder }
            if ($p.AppsJsonPath)  { $script:AppsJsonPath = $p.AppsJsonPath }
        }
        $scriptsFolderText.Text = $script:ScriptsFolder
        Build-ScriptsPanel
        Build-AppsPanel
        $refreshBtn.IsEnabled = $true
        Write-Log "✓ Список скриптов обновлён"
    }
    if (Get-BgResult -Key 'rebuildUninstall') {
        Set-BgResult -Key 'rebuildUninstall' -Value $null
        Build-UninstallPanel
    }
}

# ═══ Окно загружено — финальная инициализация ═══
$window.Add_Loaded({
    $scriptsFolderText.Text = $script:ScriptsFolder
    Write-Log "PotatoPC Optimizer v4.1 запущен"
    Write-Log "Система: $((Get-SystemInfo).OS)"
    Write-Log "Windows $($script:WindowsMajorVersion) обнаружена"
    Write-Log "Рабочая папка: $($script:WorkFolder)"
    Start-BgPoller
    Start-Background {
        try { Initialize-PotatoPC }
        catch { Write-Log "Ошибка инициализации: $_" -Color "Red" }
        Set-BgResult -Key 'init' -Value $true
    }
})

$window.Add_Closing({ Save-UIState; Stop-BgPoller })

$window.ShowDialog() | Out-Null