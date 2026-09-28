$script:CleanCheckboxes = @{}

# Движок очистки (правила + защита) лежит в cleaner/CleanGuard.ps1 и общий с
# scripts/02 Очистка/01_clean_junk.ps1. Раньше здесь была вторая копия тех же
# функций, и защита чистки в GUI расходилась с тем, что чистит скрипт.
$script:CleanGuardPath = ''
try {
    $cleanRoot = if ($script:CleanRulesPath) { Split-Path $script:CleanRulesPath -Parent }
                 elseif ($script:ModuleDir) { Join-Path (Split-Path $script:ModuleDir -Parent) 'cleaner' }
                 else { '' }
    if ($cleanRoot) {
        $script:CleanGuardPath = Join-Path $cleanRoot 'CleanGuard.ps1'
        if (Test-Path -LiteralPath $script:CleanGuardPath -PathType Leaf) { . $script:CleanGuardPath }
    }
} catch {}
if (-not (Get-Command -Name Test-CleanProtectedPath -CommandType Function -ErrorAction SilentlyContinue)) {
    $script:CleanGuardPath = ''
}

function Get-CleanGuardMissing {
    # Признак для панели: чистка недоступна, кнопки надо заблокировать.
    return [string]::IsNullOrWhiteSpace([string]$script:CleanGuardPath)
}

function Load-CleanRules {
    try {
        if ($script:CleanRulesPath -and (Test-Path $script:CleanRulesPath)) {
            return (Get-Content $script:CleanRulesPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop)
        }
    } catch { Write-Log "Правила очистки не прочитались" -Color "Yellow" }
    return $null
}

function Update-CleanCount {
    $sel = @($script:CleanCheckboxes.Values | Where-Object { $_.Box.IsChecked }).Count
    $total = $script:CleanCheckboxes.Count
    $selMB = 0L
    foreach ($kv in $script:CleanCheckboxes.Values) {
        if ($kv.Box.IsChecked -and $kv.MB -gt 0) { $selMB += [long]$kv.MB }
    }
    if ($cleanCountText) { $cleanCountText.Text = "Выбрано: $sel из $total ($(Format-CleanSize $selMB))" }
    try { Update-HeaderCount } catch {}
}

function Apply-CleanFilter {
    param([string]$Group = '')
    $script:CleanGroupFilter = $Group
    foreach ($kv in $script:CleanGroupCards.GetEnumerator()) {
        $vis = ($Group -eq '' -or $kv.Key -eq $Group)
        foreach ($c in $kv.Value) {
            try { $c.Visibility = if ($vis) { 'Visible' } else { 'Collapsed' } } catch {}
        }
    }
    foreach ($kv in $script:CleanGroupHeaders.GetEnumerator()) {
        try { $kv.Value.Visibility = if ($Group -eq '' -or $kv.Key -eq $Group) { 'Visible' } else { 'Collapsed' } } catch {}
    }
    foreach ($kv in $script:CleanFilterBtns.GetEnumerator()) {
        try {
            $kv.Value.Style = if ($kv.Key -eq $Group) { $window.FindResource('BtnPrimary') } else { $window.FindResource('BtnSecondary') }
        } catch {}
    }
}
function Build-CleanPanel {
    if ($null -eq $cleanPanel) { [Console]::WriteLine('PotatoPC: этот файл — часть приложения. Запускай menu.ps1'); return }
    $cleanPanel.Children.Clear()
    $script:CleanCheckboxes = @{}
    $script:CleanGroupCards = @{}
    $script:CleanGroupHeaders = @{}
    $script:CleanFilterBtns = @{}
    $script:CleanFilterNames = @{}
    $script:CleanGroupFilter = ''
    if ($cleanFilterRow) { try { $cleanFilterRow.Children.Clear() } catch {} }

    $rules = Load-CleanRules
    if (-not $rules -or -not $rules.Groups) {
        $t = [System.Windows.Controls.TextBlock]::new()
        $t.Text = "Нет правил очистки (cleaner/rules.json)"
        $t.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#8a8ab0")
        $t.FontSize = 12; $t.TextAlignment = "Center"; $t.Margin = [System.Windows.Thickness]::new(0,50,0,0)
        $cleanPanel.Children.Add($t) | Out-Null
        return
    }
    $gi = 0
    foreach ($group in $rules.Groups) {
        $gkey = [string]$gi
        $gicon = if ($group.Icon) { [string]$group.Icon } else { 'apps/cat_utils' }
        $ghdr = New-SectionHeader -Title ([string]$group.Name) -Icon $gicon
        $cleanPanel.Children.Add($ghdr) | Out-Null
        $script:CleanGroupHeaders[$gkey] = $ghdr
        $script:CleanGroupCards[$gkey] = @()
        $script:CleanFilterNames[$gkey] = [string]$group.Name
        $ii = 0
        foreach ($item in $group.Items) {
            $key = "$gi`:$ii"
            $isAction = (-not [string]::IsNullOrWhiteSpace([string]$item.Action))
            $needAdmin = [bool]$item.NeedsAdmin
            $card = New-Card
            $g = [System.Windows.Controls.Grid]::new()
            $c1 = [System.Windows.Controls.ColumnDefinition]::new(); $c1.Width = [System.Windows.GridLength]::new(28)
            $c2 = [System.Windows.Controls.ColumnDefinition]::new(); $c2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $c3 = [System.Windows.Controls.ColumnDefinition]::new(); $c3.Width = [System.Windows.GridLength]::Auto
            $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2); $g.ColumnDefinitions.Add($c3)
            $cb = [System.Windows.Controls.CheckBox]::new()
            $cb.VerticalAlignment = "Top"; $cb.Margin = [System.Windows.Thickness]::new(0,2,0,0)
            $cb.Tag = $key
            $cb.Add_Checked({ Update-CleanCount })
            $cb.Add_Unchecked({ Update-CleanCount })
            [System.Windows.Controls.Grid]::SetColumn($cb, 0)
            $g.Children.Add($cb) | Out-Null
            $stk = [System.Windows.Controls.StackPanel]::new(); $stk.VerticalAlignment = "Center"
            $nm = [System.Windows.Controls.TextBlock]::new()
            $nm.Text = [string]$item.Name; $nm.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#e0e0f4")
            $nm.FontSize = 12; $nm.FontWeight = "SemiBold"
            $ds = [System.Windows.Controls.TextBlock]::new()
            $ds.Text = [string]$item.Desc + $(if ($needAdmin) { " 🔒" } else { "" }); $ds.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#c4c4ee")
            $ds.FontSize = 11; $ds.TextWrapping = "Wrap"
            $stk.Children.Add($nm) | Out-Null; $stk.Children.Add($ds) | Out-Null
            [System.Windows.Controls.Grid]::SetColumn($stk, 1)
            $g.Children.Add($stk) | Out-Null
            $sz = [System.Windows.Controls.TextBlock]::new()
            $sz.Text = if ($isAction) { "⚡" } else { "—"}; $sz.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#6a6a85")
            $sz.FontSize = 12; $sz.FontWeight = "SemiBold"; $sz.VerticalAlignment = "Center"
            $sz.Margin = [System.Windows.Thickness]::new(10,0,0,0)
            [System.Windows.Controls.Grid]::SetColumn($sz, 2)
            $g.Children.Add($sz) | Out-Null
            $card.Child = $g
            Add-CardFx -Card $card
            $cleanPanel.Children.Add($card) | Out-Null
            $script:CleanCheckboxes[$key] = @{ Box = $cb; Gi = $gi; Ii = $ii; SizeLbl = $sz; MB = -1; Action = [string]$item.Action; NeedsAdmin = $needAdmin }
            $script:CleanGroupCards[$gkey] += @($card)
            $ii++
        }
        $gi++
    }
    if ($cleanFilterRow) {
        try {
            $fbAll = [System.Windows.Controls.Button]::new()
            $fbAll.Content = "Все"
            $fbAll.Style = $window.FindResource('BtnPrimary')
            $fbAll.Height = 26; $fbAll.FontSize = 11; $fbAll.Margin = [System.Windows.Thickness]::new(0,0,5,0)
            $fbAll.Padding = [System.Windows.Thickness]::new(12,0,12,0)
            $fbAll.Cursor = [System.Windows.Input.Cursors]::Hand
            $fbAll.Tag = ''
            $fbAll.Add_Click({ Apply-CleanFilter '' })
            $cleanFilterRow.Children.Add($fbAll) | Out-Null
            $script:CleanFilterBtns[''] = $fbAll
            foreach ($gk in ($script:CleanFilterNames.Keys | Sort-Object)) {
                $fb = [System.Windows.Controls.Button]::new()
                $fb.Content = $script:CleanFilterNames[$gk]
                $fb.Style = $window.FindResource('BtnSecondary')
                $fb.Height = 26; $fb.FontSize = 11; $fb.Margin = [System.Windows.Thickness]::new(0,0,5,0)
                $fb.Padding = [System.Windows.Thickness]::new(12,0,12,0)
                $fb.Cursor = [System.Windows.Input.Cursors]::Hand
                $fb.Tag = [string]$gk
                $fb.Add_Click({ Apply-CleanFilter ([string]$this.Tag) })
                $cleanFilterRow.Children.Add($fb) | Out-Null
                $script:CleanFilterBtns[[string]$gk] = $fb
            }
        } catch {}
    }
    Update-CleanCount
}

function Start-CleanScan {
    if (Get-CleanGuardMissing) {
        Write-Log "✗ Нет cleaner/CleanGuard.ps1 - чистка заблокирована (без защиты она снесёт рабочие папки PotatoPC)." -Color "Red"
        return
    }
    $jobs = @()
    $rules = Load-CleanRules
    if (-not $rules) { return }
    $gi = 0
    foreach ($group in $rules.Groups) {
        $ii = 0
        foreach ($item in $group.Items) {
            if (-not [string]::IsNullOrWhiteSpace([string]$item.Action)) { $ii++; continue }
            $jobs += @{ Key = "$gi`:$ii"; Paths = @($item.Paths); ChildSubdir = [string]$item.ChildSubdir; MinAgeDays = [int]$item.MinAgeDays }
            $ii++
        }
        $gi++
    }
    Write-Log "Замеряю мусор..."
    Set-Progress
    Start-Background {
        try {
            Clear-CleanSkipped
            $res = @()
            $n = 0
            $total = @($jobs).Count
            foreach ($job in $jobs) {
                $n++
                Set-Progress ([double]$n / [double]([Math]::Max(1, $total)))
                try {
                    $rp = @(Resolve-CleanPaths -Paths $job.Paths -ChildSubdir $job.ChildSubdir)
                    $mb = [long](Measure-CleanPaths -Resolved $rp -MinAgeDays $job.MinAgeDays)
                } catch { $mb = 0 }
                $res += @{ Key = $job.Key; MB = $mb }
            }
            Set-BgResult -Key 'cleanScan' -Value @{ Items = $res }
        } catch {}
    } -Variables @{ jobs = $jobs }
}
function Start-CleanSelected {
    if (Get-CleanGuardMissing) {
        Write-Log "✗ Нет cleaner/CleanGuard.ps1 - чистка заблокирована (без защиты она снесёт рабочие папки PotatoPC)." -Color "Red"
        return
    }
    $sel = @($script:CleanCheckboxes.GetEnumerator() | Where-Object { $_.Value.Box.IsChecked })
    if ($sel.Count -eq 0) { Write-Log "⚠ Ничего не выбрано" -Color "Yellow"; return }
    $rules = Load-CleanRules
    if (-not $rules) { return }
    $jobs = @()
    foreach ($kv in $sel) {
        $e = $kv.Value
        try {
            $rule = $rules.Groups[$e.Gi].Items[$e.Ii]
            $jobs += @{ Key = $kv.Key; Name = [string]$rule.Name; Paths = @($rule.Paths); Action = [string]$rule.Action; ChildSubdir = [string]$rule.ChildSubdir; MinAgeDays = [int]$rule.MinAgeDays }
        } catch {}
    }
    if ($jobs.Count -eq 0) { return }
    Write-Log "══ Чистка: $($jobs.Count) пунктов ══"
    Set-Progress 0
    Start-Background {
        try {
            try {
                Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
                Checkpoint-Computer -Description "PotatoPC перед чисткой" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
                Write-Log "Точка восстановления создана." -Color "Green"
            } catch { Write-Log "Без точки восстановления (продолжаю): возможно, точка уже создавалась сегодня." -Color "Yellow" }
            $freed = 0L; $errs = 0; $n = 0
            $total = @($jobs).Count
            Clear-CleanSkipped
            foreach ($job in $jobs) {
                $n++
                Set-Progress ([double]$n / [double]([Math]::Max(1, $total)))
                try {
                    if ($job.Action) {
                        foreach ($ln in (Invoke-CleanAction -Name $job.Action)) { Write-Log ("  " + $ln) }
                        Write-Log ("  ✓ {0}: выполнено" -f $job.Name) -Color "Green"
                        continue
                    }
                    $rp = @(Resolve-CleanPaths -Paths $job.Paths -ChildSubdir $job.ChildSubdir)
                    $before = [long](Measure-CleanPaths -Resolved $rp -MinAgeDays $job.MinAgeDays)
                    $errs += [int](Clear-CleanPaths -Resolved $rp -MinAgeDays $job.MinAgeDays)
                    $freed += $before
                    $gb = if ($before -ge 1MB) { ("{0} МБ" -f [math]::Round($before / 1MB, 1)) } else { "мелочь" }
                    Write-Log ("  −$gb : {0}" -f $job.Name)
                } catch {
                    $errs++
                    Write-Log ("  ✗ {0}: {1}" -f $job.Name, $_) -Color "Yellow"
                }
            }
            $skipped = @(Get-CleanSkippedReport)
            if ($skipped.Count -gt 0) {
                Write-Log ("  🛡 Защищено, не тронуто: {0} (свои папки PotatoPC, ссылки, занятые файлы)" -f $skipped.Count)
            }
            Write-Log ("Освобождено: {0} (ошибок: {1})" -f (Format-CleanSize $freed), $errs) -Color "Green"
            try {
                $hPath = Join-Path $script:WorkFolder 'clean-history.json'
                $h = @()
                if (Test-Path -LiteralPath $hPath) { try { $h = @(Get-Content $hPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop) } catch {} }
                $h += @{ Time = (Get-Date -Format 'yyyy-MM-dd HH:mm'); Freed = $freed; Errors = $errs; Items = $total }
                @($h | Select-Object -Last 50) | ConvertTo-Json -Compress | Out-File -FilePath $hPath -Encoding UTF8 -Force
            } catch {}
            Set-BgResult -Key 'cleanRescan' -Value $true
        } catch {
            Write-Log ("Чистка прервана: " + $_) -Color "Red"
        }
    } -Variables @{ jobs = $jobs }
}
