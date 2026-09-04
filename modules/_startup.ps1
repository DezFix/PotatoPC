$script:StartupCheckboxes = @{}
$script:TaskCheckboxes    = @{}
$script:StartupFilter     = "All"
$script:StartupPanelGen   = 0

function Trace-S {
    param([string]$m)
    try {
        $t = (Get-Date).ToString('HH:mm:ss') + ' S ' + $m + "`r`n"
        [System.IO.File]::AppendAllText((Join-Path $env:TEMP 'PotatoPC\trace.txt'), $t)
    } catch {}
}

function Resolve-CommandPath {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return $null }
    $cmd = $Command.Trim()
    if ($cmd.StartsWith('"')) {
        $end = $cmd.IndexOf('"', 1)
        $path = if ($end -gt 0) { $cmd.Substring(1, $end - 1) } else { $cmd.Trim('"') }
    } else {
        $path = $cmd.Split(' ')[0]
    }
    $path = [System.Environment]::ExpandEnvironmentVariables($path.Trim('"', ' '))
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    $exeIdx = $path.LastIndexOf('.exe', [System.StringComparison]::OrdinalIgnoreCase)
    if ($exeIdx -gt 0) { $path = $path.Substring(0, $exeIdx + 4) }
    if (-not [System.IO.File]::Exists($path) -and -not $path.Contains('\') -and -not $path.Contains('/')) {
        foreach ($dir in ($env:PATH -split [System.IO.Path]::PathSeparator)) {
            if ([string]::IsNullOrWhiteSpace($dir)) { continue }
            $full = [System.IO.Path]::Combine($dir, $path)
            if ([System.IO.File]::Exists($full)) { $path = $full; break }
        }
    }
    if ([System.IO.File]::Exists($path)) { return $path }
    return $null
}

function Get-StartupApprovedStatus {
    param($ApprovedKey, [string]$ValueName)
    if ($null -eq $ApprovedKey) { return $true }
    try {
        $data = $ApprovedKey.GetValue($ValueName)
        if ($data -is [byte[]] -and $data.Length -ge 4) {
            return ($data[0] -ne 0x03 -and $data[0] -ne 0x07)
        }
    } catch {}
    return $true
}

function Get-AppPublisher {
    param([string]$Command)
    $path = Resolve-CommandPath -Command $Command
    if ($path) {
        try {
            $fvi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path)
            $pub = if (-not [string]::IsNullOrWhiteSpace($fvi.CompanyName)) { $fvi.CompanyName }
                   elseif (-not [string]::IsNullOrWhiteSpace($fvi.FileDescription)) { $fvi.FileDescription }
                   else { $null }
            return @{ Publisher=$pub; FilePath=$path }
        } catch {}
    }
    return @{ Publisher=$null; FilePath=$null }
}

function Get-AppIcon {
    param([string]$Command)
    $path = Resolve-CommandPath -Command $Command
    if ($path) {
        try {
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
            $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
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
    }
    return $null
}

function Scan-RegistryStartup {
    param($RootKey, [string]$SubKeyPath, [string]$ApprovedSubKeyPath, [string]$LocationLabel)
    $result = @()
    $key = $null; $approvedKey = $null
    try {
        $key = $RootKey.OpenSubKey($SubKeyPath)
        if ($null -eq $key) { return $result }
        $approvedKey = $RootKey.OpenSubKey($ApprovedSubKeyPath)
        foreach ($name in $key.GetValueNames()) {
            $rawVal  = $key.GetValue($name)
            $cmd     = if ($null -ne $rawVal) { $rawVal.ToString() } else { '' }
            $enabled = Get-StartupApprovedStatus -ApprovedKey $approvedKey -ValueName $name
            $result += @{
                Name        = $name
                Command     = $cmd
                Location    = $LocationLabel
                PathOrKey   = "$($RootKey.Name)\$SubKeyPath"
                IsEnabled   = $enabled
                Publisher   = $null
                Icon        = $null
            }
        }
    } catch {} finally {
        try { if ($key) { $key.Dispose() } } catch {}
        try { if ($approvedKey) { $approvedKey.Dispose() } } catch {}
    }
    return $result
}

function Scan-FolderStartup {
    param([string]$DirPath, [string]$LocationLabel, $RootKeyForApproved)
    $result = @()
    if ([string]::IsNullOrWhiteSpace($DirPath) -or -not (Test-Path $DirPath)) { return $result }
    $approvedKey = $null
    try {
        $approvedPath = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApprovedStartupFolder'
        $approvedKey  = $RootKeyForApproved.OpenSubKey($approvedPath)
        foreach ($file in [System.IO.Directory]::GetFiles($DirPath)) {
            $fileName = [System.IO.Path]::GetFileName($file)
            if ($fileName -eq 'desktop.ini') { continue }
            $enabled = Get-StartupApprovedStatus -ApprovedKey $approvedKey -ValueName $fileName
            $displayName = $fileName -replace '\.disabled$', ''
            $name = [System.IO.Path]::GetFileNameWithoutExtension($displayName)
            if ([string]::IsNullOrWhiteSpace($name)) { $name = $displayName }
            $result += @{
                Name      = $name
                Command   = $file
                Location  = $LocationLabel
                PathOrKey = $DirPath
                IsEnabled = $enabled
                Publisher = 'Folder Shortcut'
                Icon      = $null
            }
        }
    } catch {} finally {
        try { if ($approvedKey) { $approvedKey.Dispose() } } catch {}
    }
    return $result
}

function Update-StartupSelectedCount {
    $apps  = @($script:StartupCheckboxes.Values | Where-Object { $_.IsChecked }).Count
    $tasks = @($script:TaskCheckboxes.Values    | Where-Object { $_.IsChecked }).Count
    $total = $apps + $tasks
    if ($startupSelectedText) { $startupSelectedText.Text = if ($total -eq 0) { "" } else { "Выбрано: $total" } }
}

function Apply-StartupFilter {
    $q = $startupSearchBox.Text.Trim().ToLower()
    foreach ($child in $startupAppsPanel.Children) {
        if ($child -isnot [System.Windows.Controls.Border]) { continue }
        $tag = $child.Tag
        if ($null -eq $tag -or -not $tag.Name) { $child.Visibility = "Visible"; continue }
        $typeOk = switch ($script:StartupFilter) {
            "Apps"  { $tag.Type -eq "App" }
            "Tasks" { $tag.Type -eq "Task" }
            default { $true }
        }
        $searchOk = $q -eq "" -or
                    "$($tag.Name)".ToLower()       -like "*$q*" -or
                    "$($tag.Publisher)".ToLower()  -like "*$q*"
        $child.Visibility = if ($typeOk -and $searchOk) { "Visible" } else { "Collapsed" }
    }
}

function Get-StartupData {
    $startupItems = @()
    $approvedRun     = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApprovedRun'
    $approvedRunOnce = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApprovedRunOnce'

    $startupItems += Scan-RegistryStartup `
        -RootKey ([Microsoft.Win32.Registry]::CurrentUser) `
        -SubKeyPath 'Software\Microsoft\Windows\CurrentVersion\Run' `
        -ApprovedSubKeyPath $approvedRun -LocationLabel 'HKCU\Run'

    $startupItems += Scan-RegistryStartup `
        -RootKey ([Microsoft.Win32.Registry]::LocalMachine) `
        -SubKeyPath 'Software\Microsoft\Windows\CurrentVersion\Run' `
        -ApprovedSubKeyPath $approvedRun -LocationLabel 'HKLM\Run'

    $startupItems += Scan-RegistryStartup `
        -RootKey ([Microsoft.Win32.Registry]::LocalMachine) `
        -SubKeyPath 'Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' `
        -ApprovedSubKeyPath $approvedRun -LocationLabel 'HKLM\Run (x86)'

    $startupItems += Scan-RegistryStartup `
        -RootKey ([Microsoft.Win32.Registry]::CurrentUser) `
        -SubKeyPath 'Software\Microsoft\Windows\CurrentVersion\RunOnce' `
        -ApprovedSubKeyPath $approvedRunOnce -LocationLabel 'HKCU\RunOnce'

    $startupItems += Scan-RegistryStartup `
        -RootKey ([Microsoft.Win32.Registry]::LocalMachine) `
        -SubKeyPath 'Software\Microsoft\Windows\CurrentVersion\RunOnce' `
        -ApprovedSubKeyPath $approvedRunOnce -LocationLabel 'HKLM\RunOnce'

    $userStartup   = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Startup)
    $commonStartup = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonStartup)

    $startupItems += Scan-FolderStartup `
        -DirPath $userStartup -LocationLabel 'Папка (пользователь)' `
        -RootKeyForApproved ([Microsoft.Win32.Registry]::CurrentUser)
    $startupItems += Scan-FolderStartup `
        -DirPath $commonStartup -LocationLabel 'Папка (все польз.)' `
        -RootKeyForApproved ([Microsoft.Win32.Registry]::LocalMachine)

    foreach ($item in $startupItems) {
        if ($null -eq $item.Publisher) {
            $info = Get-AppPublisher -Command $item.Command
            $item.Publisher = if (-not [string]::IsNullOrWhiteSpace($info.Publisher)) { $info.Publisher } else { $item.Location }
        }
        $item.Icon = Get-AppIcon -Command $item.Command
    }

    $scheduledTasks = @()
    try {
        $scheduledTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskPath -notmatch "\\Microsoft\\" } |
            Sort-Object TaskName | Select-Object -First 60)
    } catch {}

    return @{ Items=$startupItems; Tasks=$scheduledTasks }
}

function Render-StartupPanel {
    param($Data)
    $startupItems     = $Data.Items
    $scheduledTasks   = $Data.Tasks
    $enabledCount     = @($startupItems | Where-Object { $_.IsEnabled }).Count
    $totalCount       = $startupItems.Count + $scheduledTasks.Count
    $startupCountText.Text = "Приложений: $totalCount  •  Активных: $enabledCount  •  Задач: $($scheduledTasks.Count)"

    if ($startupItems.Count -eq 0) {
        $lbl = [System.Windows.Controls.TextBlock]::new()
        $lbl.Text = "Элементы автозагрузки не найдены"
        $lbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#c4c4ee")
        $lbl.FontSize = 12; $lbl.Margin = [System.Windows.Thickness]::new(4,8,0,0)
        $lbl.Tag = [PSCustomObject]@{ Type="App"; Name=""; Publisher="" }
        $startupAppsPanel.Children.Add($lbl) | Out-Null
    }

    $secApp = [System.Windows.Controls.Border]::new()
    $secApp.Margin = [System.Windows.Thickness]::new(0,8,0,4)
    $secApp.Padding = [System.Windows.Thickness]::new(0,0,0,6)
    $secApp.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#1e1e38")
    $secApp.BorderThickness = [System.Windows.Thickness]::new(0,0,0,1)
    $secApp.Tag = [PSCustomObject]@{ Type="App"; Name="__header__"; Publisher="" }
    $secTxt = [System.Windows.Controls.TextBlock]::new()
    $secTxt.Text = "📦 АВТОЗАГРУЗКА ПРИЛОЖЕНИЙ ($($startupItems.Count))"
    $secTxt.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#6c63ff")
    $secTxt.FontSize = 10; $secTxt.FontWeight = "SemiBold"
    $secApp.Child = $secTxt
    $startupAppsPanel.Children.Add($secApp) | Out-Null

    $sorted = $startupItems | Sort-Object { -([int]$_.IsEnabled) }, Name
    foreach ($item in $sorted) {
        $card = New-Card -Dimmed:(-not $item.IsEnabled)
        $card.Tag = [PSCustomObject]@{
            Type      = "App"
            Name      = $item.Name
            Publisher = if ($item.Publisher) { $item.Publisher } else { "" }
        }
        $g = [System.Windows.Controls.Grid]::new()
        $widths = @(24, 28, 0, 110, 80)
        foreach ($w in $widths) {
            $dc = [System.Windows.Controls.ColumnDefinition]::new()
            if ($w -eq 0) { $dc.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star) }
            else          { $dc.Width = [System.Windows.GridLength]::new($w) }
            $g.ColumnDefinitions.Add($dc)
        }
        $cb = [System.Windows.Controls.CheckBox]::new()
        $cb.VerticalAlignment = "Center"
        $cb.Tag = @{
            Type        = "App"
            Name        = $item.Name
            RegKey      = $item.PathOrKey
            Location    = $item.Location
            IsEnabled   = $item.IsEnabled
            Command     = $item.Command
        }
        $cb.Add_Checked({   Update-StartupSelectedCount })
        $cb.Add_Unchecked({ Update-StartupSelectedCount })
        [System.Windows.Controls.Grid]::SetColumn($cb, 0)
        $script:StartupCheckboxes["$($item.PathOrKey)|$($item.Name)"] = $cb
        $ico = [System.Windows.Controls.Image]::new()
        $ico.Width = 18; $ico.Height = 18; $ico.VerticalAlignment = "Center"
        $ico.Margin = [System.Windows.Thickness]::new(0,0,6,0)
        if ($item.Icon) { $ico.Source = $item.Icon }
        [System.Windows.Controls.Grid]::SetColumn($ico, 1)
        $nameStack = [System.Windows.Controls.StackPanel]::new()
        $nameStack.VerticalAlignment = "Center"
        $nameStack.Margin = [System.Windows.Thickness]::new(0,0,8,0)
        $nmColor = if ($item.IsEnabled) { "#e8e8ff" } else { "#808090" }
        $nm = [System.Windows.Controls.TextBlock]::new()
        $nm.Text = $item.Name; $nm.FontSize = 12; $nm.FontWeight = "SemiBold"
        $nm.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom($nmColor)
        $nm.TextTrimming = "CharacterEllipsis"
        $resolved = Resolve-CommandPath -Command $item.Command
        $cmdShort = if ($resolved) { [System.IO.Path]::GetFileName($resolved) } else { $item.Command }
        $pathLbl = [System.Windows.Controls.TextBlock]::new()
        $pathLbl.Text = $cmdShort; $pathLbl.FontSize = 10; $pathLbl.TextTrimming = "CharacterEllipsis"
        $pathLbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#9898b8")
        $nameStack.Children.Add($nm) | Out-Null
        $nameStack.Children.Add($pathLbl) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($nameStack, 2)
        $locB = [System.Windows.Controls.Border]::new()
        $locB.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $locB.Padding = [System.Windows.Thickness]::new(5,2,5,2)
        $locB.VerticalAlignment = "Center"
        $locB.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a3a")
        $locB.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#3a3a6a")
        $locB.BorderThickness = [System.Windows.Thickness]::new(1)
        $locT = [System.Windows.Controls.TextBlock]::new()
        $locT.Text = $item.Location; $locT.FontSize = 10
        $locT.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#a8a8d0")
        $locB.Child = $locT
        [System.Windows.Controls.Grid]::SetColumn($locB, 3)
        $stB = [System.Windows.Controls.Border]::new()
        $stB.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $stB.Padding = [System.Windows.Thickness]::new(6,2,6,2)
        $stB.VerticalAlignment = "Center"; $stB.HorizontalAlignment = "Center"
        $stB.BorderThickness = [System.Windows.Thickness]::new(1)
        $stT = [System.Windows.Controls.TextBlock]::new()
        $stT.FontSize = 10; $stT.FontWeight = "SemiBold"
        if ($item.IsEnabled) {
            $stB.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#0d2d1a")
            $stB.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a6b35")
            $stT.Text = "● вкл"
            $stT.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#2ecc71")
        } else {
            $stB.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#2d0d0d")
            $stB.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#6b1a1a")
            $stT.Text = "● выкл"
            $stT.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#e74c3c")
        }
        $stB.Child = $stT
        [System.Windows.Controls.Grid]::SetColumn($stB, 4)
        $g.Children.Add($cb) | Out-Null; $g.Children.Add($ico) | Out-Null
        $g.Children.Add($nameStack) | Out-Null
        $g.Children.Add($locB) | Out-Null; $g.Children.Add($stB) | Out-Null
        $card.Child = $g
        Add-CardFx -Card $card
        if ($item.IsEnabled) {
            $card.Add_MouseEnter({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#20203a") })
            $card.Add_MouseLeave({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e") })
        }
        $startupAppsPanel.Children.Add($card) | Out-Null
    }

    $secTask = [System.Windows.Controls.Border]::new()
    $secTask.Margin = [System.Windows.Thickness]::new(0,16,0,4)
    $secTask.Padding = [System.Windows.Thickness]::new(0,0,0,6)
    $secTask.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#1e1e38")
    $secTask.BorderThickness = [System.Windows.Thickness]::new(0,0,0,1)
    $secTask.Tag = [PSCustomObject]@{ Type="Task"; Name="__header__"; Publisher="" }
    $secTaskTxt = [System.Windows.Controls.TextBlock]::new()
    $secTaskTxt.Text = "🗓️ ЗАПЛАНИРОВАННЫЕ ЗАДАЧИ ($($scheduledTasks.Count))"
    $secTaskTxt.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#6c63ff")
    $secTaskTxt.FontSize = 10; $secTaskTxt.FontWeight = "SemiBold"
    $secTask.Child = $secTaskTxt
    $startupAppsPanel.Children.Add($secTask) | Out-Null

    if ($scheduledTasks.Count -eq 0) {
        $lbl = [System.Windows.Controls.TextBlock]::new()
        $lbl.Text = "Сторонних задач не найдено"
        $lbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#c4c4ee")
        $lbl.FontSize = 12; $lbl.Margin = [System.Windows.Thickness]::new(4,6,0,0)
        $lbl.Tag = [PSCustomObject]@{ Type="Task"; Name=""; Publisher="" }
        $startupAppsPanel.Children.Add($lbl) | Out-Null
    }

    foreach ($task in $scheduledTasks) {
        $card = New-Card
        $card.Tag = [PSCustomObject]@{
            Type      = "Task"
            Name      = $task.TaskName
            Publisher = ""
        }
        $g = [System.Windows.Controls.Grid]::new()
        $widths = @(24, 0, 90, 70)
        foreach ($w in $widths) {
            $dc = [System.Windows.Controls.ColumnDefinition]::new()
            if ($w -eq 0) { $dc.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star) }
            else          { $dc.Width = [System.Windows.GridLength]::new($w) }
            $g.ColumnDefinitions.Add($dc)
        }
        $cb = [System.Windows.Controls.CheckBox]::new(); $cb.VerticalAlignment = "Center"
        $cb.Tag = @{ Type="Task"; Name=$task.TaskName; Path=$task.TaskPath }
        $cb.Add_Checked({   Update-StartupSelectedCount })
        $cb.Add_Unchecked({ Update-StartupSelectedCount })
        [System.Windows.Controls.Grid]::SetColumn($cb, 0)
        $script:TaskCheckboxes["$($task.TaskPath)|$($task.TaskName)"] = $cb
        $stk = [System.Windows.Controls.StackPanel]::new(); $stk.VerticalAlignment = "Center"
        $stk.Margin = [System.Windows.Thickness]::new(0,0,8,0)
        $nm = [System.Windows.Controls.TextBlock]::new()
        $nm.Text = $task.TaskName; $nm.FontSize = 12; $nm.FontWeight = "Medium"
        $nm.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#d0d0f0")
        $nm.TextTrimming = "CharacterEllipsis"
        $trigClass = if ($task.Triggers.Count -gt 0) { $task.Triggers[0].CimClass.CimClassName } else { "" }
        $trigRu = switch -Wildcard ($trigClass) {
            "*Logon*" {"При входе"} "*Boot*" {"При запуске"}
            "*Daily*" {"Ежедневно"} "*Weekly*" {"Еженедельно"}
            "*Time*"  {"По расписанию"} default {"Триггер"}
        }
        $sub = [System.Windows.Controls.TextBlock]::new()
        $sub.Text = "$trigRu  •  $($task.TaskPath)"
        $sub.FontSize = 10; $sub.TextTrimming = "CharacterEllipsis"
        $sub.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#c0c0e8")
        $stk.Children.Add($nm) | Out-Null; $stk.Children.Add($sub) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($stk, 1)
        $trigB = [System.Windows.Controls.Border]::new()
        $trigB.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $trigB.Padding = [System.Windows.Thickness]::new(5,2,5,2)
        $trigB.VerticalAlignment = "Center"
        $trigB.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#14142a")
        $trigB.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#2a2a50")
        $trigB.BorderThickness = [System.Windows.Thickness]::new(1)
        $trigT = [System.Windows.Controls.TextBlock]::new()
        $trigT.Text = $trigRu; $trigT.FontSize = 9
        $trigT.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#a8a8d0")
        $trigB.Child = $trigT
        [System.Windows.Controls.Grid]::SetColumn($trigB, 2)
        $tStB = [System.Windows.Controls.Border]::new()
        $tStB.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $tStB.Padding = [System.Windows.Thickness]::new(6,2,6,2)
        $tStB.VerticalAlignment = "Center"; $tStB.HorizontalAlignment = "Center"
        $tStB.BorderThickness = [System.Windows.Thickness]::new(1)
        $tStT = [System.Windows.Controls.TextBlock]::new(); $tStT.FontSize = 10; $tStT.FontWeight = "SemiBold"
        $isTaskEnabled = ($task.State -ne "Disabled")
        if ($isTaskEnabled) {
            $tStB.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#0d2d1a")
            $tStB.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a6b35")
            $tStT.Text = "● вкл"; $tStT.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#2ecc71")
        } else {
            $tStB.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#2d0d0d")
            $tStB.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#6b1a1a")
            $tStT.Text = "● выкл"; $tStT.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#e74c3c")
        }
        $tStB.Child = $tStT
        [System.Windows.Controls.Grid]::SetColumn($tStB, 3)
        $g.Children.Add($cb) | Out-Null; $g.Children.Add($stk) | Out-Null
        $g.Children.Add($trigB) | Out-Null; $g.Children.Add($tStB) | Out-Null
        $card.Child = $g
        Add-CardFx -Card $card
        $card.Add_MouseEnter({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#20203a") })
        $card.Add_MouseLeave({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e") })
        $startupAppsPanel.Children.Add($card) | Out-Null
    }
    Write-Log "Автозагрузка: $($startupItems.Count) приложений (вкл: $enabledCount), $($scheduledTasks.Count) задач"
    Apply-StartupFilter
}

function Build-StartupPanel {
    Trace-S 'sync start'
    $startupAppsPanel.Children.Clear()
    $script:StartupCheckboxes.Clear()
    $script:TaskCheckboxes.Clear()
    $startupCountText.Text = "Загрузка..."
    $script:StartupPanelGen++
    $gen = $script:StartupPanelGen
    Start-Background {
        Trace-S 'task start'
        try {
            $data = Get-StartupData
            Trace-S ('scanned items=' + @($data.Items).Count + ' tasks=' + @($data.Tasks).Count)
            Set-BgResult -Key 'startup' -Value @{ Gen = $gen; Data = $data }
            Trace-S 'stashed'
        } catch {
            Trace-S ('CATCH ' + $_.Exception.Message)
            Write-Log "Ошибка сканирования автозагрузки: $_" -Color "Red"
        }
    } -Variables @{ gen = $gen }
}