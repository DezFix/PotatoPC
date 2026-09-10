$script:UpdateCheckboxes = @{}
$script:UpdateIconImgs = @{}
$script:UpdateIconImgs = @{}
$script:UpdatesCache = $null

function Get-StartMenuAppIcon {
    # Вызывать в фоне. Ищет ярлык программы в меню Пуск, тянет иконку exe.
    # Возвращает замороженный ImageSource или $null. Кэш lnk живёт в сессии фона.
    param([string]$AppName)
    try {
        if (-not ('PotatoPC_Gdi32' -as [type])) {
            Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class PotatoPC_Gdi32 { [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr hObject); }' -ErrorAction Stop
        }
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        if (-not $script:StartMenuLnkCache) {
            $all = @()
            foreach ($d in @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs")) {
                if (Test-Path $d) {
                    $all += @(Get-ChildItem -LiteralPath $d -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue)
                }
            }
            $script:StartMenuLnkCache = $all
        }
        $words = @($AppName -split '\s+' | Where-Object { $_.Length -ge 4 } | Select-Object -First 2)
        if ($words.Count -eq 0) { return $null }
        $sh = New-Object -ComObject WScript.Shell -ErrorAction Stop
        $tried = 0
        foreach ($w in $words) {
            foreach ($lnk in $script:StartMenuLnkCache) {
                if ($tried -ge 6) { return $null }
                if ($lnk.BaseName -notlike ('*' + $w + '*')) { continue }
                $tried++
                try {
                    $target = $sh.CreateShortcut($lnk.FullName).TargetPath
                    if (-not $target -or -not (Test-Path $target)) { continue }
                    if ($target -like '*.msc*') { continue }
                    $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($target)
                    if (-not $ico) { continue }
                    try {
                        $bmp = $ico.ToBitmap()
                        $h = $bmp.GetHbitmap()
                        try {
                            $src = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHBitmap($h, [IntPtr]::Zero, [System.Windows.Int32Rect]::Empty, [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
                            $src.Freeze()
                            return $src
                        } finally { try { [PotatoPC_Gdi32]::DeleteObject($h) | Out-Null } catch {} }
                    } finally { try { $bmp.Dispose() } catch {}; try { $ico.Dispose() } catch {} }
                } catch {}
            }
        }
    } catch { return $null }
    return $null
}

function ConvertFrom-WingetUpgradeOutput {
    param([string]$RawOutput)
    $packages = @()
    if ([string]::IsNullOrWhiteSpace($RawOutput)) { return $packages }
    $lines = $RawOutput -split "`n" | Where-Object { $_ -match '\S' }
    $headerFound = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*-+\s*$') { $headerFound = $true; continue }
        if (-not $headerFound) { continue }
        if ($line -match '(доступн|available|upgrade available|обновлен)') { continue }
        # По-токенно: работает и при схлопнутых пробелах (пайп), и при ровной таблице.
        # Id = первый токен с точкой и буквой; имя = всё до него.
        # Версии берём с конца (источник отбрасываем): ячейка версии может содержать пробел.
        $tokens = @($line -split '\s+' | Where-Object { $_ -ne '' })
        if ($tokens.Count -ge 1 -and $tokens[-1] -match '^(winget|msstore)$') {
            $tokens = @($tokens[0..($tokens.Count - 2)])
        }
        if ($tokens.Count -lt 4) { continue }
        $newVersion = $tokens[-1].Trim()
        $version    = $tokens[-2].Trim()
        $idIdx = -1
        for ($i = 0; $i -le ($tokens.Count - 3); $i++) {
            if ($tokens[$i] -match '\.' -and $tokens[$i] -match '[A-Za-z]' -and $tokens[$i] -notmatch '^\d[\d.]*$') { $idIdx = $i; break }
        }
        if ($idIdx -le 0) { continue }
        $name       = ($tokens[0..($idIdx - 1)] -join ' ').Trim()
        $id         = $tokens[$idIdx].Trim()
        if ($version -match '^(winget|msstore|Unknown|Name|Имя|Версия)$') { continue }
        if ($newVersion -match '^(winget|msstore|Unknown)$') { continue }
        if ($version -notmatch '\d' -or $newVersion -notmatch '\d') { continue }
        if ($version -eq $newVersion) { continue }
        if ($id -match '^\d+[\.\d]+$') { continue }
        if ($id -notmatch '\.') { continue }
        $packages += @{
            Name       = $name
            Id         = $id
            Version    = $version
            NewVersion = $newVersion
        }
    }
    return $packages
}

function ConvertFrom-WingetPinOutput {
    param([string]$RawOutput)
    $pins = @()
    if ([string]::IsNullOrWhiteSpace($RawOutput)) { return $pins }
    $lines = $RawOutput -split "`n" | Where-Object { $_ -match '\S' }
    $headerFound = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*-+\s*$') { $headerFound = $true; continue }
        if (-not $headerFound) { continue }
        $tokens = @($line -split '\s+' | Where-Object { $_ -ne '' })
        $idIdx = -1
        for ($i = 0; $i -lt $tokens.Count; $i++) {
            if ($tokens[$i] -match '\.' -and $tokens[$i] -match '[A-Za-z]' -and $tokens[$i] -notmatch '^\d[\d.]*$') { $idIdx = $i; break }
        }
        if ($idIdx -le 0) { continue }
        $id = $tokens[$idIdx].Trim()
        if ($id -notmatch '^(Unknown|winget|msstore|Name)$') {
            $pins += @{ Id = $id; Name = ($tokens[0..($idIdx - 1)] -join ' ').Trim() }
        }
    }
    return $pins
}

function Render-UpdatesPanel {
    param($Packages, $PinnedItems = @())
    if ($null -eq $updatesPanel) { [Console]::WriteLine('PotatoPC: этот файл — часть приложения. Запускай menu.ps1'); return }
    if ($Packages.Count -eq 0) {
        $emptyWrap = [System.Windows.Controls.StackPanel]::new()
        $emptyWrap.HorizontalAlignment = "Center"; $emptyWrap.Margin = "0,60,0,0"
        $emptyImg = Get-IconImage -Name 'actions/select_all' -Size 32
        if ($emptyImg) {
            $emptyImg.HorizontalAlignment = "Center"
            $emptyImg.Margin = [System.Windows.Thickness]::new(0,0,0,10)
            $emptyWrap.Children.Add($emptyImg) | Out-Null
        }
        $lbl = [System.Windows.Controls.TextBlock]::new()
        $lbl.Text = "Все пакеты актуальны — обновлений нет."
        $lbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#50e050")
        $lbl.FontSize = 13; $lbl.TextAlignment = "Center"; $lbl.Margin = "0,0,0,0"
        $emptyWrap.Children.Add($lbl) | Out-Null
        $updatesPanel.Children.Add($emptyWrap) | Out-Null
        $updateStatusText.Text = "Обновлений нет"; Write-Log "Обновлений нет"; return
    }
    $updatesPanel.Children.Add((New-CategoryHeader -Title ("Доступные обновления ({0})" -f @($Packages).Count))) | Out-Null
    $hg = [System.Windows.Controls.Grid]::new()
    $hw0 = [System.Windows.Controls.ColumnDefinition]::new(); $hw0.Width = [System.Windows.GridLength]::new(34)
    $hw1 = [System.Windows.Controls.ColumnDefinition]::new(); $hw1.Width = [System.Windows.GridLength]::new(28)
    $hw2 = [System.Windows.Controls.ColumnDefinition]::new(); $hw2.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
    $hw3 = [System.Windows.Controls.ColumnDefinition]::new(); $hw3.Width = [System.Windows.GridLength]::Auto
    $hw4 = [System.Windows.Controls.ColumnDefinition]::new(); $hw4.Width = [System.Windows.GridLength]::Auto
    $hw5 = [System.Windows.Controls.ColumnDefinition]::new(); $hw5.Width = [System.Windows.GridLength]::Auto
    $hg.ColumnDefinitions.Add($hw0); $hg.ColumnDefinitions.Add($hw1); $hg.ColumnDefinitions.Add($hw2)
    $hg.ColumnDefinitions.Add($hw3); $hg.ColumnDefinitions.Add($hw4); $hg.ColumnDefinitions.Add($hw5)
    $hg.Margin = [System.Windows.Thickness]::new(0,0,0,2)
    $hn = [System.Windows.Controls.TextBlock]::new()
    $hn.Text = "ПРИЛОЖЕНИЕ"; $hn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#6a6a85")
    $hn.FontSize = 10; $hn.FontWeight = "SemiBold"; $hn.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($hn, 2)
    $hv = [System.Windows.Controls.TextBlock]::new()
    $hv.Text = "ВЕРСИЯ → ДОСТУПНА"; $hv.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#6a6a85")
    $hv.FontSize = 10; $hv.FontWeight = "SemiBold"; $hv.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($hv, 3)
    $hg.Children.Add($hn) | Out-Null; $hg.Children.Add($hv) | Out-Null
    $updatesPanel.Children.Add($hg) | Out-Null

    foreach ($pkg in $Packages) {
        $card = New-Card
        $g = [System.Windows.Controls.Grid]::new()
        $c1 = [System.Windows.Controls.ColumnDefinition]::new(); $c1.Width = [System.Windows.GridLength]::new(28)
        $c2 = [System.Windows.Controls.ColumnDefinition]::new(); $c2.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
        $c3 = [System.Windows.Controls.ColumnDefinition]::new(); $c3.Width = [System.Windows.GridLength]::Auto
        $c4 = [System.Windows.Controls.ColumnDefinition]::new(); $c4.Width = [System.Windows.GridLength]::Auto
        $c5 = [System.Windows.Controls.ColumnDefinition]::new(); $c5.Width = [System.Windows.GridLength]::Auto
        $c0 = [System.Windows.Controls.ColumnDefinition]::new(); $c0.Width = [System.Windows.GridLength]::new(34)
        $g.ColumnDefinitions.Add($c0); $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2); $g.ColumnDefinitions.Add($c3); $g.ColumnDefinitions.Add($c4); $g.ColumnDefinitions.Add($c5)
        $cb = [System.Windows.Controls.CheckBox]::new(); $cb.VerticalAlignment = "Center"; $cb.Tag = $pkg.Id
        $cb.Add_Checked({   Update-UpdateCount })
        $cb.Add_Unchecked({ Update-UpdateCount })
        [System.Windows.Controls.Grid]::SetColumn($cb, 1)
        $script:UpdateCheckboxes[$pkg.Id] = $cb
        $uimg = Get-IconImage -Name 'mimetypes/nav_apps' -Size 24
        if (-not $uimg) {
            $uimg = New-Object System.Windows.Controls.Image
            $uimg.Width = 24; $uimg.Height = 24
        }
        $uimg.VerticalAlignment = "Center"; $uimg.Margin = [System.Windows.Thickness]::new(0,0,6,0)
        [System.Windows.Controls.Grid]::SetColumn($uimg, 0)
        $g.Children.Add($uimg) | Out-Null
        $script:UpdateIconImgs[$pkg.Id] = $uimg
        $info = [System.Windows.Controls.StackPanel]::new(); $info.VerticalAlignment = "Center"
        $nm = [System.Windows.Controls.TextBlock]::new()
        $nm.Text = $pkg.Name; $nm.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#e0e0f4")
        $nm.FontSize = 12; $nm.FontWeight = "SemiBold"; $nm.TextTrimming = "CharacterEllipsis"
        $id = [System.Windows.Controls.TextBlock]::new()
        $id.Text = $pkg.Id; $id.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#9898c8")
        $id.FontSize = 10; $id.Margin = [System.Windows.Thickness]::new(0,1,0,0); $id.TextTrimming = "CharacterEllipsis"
        $info.Children.Add($nm) | Out-Null; $info.Children.Add($id) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($info, 2)
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
        [System.Windows.Controls.Grid]::SetColumn($verStack, 3)
        $g.Children.Add($cb) | Out-Null; $g.Children.Add($info) | Out-Null; $g.Children.Add($verStack) | Out-Null
        $oneBtn=[System.Windows.Controls.Button]::new()
        $oneBtn.Content=(New-IconButtonContent -Text 'Обновить' -Icon 'actions/go_up' -Size 11)
        $oneBtn.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#2d2d35")
        $oneBtn.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#d4d4e0")
        $oneBtn.BorderThickness=[System.Windows.Thickness]::new(0); $oneBtn.Cursor=[System.Windows.Input.Cursors]::Hand
        $oneBtn.FontSize=11; $oneBtn.Padding=[System.Windows.Thickness]::new(10,5,10,5); $oneBtn.VerticalAlignment="Center"
        $oneBtn.Margin=[System.Windows.Thickness]::new(10,0,0,0); $oneBtn.Tag=$pkg.Id
        $oneBtn.ToolTip="Обновить только этот пакет"
        $oneBtn.Add_Click({
            $singleId=$this.Tag; $singleBtn=$this
            $singleBtn.IsEnabled=$false
            Write-Log ("Обновление: " + $singleId)
            Set-Progress
            Invoke-Async -ScriptBlock {
                try {
                $wg=Get-WingetPath
                & $wg upgrade --id $id --silent --accept-source-agreements --accept-package-agreements 2>&1 |
                    ForEach-Object { Write-Log ("   " + $_) }
                if ($LASTEXITCODE -eq 0) { Write-Log ("Готово: " + $id) -Color "Green" }
                else { Write-Log ("Ошибка $id (код $LASTEXITCODE)") -Color "Red" }
                Set-BgResult -Key 'updatesRefresh' -Value $true
                } finally { Clear-Progress }
            } -Variables @{ id=$singleId }
        })
        [System.Windows.Controls.Grid]::SetColumn($oneBtn,4)
        $g.Children.Add($oneBtn) | Out-Null
        $pinBtn=[System.Windows.Controls.Button]::new()
        $pinBtn.Content="📌"
        $pinBtn.ToolTip="Не предлагать это обновление"
        $pinBtn.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#2d2d35")
        $pinBtn.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#d4d4e0")
        $pinBtn.BorderThickness=[System.Windows.Thickness]::new(0); $pinBtn.Cursor=[System.Windows.Input.Cursors]::Hand
        $pinBtn.FontSize=11; $pinBtn.Padding=[System.Windows.Thickness]::new(8,5,8,5); $pinBtn.VerticalAlignment="Center"
        $pinBtn.Margin=[System.Windows.Thickness]::new(6,0,0,0); $pinBtn.Tag=$pkg.Id
        $pinBtn.Add_Click({
            $pinId=$this.Tag
            Write-Log ("Скрываю обновление: " + $pinId)
            Set-Progress
            Invoke-Async -ScriptBlock {
                try {
                $wg=Get-WingetPath
                & $wg pin add --id $id 2>&1 | ForEach-Object { Write-Log ("   " + $_) }
                if ($LASTEXITCODE -eq 0) { Write-Log ("Скрыто: " + $id) -Color "Green" }
                else { Write-Log ("Не вышло скрыть $id (код $LASTEXITCODE)") -Color "Yellow" }
                Set-BgResult -Key 'updatesRefresh' -Value $true
                } finally { Clear-Progress }
            } -Variables @{ id=$pinId }
        })
        [System.Windows.Controls.Grid]::SetColumn($pinBtn,5)
        $g.Children.Add($pinBtn) | Out-Null
        $card.Child = $g
        Add-CardFx -Card $card
        $card.Add_MouseEnter({ $this.Background = $script:Theme.CardBgHover })
        $card.Add_MouseLeave({ $this.Background = $script:Theme.CardBg })
        $updatesPanel.Children.Add($card) | Out-Null
    }
    $hidden = @($PinnedItems)
    if ($hidden.Count -gt 0) {
        $updatesPanel.Children.Add((New-CategoryHeader -Title "Скрытые — не предлагаются")) | Out-Null
        foreach ($h in $hidden) {
            $hcard=New-Card
            $hg2=[System.Windows.Controls.Grid]::new()
            $hc1=[System.Windows.Controls.ColumnDefinition]::new(); $hc1.Width=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
            $hc2=[System.Windows.Controls.ColumnDefinition]::new(); $hc2.Width=[System.Windows.GridLength]::Auto
            $hg2.ColumnDefinitions.Add($hc1); $hg2.ColumnDefinitions.Add($hc2)
            $hnm=[System.Windows.Controls.TextBlock]::new()
            $hnm.Text=[string]$h.Name; $hnm.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#9898c8")
            $hnm.FontSize=12; $hnm.VerticalAlignment="Center"; $hnm.TextTrimming="CharacterEllipsis"
            [System.Windows.Controls.Grid]::SetColumn($hnm,0)
            $hg2.Children.Add($hnm) | Out-Null
            $unBtn=[System.Windows.Controls.Button]::new()
            $unBtn.Content="Вернуть"
            $unBtn.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#2d2d35")
            $unBtn.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#d4d4e0")
            $unBtn.BorderThickness=[System.Windows.Thickness]::new(0); $unBtn.Cursor=[System.Windows.Input.Cursors]::Hand
            $unBtn.FontSize=11; $unBtn.Padding=[System.Windows.Thickness]::new(10,5,10,5); $unBtn.VerticalAlignment="Center"
            $unBtn.Margin=[System.Windows.Thickness]::new(10,0,0,0); $unBtn.Tag=[string]$h.Id
            $unBtn.ToolTip="Снова предлагать это обновление"
            $unBtn.Add_Click({
                $unId=$this.Tag
                Write-Log ("Возвращаю обновление: " + $unId)
            Invoke-Async -ScriptBlock {
                try {
                $wg=Get-WingetPath
                & $wg pin remove --id $id 2>&1 | ForEach-Object { Write-Log ("   " + $_) }
                if ($LASTEXITCODE -eq 0) { Write-Log ("Вернуто: " + $id) -Color "Green" }
                else { Write-Log ("Не вышло вернуть $id (код $LASTEXITCODE)") -Color "Yellow" }
                Set-BgResult -Key 'updatesRefresh' -Value $true
                } finally { Clear-Progress }
            } -Variables @{ id=$unId }
            })
            [System.Windows.Controls.Grid]::SetColumn($unBtn,1)
            $hg2.Children.Add($unBtn) | Out-Null
            $hcard.Child=$hg2
            $updatesPanel.Children.Add($hcard) | Out-Null
        }
    }
    $updateStatusText.Text = "Найдено обновлений: $($Packages.Count)"
    $updateCountText.Text = "Выбрано: 0"
    Write-Log "🔄 Найдено $($Packages.Count) обновлений"
}

function Update-UpdateCount {
    $count = @($script:UpdateCheckboxes.Values | Where-Object { $_.IsChecked }).Count
    if ($updateCountText) { $updateCountText.Text = "Выбрано: $count" }
    try { Update-HeaderCount } catch {}
}

function Build-UpdatesPanel {
    param([switch]$Force)
    if ($null -eq $updatesPanel) { [Console]::WriteLine('PotatoPC: этот файл — часть приложения. Запускай menu.ps1'); return }
    try {
        if (-not $Force -and $script:UpdatesCache -and $script:UpdatesCache.Time) {
            $age = (Get-Date) - $script:UpdatesCache.Time
            if ($age.TotalMinutes -lt 15) {
                $updatesPanel.Children.Clear()
                $script:UpdateCheckboxes.Clear()
                $script:UpdateIconImgs = @{}
                Render-UpdatesPanel -Packages @($script:UpdatesCache.Data) -PinnedItems @($script:UpdatesCache.PinnedItems)
                $updateStatusText.Text = "Найдено обновлений: $(@($script:UpdatesCache.Data).Count) (проверено $([int]$age.TotalMinutes) мин назад)"
                return
            }
        }
    } catch {}
    $updatesPanel.Children.Clear()
    $script:UpdateCheckboxes.Clear()
    $script:UpdateIconImgs = @{}
    $updateStatusText.Text = "Идёт проверка обновлений..."; $updateCountText.Text = ""
    Set-Progress
    Start-Background {
        try {
            $wg = Get-WingetPath
            if ($wg -eq "winget" -and -not (Get-Command winget -ErrorAction SilentlyContinue)) {
                throw "winget не найден. Установи App Installer из Microsoft Store."
            }
            $raw = & $wg upgrade --accept-source-agreements 2>&1 | Out-String
            $packages = @(ConvertFrom-WingetUpgradeOutput -RawOutput $raw)
            try {
                $pinRaw = & $wg pin list 2>&1 | Out-String
                $pinned = @(ConvertFrom-WingetPinOutput -RawOutput $pinRaw)
            } catch { $pinned = @() }
            $pinnedIds = @($pinned | ForEach-Object { $_.Id })
            if ($pinnedIds.Count -gt 0) {
                $packages = @($packages | Where-Object { $pinnedIds -notcontains $_.Id })
            }
            Set-BgResult -Key 'updates' -Value @{ Data = $packages; Pinned = $pinned }
            try {
                $icons = @()
                foreach ($pkg in $packages) {
                    try {
                        $src = Get-StartMenuAppIcon -AppName $pkg.Name
                        if ($src) { $icons += @{ Id = $pkg.Id; Img = $src } }
                    } catch {}
                }
                if ($icons.Count -gt 0) { Set-BgResult -Key 'updateIcons' -Value @{ Items = $icons } }
            } catch {}
        } catch {
            Set-BgResult -Key 'updates' -Value @{ Data = @(); Error = [string]$_ }
        }
    }
}

function Install-SelectedUpdates {
    $sel = $script:UpdateCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked }
    if (-not $sel) { Write-Log "⚠ Нет выбранных" -Color "Yellow"; return }
    $idList = @($sel | ForEach-Object { $_.Key })
    Write-Log "══ Обновление $($idList.Count) пакетов ══"
    Invoke-Async -ScriptBlock {
        $wg = Get-WingetPath
        $ok = 0; $fail = 0; $i = 0
        $total=@($idList).Count
        Write-Log "Не закрывай окно: большие пакеты ставятся молча по несколько минут."
        try {
        foreach ($id in $idList) {
            $i++
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            Write-Log "⬆ [$i/$total] $id..."
            Set-Progress ([double]$i / [double]([Math]::Max(1, $total)))
            & $wg upgrade --id $id --silent --accept-source-agreements --accept-package-agreements 2>&1 |
                ForEach-Object { Write-Log "   $_" }
            $sw.Stop()
            $dur = if ($sw.Elapsed.TotalSeconds -ge 60) { "{0} мин" -f [int]$sw.Elapsed.TotalMinutes } else { "{0} сек" -f [int]$sw.Elapsed.TotalSeconds }
            if ($LASTEXITCODE -eq 0) { Write-Log "   ✓ Готово за $dur" -Color "Green"; $ok++ }
            else { Write-Log "   ✗ Ошибка (код $LASTEXITCODE)" -Color "Red"; $fail++ }
        }
        Write-Log "══ Обновление завершено: ✓$ok$(if($fail -gt 0){ `" ✗$fail`" }) ══"
        Set-BgResult -Key 'updatesRefresh' -Value $true
        } finally { Clear-Progress }
    } -Variables @{ idList = $idList }
}

function Show-HiddenUpdatesDialog {
    $pins = @()
    try { $pins = @($script:UpdatesCache.PinnedItems) } catch {}
    if ($pins.Count -eq 0) {
        $res = [System.Windows.MessageBox]::Show("Скрытых пока нет. Если только что скрыл — список ещё обновляется (10-30 сек).`n`nПроверить сейчас?", "Скрытые", "YesNo", "Question")
        if ($res -eq "Yes") {
            try { Build-UpdatesPanel -Force } catch {}
        }
        return
    }
    $dlg = New-Object System.Windows.Window
    $dlg.Title = "Скрытые обновления"
    $dlg.Width = 480; $dlg.Height = 420
    $dlg.WindowStartupLocation = "CenterScreen"
    $dlg.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#202020")
    try { $dlg.Owner = $window } catch {}
    $root = New-Object System.Windows.Controls.StackPanel
    $root.Margin = [System.Windows.Thickness]::new(16)
    $cap = New-Object System.Windows.Controls.TextBlock
    $cap.Text = "Не предлагаются ($($pins.Count)). Верни любое кнопкой — список обновится сам."
    $cap.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#a8a8d8")
    $cap.FontSize = 11; $cap.TextWrapping = "Wrap"; $cap.Margin = [System.Windows.Thickness]::new(0,0,0,10)
    $root.Children.Add($cap) | Out-Null
    $sv = New-Object System.Windows.Controls.ScrollViewer
    $sv.VerticalScrollBarVisibility = "Auto"; $sv.Height = 270
    $list = New-Object System.Windows.Controls.StackPanel
    $sv.Content = $list
    $root.Children.Add($sv) | Out-Null
    foreach ($h in $pins) {
        $row = New-Object System.Windows.Controls.Border
        $row.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#26262e")
        $row.CornerRadius = [System.Windows.CornerRadius]::new(8)
        $row.Margin = [System.Windows.Thickness]::new(0,0,0,6)
        $row.Padding = [System.Windows.Thickness]::new(12,8,12,8)
        $g = New-Object System.Windows.Controls.Grid
        $cc1 = New-Object System.Windows.Controls.ColumnDefinition
        $cc1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $cc2 = New-Object System.Windows.Controls.ColumnDefinition
        $cc2.Width = [System.Windows.GridLength]::Auto
        $g.ColumnDefinitions.Add($cc1); $g.ColumnDefinitions.Add($cc2)
        $nm = New-Object System.Windows.Controls.TextBlock
        $nm.Text = [string]$h.Name
        $nm.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#e0e0f4")
        $nm.FontSize = 12; $nm.VerticalAlignment = "Center"; $nm.TextTrimming = "CharacterEllipsis"
        [System.Windows.Controls.Grid]::SetColumn($nm, 0)
        $g.Children.Add($nm) | Out-Null
        $ub = New-Object System.Windows.Controls.Button
        $ub.Content = "Вернуть"
        $ub.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#2d2d35")
        $ub.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#d4d4e0")
        $ub.BorderThickness = [System.Windows.Thickness]::new(0)
        $ub.Cursor = [System.Windows.Input.Cursors]::Hand
        $ub.FontSize = 11; $ub.Padding = [System.Windows.Thickness]::new(10,5,10,5)
        $ub.Margin = [System.Windows.Thickness]::new(10,0,0,0); $ub.Tag = [string]$h.Id
        $ubRow = $row; $ubList = $list; $ubDlg = $dlg
        $ub.Add_Click({
            $unId = $this.Tag
            $this.IsEnabled = $false
            Write-Log ("Возвращаю обновление: " + $unId)
            try { $ubList.Children.Remove($ubRow) } catch {}
            if ($ubList.Children.Count -eq 0) { try { $ubDlg.Close() } catch {} }
            Set-Progress
            Invoke-Async -ScriptBlock {
                try {
                $wg=Get-WingetPath
                & $wg pin remove --id $id 2>&1 | ForEach-Object { Write-Log ("   " + $_) }
                if ($LASTEXITCODE -eq 0) { Write-Log ("Вернуто: " + $id) -Color "Green" }
                else { Write-Log ("Не вышло вернуть $id (код $LASTEXITCODE)") -Color "Yellow" }
                Set-BgResult -Key 'updatesRefresh' -Value $true
                } finally { Clear-Progress }
            } -Variables @{ id = $unId }
        }.GetNewClosure())
        [System.Windows.Controls.Grid]::SetColumn($ub, 1)
        $g.Children.Add($ub) | Out-Null
        $row.Child = $g
        $list.Children.Add($row) | Out-Null
    }
    $dlg.Content = $root
    $dlg.ShowDialog() | Out-Null
}