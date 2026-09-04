# Вкладка "Удаление" — гибрид: свой метод (штатный деинсталлятор + безопасные остатки)
# + сложные случаи через BCU-console (Apache 2.0, качается по требованию в TEMP, в репо не хранится).

$script:UninstallCheckboxes = @{}
$script:UninstallApps      = @()
$script:UninstallFilter    = "All"
$script:UninstallPanelGen  = 0

$script:BcuVersion       = "6.2"
$script:BcuNetAsset      = "BCUninstaller_6.2.0_net8.0-windows10.0.18362.0.zip"
$script:BcuPortableAsset = "BCUninstaller_6.2.0_portable.zip"

function Get-BcuToolsDir {
    return (Join-Path $script:WorkFolder "tools\BCU")
}

function Split-UninstallCommand {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return $null }
    $cmd = [System.Environment]::ExpandEnvironmentVariables($Command.Trim())
    $file = $null; $args = ""
    if ($cmd.StartsWith('"')) {
        $end = $cmd.IndexOf('"', 1)
        if ($end -gt 0) { $file = $cmd.Substring(1, $end - 1); $args = $cmd.Substring($end + 1).Trim() }
        else { $file = $cmd.Trim('"') }
    } else {
        $parts = $cmd.Split(' ', 2, [System.StringSplitOptions]::RemoveEmptyEntries)
        $file = $parts[0]
        if ($parts.Count -gt 1) { $args = $parts[1] }
    }
    if ([string]::IsNullOrWhiteSpace($file)) { return $null }
    return @{ File = $file; Arguments = $args }
}

function Get-QuietUninstallCommand {
    param($App)
    if ($App.Source -eq "Store") { return @{ Store = $true } }
    if (-not [string]::IsNullOrWhiteSpace($App.QuietUninstallString)) {
        $q = Split-UninstallCommand -Command $App.QuietUninstallString
        if ($q) { return $q }
    }
    $raw = [string]$App.UninstallString
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $m = [regex]::Match($raw, '(?i)msiexec(?:\.exe)?\s*/[IX]\s*(\{[0-9A-F\-]+\})')
    if ($m.Success) {
        return @{ File = "msiexec.exe"; Arguments = "/x $($m.Groups[1].Value) /qn /norestart" }
    }
    $base = Split-UninstallCommand -Command $raw
    if (-not $base) { return $null }
    $leaf = ""
    try { $leaf = [System.IO.Path]::GetFileName($base.File).ToLower() } catch { $leaf = "" }
    if ($leaf -eq "unins000.exe" -or $leaf -like "unins???.exe") {
        $base.Arguments = ($base.Arguments + " /VERYSILENT /SUPPRESSMSGBOXES /NORESTART").Trim()
        return $base
    }
    if ($leaf -eq "uninstall.exe" -or $leaf -eq "uninstall*.exe" -or $leaf -eq "helper.exe") {
        if ($base.Arguments -notmatch '(?i)(^|\s)/S(\s|$)') { $base.Arguments = ($base.Arguments + " /S").Trim() }
        return $base
    }
    return $null
}

function Get-InstalledApps {
    $apps = @()
    $roots = @(
        @{ Hive = [Microsoft.Win32.Registry]::LocalMachine; Label = "HKLM"; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' },
        @{ Hive = [Microsoft.Win32.Registry]::LocalMachine; Label = "HKLM"; Path = 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' },
        @{ Hive = [Microsoft.Win32.Registry]::CurrentUser;  Label = "HKCU"; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' }
    )
    foreach ($r in $roots) {
        $base = $null
        try { $base = $r.Hive.OpenSubKey($r.Path) } catch { continue }
        if ($null -eq $base) { continue }
        try {
            foreach ($sub in $base.GetSubKeyNames()) {
                $k = $null
                try { $k = $base.OpenSubKey($sub) } catch { continue }
                if ($null -eq $k) { continue }
                try {
                    $name = [string]$k.GetValue("DisplayName")
                    if ([string]::IsNullOrWhiteSpace($name)) { continue }
                    try { if ([int]$k.GetValue("SystemComponent", 0) -eq 1) { continue } } catch {}
                    $parent = [string]$k.GetValue("ParentKeyName")
                    if (-not [string]::IsNullOrWhiteSpace($parent)) { continue }
                    $rel = [string]$k.GetValue("ReleaseType")
                    if ($rel -match '(?i)hotfix|security update|update rollup') { continue }
                    $uninst  = [string]$k.GetValue("UninstallString")
                    $uninstQ = [string]$k.GetValue("QuietUninstallString")
                    if ([string]::IsNullOrWhiteSpace($uninst) -and [string]::IsNullOrWhiteSpace($uninstQ)) { continue }
                    $sizeMB = $null
                    try {
                        $kb = $k.GetValue("EstimatedSize")
                        if ($kb -is [int] -and $kb -gt 0) { $sizeMB = [math]::Round($kb / 1024, 1) }
                    } catch {}
                    $apps += @{
                        Source               = "Win32"
                        Name                 = $name.Trim()
                        Version              = [string]$k.GetValue("DisplayVersion")
                        Publisher            = [string]$k.GetValue("Publisher")
                        SizeMB               = $sizeMB
                        UninstallString      = $uninst
                        QuietUninstallString = $uninstQ
                        InstallLocation      = [string]$k.GetValue("InstallLocation")
                        DisplayIcon          = [string]$k.GetValue("DisplayIcon")
                        KeyPath              = "$($r.Label):\$($r.Path)\$sub"
                    }
                } catch {} finally { try { $k.Dispose() } catch {} }
            }
        } catch {} finally { try { $base.Dispose() } catch {} }
    }
    try {
        foreach ($p in (Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { -not $_.IsFramework })) {
            if ([string]::IsNullOrWhiteSpace($p.Name)) { continue }
            $apps += @{
                Source               = "Store"
                Name                 = $p.Name
                Version              = [string]$p.Version
                Publisher            = ""
                SizeMB               = $null
                UninstallString      = ""
                QuietUninstallString = ""
                InstallLocation      = [string]$p.InstallLocation
                DisplayIcon          = ""
                KeyPath              = ""
                PackageFullName      = $p.PackageFullName
            }
        }
    } catch {}
    $seen = @{}
    $dedup = @()
    foreach ($a in ($apps | Sort-Object { $_.Source -ne "Win32" }, Name)) {
        $key = "$($a.Name)|$($a.Version)|$($a.Publisher)"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $a.Quiet = (Get-QuietUninstallCommand -App $a) -ne $null
        $a.Icon = Get-UninstallAppIcon -FilePath (Resolve-UninstallIconPath -App $a)
        $dedup += $a
    }
    return $dedup
}

function Get-UninstallAppIcon {
    # Из exe/dll (как в автозагрузке) или из PNG-логотипа Store-пакета.
    param([string]$FilePath)
    if ([string]::IsNullOrWhiteSpace($FilePath)) { return $null }
    try { $FilePath = [System.Environment]::ExpandEnvironmentVariables($FilePath.Trim().Trim('"')) } catch {}
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { return $null }
    try {
        $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
        if ($ext -eq ".png") {
            $img = [System.Windows.Media.Imaging.BitmapImage]::new()
            $img.BeginInit()
            $img.UriSource = [System.Uri]::new($FilePath)
            $img.DecodePixelWidth = 32
            $img.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $img.EndInit()
            $img.Freeze()
            return $img
        }
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($FilePath)
        if ($icon) {
            $bmp = $icon.ToBitmap()
            $ms  = [System.IO.MemoryStream]::new()
            $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            $ms.Position = 0
            $img = [System.Windows.Media.Imaging.BitmapImage]::new()
            $img.BeginInit()
            $img.StreamSource = $ms
            $img.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $img.EndInit()
            $img.Freeze()
            $icon.Dispose(); $bmp.Dispose(); $ms.Dispose()
            return $img
        }
    } catch {}
    return $null
}

function Resolve-UninstallIconPath {
    param($App)
    if ($App.Source -eq "Store") {
        try {
            $manifest = Join-Path $App.InstallLocation "AppxManifest.xml"
            if (Test-Path -LiteralPath $manifest -PathType Leaf) {
                [xml]$mx = [System.IO.File]::ReadAllText($manifest)
                $logo = $mx.Package.Properties.Logo
                if (-not [string]::IsNullOrWhiteSpace($logo)) {
                    $full = Join-Path $App.InstallLocation $logo
                    if (Test-Path -LiteralPath $full -PathType Leaf) { return $full }
                    $dir = Split-Path $full -Parent
                    $base = [System.IO.Path]::GetFileNameWithoutExtension($full)
                    $cand = Get-ChildItem -LiteralPath $dir -Filter ($base + "*.png") -ErrorAction SilentlyContinue |
                            Sort-Object Name | Select-Object -First 1
                    if ($cand) { return $cand.FullName }
                }
            }
        } catch {}
        return $null
    }
    foreach ($raw in @($App.DisplayIcon, $App.UninstallString)) {
        try {
            if ([string]::IsNullOrWhiteSpace($raw)) { continue }
            $s = [System.Environment]::ExpandEnvironmentVariables($raw.Trim())
            $s = ($s -split ',')[0].Trim().Trim('"')
            if ($s -match '(?i)msiexec') { continue }
            if ($s.ToLower().EndsWith('.exe') -or $s.ToLower().EndsWith('.dll')) {
                if (Test-Path -LiteralPath $s -PathType Leaf) { return $s }
            }
        } catch {}
    }
    if (-not [string]::IsNullOrWhiteSpace($App.InstallLocation)) {
        try {
            $loc = [System.Environment]::ExpandEnvironmentVariables($App.InstallLocation.Trim().Trim('"'))
            if ((Test-Path -LiteralPath $loc -PathType Leaf) -and
                ($loc.ToLower().EndsWith('.exe') -or $loc.ToLower().EndsWith('.dll'))) { return $loc }
        } catch {}
    }
    return $null
}

function Test-SafeLeftoverPath {    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try { $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/') } catch { return $false }
    $lower = $full.ToLower()
    $windir = $env:WINDIR.ToLower()
    $sysdrive = [System.IO.Path]::GetPathRoot($full).TrimEnd('\', '/').ToLower()
    if ($full.Length -le 3) { return $false }
    if ($lower -eq $windir -or $lower -eq "$windir\system32" -or $lower -eq $sysdrive) { return $false }
    if ($lower -eq ${env:ProgramFiles}.ToLower() -or $lower -eq ${env:ProgramFiles(x86)}.ToLower()) { return $false }
    if ($lower -eq $env:APPDATA.ToLower() -or $lower -eq $env:LOCALAPPDATA.ToLower()) { return $false }
    return (Test-Path -LiteralPath $full)
}

function Find-AppLeftovers {
    param($App)
    $found = @()
    if (-not [string]::IsNullOrWhiteSpace($App.InstallLocation) -and (Test-SafeLeftoverPath -Path $App.InstallLocation)) {
        $found += @{ Kind = "dir"; Path = $App.InstallLocation; Note = "Папка установки" }
    }
    $base = [string]$App.Name
    foreach ($root in @($env:LOCALAPPDATA, $env:APPDATA)) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        foreach ($cand in @($base, ($base -replace '[\\/:*?"<>|]', '').Trim())) {
            if ([string]::IsNullOrWhiteSpace($cand)) { continue }
            $p = Join-Path $root $cand
            if ((Test-SafeLeftoverPath -Path $p) -and -not ($found | Where-Object { $_.Path -eq $p })) {
                $found += @{ Kind = "dir"; Path = $p; Note = "Данные приложения" }
            }
        }
    }
    return $found
}

function Trace-U {
    param([string]$m)
    try {
        $t = (Get-Date).ToString('HH:mm:ss') + ' U ' + $m + "`r`n"
        [System.IO.File]::AppendAllText((Join-Path $env:TEMP 'PotatoPC\trace.txt'), $t)
    } catch {}
}

function Update-UninstallCounts {
    $sel = @($script:UninstallCheckboxes.Values | Where-Object { $_.IsChecked }).Count
    if ($uninstallSelectedText) { $uninstallSelectedText.Text = if ($sel -eq 0) { "" } else { "Выбрано: $sel" } }
}

function Apply-UninstallFilter {
    $q = ""
    try { $q = $uninstallSearchBox.Text.Trim().ToLower() } catch {}
    foreach ($child in $uninstallAppsPanel.Children) {
        if ($child -isnot [System.Windows.Controls.Border]) { continue }
        $tag = $child.Tag
        if ($null -eq $tag -or -not $tag.Name) { $child.Visibility = "Visible"; continue }
        $typeOk = switch ($script:UninstallFilter) {
            "Win32" { $tag.Type -eq "Win32" }
            "Store" { $tag.Type -eq "Store" }
            default { $true }
        }
        $searchOk = $q -eq "" -or
                    "$($tag.Name)".ToLower()      -like "*$q*" -or
                    "$($tag.Publisher)".ToLower() -like "*$q*"
        $child.Visibility = if ($typeOk -and $searchOk) { "Visible" } else { "Collapsed" }
    }
}

function New-UninstallBadge {
    param([string]$Text, [string]$Bg, [string]$Border, [string]$Fg)
    $b = [System.Windows.Controls.Border]::new()
    $b.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $b.Padding = [System.Windows.Thickness]::new(6,2,6,2)
    $b.VerticalAlignment = "Center"; $b.HorizontalAlignment = "Center"
    $b.Background = [Windows.Media.BrushConverter]::new().ConvertFrom($Bg)
    $b.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom($Border)
    $b.BorderThickness = [System.Windows.Thickness]::new(1)
    $t = [System.Windows.Controls.TextBlock]::new()
    $t.Text = $Text; $t.FontSize = 10; $t.FontWeight = "SemiBold"
    $t.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom($Fg)
    $b.Child = $t
    return $b
}

function Render-UninstallPanel {
    param($Apps)
    $uninstallAppsPanel.Children.Clear()
    $script:UninstallCheckboxes.Clear()
    $w32 = @($Apps | Where-Object { $_.Source -eq "Win32" }).Count
    $st  = @($Apps | Where-Object { $_.Source -eq "Store" }).Count
    $uninstallCountText.Text = "Программ: $w32  •  Store: $st  •  Всего: $($Apps.Count)"
    if ($Apps.Count -eq 0) {
        $lbl = [System.Windows.Controls.TextBlock]::new()
        $lbl.Text = "Установленные программы не найдены"
        $lbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#c4c4ee")
        $lbl.FontSize = 12; $lbl.Margin = [System.Windows.Thickness]::new(4,8,0,0)
        $uninstallAppsPanel.Children.Add($lbl) | Out-Null
        return
    }
    foreach ($app in ($Apps | Sort-Object Name)) {
        $card = New-Card
        $card.Tag = [PSCustomObject]@{
            Type      = $app.Source
            Name      = $app.Name
            Publisher = if ($app.Publisher) { $app.Publisher } else { "" }
        }
        $g = [System.Windows.Controls.Grid]::new()
        foreach ($w in @(24, 28, 0, 110, 90)) {
            $dc = [System.Windows.Controls.ColumnDefinition]::new()
            if ($w -eq 0) { $dc.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
            else          { $dc.Width = [System.Windows.GridLength]::new($w) }
            $g.ColumnDefinitions.Add($dc)
        }
        $cb = [System.Windows.Controls.CheckBox]::new()
        $cb.VerticalAlignment = "Center"
        $cb.Tag = $app
        $cb.Add_Checked({   Update-UninstallCounts })
        $cb.Add_Unchecked({ Update-UninstallCounts })
        [System.Windows.Controls.Grid]::SetColumn($cb, 0)
        $script:UninstallCheckboxes["$($app.Source)|$($app.Name)"] = $cb
        $ico = [System.Windows.Controls.Image]::new()
        $ico.Width = 18; $ico.Height = 18; $ico.VerticalAlignment = "Center"
        $ico.Margin = [System.Windows.Thickness]::new(0,0,6,0)
        if ($app.Icon) { $ico.Source = $app.Icon }
        [System.Windows.Controls.Grid]::SetColumn($ico, 1)
        $stk = [System.Windows.Controls.StackPanel]::new()
        $stk.VerticalAlignment = "Center"; $stk.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
        $nm = [System.Windows.Controls.TextBlock]::new()
        $nm.Text = $app.Name; $nm.FontSize = 12; $nm.FontWeight = "SemiBold"
        $nm.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#e8e8ff")
        $nm.TextTrimming = "CharacterEllipsis"
        $sub = [System.Windows.Controls.TextBlock]::new()
        $parts = @()
        if (-not [string]::IsNullOrWhiteSpace($app.Publisher)) { $parts += $app.Publisher }
        if (-not [string]::IsNullOrWhiteSpace($app.Version))   { $parts += "v$($app.Version)" }
        if ($null -ne $app.SizeMB)                             { $parts += "$($app.SizeMB) МБ" }
        $sub.Text = ($parts -join "  •  ")
        $sub.FontSize = 10; $sub.TextTrimming = "CharacterEllipsis"
        $sub.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#9898b8")
        $stk.Children.Add($nm) | Out-Null
        if ($sub.Text) { $stk.Children.Add($sub) | Out-Null }
        [System.Windows.Controls.Grid]::SetColumn($stk, 2)
        if ($app.Source -eq "Store") {
            $srcB = New-UninstallBadge -Text "🏪 Store" -Bg "#0a1a2e" -Border "#1a5aaa" -Fg "#4a9eff"
        } else {
            $srcB = New-UninstallBadge -Text "📦 Win32" -Bg "#1a1a3a" -Border "#3a3a6a" -Fg "#a8a8d0"
        }
        [System.Windows.Controls.Grid]::SetColumn($srcB, 3)
        if ($app.Quiet) {
            $qB = New-UninstallBadge -Text "🤫 тихо" -Bg "#0d2d1a" -Border "#1a6b35" -Fg "#2ecc71"
        } else {
            $qB = New-UninstallBadge -Text "🔧 вручную" -Bg "#14142a" -Border "#2a2a50" -Fg "#808090"
        }
        [System.Windows.Controls.Grid]::SetColumn($qB, 4)
        $g.Children.Add($cb) | Out-Null; $g.Children.Add($ico) | Out-Null
        $g.Children.Add($stk) | Out-Null
        $g.Children.Add($srcB) | Out-Null; $g.Children.Add($qB) | Out-Null
        $card.Child = $g
        Add-CardFx -Card $card
        $card.Add_MouseEnter({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#20203a") })
        $card.Add_MouseLeave({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e") })
        $uninstallAppsPanel.Children.Add($card) | Out-Null
    }
    Write-Log "Удаление: найдено $($Apps.Count) (Win32: $w32, Store: $st)"
    Apply-UninstallFilter
    Update-UninstallCounts
}

function Build-UninstallPanel {
    Trace-U 'sync start'
    $uninstallAppsPanel.Children.Clear()
    $script:UninstallCheckboxes.Clear()
    $uninstallCountText.Text = "Сканирование..."
    $script:UninstallPanelGen++
    $gen = $script:UninstallPanelGen
    Start-Background {
        Trace-U 'task start'
        try {
            $data = Get-InstalledApps
            Trace-U ('scanned count=' + @($data).Count)
            Set-BgResult -Key 'uninstall' -Value @{ Gen = $gen; Data = @($data) }
            Trace-U 'stashed'
        } catch {
            Trace-U ('CATCH ' + $_.Exception.Message)
            Write-Log "Ошибка сканирования программ: $_" -Color "Red"
        }
    } -Variables @{ gen = $gen }
}

function Uninstall-SelectedNative {
    $sel = @($script:UninstallCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked })
    if ($sel.Count -eq 0) { Write-Log "⚠ Нет выбранных программ" -Color "Yellow"; return }
    $quiet = $quietUninstallChk.IsChecked -eq $true
    $clean = $cleanLeftoversChk.IsChecked -eq $true
    $noisy = @($sel | Where-Object { -not $_.Value.Tag.Quiet })
    $msg = "Удалить $($sel.Count) программ своим методом?"
    if ($quiet -and $noisy.Count -gt 0) {
        $msg += "`n`nБез тихого режима ($($noisy.Count)): `n- " + (($noisy | ForEach-Object { $_.Value.Tag.Name } | Select-Object -First 5) -join "`n- ")
        if ($noisy.Count -gt 5) { $msg += "`n- ... и ещё $($noisy.Count - 5)" }
        $msg += "`nИх деинсталлятор откроется с вопросами."
    }
    if ($clean) { $msg += "`n`nОстатки: папка установки + данные в AppData + остаток ключа реестра (только явные совпадения)." }
    $confirm = [System.Windows.MessageBox]::Show($msg, "Удаление программ",
        [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($confirm -ne "Yes") { Write-Log "Удаление отменено." -Color "Yellow"; return }
    $jobs = @()
    foreach ($kv in $sel) {
        $app = $kv.Value.Tag
        $cmd = $null
        if ($quiet) { $cmd = Get-QuietUninstallCommand -App $app }
        if ($null -eq $cmd -and $app.Source -eq "Win32") {
            $cmd = Split-UninstallCommand -Command $app.UninstallString
        }
        $leftovers = @()
        if ($clean) { $leftovers = @(Find-AppLeftovers -App $app) }
        $jobs += @{
            Name          = $app.Name
            Source        = $app.Source
            PackageFullName = if ($app.PackageFullName) { $app.PackageFullName } else { "" }
            File          = if ($cmd -and $cmd.File) { $cmd.File } else { "" }
            Arguments     = if ($cmd -and $cmd.Arguments) { $cmd.Arguments } else { "" }
            KeyPath       = $app.KeyPath
            Leftovers     = @($leftovers | ForEach-Object { $_.Path })
        }
    }
    Write-Log "══ Удаление $($jobs.Count) программ ══"
    Invoke-Async -ScriptBlock {
        $ok = 0; $fail = 0; $junk = 0
        foreach ($j in $jobs) {
            Write-Log "🗑 $($j.Name)..."
            $removed = $false
            try {
                if ($j.Source -eq "Store") {
                    Remove-AppxPackage -Package $j.PackageFullName -ErrorAction Stop
                    Write-Log "   ✓ Пакет удалён" -Color "Green"; $removed = $true
                } else {
                    if ([string]::IsNullOrWhiteSpace($j.File)) { throw "Нет команды удаления" }
                    $p = Start-Process -FilePath $j.File -ArgumentList $j.Arguments -Wait -PassThru -ErrorAction Stop
                    if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
                        Write-Log "   ✓ Деинсталлятор завершён (код $($p.ExitCode))" -Color "Green"; $removed = $true
                    } else {
                        Write-Log "   ⚠ Код выхода $($p.ExitCode), проверяю остатки" -Color "Yellow"; $removed = $true
                    }
                }
            } catch { Write-Log "   ✗ Ошибка: $_" -Color "Red"; $fail++ }
            if ($removed) {
                $ok++
                if ($cleanLeftovers) {
                    foreach ($lp in $j.Leftovers) {
                        try {
                            if (Test-Path -LiteralPath $lp) {
                                Remove-Item -LiteralPath $lp -Recurse -Force -ErrorAction Stop
                                Write-Log "   🧹 Остаток удалён: $lp" -Color "Green"; $junk++
                            }
                        } catch { Write-Log "   ⚠ Остаток не удалён ($lp): $_" -Color "Yellow" }
                    }
                    try {
                        if (-not [string]::IsNullOrWhiteSpace($j.KeyPath) -and (Test-Path -LiteralPath $j.KeyPath)) {
                            Remove-Item -LiteralPath $j.KeyPath -Recurse -Force -ErrorAction Stop
                            Write-Log "   🧹 Остаток ключа реестра удалён" -Color "Green"; $junk++
                        }
                    } catch { Write-Log "   ⚠ Ключ реестра не удалён: $_" -Color "Yellow" }
                }
            }
        }
        Write-Log "══ Готово: удалено ✓$ok, ошибок ✗$fail$(if($cleanLeftovers){" , остатков 🧹$junk"}) ══" -Color "Green"
        Set-BgResult -Key 'rebuildUninstall' -Value $true
    } -Variables @{ jobs = $jobs; cleanLeftovers = $clean }
}

function Get-BcuConsolePath {
    $exe = Join-Path (Get-BcuToolsDir) "BCU-console.exe"
    if (Test-Path -LiteralPath $exe) { return $exe }
    try {
        $found = Get-ChildItem -Path (Get-BcuToolsDir) -Filter "BCU-console.exe" -Recurse -ErrorAction SilentlyContinue |
                 Select-Object -First 1
        if ($found) { return $found.FullName }
    } catch {}
    return $null
}

function Test-BcuRuntime {
    try {
        $r = Get-ChildItem -Path "$env:ProgramFiles\dotnet\shared\Microsoft.WindowsDesktop.App" -Directory -ErrorAction Stop |
             Where-Object { $_.Name -like "8.*" } | Select-Object -First 1
        return ($null -ne $r)
    } catch { return $false }
}

function New-BcuListFile {
    param([string[]]$AppNames)
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("potatopc_bcu_{0}.bcul" -f ([guid]::NewGuid().ToString("N")))
    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.Indent = $true
    $settings.Encoding = [System.Text.Encoding]::Unicode
    $w = [System.Xml.XmlWriter]::Create($tmp, $settings)
    try {
        $w.WriteStartDocument()
        $w.WriteStartElement("UninstallList")
        $w.WriteElementString("Enabled", "true")
        $w.WriteStartElement("Filters")
        foreach ($n in $AppNames) {
            $w.WriteStartElement("Filter")
            $w.WriteElementString("Name", $n)
            $w.WriteElementString("Exclude", "false")
            $w.WriteElementString("Enabled", "true")
            $w.WriteStartElement("ComparisonEntries")
            $w.WriteStartElement("FilterCondition")
            $w.WriteElementString("InvertResults", "false")
            $w.WriteElementString("ComparisonMethod", "Equals")
            $w.WriteElementString("FilterText", $n)
            $w.WriteElementString("TargetPropertyId", "DisplayName")
            $w.WriteElementString("Enabled", "true")
            $w.WriteEndElement()
            $w.WriteEndElement()
            $w.WriteEndElement()
        }
        $w.WriteEndElement()
        $w.WriteEndElement()
        $w.WriteEndDocument()
    } finally { $w.Dispose() }
    return $tmp
}

function Uninstall-SelectedViaBcu {
    $sel = @($script:UninstallCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked })
    if ($sel.Count -eq 0) { Write-Log "⚠ Нет выбранных программ" -Color "Yellow"; return }
    $names = @($sel | ForEach-Object { [string]$_.Value.Tag.Name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $confirm = [System.Windows.MessageBox]::Show(
        "Удалить $($names.Count) программ через BCU-console?`n`nТихо (/Q), без запросов (/U), с чисткой остатков уровня VeryGood.`nПодтверждение уже показано — дальше всё без остановок.",
        "BCU — пакетное удаление",
        [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($confirm -ne "Yes") { Write-Log "BCU-удаление отменено." -Color "Yellow"; return }
    $asset = $script:BcuNetAsset
    if ((-not (Get-BcuConsolePath)) -and (-not (Test-BcuRuntime))) {
        $choice = [System.Windows.MessageBox]::Show(
            "Для компактной версии BCU нужен .NET 8 Desktop Runtime, он не найден.`n`nДа — скачать portable-версию BCU (~76 МБ, рантайм внутри).`nНет — отмена.",
            "BCU — нет .NET 8",
            [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($choice -ne "Yes") { Write-Log "BCU-удаление отменено (нет .NET 8)." -Color "Yellow"; return }
        $asset = $script:BcuPortableAsset
    }
    $bcul = New-BcuListFile -AppNames $names
    Write-Log "══ BCU: удаление $($names.Count) программ ══"
    Invoke-Async -ScriptBlock {
        try {
            $console = $bcuConsole
            if ([string]::IsNullOrWhiteSpace($console) -or -not (Test-Path -LiteralPath $console)) {
                Write-Log "Загрузка BCU $($bcuVer) ($bcuAsset)..."
                $toolsDir = $bcuToolsDir
                if (-not (Test-Path -LiteralPath $toolsDir)) {
                    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
                }
                $zip = Join-Path ([System.IO.Path]::GetTempPath()) "potatopc_bcu.zip"
                try {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    Invoke-WebRequest -Uri "https://github.com/BCUninstaller/Bulk-Crap-Uninstaller/releases/download/v$bcuVer/$bcuAsset" `
                        -OutFile $zip -UseBasicParsing -ErrorAction Stop
                    Expand-Archive -Path $zip -DestinationPath $toolsDir -Force -ErrorAction Stop
                } finally { Remove-Item $zip -Force -ErrorAction SilentlyContinue }
                $found = Get-ChildItem -Path $toolsDir -Filter "BCU-console.exe" -Recurse -ErrorAction SilentlyContinue |
                         Select-Object -First 1
                if (-not $found) { throw "BCU-console.exe не найден в архиве" }
                $console = $found.FullName
                Write-Log "BCU готов: $console"
            }
            Write-Log "Запуск: BCU-console uninstall ... /Q /U /J=VeryGood"
            $out = & $console uninstall $bcuFile /Q /U /J=VeryGood 2>&1 | Out-String
            foreach ($line in ($out -split "`r?`n")) {
                if (-not [string]::IsNullOrWhiteSpace($line)) { Write-Log "   $line" }
            }
            Write-Log "══ BCU завершил работу ══" -Color "Green"
        } catch {
            Write-Log "✗ BCU-удаление: $_" -Color "Red"
        } finally {
            try { if (Test-Path -LiteralPath $bcuFile) { Remove-Item -LiteralPath $bcuFile -Force } } catch {}
        }
        Set-BgResult -Key 'rebuildUninstall' -Value $true
    } -Variables @{
        bcuConsole  = (Get-BcuConsolePath)
        bcuToolsDir = (Get-BcuToolsDir)
        bcuVer      = $script:BcuVersion
        bcuAsset    = $asset
        bcuFile     = $bcul
    }
}
