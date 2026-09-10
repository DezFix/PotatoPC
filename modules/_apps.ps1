$script:AppCheckboxes = @{}
$script:AppBadges = @{}
$script:AppIconImgs = @{}
$script:InstalledAppIds = @{}

function Load-Apps {
    $fallback = [PSCustomObject]@{
        "Утилиты" = @(
            @{ Name="7-Zip"; Id="7zip.7zip"; Description="Бесплатный архиватор." }
            @{ Name="Notepad++"; Id="Notepad++.Notepad++"; Description="Текстовый редактор." }
        )
        "Медиа" = @(@{ Name="VLC"; Id="VideoLAN.VLC"; Description="Универсальный медиаплеер." })
    }
    if (Test-Path $script:AppsJsonPath) {
        try {
            $j = Get-Content $script:AppsJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.ManualCategories) {
                $n = @($j.ManualCategories.PSObject.Properties).Count
                Write-Log "apps.json: $n категорий"
                return $j
            }
        } catch {
            Write-Log "Ошибка apps.json, резервный список." -Color "Yellow"
        }
    }
    return [PSCustomObject]@{ ManualCategories = $fallback; Presets = @{} }
}

function Update-AppsCount {
    $sel   = @($script:AppCheckboxes.Values | Where-Object { $_.IsChecked }).Count
    $total = $script:AppCheckboxes.Count
    if ($AppCountText) { $AppCountText.Text = "Выбрано: $sel из $total" }
    try { Update-HeaderCount } catch {}
}

function Get-AppCategoryIcon {
    param([string]$Name)
    $n = [string]$Name
    if ($n -match 'Игр')                            { return 'apps/games' }
    if ($n -match 'Офис|Документ')                  { return 'apps/office' }
    if ($n -match 'Браузер|Интернет')               { return 'apps/cat_internet' }
    if ($n -match 'Медиа|Видео|Аудио|Музык|Плеер')  { return 'apps/cat_multimedia' }
    if ($n -match 'Разработ|Код|Программ')          { return 'apps/cat_dev' }
    if ($n -match 'Систем|Утилит|Архив|Файл')       { return 'apps/cat_utils' }
    if ($n -match 'Связь|Сеть|Мессендж')            { return 'devices/network' }
    return 'mimetypes/nav_apps'
}

function Get-AppFaviconImage {
    # Вызывать в фоне. Качает фавикон 64px в кэш TEMP, возвращает замороженный BitmapImage или $null.
    param([string]$Domain, [string]$CacheDir)
    try {
        if ([string]::IsNullOrWhiteSpace($Domain)) { return $null }
        if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null }
        $file = Join-Path $CacheDir ($Domain + '.png')
        if (-not (Test-Path $file)) {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri ('https://www.google.com/s2/favicons?domain=' + $Domain + '&sz=64') -OutFile $file -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        }
        $bi = New-Object System.Windows.Media.Imaging.BitmapImage
        $bi.BeginInit()
        $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bi.UriSource = (New-Object System.Uri($file, [System.UriKind]::Absolute))
        $bi.DecodePixelWidth = 48
        $bi.EndInit()
        $bi.Freeze()
        return $bi
    } catch {
        try { Remove-Item (Join-Path $CacheDir ($Domain + '.png')) -Force -ErrorAction SilentlyContinue } catch {}
        return $null
    }
}

function Get-AppFaviconDomain {
    # Самодостаточная (копия уходит в фон): winget-id -> домен для фавиконки.
    param([string]$Id)
    $map = @{
        'Brave.Brave' = 'brave.com'; 'Opera.Opera' = 'opera.com'; 'Opera.OperaGX' = 'opera.com'
        'Google.Chrome' = 'google.com'; 'Mozilla.Firefox' = 'mozilla.org'; 'LibreWolf.LibreWolf' = 'librewolf.net'
        'VideoLAN.VLC' = 'videolan.org'; 'GIMP.GIMP' = 'gimp.org'; 'IrfanSkiljan.IrfanView' = 'irfanview.com'
        'Audacity.Audacity' = 'audacityteam.org'; 'Meltytech.Shotcut' = 'shotcut.org'; 'KDE.Kdenlive' = 'kdenlive.org'
        'OBSProject.OBSStudio' = 'obsproject.com'; 'Spotify.Spotify' = 'spotify.com'
        'PeterPawlowski.foobar2000' = 'foobar2000.org'; 'HandBrake.HandBrake' = 'handbrake.fr'
        'ONLYOFFICE.DesktopEditors' = 'onlyoffice.com'; 'SoftMaker.FreeOffice' = 'softmaker.com'
        'TheDocumentFoundation.LibreOffice' = 'libreoffice.org'; 'SumatraPDF.SumatraPDF' = 'sumatrapdfreader.org'
        'Notepad++.Notepad++' = 'notepad-plus-plus.org'; 'Mozilla.Thunderbird' = 'thunderbird.net'
        'calibre.calibre' = 'calibre-ebook.com'; '7zip.7zip' = '7-zip.org'; 'M2Team.NanaZip' = 'github.com'
        'Giorgiotani.Peazip' = 'peazip.org'; 'SoftDeluxe.FreeDownloadManager' = 'freedownloadmanager.org'
        'AdrienAllard.FileConverter' = 'file-converter.org'; 'ShareX.ShareX' = 'getsharex.com'
        'WinSCP.WinSCP' = 'winscp.net'; 'qBittorrent.qBittorrent' = 'qbittorrent.org'
        'AnyDesk.AnyDesk' = 'anydesk.com'; 'Klocman.BulkCrapUninstaller' = 'github.com'
        'QL-Win.QuickLook' = 'github.com'; 'File-New-Project.EarTrumpet' = 'eartrumpet.app'
        'valinet.ExplorerPatcher' = 'github.com'; 'MarkGriffiths.NetTime' = 'timesynctool.com'
        'dynobo.NormCap' = 'normcap.org'; 'CrystalRich.LockHunter' = 'lockhunter.com'
        'Flameshot.Flameshot' = 'flameshot.org'; 'voidtools.Everything' = 'voidtools.com'
        'AntibodySoftware.WizTree' = 'antibody-software.com'; 'KeePassXCTeam.KeePassXC' = 'keepassxc.org'
        'Telegram.TelegramDesktop' = 'telegram.org'; 'Rakuten.Viber' = 'viber.com'
        'Microsoft.Teams' = 'teams.microsoft.com'; 'Zoom.Zoom' = 'zoom.us'
        'OpenWhisperSystems.Signal' = 'signal.org'; 'Microsoft.VisualStudioCode' = 'code.visualstudio.com'
        'Git.Git' = 'git-scm.com'; 'Python.Python' = 'python.org'; 'Docker.DockerDesktop' = 'docker.com'
        'GitHub.GitHubDesktop' = 'desktop.github.com'; 'Valve.Steam' = 'store.steampowered.com'
        'Discord.Discord' = 'discord.com'; 'HeroicGamesLauncher.HeroicGamesLauncher' = 'heroicgameslauncher.com'
        'GOG.Galaxy' = 'gog.com'; 'EpicGames.EpicGamesLauncher' = 'epicgames.com'
        'PrismLauncher.PrismLauncher' = 'prismlauncher.org'
    }
    if ($map.ContainsKey($Id)) { return $map[$Id] }
    return $null
}

function Build-AppsPanel {
    if ($null -eq $appsPanel) { [Console]::WriteLine('PotatoPC: этот файл — часть приложения. Запускай menu.ps1'); return }
    $appsPanel.Children.Clear()
    $script:AppCheckboxes = @{}
    $script:AppBadges = @{}
    $script:AppIconImgs = @{}


    $appsData = Load-Apps
    foreach ($category in $appsData.ManualCategories.PSObject.Properties) {
        $appsPanel.Children.Add((New-SectionHeader -Title ("{0} ({1})" -f $category.Name, @($category.Value).Count) -Icon (Get-AppCategoryIcon -Name $category.Name))) | Out-Null
        foreach ($app in $category.Value) {
            if (-not $app -or [string]::IsNullOrWhiteSpace([string]$app.Id)) { continue }
            $card=New-Card
            $stk=[System.Windows.Controls.StackPanel]::new(); $stk.VerticalAlignment="Center"
            $cb=[System.Windows.Controls.CheckBox]::new(); $cb.Content=$app.Name; $cb.Tag=$app.Id
            $cb.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#c8c8e0"); $cb.FontSize=13; $cb.FontWeight="Medium"
            $cb.Add_Checked({ Update-AppsCount }); $cb.Add_Unchecked({ Update-AppsCount })
            $script:AppCheckboxes[$app.Id]=$cb
            $desc=[System.Windows.Controls.TextBlock]::new(); $desc.Text=[string]$app.Description
            $desc.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#c4c4ee"); $desc.FontSize=11; $desc.Margin=[System.Windows.Thickness]::new(28,2,0,0); $desc.TextWrapping="Wrap"
            $wid=[System.Windows.Controls.TextBlock]::new(); $wid.Text=[string]$app.Id
            $wid.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#6a6a85"); $wid.FontSize=10; $wid.Margin=[System.Windows.Thickness]::new(28,1,0,0); $wid.TextTrimming="CharacterEllipsis"
            $badge=[System.Windows.Controls.Border]::new()
            $badge.CornerRadius=[System.Windows.CornerRadius]::new(4); $badge.Padding=[System.Windows.Thickness]::new(6,1,6,1)
            $badge.Margin=[System.Windows.Thickness]::new(28,4,0,0); $badge.HorizontalAlignment="Left"; $badge.Visibility="Collapsed"
            $badge.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#0e2a1a"); $badge.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFrom("#2da86a")
            $badge.BorderThickness=[System.Windows.Thickness]::new(1)
            $btxt=[System.Windows.Controls.TextBlock]::new(); $btxt.Text="✓ уже стоит"; $btxt.FontSize=10; $btxt.FontWeight="SemiBold"
            $btxt.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#2ecc71")
            $badge.Child=$btxt
            $script:AppBadges[[string]$app.Id]=$badge
            $stk.Children.Add($cb) | Out-Null; $stk.Children.Add($desc) | Out-Null; $stk.Children.Add($wid) | Out-Null; $stk.Children.Add($badge) | Out-Null
            $agrid=[System.Windows.Controls.Grid]::new()
            $aic=[System.Windows.Controls.ColumnDefinition]::new(); $aic.Width=[System.Windows.GridLength]::Auto
            $asc=[System.Windows.Controls.ColumnDefinition]::new(); $asc.Width=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
            $agrid.ColumnDefinitions.Add($aic); $agrid.ColumnDefinitions.Add($asc)
            $aimg=Get-IconImage -Name (Get-AppCategoryIcon -Name $category.Name) -Size 24
            if (-not $aimg) {
                $aimg=New-Object System.Windows.Controls.Image
                $aimg.Width=24; $aimg.Height=24
            }
            $aimg.Margin=[System.Windows.Thickness]::new(0,2,10,0); $aimg.VerticalAlignment="Top"
            [System.Windows.Controls.Grid]::SetColumn($aimg,0)
            $agrid.Children.Add($aimg) | Out-Null
            [System.Windows.Controls.Grid]::SetColumn($stk,1)
            $agrid.Children.Add($stk) | Out-Null
            $script:AppIconImgs[[string]$app.Id]=$aimg
            $card.Child=$agrid
            Add-CardFx -Card $card
            $appsPanel.Children.Add($card) | Out-Null
        }
    }
    Update-AppsCount
    # Фоновая сверка установленных (winget list): бейджи + пропуск при установке.
    Start-Background {
        try {
            $wg = Get-WingetPath
            $raw = & $wg list --accept-source-agreements 2>$null | Out-String
            $ids = @()
            $hf = $false
            foreach ($ln in ($raw -split "`n")) {
                if ($ln -match '^\s*-+\s*$') { $hf = $true; continue }
                if (-not $hf) { continue }
                $p = @($ln -split '\s{2,}' | Where-Object { $_.Trim() -ne '' })
                if ($p.Count -ge 2) {
                    $id = $p[1].Trim()
                    if ($id -match '\.' -and $id -notmatch '^(Unknown|winget|msstore)$') { $ids += $id }
                }
            }
            Set-BgResult -Key 'installedApps' -Value @{ Ids = $ids }
        } catch {}
    }
    # Фавиконки брендов: тихо подгружаются поверх иконок категорий.
    $iconJobs = @()
    foreach ($kv in $script:AppIconImgs.GetEnumerator()) {
        $d = Get-AppFaviconDomain -Id $kv.Key
        if ($d) { $iconJobs += @{ Id = [string]$kv.Key; Domain = $d } }
    }
    $iconDir = Join-Path $script:WorkFolder 'icons'
    Start-Background {
        try {
            $res = @()
            foreach ($job in $iconJobs) {
                try {
                    $img = Get-AppFaviconImage -Domain $job.Domain -CacheDir $iconDir
                    if ($img) { $res += @{ Id = $job.Id; Img = $img } }
                } catch {}
            }
            if ($res.Count -gt 0) { Set-BgResult -Key 'appIcons' -Value @{ Items = $res } }
        } catch {}
    } -Variables @{ iconJobs = $iconJobs; iconDir = $iconDir }
}

function Select-Preset {
    param($presetName)
    $appsData = Load-Apps
    $presetList = $null
    if ($appsData.Presets -is [hashtable]) {
        if ($appsData.Presets.ContainsKey($presetName)) { $presetList = $appsData.Presets[$presetName] }
    } else {
        $prop = $appsData.Presets.PSObject.Properties[$presetName]
        if ($prop) { $presetList = $prop.Value }
    }
    if ($null -eq $presetList) { Write-Log "Пресет '$presetName' не найден" -Color "Yellow"; return }
    foreach ($cb in $script:AppCheckboxes.Values) { $cb.IsChecked = $false }
    foreach ($entry in $presetList) {
        $matched = $null
        if ($script:AppCheckboxes.ContainsKey($entry)) {
            $matched = $script:AppCheckboxes[$entry]
        } else {
            foreach ($kv in $script:AppCheckboxes.GetEnumerator()) {
                if ($kv.Value.Content -eq $entry) { $matched = $kv.Value; break }
            }
        }
        if ($matched) { $matched.IsChecked = $true }
        else { Write-Log "Пресет '$presetName': приложение '$entry' не найдено в списке" -Color "Yellow" }
    }
    Update-AppsCount
    Write-Log "Пресет $presetName применён" -Color "Green"
}
