$script:CleanCheckboxes = @{}

function Expand-CleanEnv {
    # Самодостаточная: ${VAR} -> пути Windows.
    param([string]$Path)
    $pfx86 = ${env:ProgramFiles(x86)}
    if ([string]::IsNullOrWhiteSpace($pfx86)) { $pfx86 = $env:ProgramFiles }
    $map = @{
        'LOCALAPPDATA' = $env:LOCALAPPDATA; 'APPDATA' = $env:APPDATA
        'PROGRAMDATA' = $env:PROGRAMDATA; 'WINDIR' = $env:SystemRoot
        'SYSTEMROOT' = $env:SystemRoot; 'PROGRAMFILES' = $env:ProgramFiles
        'PROGRAMFILES_X86' = $pfx86; 'USERPROFILE' = $env:USERPROFILE
        'TEMP' = $env:TEMP; 'TMP' = $env:TEMP; 'SYSTEMDRIVE' = $env:SystemDrive
    }
    return [regex]::Replace([string]$Path, '\$\{(\w+)\}', {
        param($m)
        $k = $m.Groups[1].Value
        if ($map.ContainsKey($k) -and $map[$k]) { return $map[$k] }
        return $m.Value
    })
}

function Resolve-CleanPaths {
    # Самодостаточная: шаблоны (* поддерживаются) -> существующие пути.
    # ChildSubdir: для версионных папок (JetBrains/<версия>/caches): берём base/*/ChildSubdir.
    param([string[]]$Paths, [string]$ChildSubdir = '')
    $out = @()
    foreach ($p in $Paths) {
        $e = Expand-CleanEnv $p
        if ([string]::IsNullOrWhiteSpace($e) -or $e -match '\$\{') { continue }
        try {
            if ([string]::IsNullOrWhiteSpace($ChildSubdir)) {
                if (Test-Path -LiteralPath $e) { $out += $e; continue }
                foreach ($f in @(Get-ChildItem -Path $e -Force -ErrorAction SilentlyContinue)) {
                    $out += $f.FullName
                }
            } else {
                $bases = @()
                if (Test-Path -LiteralPath $e) { $bases += $e }
                else { foreach ($f in @(Get-ChildItem -Path $e -Force -ErrorAction SilentlyContinue)) { $bases += $f.FullName } }
                foreach ($b in $bases) {
                    foreach ($d in @(Get-ChildItem -LiteralPath $b -Directory -Force -ErrorAction SilentlyContinue)) {
                        $cand = Join-Path $d.FullName $ChildSubdir
                        if (Test-Path -LiteralPath $cand) { $out += $cand }
                    }
                }
            }
        } catch {}
    }
    return $out
}

function Measure-CleanPaths {
    # Самодостаточная: суммарный размер байт. MinAgeDays>0: считаем только файлы старше N дней.
    param([string[]]$Resolved, [int]$MinAgeDays = 0)
    $cutoff = $null
    if ($MinAgeDays -gt 0) { $cutoff = (Get-Date).AddDays(-$MinAgeDays) }
    $sum = 0L
    foreach ($r in $Resolved) {
        try {
            if (Test-Path -LiteralPath $r -PathType Leaf) {
                $it = Get-Item -LiteralPath $r -Force -ErrorAction SilentlyContinue
                if ($it -and ($null -eq $cutoff -or $it.LastWriteTime -lt $cutoff)) { $sum += $it.Length }
            } else {
                $files = @(Get-ChildItem -LiteralPath $r -Recurse -File -Force -ErrorAction SilentlyContinue)
                if ($cutoff) { $files = @($files | Where-Object { $_.LastWriteTime -lt $cutoff }) }
                $s = ($files | Measure-Object Length -Sum).Sum
                if ($s) { $sum += [long]$s }
            }
        } catch {}
    }
    return $sum
}

function Clear-CleanPaths {
    # Самодостаточная: удаляет СОДЕРЖИМОЕ папок и файлы. Возвращает число ошибок.
    # MinAgeDays>0: свежие файлы не трогаем (идея Kudu minAgeDays для логов), пустые папки подчищаем.
    param([string[]]$Resolved, [int]$MinAgeDays = 0)
    $cutoff = $null
    if ($MinAgeDays -gt 0) { $cutoff = (Get-Date).AddDays(-$MinAgeDays) }
    $err = 0
    foreach ($r in $Resolved) {
        try {
            if (Test-Path -LiteralPath $r -PathType Leaf) {
                if ($cutoff) {
                    try { if ((Get-Item -LiteralPath $r -Force -ErrorAction Stop).LastWriteTime -ge $cutoff) { continue } } catch {}
                }
                Remove-Item -LiteralPath $r -Force -ErrorAction Stop
            } elseif ($cutoff) {
                foreach ($f in @(Get-ChildItem -LiteralPath $r -Recurse -File -Force -ErrorAction SilentlyContinue |
                        Where-Object { $_.LastWriteTime -lt $cutoff })) {
                    try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop }
                    catch { $err++ }
                }
                foreach ($d in @(Get-ChildItem -LiteralPath $r -Recurse -Directory -Force -ErrorAction SilentlyContinue |
                        Sort-Object { $_.FullName.Length } -Descending)) {
                    try {
                        if ((Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction Stop | Measure-Object).Count -eq 0) {
                            Remove-Item -LiteralPath $d.FullName -Force -ErrorAction Stop
                        }
                    } catch {}
                }
            } else {
                Get-ChildItem -LiteralPath $r -Force -ErrorAction SilentlyContinue |
                    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch { $err++ }
    }
    return $err
}

function Format-CleanSize {
    param([long]$Bytes)
    if ($Bytes -le 0) { return "нет" }
    if ($Bytes -ge 1GB) { return ("{0} ГБ" -f [math]::Round($Bytes / 1GB, 1)) }
    if ($Bytes -ge 1MB) { return ("{0} МБ" -f [math]::Round($Bytes / 1MB, 1)) }
    return ("{0} КБ" -f [math]::Max(1, [int]($Bytes / 1KB)))
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

function Invoke-CleanAction {
    # Самодостаточная: именованное действие сети. Возвращает строки для лога.
    param([string]$Name)
    $out = @()
    try {
        if ($Name -eq 'flushdns') {
            $r = ipconfig /flushdns 2>&1 | Out-String
            $out += @(($r -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -First 2))
        } elseif ($Name -eq 'arpclear') {
            try {
                Get-NetNeighbor -ErrorAction Stop | Remove-NetNeighbor -Confirm:$false -ErrorAction Stop
                $out += @('ARP-кэш очищен (Remove-NetNeighbor)')
            } catch {
                try { $r = arp -d * 2>&1 | Out-String } catch { $r = '' }
                $out += @(($r -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -First 3))
                if ($out.Count -eq 0) { $out += @('ARP-кэш очищен') }
            }
        } else { $out += @('Неизвестное действие') }
    } catch { $out += @('Ошибка: ' + $_) }
    return $out
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
            $fbAll.Add_Click({ Apply-CleanFilter '' }.GetNewClosure())
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
                $fb.Add_Click({ Apply-CleanFilter ([string]$this.Tag) }.GetNewClosure())
                $cleanFilterRow.Children.Add($fb) | Out-Null
                $script:CleanFilterBtns[[string]$gk] = $fb
            }
        } catch {}
    }
    Update-CleanCount
}

function Start-CleanScan {
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
