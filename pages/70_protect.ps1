# PAGE: protect
# TITLE: Защита
# ICON: shield
# ORDER: 70

$script:PrUi = $null
function Get-BrowserPolicyKeys {
    return @('SOFTWARE\Policies\Google\Chrome', 'SOFTWARE\Policies\Microsoft\Edge', 'SOFTWARE\Policies\BraveSoftware\Brave', 'SOFTWARE\Policies\YandexBrowser', 'SOFTWARE\Policies\Mozilla\Firefox', 'SOFTWARE\Policies\Opera Software\Opera')
}

function Get-SecurityState {
    # Фон. Антивирус, проверки. (DNS теперь на странице «Сеть».)
    $r = @{ Av = (Get-AntivirusState); Mp = $null; Threats = @(); Checks = @() }
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        $pref = Get-MpPreference -ErrorAction SilentlyContinue
        $r.Mp = @{
            Rtp = [bool]$mp.RealTimeProtectionEnabled; Av = [bool]$mp.AntivirusEnabled; Sig = $mp.AntivirusSignatureLastUpdated
            Quick = $mp.QuickScanEndTime; Full = $mp.FullScanEndTime; Tamper = [bool]$mp.IsTamperProtected
            Pua = $(if ($pref) { [int]$pref.PUAProtection } else { -1 })
        }
        $names = @{}
        foreach ($t in @(Get-MpThreat -ErrorAction SilentlyContinue)) { $names[[string]$t.ThreatID] = [string]$t.ThreatName }
        $r.Threats = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Sort-Object InitialDetectionTime -Descending | Select-Object -First 6 | ForEach-Object {
            @{ Name = $(if ($names[[string]$_.ThreatID]) { $names[[string]$_.ThreatID] } else { 'ID ' + $_.ThreatID }); Time = $_.InitialDetectionTime; Path = (@($_.Resources) -join '; ') -replace '^file:_', ''; Action = [int]$_.ThreatStatusID }
        })
    } catch {}
    $c = @()
    try { $off = @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { -not $_.Enabled }); $c += @{ Id = 'fw'; Title = 'Брандмауэр'; Ok = ($off.Count -eq 0); Detail = $(if ($off.Count) { 'выключен: ' + (($off | ForEach-Object { $_.Name }) -join ', ') } else { 'включён для всех сетей' }); Plugin = '01_firewall_on' } } catch {}
    $c += @{ Id = 'uac'; Title = 'Контроль учётных записей (UAC)'; Ok = (Test-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA' 1); Detail = 'запрос подтверждения перед изменениями системы'; Plugin = '03_uac_on' }
    $c += @{ Id = 'autorun'; Title = 'Автозапуск с флешек выключен'; Ok = (Test-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun' 255); Detail = 'частый путь заражения через USB'; Plugin = '05_no_autorun' }
    try { $c += @{ Id = 'smb1'; Title = 'Устаревший SMBv1 выключен'; Ok = (Test-Smb1Off); Detail = 'через него распространялся WannaCry'; Plugin = '07_smb1_off' } } catch {}
    try { $rdp = [int](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction Stop).fDenyTSConnections; $c += @{ Id = 'rdp'; Title = 'Удалённый рабочий стол закрыт'; Ok = ($rdp -eq 1); Detail = 'если не пользуетесь - держите закрытым'; Plugin = '' } } catch {}
    try { $g = Get-LocalUser -ErrorAction Stop | Where-Object { $_.SID.Value -like 'S-1-5-21-*-501' } | Select-Object -First 1; if ($g) { $c += @{ Id = 'guest'; Title = 'Гостевая запись выключена'; Ok = (-not $g.Enabled); Detail = 'вход без пароля для кого угодно'; Plugin = '04_no_guest' } } } catch {}
    if ($r.Mp) { $c += @{ Id = 'pua'; Title = 'Блокировка нежелательных программ'; Ok = ($r.Mp.Pua -eq 1); Detail = 'рекламные тулбары, «ускорители», навязанные установщики'; Plugin = '06_pua_protection' } }
    try { $wu = Get-Service wuauserv -ErrorAction Stop; $c += @{ Id = 'wu'; Title = 'Центр обновления Windows работает'; Ok = ($wu.StartType -ne 'Disabled'); Detail = 'без него не приходят исправления безопасности'; Plugin = '' } } catch {}
    $r.Checks = $c
    return $r
}

function Test-Smb1Off {
    # Быстро, без DISM: сервер SMBv1 выключен и клиентский драйвер mrxsmb10 не запускается.
    $srv = $true
    try { $srv = -not (Get-SmbServerConfiguration -ErrorAction Stop).EnableSMB1Protocol } catch {}
    $cli = $true
    try { $st = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\mrxsmb10' -Name Start -ErrorAction Stop).Start; $cli = ([int]$st -eq 4) } catch {}
    return ($srv -and $cli)
}

function Get-ChromiumExtName {
    param([string]$Dir)
    try {
        $m = Get-Content -LiteralPath (Join-Path $Dir 'manifest.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $n = [string]$m.name
        if ($n -match '^__MSG_(.+)__$') {
            $key = $Matches[1]
            foreach ($loc in @($m.default_locale, 'ru', 'en', 'en_US')) {
                if (-not $loc) { continue }
                $f = Join-Path $Dir ('_locales\' + $loc + '\messages.json')
                if (Test-Path -LiteralPath $f) {
                    $msg = Get-Content -LiteralPath $f -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                    foreach ($p in $msg.PSObject.Properties) { if ($p.Name -ieq $key) { return [string]$p.Value.message } }
                }
            }
        }
        return @{ Name = $n; Update = [string]$m.update_url }
    } catch { return $null }
}

function Get-BrowserReport {
    # Фон. Поисковик, стартовые страницы, расширения, политики и прокси.
    $res = @{ Browsers = @(); Policies = @(); Proxy = $null }
    $chromium = @(
        @{ Name = 'Google Chrome'; Root = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data' },
        @{ Name = 'Microsoft Edge'; Root = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data' },
        @{ Name = 'Brave'; Root = Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data' },
        @{ Name = 'Яндекс Браузер'; Root = Join-Path $env:LOCALAPPDATA 'Yandex\YandexBrowser\User Data' },
        @{ Name = 'Vivaldi'; Root = Join-Path $env:LOCALAPPDATA 'Vivaldi\User Data' },
        @{ Name = 'Opera'; Root = Join-Path $env:APPDATA 'Opera Software\Opera Stable'; Single = $true }
    )
    $storeUpdate = 'clients2.google.com|edge.microsoft.com|extension-updates.opera.com|yandex'
    foreach ($b in $chromium) {
        if (-not (Test-Path -LiteralPath $b.Root)) { continue }
        $profiles = if ($b.Single) { @(Get-Item -LiteralPath $b.Root) } else { @(Get-ChildItem -LiteralPath $b.Root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }) }
        foreach ($pd in $profiles) {
            $prefFile = Join-Path $pd.FullName 'Preferences'
            if (-not (Test-Path -LiteralPath $prefFile)) { continue }
            $info = @{ Browser = $b.Name; Profile = $pd.Name; Search = ''; Start = @(); Extensions = @(); Issues = @() }
            try {
                $pref = Get-Content -LiteralPath $prefFile -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                $u = $null; try { $u = [string]$pref.default_search_provider_data.template_url_data.url } catch {}
                if ($u) {
                    $info.Search = ([uri]($u -replace '\{[^}]+\}', 'x')).Host
                    if ($info.Search -notmatch '(?i)google\.|bing\.com|yandex\.|duckduckgo|ecosia|mail\.ru|brave\.com|startpage|qwant|ya\.ru|search\.brave') { $info.Issues += 'Нестандартный поисковик: ' + $info.Search }
                }
                try { if ([int]$pref.session.restore_on_startup -eq 4) { $info.Start = @($pref.session.startup_urls) } } catch {}
                try { if ($pref.homepage -and -not $pref.homepage_is_newtabpage) { $info.Start += [string]$pref.homepage } } catch {}
                foreach ($s in $info.Start) { if ($s -and $s -notmatch '(?i)google\.|bing\.|yandex\.|ya\.ru|mail\.ru|chrome://|edge://|about:') { $info.Issues += 'Стартовая страница: ' + $s } }
                $settings = @{}
                foreach ($f in @('Preferences', 'Secure Preferences')) {
                    try {
                        $j = if ($f -eq 'Preferences') { $pref } else { Get-Content -LiteralPath (Join-Path $pd.FullName $f) -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
                        foreach ($p in $j.extensions.settings.PSObject.Properties) { $settings[$p.Name] = $p.Value }
                    } catch {}
                }
                foreach ($id in $settings.Keys) {
                    $e = $settings[$id]
                    # 0 - служебная запись без установки, 5/10 - встроенные компоненты браузера.
                    $loc = if ($null -ne $e.location) { [int]$e.location } else { 0 }
                    if ($loc -in @(0, 5, 10)) { continue }
                    $dir = Join-Path $pd.FullName ('Extensions\' + $id)
                    $ver = Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
                    # Нет файлов - это остаток в настройках, а не установленное расширение.
                    if (-not $ver -and $loc -ne 4) { continue }
                    $name = $id; $upd = ''
                    if ($ver) { $nm = Get-ChromiumExtName -Dir $ver.FullName; if ($nm -is [hashtable]) { $name = $nm.Name; $upd = $nm.Update } elseif ($nm) { $name = [string]$nm } }
                    if ($loc -eq 4 -and $e.path) { $name = [string]$e.path }
                    $fromStore = ([bool]$e.from_webstore) -or ($upd -match $storeUpdate)
                    $flag = ''
                    if ($loc -eq 4) { $flag = 'распакованное, загружено вручную' }
                    elseif ($fromStore) { $flag = '' }
                    elseif ($loc -in @(2, 3, 6)) { $flag = 'установлено сторонней программой' }
                    elseif ($loc -in @(7, 9)) { $flag = 'установлено политикой, не из магазина' }
                    elseif ($loc -eq 1 -and $upd) { $flag = 'не из магазина расширений' }
                    $enabled = -not ($e.disable_reasons -and @($e.disable_reasons).Count -gt 0) -and ([int]$e.state -ne 0 -or $null -eq $e.state)
                    $info.Extensions += @{ Id = $id; Name = $name; Flag = $flag; Enabled = $enabled }
                }
            } catch { $info.Issues += 'Настройки не прочитались: ' + $_.Exception.Message }
            $res.Browsers += $info
        }
    }
    # Firefox
    $ffRoot = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
    foreach ($pd in @(Get-ChildItem -LiteralPath $ffRoot -Directory -ErrorAction SilentlyContinue)) {
        $info = @{ Browser = 'Firefox'; Profile = $pd.Name; Search = ''; Start = @(); Extensions = @(); Issues = @() }
        try {
            $pj = Join-Path $pd.FullName 'prefs.js'
            if (Test-Path -LiteralPath $pj) {
                $m = Select-String -LiteralPath $pj -Pattern 'user_pref\("browser\.startup\.homepage",\s*"([^"]+)"' -ErrorAction Stop | Select-Object -First 1
                if ($m) { $info.Start = @($m.Matches[0].Groups[1].Value -split '\|'); foreach ($s in $info.Start) { if ($s -notmatch '(?i)google\.|yandex\.|about:|mozilla') { $info.Issues += 'Стартовая страница: ' + $s } } }
            }
            $ej = Join-Path $pd.FullName 'extensions.json'
            if (Test-Path -LiteralPath $ej) {
                $j = Get-Content -LiteralPath $ej -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                foreach ($a in @($j.addons | Where-Object { $_.type -eq 'extension' -and $_.location -ne 'app-builtin' -and $_.location -ne 'app-system-defaults' })) {
                    $flag = ''
                    if ($a.location -ne 'app-profile') { $flag = 'установлено сторонней программой' }
                    elseif ([int]$a.signedState -lt 1) { $flag = 'без подписи Mozilla' }
                    $info.Extensions += @{ Id = [string]$a.id; Name = [string]$a.defaultLocale.name; Flag = $flag; Enabled = [bool]$a.active }
                }
            }
        } catch {}
        if ($info.Start.Count -or $info.Extensions.Count) { $res.Browsers += $info }
    }
    # Политики (так часто прописываются угонщики браузера)
    foreach ($hive in @('HKLM', 'HKCU')) {
        foreach ($k in (Get-BrowserPolicyKeys)) {
            $path = $hive + ':\' + $k
            if (-not (Test-Path -LiteralPath $path)) { continue }
            $vals = @()
            try { $vals += @((Get-Item -LiteralPath $path -ErrorAction Stop).Property) } catch {}
            try { $vals += @(Get-ChildItem -LiteralPath $path -ErrorAction SilentlyContinue | ForEach-Object { $_.PSChildName }) } catch {}
            if ($vals.Count) { $res.Policies += @{ Path = ($hive + '\' + $k); Items = $vals } }
        }
    }
    try {
        $is = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        if ([int]$is.ProxyEnable -eq 1 -or $is.AutoConfigURL) { $res.Proxy = @{ Server = [string]$is.ProxyServer; Pac = [string]$is.AutoConfigURL } }
    } catch {}
    return $res
}

function Reset-BrowserPolicies {
    $dir = Join-Path $BackupFolder ('browser-policies-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $n = 0
    foreach ($hive in @('HKLM', 'HKCU')) {
        foreach ($k in (Get-BrowserPolicyKeys)) {
            $path = $hive + ':\' + $k
            if (-not (Test-Path -LiteralPath $path)) { continue }
            $file = Join-Path $dir (($hive + '_' + $k) -replace '[\\ ]', '_') + '.reg'
            & reg.exe export ($hive + '\' + $k) $file /y | Out-Null
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            $n++
            Write-Log ('Удалены политики: ' + $hive + '\' + $k) 'ok'
        }
    }
    Write-Log ('Копия удалённых политик: ' + $dir)
    Add-History -Kind 'protect' -Name ('Сброс политик браузеров (' + $n + ')') -Ref $dir
}

function Build-Page_protect {
    $ui = @{}
    $refresh = New-Button -Text 'Обновить' -Icon 'refresh' -OnClick { Update-ProtectPage }
    $L = New-PageLayout -Title 'Защита' -Subtitle 'Антивирус, настройки безопасности, браузеры и DNS' -HeaderRight @($refresh)
    # Антивирус
    $avs = New-Stack
    $top = New-Object System.Windows.Controls.DockPanel
    $ui.AvIcon = New-IconTile -Icon 'shield' -Color 'Muted' -Size 48
    $ui.AvIcon.Margin = New-Thickness 0, 0, 16, 0
    [System.Windows.Controls.DockPanel]::SetDock($ui.AvIcon, 'Left')
    [void]$top.Children.Add($ui.AvIcon)
    $ts = New-Stack; $ts.VerticalAlignment = 'Center'
    $ui.AvTitle = New-Text -Text 'Проверяю…' -Size 18 -Weight 'Bold'
    $ui.AvSub = New-Text -Text '' -Size 13 -Color 'Muted' -Wrap -Margin (0, 4, 0, 0)
    [void]$ts.Children.Add($ui.AvTitle); [void]$ts.Children.Add($ui.AvSub)
    [void]$top.Children.Add($ts)
    [void]$avs.Children.Add($top)
    $bw = New-Object System.Windows.Controls.WrapPanel
    $bw.Margin = New-Thickness 0, 14, 0, 0
    foreach ($b in @(@('Обновить базы', 'refresh', 'sig'), @('Быстрая проверка', 'search', 'quick'), @('Полная проверка', 'disk', 'full'), @('Автономная проверка', 'power', 'offline'))) {
        $btn = New-Button -Text $b[0] -Icon $b[1] -Kind $(if ($b[2] -eq 'quick') { 'Primary' } else { 'Secondary' }) -Tag $b[2] -OnClick { Start-DefenderAction -Action $this.Tag }
        $btn.Margin = New-Thickness 0, 0, 10, 8
        [void]$bw.Children.Add($btn)
    }
    $ui.AvButtons = $bw
    [void]$avs.Children.Add($bw)
    $ui.Threats = New-Stack
    [void]$avs.Children.Add($ui.Threats)
    [void]$L.Body.Children.Add((New-Card -Child $avs -Margin (0, 0, 0, 16)))

    $ui.ChecksSec = New-Section -Title 'Настройки безопасности'
    [void]$ui.ChecksSec.Body.Children.Add((New-Placeholder))
    [void]$L.Body.Children.Add($ui.ChecksSec.Root)

    $scanBr = New-Button -Text 'Проверить браузеры' -Kind Ghost -OnClick { Update-BrowserSection }
    $ui.BrSec = New-Section -Title 'Браузеры' -Right @($scanBr)
    [void]$ui.BrSec.Body.Children.Add((New-Placeholder 'Ищу подменённый поисковик, чужие стартовые страницы, расширения не из магазина и политики, которые прописывают рекламные программы.'))
    [void]$L.Body.Children.Add($ui.BrSec.Root)

    $toNet = New-Button -Text 'Безопасный DNS - на странице «Сеть» →' -Kind Ghost -OnClick { Show-Page -Id 'network' }
    $toNet.HorizontalAlignment = 'Left'
    [void]$L.Body.Children.Add($toNet)
    $script:PrUi = $ui
    return $L.Root
}

function Show-Page_protect {
    param($Arg)
    if (-not $script:PrUi.Loaded) { Update-ProtectPage; Update-BrowserSection }
}

function Update-ProtectPage {
    $script:PrUi.Loaded = $true
    Start-BgTask -Name 'Проверка защиты' -Script { Get-SecurityState } -OnDone { param($r) if ($r) { Set-ProtectData $r } } | Out-Null
}

function Set-ProtectData {
    param($r)
    $ui = $script:PrUi
    $ok = $r.Av.Ok
    $ui.AvTitle.Text = $r.Av.Title
    $ui.AvIcon.Child.Child.Children[0].Stroke = Get-Brush $(if ($ok) { 'Ok' } else { 'Bad' })
    $parts = @()
    if ($r.Mp) {
        if ($r.Mp.Sig) { $parts += 'базы от ' + ([datetime]$r.Mp.Sig).ToString('dd.MM HH:mm') }
        if ($r.Mp.Quick -and ([datetime]$r.Mp.Quick).Year -gt 2000) { $parts += 'быстрая проверка: ' + ([datetime]$r.Mp.Quick).ToString('dd.MM.yyyy') }
        if ($r.Mp.Tamper) { $parts += 'защита от изменений включена' }
    }
    $other = @($r.Av.Products | Where-Object { $_.Name -notmatch '(?i)defender' } | ForEach-Object { $_.Name })
    if ($other.Count) { $parts += 'также установлено: ' + ($other -join ', ') }
    $ui.AvSub.Text = $r.Av.Detail + $(if ($parts.Count) { ' · ' + ($parts -join ' · ') } else { '' })
    $ui.AvButtons.IsEnabled = [bool]$r.Mp -and $r.Mp.Av
    $ui.Threats.Children.Clear()
    if ($r.Threats.Count) {
        [void]$ui.Threats.Children.Add((New-Text -Text 'Последние найденные угрозы' -Size 13 -Weight 'SemiBold' -Margin (0, 10, 0, 6)))
        foreach ($t in $r.Threats) {
            $st = if ($t.Action -in @(3, 4, 5, 6, 102, 103, 104, 105, 106)) { New-Badge 'обезврежена' 'ok' } else { New-Badge 'требует внимания' 'bad' }
            $row = New-Row -Main (New-TitleBlock -Title $t.Name -Sub ((([datetime]$t.Time).ToString('dd.MM.yyyy HH:mm')) + ' · ' + $t.Path)) -Right @($st) -Padding (0, 6, 0, 6)
            [void]$ui.Threats.Children.Add($row)
        }
    }
    $body = $ui.ChecksSec.Body
    $body.Children.Clear()
    foreach ($c in @($r.Checks | Sort-Object { $_.Ok })) {
        $fix = $null
        if (-not $c.Ok) {
            $fix = New-Button -Text 'Исправить' -Kind Small -Tag $c -OnClick {
                $this.IsEnabled = $false
                Set-ButtonText -Button $this -Text 'Исправляю…'
                Repair-SecurityCheck -Check $this.Tag
            }
        }
        $row = New-Row -Left (New-Icon -Name $(if ($c.Ok) { 'check' } else { 'warn' }) -Size 18 -Color $(if ($c.Ok) { 'Ok' } else { 'Warn' })) -Main (New-TitleBlock -Title $c.Title -Sub $c.Detail) -Right @($fix) -Padding (16, 8, 12, 8)
        [void]$body.Children.Add($row)
    }
}

function Repair-SecurityCheck {
    param($Check)
    $plugin = $null
    if ($Check.Plugin) { $plugin = @(Get-Plugins | Where-Object { $_.Id -like ('*' + $Check.Plugin + '*') -and -not $_.IsUndo } | Select-Object -First 1) }
    $fixVars = @{ Id = $Check.Id; P = $plugin }
    Write-Log ('Исправляю: ' + $Check.Title + $(if ($Check.Id -eq 'smb1') { ' (через DISM, может занять несколько минут)' } else { '' }))
    Start-BgTask -Name ('Исправление: ' + $Check.Title) -Vars $fixVars -Script {
        switch ($Id) {
            'rdp' { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 1 -Type DWord; Write-Log 'Удалённый рабочий стол закрыт' 'ok'; Add-History -Kind 'protect' -Name 'Закрыт удалённый рабочий стол' }
            'wu' { Set-Service wuauserv -StartupType Manual; Start-Service wuauserv -ErrorAction SilentlyContinue; Write-Log 'Центр обновления включён' 'ok'; Add-History -Kind 'protect' -Name 'Включён Центр обновления' }
            default { if (@($P).Count) { [void](Invoke-PluginBatch -Plugins @($P) -RestorePoint $false -Title 'Исправление') } }
        }
    } -OnDone { Update-ProtectPage } | Out-Null
}

function Start-DefenderAction {
    param([string]$Action)
    if ($Action -eq 'offline' -and -not (Show-Confirm -Message 'Автономная проверка перезагрузит компьютер и проверит его до запуска Windows (около 15 минут). Сохраните открытые документы. Продолжить?' -Warning)) { return }
    if ($Action -eq 'full' -and -not (Show-Confirm -Message 'Полная проверка может занять от 30 минут до нескольких часов. Работать за компьютером можно, но он будет медленнее. Начать?')) { return }
    $name = switch ($Action) { 'sig' { 'Обновление баз' } 'quick' { 'Быстрая проверка' } 'full' { 'Полная проверка' } default { 'Автономная проверка' } }
    Start-BgTask -Name $name -Vars @{ A = $Action } -Script {
        $t0 = Get-Date
        switch ($A) {
            'sig' { Write-Log 'Обновляю базы Защитника...'; Update-MpSignature -ErrorAction Stop; Write-Log 'Базы обновлены' 'ok' }
            'quick' { Write-Log 'Быстрая проверка...'; Start-MpScan -ScanType QuickScan -ErrorAction Stop }
            'full' { Write-Log 'Полная проверка... (долго)'; Start-MpScan -ScanType FullScan -ErrorAction Stop }
            'offline' { Write-Log 'Компьютер перезагрузится для автономной проверки'; Start-MpWDOScan -ErrorAction Stop }
        }
        if ($A -eq 'quick' -or $A -eq 'full') {
            $found = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.InitialDetectionTime -ge $t0 })
            if ($found.Count) { Write-Log ('Найдено угроз: ' + $found.Count + '. Подробности - на этой странице и в «Безопасность Windows».') 'warn' }
            else { Write-Log 'Угроз не найдено' 'ok' }
            Add-History -Kind 'protect' -Name ($(if ($A -eq 'quick') { 'Быстрая' } else { 'Полная' }) + ' проверка Защитником: найдено ' + $found.Count)
        }
    } -OnDone { Update-ProtectPage } | Out-Null
}

function Update-BrowserSection {
    $ui = $script:PrUi
    $ui.BrSec.Body.Children.Clear()
    [void]$ui.BrSec.Body.Children.Add((New-Placeholder 'Проверяю браузеры…'))
    Start-BgTask -Name 'Проверка браузеров' -Script { Get-BrowserReport } -OnDone { param($r) if ($r) { Set-BrowserSection $r } } | Out-Null
}

function Set-BrowserSection {
    param($r)
    $body = $script:PrUi.BrSec.Body
    $body.Children.Clear()
    if ($r.Policies.Count) {
        $txt = 'Браузером управляют политики (так часто делают рекламные программы): ' + (($r.Policies | ForEach-Object { $_.Path + ' [' + ($_.Items -join ', ') + ']' }) -join '; ')
        $btn = New-Button -Text 'Сбросить политики' -Kind SmallDanger -OnClick {
            if (-not (Show-Confirm -Message 'Удалить политики браузеров из реестра? Копия сохранится в резервных копиях PotatoPC. Если компьютер рабочий и браузер настраивает администратор организации - нажмите «Нет».' -Warning)) { return }
            Start-BgTask -Name 'Сброс политик браузеров' -Script { Reset-BrowserPolicies } -OnDone { Update-BrowserSection } | Out-Null
        }
        [void]$body.Children.Add((New-Row -Left (New-Icon -Name 'warn' -Size 18 -Color 'Bad') -Main (New-Text -Text $txt -Size 13 -Wrap) -Right @($btn)))
    }
    if ($r.Proxy) {
        $btn = New-Button -Text 'Выключить прокси' -Kind Small -OnClick {
            $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
            Set-ItemProperty -LiteralPath $k -Name ProxyEnable -Value 0 -Type DWord -ErrorAction Stop
            Remove-ItemProperty -LiteralPath $k -Name AutoConfigURL -ErrorAction SilentlyContinue
            Write-Log 'Системный прокси выключен' 'ok'; Add-History -Kind 'protect' -Name 'Выключен системный прокси'
            Update-BrowserSection
        }
        $t = 'Включён системный прокси' + $(if ($r.Proxy.Server) { ': ' + $r.Proxy.Server } else { '' }) + $(if ($r.Proxy.Pac) { ' · PAC: ' + $r.Proxy.Pac } else { '' }) + '. Если вы его не настраивали - через него могут подменять страницы.'
        [void]$body.Children.Add((New-Row -Left (New-Icon -Name 'warn' -Size 18 -Color 'Warn') -Main (New-Text -Text $t -Size 13 -Wrap) -Right @($btn)))
    }
    if ($r.Browsers.Count -eq 0) { [void]$body.Children.Add((New-Placeholder 'Браузеры не найдены.')); return }
    foreach ($b in $r.Browsers) {
        $bad = @($b.Extensions | Where-Object { $_.Flag })
        $sub = @()
        if ($b.Search) { $sub += 'поиск: ' + $b.Search }
        $sub += 'расширений: ' + $b.Extensions.Count
        $badge = if ($b.Issues.Count -or $bad.Count) { New-Badge ('проверить: ' + ($b.Issues.Count + $bad.Count)) 'warn' } else { New-Badge 'в порядке' 'ok' }
        $main = New-Stack
        [void]$main.Children.Add((New-TitleBlock -Title ($b.Browser + $(if ($b.Profile -and $b.Profile -ne 'Default' -and $b.Profile -ne 'Opera Stable') { ' · ' + $b.Profile } else { '' })) -Sub ($sub -join ' · ')))
        foreach ($i in $b.Issues) { [void]$main.Children.Add((New-Text -Text ('⚠ ' + $i) -Size 12 -Color 'Warn' -Wrap -Margin (0, 4, 0, 0))) }
        foreach ($e in $bad) { [void]$main.Children.Add((New-Text -Text ('⚠ Расширение «' + $e.Name + '» - ' + $e.Flag + $(if (-not $e.Enabled) { ' (выключено)' } else { '' })) -Size 12 -Color 'Warn' -Wrap -Margin (0, 4, 0, 0))) }
        $main.ToolTip = 'Все расширения: ' + (($b.Extensions | ForEach-Object { $_.Name }) -join ', ')
        [void]$body.Children.Add((New-Row -Left (New-AppIcon -Name $b.Browser -Size 34) -Main $main -Right @($badge)))
    }
    [void]$body.Children.Add((New-Text -Text 'Подозрительные расширения удаляются в самом браузере: «Расширения» → «Удалить». PotatoPC их не удаляет, чтобы не стереть нужное.' -Size 12 -Color 'Muted' -Wrap -Margin (16, 8, 16, 12)))
}

