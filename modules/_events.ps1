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
$scriptPresetPotatoBtn.Add_Click({
    if (-not (Get-Command Select-ScriptPreset -ErrorAction SilentlyContinue)) {
        Write-Log "ОШИБКА: модуль _scripts.ps1 не загружен. Удали $env:TEMP\PotatoPC и перезапусти." -Color Red
        return
    }
    Select-ScriptPreset "potato"
})
$scriptPresetOfficeBtn.Add_Click({
    if (-not (Get-Command Select-ScriptPreset -ErrorAction SilentlyContinue)) {
        Write-Log "ОШИБКА: модуль _scripts.ps1 не загружен. Удали $env:TEMP\PotatoPC и перезапусти." -Color Red
        return
    }
    Select-ScriptPreset "office"
})
$scriptPresetGameBtn.Add_Click({
    if (-not (Get-Command Select-ScriptPreset -ErrorAction SilentlyContinue)) {
        Write-Log "ОШИБКА: модуль _scripts.ps1 не загружен. Удали $env:TEMP\PotatoPC и перезапусти." -Color Red
        return
    }
    Select-ScriptPreset "game"
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

$clearLogBtn.Add_Click({ try { $LogBox.Document.Blocks.Clear() } catch {} })
$copyLogBtn.Add_Click({
    try {
        [System.Windows.Clipboard]::SetText((Get-LogPlainText -Box $LogBox))
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

# ═══ Иконки Papirus в шапке/сайдбаре (null-safe) ═══
try { Initialize-WindowIcons } catch {}

# ═══ Навигация сайдбара 2026 (null-safe: старый XAML тоже запустится) ═══
try { if ($NavModulesBtn) { $NavModulesBtn.Add_Click({ Set-ActiveNav -Index 0 }) } } catch {}
try { if ($NavStartupBtn) { $NavStartupBtn.Add_Click({ Set-ActiveNav -Index 1 }) } } catch {}
try { if ($NavUsersBtn)   { $NavUsersBtn.Add_Click({ Set-ActiveNav -Index 2 }) } } catch {}
try { if ($NavAppsBtn)    { $NavAppsBtn.Add_Click({ Set-ActiveNav -Index 3 }) } } catch {}
try { if ($NavUpdatesBtn) { $NavUpdatesBtn.Add_Click({ Set-ActiveNav -Index 4 }) } } catch {}
try { if ($NavDiagBtn)    { $NavDiagBtn.Add_Click({ Set-ActiveNav -Index 5 }) } } catch {}
try { if ($NavSysBtn)     { $NavSysBtn.Add_Click({ Set-ActiveNav -Index 6 }) } } catch {}
try { if ($MainTabControl) { $MainTabControl.Add_SelectionChanged({ try { Set-ActiveNav -Index $MainTabControl.SelectedIndex } catch {} }) } } catch {}
$presetPotatoBtn.Add_Click({ Select-Preset "Potato-pack" })
$presetOfficeBtn.Add_Click({ Select-Preset "Office-pack" })
$presetGamesBtn.Add_Click({ Select-Preset "Games-pack" })

$installAppsBtn.Add_Click({
    $sel = $script:AppCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked }
    if (-not $sel) { Write-Log "⚠ Нет выбранных приложений" -Color "Yellow"; return }
    try {
        $wgTest = Get-WingetPath
        if ($wgTest -eq "winget" -and -not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Log "winget не найден. Поставь его: Модули → Магазин программ." -Color "Red"
            return
        }
    } catch {}
    $idList = @($sel | ForEach-Object { $_.Key })
    try { $knownIds = @($script:InstalledAppIds) } catch { $knownIds = @() }
    $skipped = @($idList | Where-Object { $knownIds -contains $_ })
    $idList = @($idList | Where-Object { $knownIds -notcontains $_ })
    if ($skipped.Count -gt 0) { Write-Log ("Пропускаю уже установленные: " + ($skipped -join ", ")) }
    if ($idList.Count -eq 0) { Write-Log "Все выбранные уже стоят." -Color "Green"; return }
    Write-Log "══ Установка $($idList.Count) приложений ══"
    Invoke-Async -ScriptBlock {
        $wg = Get-WingetPath
        $ok = 0; $fail = 0; $i = 0
        $total=@($idList).Count
        Write-Log "Не закрывай окно: большие пакеты ставятся молча по несколько минут."
        try {
        foreach ($id in $idList) {
            $i++
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            Write-Log "⏳ Установка [$i/$total]: $id..."
            Set-Progress ([double]$i / [double]([Math]::Max(1, $total)))
            & $wg install --id $id --silent --accept-source-agreements --accept-package-agreements 2>&1 |
                ForEach-Object { Write-Log "   $_" }
            $sw.Stop()
            $dur = if ($sw.Elapsed.TotalSeconds -ge 60) { "{0} мин" -f [int]$sw.Elapsed.TotalMinutes } else { "{0} сек" -f [int]$sw.Elapsed.TotalSeconds }
            if ($LASTEXITCODE -eq 0) { Write-Log "✓ $id установлена за $dur" -Color "Green"; $ok++ }
            else { Write-Log "✗ ${id}: ошибка (код $LASTEXITCODE)" -Color "Red"; $fail++ }
        }
        Write-Log "══ Установка завершена: ✓$ok$(if($fail -gt 0){ `" ✗$fail`" }) ══"
        Set-BgResult -Key 'appsRefresh' -Value $true
        } finally { Clear-Progress }
    } -Variables @{ idList = $idList }
})
$selectAllAppsBtn.Add_Click({ foreach($cb in $script:AppCheckboxes.Values){$cb.IsChecked=$true}; Update-AppsCount })
$deselectAllAppsBtn.Add_Click({ foreach($cb in $script:AppCheckboxes.Values){$cb.IsChecked=$false}; Update-AppsCount })

# ═══ Кнопки обновлений ═══
$checkUpdatesBtn.Add_Click({ $updatesPanel.Children.Clear(); $script:UpdateCheckboxes.Clear(); Build-UpdatesPanel -Force })
$selectAllUpdatesBtn.Add_Click({ foreach($cb in $script:UpdateCheckboxes.Values){$cb.IsChecked=$true}; Update-UpdateCount })
$deselectAllUpdatesBtn.Add_Click({ foreach($cb in $script:UpdateCheckboxes.Values){$cb.IsChecked=$false}; Update-UpdateCount })
$installUpdatesBtn.Add_Click({ Install-SelectedUpdates })
$updateAllBtn.Add_Click({
    foreach ($cb in $script:UpdateCheckboxes.Values) { $cb.IsChecked = $true }
    Update-UpdateCount
    Install-SelectedUpdates
})
$hiddenUpdatesBtn.Add_Click({
    if (-not (Get-Command Show-HiddenUpdatesDialog -ErrorAction SilentlyContinue)) {
        Write-Log "ОШИБКА: модуль _updates.ps1 не загружен." -Color Red
        return
    }
    Show-HiddenUpdatesDialog
})

# ═══ Очередь фон->UI: таймер забирает готовые результаты из шины ═══
function Test-BgQueue {
    Drain-BgLog
    try { Update-ProgressUI } catch {}
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
            Write-Log "✓ Готов к работе." -Color "Green"
            try {
                if ($sideStatusText) {
                    $sideStatusText.Text = "Скриптов: $($script:ScriptCheckboxes.Count) • Программ: $($script:AppCheckboxes.Count)"
                }
                Update-HeaderCount
            } catch {}
            $restoreResult=[System.Windows.MessageBox]::Show(
                "Рекомендуется создать точку восстановления системы перед внесением изменений.`n`nСоздать точку восстановления сейчас?",
                "PotatoPC Optimizer",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Question)
            if ($restoreResult -eq "Yes") { Start-Background { Create-RestorePoint } }
        }
        return
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
        else {
            $pins = @($up.Pinned)
            $script:UpdatesCache = @{ Time = (Get-Date); Data = @($up.Data); PinnedItems = $pins }
            if ($pins.Count -gt 0) { Write-Log "Скрыто закреплённых: $($pins.Count)" }
            try {
                if ($hiddenUpdatesBtnText) {
                    $hiddenUpdatesBtnText.Text = if ($pins.Count -gt 0) { "📌 Скрытые ($($pins.Count))" } else { "📌 Скрытые" }
                }
            } catch {}
        }
        $cpins = @(); try { $cpins = @($script:UpdatesCache.PinnedItems) } catch {}
        Render-UpdatesPanel -Packages @($up.Data) -PinnedItems $cpins
        try { Clear-Progress } catch {}
    }
    if (Get-BgResult -Key 'updatesRefresh') {
        Set-BgResult -Key 'updatesRefresh' -Value $null
        try { $updatesPanel.Children.Clear(); $script:UpdateCheckboxes.Clear(); Build-UpdatesPanel -Force } catch {}
    }
    if (Get-BgResult -Key 'appsRefresh') {
        Set-BgResult -Key 'appsRefresh' -Value $null
        try { Build-AppsPanel } catch {}
    }
    $ai = Get-BgResult -Key 'appIcons'
    if ($ai -and -not $ai.Consumed) {
        $ai.Consumed = $true
        try {
            foreach ($it in @($ai.Items)) {
                if ($script:AppIconImgs.ContainsKey($it.Id)) {
                    $ctl = $script:AppIconImgs[$it.Id]
                    if ($ctl -is [System.Windows.Controls.Image]) { $ctl.Source = $it.Img }
                }
            }
            try { Clear-Progress } catch {}
        } catch {}
    }
    $ui = Get-BgResult -Key 'updateIcons'
    if ($ui -and -not $ui.Consumed) {
        $ui.Consumed = $true
        try {
            foreach ($it in @($ui.Items)) {
                if ($script:UpdateIconImgs.ContainsKey($it.Id)) {
                    $ctl = $script:UpdateIconImgs[$it.Id]
                    if ($ctl -is [System.Windows.Controls.Image]) { $ctl.Source = $it.Img }
                }
            }
        } catch {}
    }
    $ia = Get-BgResult -Key 'installedApps'
    if ($ia -and -not $ia.Consumed) {
        $ia.Consumed = $true
        try {
            $ids = @($ia.Ids)
            $script:InstalledAppIds = $ids
            $n = 0
            foreach ($id in $ids) {
                if ($script:AppBadges.ContainsKey($id)) {
                    $script:AppBadges[$id].Visibility = "Visible"
                    $n++
                }
            }
            if ($n -gt 0) { Write-Log "Установлено приложений из списка: $n" }
            try { Clear-Progress } catch {}
        } catch {}
    }
    $ar = Get-BgResult -Key 'auditReport'
    if ($ar -and -not $ar.Consumed) {
        $ar.Consumed = $true
        Set-BgResult -Key 'auditReport' -Value $null
        try {
            if ($ar.Path) { $script:LastAuditReport = $ar.Path }
            if ($script:AuditStatusLbl) {
                $script:AuditStatusLbl.Text = "готово: ошибок $($ar.Err), предупреждений $($ar.Warn)"
                $c = if ($ar.Err -gt 0) { "#e74c3c" } elseif ($ar.Warn -gt 0) { "#f0c040" } else { "#2ecc71" }
                $script:AuditStatusLbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom($c)
            }
            if ($script:AuditOpenBtn -and $script:LastAuditReport -and (Test-Path $script:LastAuditReport)) {
                $script:AuditOpenBtn.IsEnabled = $true
            }
            try { Clear-Progress } catch {}
        } catch {}
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
}

# ═══ Окно загружено — финальная инициализация ═══
$window.Add_Loaded({
    try { Enable-DarkTitleBar -Window $window } catch {}
    try {
        if (-not $window.TaskbarItemInfo) {
            $window.TaskbarItemInfo = New-Object System.Windows.Shell.TaskbarItemInfo
        }
    } catch {}
    $scriptsFolderText.Text = $script:ScriptsFolder
    Write-Log "PotatoPC Optimizer v5.0 (Sidebar 2026, локально, без пуша) запущен"
    Write-Log "Система: $((Get-SystemInfo).OS)"
    Write-Log "Windows $($script:WindowsMajorVersion) обнаружена"
    Write-Log "Рабочая папка: $($script:WorkFolder)"
    try { Set-ActiveNav -Index $MainTabControl.SelectedIndex } catch {}
    Start-BgPoller
    Start-Background {
        try { Initialize-PotatoPC }
        catch { Write-Log "Ошибка инициализации: $_" -Color "Red" }
        Set-BgResult -Key 'init' -Value $true
    }
})

$window.Add_Closing({ Save-UIState; Stop-BgPoller })

$window.ShowDialog() | Out-Null