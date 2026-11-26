# PAGE: network
# TITLE: Сеть
# ICON: network
# ORDER: 57

# Сеть: замер скорости (speed.cloudflare.com), диагностика по шагам с вердиктом,
# быстрые исправления, DNS (перенесён со страницы «Защита») и сведения для мастера.

$script:NetUi = $null
$script:DnsPresets = [ordered]@{
    cloudflare = @{ Name = 'Cloudflare (защита от вредоносных сайтов)'; V4 = @('1.1.1.2', '1.0.0.2') }
    quad9      = @{ Name = 'Quad9 (защита от вредоносных сайтов)'; V4 = @('9.9.9.9', '149.112.112.112') }
    adguard    = @{ Name = 'AdGuard (блокирует рекламу и трекеры)'; V4 = @('94.140.14.14', '94.140.15.15') }
    auto       = @{ Name = 'Как у провайдера (автоматически)'; V4 = @() }
}

# ---------- Фон: сбор данных ----------

function Get-DnsState {
    $out = @()
    try {
        foreach ($a in @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })) {
            $d = Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $out += @{ Name = [string]$a.Name; Index = [int]$a.ifIndex; Servers = @($d.ServerAddresses) }
        }
    } catch {}
    return $out
}

function Get-ActiveNetAdapter {
    # Адаптер, через который идёт маршрут по умолчанию.
    $routes = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object { [int]$_.RouteMetric + [int]$_.InterfaceMetric })
    foreach ($r in $routes) {
        $a = Get-NetAdapter -InterfaceIndex $r.ifIndex -ErrorAction SilentlyContinue
        if ($a -and $a.Status -eq 'Up') {
            $wl = ([string]$a.PhysicalMediaType -match '802\.11') -or ([int]$a.NdisPhysicalMedium -eq 9) -or ([string]$a.InterfaceDescription -match '(?i)wi-?fi|wireless|802\.11|wlan')
            return @{ Index = [int]$a.ifIndex; Name = [string]$a.Name; Desc = [string]$a.InterfaceDescription; Speed = [string]$a.LinkSpeed; Mac = [string]$a.MacAddress; Wireless = $wl; Gateway = [string]$r.NextHop }
        }
    }
    return $null
}

function Invoke-NetPing {
    param([string]$Target, [int]$Count = 4, [int]$Timeout = 1000)
    $p = New-Object System.Net.NetworkInformation.Ping
    $t = @()
    for ($i = 0; $i -lt $Count; $i++) {
        if (Test-JobCancel) { break }
        try { $r = $p.Send($Target, $Timeout); if ($r.Status -eq 'Success') { $t += [double]$r.RoundtripTime } } catch {}
        if ($i -lt $Count - 1) { Start-Sleep -Milliseconds 120 }
    }
    $p.Dispose()
    $avg = 0; $jit = 0
    if ($t.Count) { $avg = ($t | Measure-Object -Average).Average }
    if ($t.Count -gt 1) { $d = 0; for ($i = 1; $i -lt $t.Count; $i++) { $d += [Math]::Abs($t[$i] - $t[$i - 1]) }; $jit = $d / ($t.Count - 1) }
    return @{ Sent = $Count; Ok = $t.Count; Loss = $(if ($Count) { [Math]::Round(100.0 * ($Count - $t.Count) / $Count) } else { 0 }); Avg = [Math]::Round($avg); Jitter = [Math]::Round($jit) }
}

function Measure-DnsServer {
    # Время ответа DNS-сервера (мс), -1 - не ответил. Лучшее из двух запросов.
    param([string]$Server)
    $best = -1
    foreach ($n in @('www.microsoft.com', 'www.google.com')) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            [void](Resolve-DnsName -Name $n -Server $Server -Type A -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction Stop)
            $ms = [int]$sw.ElapsedMilliseconds
            if ($best -lt 0 -or $ms -lt $best) { $best = $ms }
        } catch {}
    }
    return $best
}

function Get-NetshFields {
    # Вывод netsh «  Ключ   : значение» -> список пар (язык Windows не важен).
    param([string]$Arguments)
    $r = Invoke-ProcessLive -FilePath (Join-Path $env:WINDIR 'System32\netsh.exe') -Arguments $Arguments -TimeoutSec 30 -Quiet
    $out = @()
    foreach ($l in ([string]$r.Output -split "`r?`n")) {
        $m = [regex]::Match($l, '^\s+([^:]+?)\s*:\s(.*)$')
        if ($m.Success) { $out += , @($m.Groups[1].Value.Trim(), $m.Groups[2].Value.Trim()) }
    }
    return , $out
}

function Get-WifiState {
    $f = Get-NetshFields 'wlan show interfaces'
    $r = @{ Ssid = ''; Signal = -1; Channel = 0; Radio = '' }
    foreach ($p in $f) {
        if ($p[0] -eq 'SSID' -and -not $r.Ssid) { $r.Ssid = $p[1] }
        elseif ($p[1] -match '^(\d{1,3})\s*%$' -and $r.Signal -lt 0) { $r.Signal = [int]$Matches[1] }
        elseif ($p[0] -match '(?i)^(channel|канал)$') { $r.Channel = [int]($p[1] -replace '\D', '') }
        elseif ($p[0] -match '(?i)radio|радио') { $r.Radio = $p[1] }
    }
    $r.Neighbors = 0
    if ($r.Channel -gt 0) {
        $n = Get-NetshFields 'wlan show networks mode=bssid'
        $r.Neighbors = @($n | Where-Object { $_[0] -match '(?i)^(channel|канал)$' -and [int]($_[1] -replace '\D', '') -eq $r.Channel }).Count
        if ($r.Neighbors -gt 0) { $r.Neighbors-- }   # минус своя точка
    }
    return $r
}

function Get-HostsReport {
    $path = Join-Path $env:WINDIR 'System32\drivers\etc\hosts'
    $r = @{ Path = $path; Block = 0; Redirect = @(); Danger = @() }
    $sens = '(?i)(microsoft|windowsupdate|windows\.com|live\.com|google|gstatic|yandex|vk\.com|mail\.ru|ok\.ru|kaspersky|eset|drweb|avast|avg\.com|malwarebytes|bitdefender|norton|mcafee|virustotal|privat24|privatbank|monobank|oschadbank|raiffeisen|ukrsibbank|pumb|diia|sberbank|tinkoff|vtb|alfabank|gosuslugi|nalog|paypal|steam|epicgames)'
    try {
        foreach ($l in [System.IO.File]::ReadAllLines($path)) {
            $t = ($l -replace '#.*$', '').Trim()
            if (-not $t) { continue }
            $parts = $t -split '\s+'
            if ($parts.Count -lt 2) { continue }
            $ip = $parts[0]
            foreach ($h in $parts[1..($parts.Count - 1)]) {
                if ($h -match '^(localhost|localhost\.localdomain|ip6-localhost)$') { continue }
                $isBlock = $ip -in @('0.0.0.0', '127.0.0.1', '::1', '::')
                if ($h -match $sens) { $r.Danger += ($h + ' → ' + $ip) }
                elseif ($isBlock) { $r.Block++ }
                else { $r.Redirect += ($h + ' → ' + $ip) }
            }
        }
    } catch {}
    return $r
}

function Get-ProxyState {
    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $p = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue
    return @{ On = ([int]$p.ProxyEnable -eq 1); Server = [string]$p.ProxyServer; Pac = [string]$p.AutoConfigURL }
}

function Invoke-NetDiagnostics {
    # Фон. Проверка по шагам + вердикт.
    $steps = New-Object System.Collections.ArrayList
    $add = { param($Id, $Title, $State, $Detail, $Value) [void]$steps.Add(@{ Id = $Id; Title = $Title; State = $State; Detail = $Detail; Value = $Value }) }
    $f = @{}
    # 1. Адаптер
    Set-JobProgress 0.05 'Адаптер'
    $a = Get-ActiveNetAdapter
    $f.Adapter = $a
    if ($a) {
        & $add 'adapter' 'Адаптер' 'ok' (($(if ($a.Wireless) { 'Wi-Fi' } else { 'Кабель' })) + ' · ' + $a.Desc + ' · ' + $a.Speed) 'Подключён'
    } else {
        $phys = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)
        $why = if (-not $phys.Count) { 'сетевых адаптеров не найдено - нужен драйвер (страница «Драйверы»)' }
               elseif (@($phys | Where-Object { $_.Status -eq 'Disabled' }).Count -eq $phys.Count) { 'все адаптеры выключены: ' + (($phys | ForEach-Object { $_.Name }) -join ', ') }
               else { (($phys | ForEach-Object { $_.Name + ' - ' + $(switch ([string]$_.Status) { 'Disconnected' { 'не подключён' } 'Disabled' { 'выключен' } default { [string]$_.Status } }) }) -join ' · ') }
        $f.AdapterWhy = $why
        $f.AnyDisabled = @($phys | Where-Object { $_.Status -eq 'Disabled' }).Count -gt 0
        & $add 'adapter' 'Адаптер' 'bad' $why 'Нет связи'
    }
    # 2. Адрес
    Set-JobProgress 0.15 'Адрес'
    $f.IpOk = $false
    if ($a) {
        $ip = @(Get-NetIPAddress -InterfaceIndex $a.Index -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1)
        $dhcp = $false
        try { $dhcp = ([string](Get-NetIPInterface -InterfaceIndex $a.Index -AddressFamily IPv4 -ErrorAction Stop).Dhcp -eq 'Enabled') } catch {}
        $addr = if ($ip.Count) { [string]$ip[0].IPAddress } else { '' }
        if (-not $addr -or $addr -like '169.254.*') {
            & $add 'ip' 'Адрес от роутера' 'bad' ('роутер не выдал адрес' + $(if ($addr) { ' (' + $addr + ' - это адрес-заглушка Windows)' } else { '' })) 'Нет'
        } elseif (-not $a.Gateway -or $a.Gateway -eq '0.0.0.0') {
            & $add 'ip' 'Адрес от роутера' 'bad' ($addr + ' · шлюз не задан') 'Нет шлюза'
        } else {
            $f.IpOk = $true
            & $add 'ip' 'Адрес от роутера' 'ok' ($addr + ' · шлюз ' + $a.Gateway + $(if ($dhcp) { ' (DHCP)' } else { ' (вручную)' })) 'Есть'
        }
    } else { & $add 'ip' 'Адрес от роутера' 'na' 'нет активного подключения' '—' }
    # 3. Роутер
    Set-JobProgress 0.25 'Роутер'
    $f.GwOk = $false
    if ($f.IpOk) {
        $g = Invoke-NetPing -Target $a.Gateway -Count 4
        $f.GwOk = $g.Ok -gt 0
        if ($g.Ok -eq 0) { & $add 'gw' 'Роутер отвечает' 'warn' 'роутер не ответил на пинг (некоторые роутеры так настроены)' 'Нет ответа' }
        else { & $add 'gw' 'Роутер отвечает' $(if ($g.Loss -gt 0) { 'warn' } else { 'ok' }) ('пинг ' + $g.Avg + ' мс, потери ' + $g.Loss + '%') ([string]$g.Avg + ' мс') }
    } else { & $add 'gw' 'Роутер отвечает' 'na' 'пропущено' '—' }
    # 4. Интернет (по IP и по HTTP)
    Set-JobProgress 0.4 'Интернет'
    $ipNet = 0
    foreach ($t in @('1.1.1.1', '8.8.8.8')) { $ipNet += (Invoke-NetPing -Target $t -Count 2 -Timeout 1500).Ok }
    $f.IpNet = $ipNet -gt 0
    $f.Http = 'fail'
    try {
        $w = Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 8 -MaximumRedirection 0 -ErrorAction Stop
        $f.Http = if ([string]$w.Content -match 'Microsoft Connect Test') { 'ok' } else { 'portal' }
    } catch {
        $resp = $_.Exception.Response
        if ($resp -and [int]$resp.StatusCode -ge 300 -and [int]$resp.StatusCode -lt 400) { $f.Http = 'portal' }
    }
    # 5. DNS
    Set-JobProgress 0.55 'DNS'
    $f.DnsMs = -1; $f.DnsSlow = $false; $f.DnsOk = $false
    $servers = @()
    if ($a) { $servers = @((Get-DnsClientServerAddress -InterfaceIndex $a.Index -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses) }
    if ($a -and $servers.Count) {
        $parts = @()
        foreach ($s in ($servers | Select-Object -First 2)) {
            $ms = Measure-DnsServer $s
            $parts += $s + ' - ' + $(if ($ms -ge 0) { [string]$ms + ' мс' } else { 'не отвечает' })
            if ($ms -ge 0 -and ($f.DnsMs -lt 0 -or $ms -lt $f.DnsMs)) { $f.DnsMs = $ms }
        }
        $ref = if ($servers -notcontains '1.1.1.1') { Measure-DnsServer '1.1.1.1' } else { -1 }
        if ($ref -ge 0) { $parts += 'для сравнения Cloudflare 1.1.1.1 - ' + $ref + ' мс' }
        $f.DnsOk = $f.DnsMs -ge 0
        $f.DnsSlow = $f.DnsOk -and $f.DnsMs -gt 250 -and ($ref -lt 0 -or $ref * 3 -lt $f.DnsMs)
        $st = if (-not $f.DnsOk) { 'bad' } elseif ($f.DnsSlow) { 'warn' } else { 'ok' }
        & $add 'dns' 'DNS' $st ($parts -join ' · ') $(if (-not $f.DnsOk) { 'Не отвечает' } elseif ($f.DnsSlow) { 'Медленно' } else { [string]$f.DnsMs + ' мс' })
    } elseif ($a) { & $add 'dns' 'DNS' 'bad' 'DNS-серверы не заданы' 'Нет' }
    else { & $add 'dns' 'DNS' 'na' 'пропущено' '—' }
    # интернет-шаг пишем после DNS - так понятнее вердикт
    switch ($f.Http) {
        'ok' { & $add 'net' 'Интернет' 'ok' 'проверка Microsoft пройдена, внешние серверы отвечают' 'Есть' }
        'portal' { & $add 'net' 'Интернет' 'warn' 'сеть просит войти (страница входа гостиницы, кафе, провайдера)' 'Нужен вход' }
        default {
            if ($f.IpNet -and -not $f.DnsOk) { & $add 'net' 'Интернет' 'warn' 'серверы по IP отвечают, но имена сайтов не открываются - виноват DNS' 'Частично' }
            elseif ($f.IpNet) { & $add 'net' 'Интернет' 'warn' 'серверы по IP отвечают, но сайты не открываются (прокси, hosts, фильтр)' 'Частично' }
            else { & $add 'net' 'Интернет' 'bad' $(if ($a) { 'за роутером интернета нет' } else { 'нет подключения' }) 'Нет' }
        }
    }
    # 6. Качество
    Set-JobProgress 0.7 'Качество связи'
    $f.Quality = 'na'
    if ($f.IpNet) {
        $q = Invoke-NetPing -Target '1.1.1.1' -Count 20 -Timeout 1000
        $f.Q = $q
        $st = if ($q.Loss -ge 10 -or $q.Avg -gt 250) { 'bad' } elseif ($q.Loss -gt 0 -or $q.Jitter -gt 30 -or $q.Avg -gt 120) { 'warn' } else { 'ok' }
        $f.Quality = $st
        & $add 'quality' 'Качество связи' $st ('задержка ' + $q.Avg + ' мс · разброс ' + $q.Jitter + ' мс · потери ' + $q.Loss + '%') $(switch ($st) { 'ok' { 'Хорошо' } 'warn' { 'Средне' } default { 'Плохо' } })
    } else { & $add 'quality' 'Качество связи' 'na' 'пропущено - нет интернета' '—' }
    # 7. Wi-Fi
    Set-JobProgress 0.82 'Wi-Fi'
    $f.WifiWeak = $false
    if ($a -and $a.Wireless) {
        $wf = Get-WifiState
        if ($wf.Signal -ge 0) {
            $band = if ($wf.Channel -gt 14) { '5 ГГц' } elseif ($wf.Channel -gt 0) { '2,4 ГГц' } else { '' }
            $d = [string]$wf.Signal + '%' + $(if ($wf.Ssid) { ' · ' + $wf.Ssid }) + $(if ($wf.Channel) { ' · канал ' + $wf.Channel + ' (' + $band + ')' }) + $(if ($wf.Radio) { ' · ' + $wf.Radio })
            if ($wf.Neighbors -ge 4) { $d += ' · на этом канале ещё ' + $wf.Neighbors + ' сетей' }
            $st = if ($wf.Signal -lt 40) { 'bad' } elseif ($wf.Signal -lt 65 -or $wf.Neighbors -ge 6) { 'warn' } else { 'ok' }
            $f.WifiWeak = $st -ne 'ok'; $f.Wifi = $wf
            & $add 'wifi' 'Wi-Fi сигнал' $st $d $(switch ($st) { 'ok' { 'Сильный' } 'warn' { 'Средний' } default { 'Слабый' } })
        } else { & $add 'wifi' 'Wi-Fi сигнал' 'na' 'драйвер не сообщает уровень сигнала' 'нет данных' }
    } elseif ($a) { & $add 'wifi' 'Wi-Fi сигнал' 'na' 'подключение по кабелю - проверка не нужна' '—' }
    # 8. Прокси и hosts
    Set-JobProgress 0.92 'Прокси и hosts'
    $px = Get-ProxyState
    $hs = Get-HostsReport
    $f.Proxy = $px; $f.Hosts = $hs
    $d = @(); $st = 'ok'
    if ($px.On) { $d += 'включён прокси ' + $px.Server; $st = 'warn' }
    if ($px.Pac) { $d += 'скрипт прокси ' + $px.Pac; $st = 'warn' }
    if ($hs.Danger.Count) { $d += 'hosts подменяет: ' + (($hs.Danger | Select-Object -First 3) -join ', '); $st = 'bad' }
    if ($hs.Redirect.Count) { $d += 'hosts перенаправляет ' + $hs.Redirect.Count + ' адрес(ов)'; if ($st -eq 'ok') { $st = 'warn' } }
    if ($hs.Block) { $d += 'hosts блокирует ' + $hs.Block + ' адрес(ов) - обычно это блокировка рекламы' }
    if (-not $d.Count) { $d += 'прокси выключен, в hosts нет посторонних записей' }
    & $add 'proxy' 'Прокси и hosts' $st ($d -join ' · ') $(switch ($st) { 'ok' { 'Чисто' } 'warn' { 'Проверьте' } default { 'Подмена' } })
    # Вердикт
    $v = @{ Kind = 'ok'; Title = 'Всё в порядке'; Sub = 'Подключение работает без проблем.'; Fix = ''; FixText = '' }
    if (-not $a) {
        $v = @{ Kind = 'bad'; Title = 'Нет подключения к сети'; Sub = $f.AdapterWhy + '. Проверьте кабель или подключитесь к Wi-Fi.'; Fix = $(if ($f.AnyDisabled) { 'adapter' } else { '' }); FixText = 'Включить адаптер' }
    } elseif (-not $f.IpOk) {
        $v = @{ Kind = 'bad'; Title = 'Роутер не выдал адрес'; Sub = 'Попробуйте получить адрес заново. Не помогло - перезагрузите роутер (выключить на 30 секунд).'; Fix = 'renew'; FixText = 'Получить адрес заново' }
    } elseif ($f.Http -eq 'portal') {
        $v = @{ Kind = 'warn'; Title = 'Сеть просит войти'; Sub = 'Это сеть гостиницы, кафе или провайдера со страницей входа. Откройте её и войдите.'; Fix = 'portal'; FixText = 'Открыть страницу входа' }
    } elseif ($hs.Danger.Count) {
        $v = @{ Kind = 'bad'; Title = 'Файл hosts подменяет известные сайты'; Sub = 'Так делают вирусы: блокируют антивирусы и обновления или подсовывают поддельные сайты.'; Fix = 'hosts'; FixText = 'Восстановить hosts' }
    } elseif ($f.Http -ne 'ok' -and ($px.On -or $px.Pac)) {
        $v = @{ Kind = 'bad'; Title = 'Сайты не открываются из-за прокси'; Sub = 'Включён прокси-сервер, который не отвечает. Его часто оставляют VPN-программы и рекламное ПО.'; Fix = 'proxy'; FixText = 'Сбросить прокси' }
    } elseif (-not $f.IpNet -and $f.Http -ne 'ok') {
        $v = @{ Kind = 'bad'; Title = $(if ($f.GwOk) { 'Роутер работает, но интернета за ним нет' } else { 'Нет связи с интернетом' }); Sub = 'Перезагрузите роутер. Если не поможет - проблема у провайдера (проверьте оплату, позвоните в поддержку).'; Fix = 'adapter'; FixText = 'Перезапустить адаптер' }
    } elseif (-not $f.DnsOk) {
        $v = @{ Kind = 'bad'; Title = 'Не работает DNS - сайты не открываются по имени'; Sub = 'Интернет есть, но DNS-сервер провайдера не отвечает. Поможет надёжный DNS Cloudflare.'; Fix = 'dns'; FixText = 'Включить Cloudflare DNS' }
    } elseif ($f.Http -ne 'ok') {
        $v = @{ Kind = 'warn'; Title = 'Сайты открываются не все'; Sub = 'Интернет по IP работает, но проверка сайта не прошла. Попробуйте сбросить кэш DNS и Winsock.'; Fix = 'flush'; FixText = 'Сбросить кэш DNS' }
    } elseif ($f.DnsSlow) {
        $v = @{ Kind = 'warn'; Title = 'Интернет есть, но сайты открываются с задержкой'; Sub = 'DNS провайдера отвечает за ' + $f.DnsMs + ' мс. DNS Cloudflare ускорит открытие сайтов.'; Fix = 'dns'; FixText = 'Включить Cloudflare DNS' }
    } elseif ($f.Quality -eq 'bad' -or $f.Quality -eq 'warn') {
        $v = @{ Kind = 'warn'; Title = 'Связь нестабильная'; Sub = ('Потери ' + $f.Q.Loss + '%, разброс задержки ' + $f.Q.Jitter + ' мс.' + $(if ($f.WifiWeak) { ' Причина, скорее всего, в Wi-Fi: подойдите ближе к роутеру или подключитесь к сети 5 ГГц.' } else { ' Возможна перегрузка канала у провайдера или роутера.' })); Fix = ''; FixText = '' }
    } elseif ($f.WifiWeak) {
        $v = @{ Kind = 'warn'; Title = 'Слабый Wi-Fi'; Sub = 'Интернет работает, но сигнал слабый или канал занят соседями. Подойдите ближе к роутеру или смените канал в его настройках.'; Fix = ''; FixText = '' }
    } elseif ($px.On -or $px.Pac -or $hs.Redirect.Count) {
        $v = @{ Kind = 'warn'; Title = 'Интернет работает, но есть что проверить'; Sub = 'Включён прокси или hosts перенаправляет адреса. Если вы это не настраивали - сбросьте.'; Fix = $(if ($px.On -or $px.Pac) { 'proxy' } else { 'hosts' }); FixText = $(if ($px.On -or $px.Pac) { 'Сбросить прокси' } else { 'Восстановить hosts' }) }
    }
    Add-History -Kind 'network' -Name ('Диагностика сети: ' + $v.Title) -Result $(if ($v.Kind -eq 'ok') { 'ok' } else { 'warn' })
    return @{ Steps = @($steps); Verdict = $v; Time = Get-Date }
}

# ---------- Фон: исправления ----------

function Invoke-NetFix {
    param([string]$Id)
    switch ($Id) {
        'flush' {
            Clear-DnsClientCache -ErrorAction SilentlyContinue
            Write-Log 'Кэш DNS очищен' 'ok'
        }
        'adapter' {
            $a = Get-ActiveNetAdapter
            if ($a) {
                Write-Log ('Перезапускаю «' + $a.Name + '» - связь пропадёт на несколько секунд...')
                Restart-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction Stop
            } else {
                foreach ($x in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Disabled' })) {
                    Write-Log ('Включаю «' + $x.Name + '»')
                    Enable-NetAdapter -Name $x.Name -Confirm:$false -ErrorAction SilentlyContinue
                }
            }
            Start-Sleep -Seconds 6
            Write-Log 'Адаптер перезапущен' 'ok'
        }
        'renew' {
            $ipc = Join-Path $env:WINDIR 'System32\ipconfig.exe'
            Write-Log 'Отпускаю адрес и прошу новый у роутера...'
            [void](Invoke-ProcessLive -FilePath $ipc -Arguments '/release' -TimeoutSec 60 -Quiet)
            $r = Invoke-ProcessLive -FilePath $ipc -Arguments '/renew' -TimeoutSec 90 -Quiet
            Write-Log $(if ($r.Code -eq 0) { 'Адрес получен заново' } else { 'Роутер не ответил на запрос адреса' }) $(if ($r.Code -eq 0) { 'ok' } else { 'warn' })
            Start-Sleep -Seconds 2
        }
        'proxy' {
            $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
            $p = Get-ProxyState
            Set-ItemProperty -LiteralPath $k -Name ProxyEnable -Value 0 -Type DWord -ErrorAction Stop
            Remove-ItemProperty -LiteralPath $k -Name ProxyServer -ErrorAction SilentlyContinue
            Remove-ItemProperty -LiteralPath $k -Name AutoConfigURL -ErrorAction SilentlyContinue
            [void](Invoke-ProcessLive -FilePath (Join-Path $env:WINDIR 'System32\netsh.exe') -Arguments 'winhttp reset proxy' -TimeoutSec 30 -Quiet)
            Write-Log ('Прокси сброшен' + $(if ($p.Server) { ' (был ' + $p.Server + ')' } else { '' })) 'ok'
            Add-History -Kind 'network' -Name 'Сброшен прокси' -Detail ('ProxyServer=' + $p.Server + '; AutoConfigURL=' + $p.Pac)
            return
        }
        'hosts' {
            $path = Join-Path $env:WINDIR 'System32\drivers\etc\hosts'
            if (-not (Test-Path -LiteralPath $BackupFolder)) { New-Item -ItemType Directory -Path $BackupFolder -Force -ErrorAction Stop | Out-Null }
            $bk = Join-Path $BackupFolder ('hosts-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
            Copy-Item -LiteralPath $path -Destination $bk -Force -ErrorAction Stop
            try { (Get-Item -LiteralPath $path -ErrorAction Stop).Attributes = 'Normal' } catch {}
            $txt = "# Стандартный файл hosts Windows (восстановлен PotatoPC $(Get-Date -Format 'dd.MM.yyyy')).`r`n# Прежняя версия: $bk`r`n#`r`n# localhost name resolution is handled within DNS itself.`r`n#`t127.0.0.1       localhost`r`n#`t::1             localhost`r`n"
            [System.IO.File]::WriteAllText($path, $txt, (New-Object System.Text.UTF8Encoding $false))
            Clear-DnsClientCache -ErrorAction SilentlyContinue
            Write-Log ('hosts восстановлен, копия: ' + $bk) 'ok'
            Add-History -Kind 'network' -Name 'Восстановлен файл hosts' -Ref $bk
            return
        }
        'winsock' {
            $ns = Join-Path $env:WINDIR 'System32\netsh.exe'
            [void](Invoke-ProcessLive -FilePath $ns -Arguments 'winsock reset' -TimeoutSec 60)
            [void](Invoke-ProcessLive -FilePath $ns -Arguments 'int ip reset' -TimeoutSec 60)
            Write-Log 'Winsock и TCP/IP сброшены - нужна перезагрузка' 'warn'
        }
        'dns' {
            Set-NetDnsServers -V4 @('1.1.1.2', '1.0.0.2') -Name 'Cloudflare (защита от вредоносных сайтов)'
            return
        }
    }
    Add-History -Kind 'network' -Name ('Сеть: ' + $(switch ($Id) { 'flush' { 'сброс кэша DNS' } 'adapter' { 'перезапуск адаптера' } 'renew' { 'новый адрес от роутера' } 'winsock' { 'сброс Winsock и TCP/IP' } default { $Id } }))
}

function Set-NetDnsServers {
    param([string[]]$V4 = @(), [string]$Name = '')
    foreach ($a in @(Get-DnsState)) {
        if ($V4.Count) { Set-DnsClientServerAddress -InterfaceIndex $a.Index -ServerAddresses $V4 -ErrorAction Stop }
        else { Set-DnsClientServerAddress -InterfaceIndex $a.Index -ResetServerAddresses -ErrorAction Stop }
        Write-Log ('DNS для «' + $a.Name + '»: ' + $Name) 'ok'
    }
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    Add-History -Kind 'network' -Name ('DNS: ' + $Name)
}

# ---------- Фон: сведения ----------

function Get-NetAdaptersInfo {
    $out = @()
    foreach ($a in @(Get-NetAdapter -ErrorAction SilentlyContinue | Sort-Object { $_.Status -ne 'Up' }, Name)) {
        $ip = @(Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.IPAddress })
        $out += @{ Name = [string]$a.Name; Desc = [string]$a.InterfaceDescription; Status = [string]$a.Status; Speed = [string]$a.LinkSpeed; Mac = [string]$a.MacAddress; Ip = ($ip -join ', '); Virtual = -not $a.HardwareInterface }
    }
    return , $out
}

function Get-WifiProfiles {
    $out = @()
    foreach ($p in (Get-NetshFields 'wlan show profiles')) {
        if ($p[0] -notmatch '(?i)profile|профил') { continue }
        $name = $p[1]
        if (-not $name) { continue }
        $f = Get-NetshFields ('wlan show profile name="' + ($name -replace '"', '') + '" key=clear')
        $auth = ''; $key = ''
        foreach ($x in $f) {
            if ($x[0] -match '(?i)^(authentication|проверка подлинности)$' -and -not $auth) { $auth = $x[1] }
            elseif ($x[0] -match '(?i)key content|содержимое ключа') { $key = $x[1] }
        }
        $out += @{ Name = $name; Auth = $auth; Key = $key }
    }
    return , $out
}

# ---------- Кто сейчас в сети ----------

$script:NetKnownPorts = @{ 135 = 'служба Windows (RPC)'; 139 = 'общий доступ (NetBIOS)'; 445 = 'общий доступ к файлам'; 3389 = 'удалённый рабочий стол'; 5357 = 'обнаружение устройств в сети'; 5040 = 'служба Windows'; 7680 = 'раздача обновлений Windows'; 27036 = 'Steam: игры по локальной сети'; 5900 = 'удалённый доступ (VNC)'; 22 = 'SSH'; 21 = 'FTP'; 80 = 'веб-сервер'; 443 = 'веб-сервер'; 1900 = 'UPnP' }
$script:NetCriticalProcs = @('System', 'Idle', 'svchost', 'lsass', 'csrss', 'wininit', 'winlogon', 'services', 'smss', 'spoolsv', 'dwm', 'explorer', 'MsMpEng', 'NisSrv', 'powershell', 'pwsh')

function Get-NetBlockId {
    # Имя правила брандмауэра для программы: одно и то же для одного пути.
    param([string]$Path)
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $h = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Path.ToLowerInvariant()))
    return 'PotatoPC-block-' + (([BitConverter]::ToString($h)).Replace('-', '').Substring(0, 12))
}

function Get-NetWhoOnline {
    # Фон. Программы с соединениями и открытыми портами. $Cache - общий словарь между обновлениями
    # (подписи файлов и список служб: их проверка дорогая, а меняются они редко).
    param($Cache)
    if (-not $Cache) { $Cache = @{} }
    $dns = @{}
    try {
        foreach ($e in @(Get-DnsClientCache -ErrorAction Stop)) {
            if (($e.Type -eq 1 -or $e.Type -eq 28) -and $e.Data -and -not $dns.ContainsKey([string]$e.Data)) { $dns[[string]$e.Data] = [string]$e.Entry }
        }
    } catch {}
    $now = Get-Date
    if (-not $Cache['SvcTime'] -or ($now - $Cache['SvcTime']).TotalSeconds -gt 30) {
        $svc = @{}
        try {
            foreach ($s in @(Get-CimInstance Win32_Service -Filter "State='Running'" -ErrorAction Stop)) {
                $k = [string]$s.ProcessId
                if (-not $svc.ContainsKey($k)) { $svc[$k] = @() }
                $svc[$k] += [string]$s.DisplayName
            }
        } catch {}
        $Cache['Svc'] = $svc; $Cache['SvcTime'] = $now
    }
    $svc = $Cache['Svc']
    $tcp = @(Get-NetTCPConnection -ErrorAction SilentlyContinue)
    $byPid = @{}
    foreach ($c in $tcp) {
        $st = [string]$c.State
        $isEst = $st -eq 'Established' -and [string]$c.RemoteAddress -notmatch '^(127\.|::1$|0\.0\.0\.0$|::$)'
        $isLis = $st -eq 'Listen' -and [string]$c.LocalAddress -notmatch '^(127\.|::1$)'
        if (-not $isEst -and -not $isLis) { continue }
        $k = [int]$c.OwningProcess
        if (-not $byPid.ContainsKey($k)) { $byPid[$k] = @{ Est = 0; Hosts = New-Object System.Collections.ArrayList; Ports = New-Object System.Collections.ArrayList; Listen = New-Object System.Collections.ArrayList } }
        $x = $byPid[$k]
        if ($isEst) {
            $x.Est++
            $ip = [string]$c.RemoteAddress
            $h = if ($dns.ContainsKey($ip)) { $dns[$ip] } else { $ip }
            if (-not $x.Hosts.Contains($h)) { [void]$x.Hosts.Add($h) }
            $rp = [int]$c.RemotePort
            if (-not $x.Ports.Contains($rp)) { [void]$x.Ports.Add($rp) }
        } else {
            $lp = [int]$c.LocalPort
            if (-not $x.Listen.Contains($lp)) { [void]$x.Listen.Add($lp) }
        }
    }
    if (-not $Cache.ContainsKey('Sig')) { $Cache['Sig'] = @{} }
    $sig = $Cache['Sig']
    # Проверка подписи файла бывает долгой (до секунды-двух на файл), поэтому за одно обновление
    # проверяем сколько успеем примерно за 1.5 с, остальное - при следующих обновлениях.
    # Самый первый проход - без проверки подписей, чтобы список появился сразу.
    $sigWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $sigBudget = if ($Cache['Pass']) { 1500 } else { 0 }
    $Cache['Pass'] = [int]$Cache['Pass'] + 1
    $win = $env:WINDIR.TrimEnd('\') + '\'
    $out = @()
    foreach ($k in $byPid.Keys) {
        $x = $byPid[$k]
        $name = ''; $path = ''
        if ($k -eq 4) { $name = 'System' } elseif ($k -eq 0) { $name = 'Idle' }
        else {
            $pr = Get-Process -Id $k -ErrorAction SilentlyContinue
            if ($pr) { $name = [string]$pr.ProcessName; try { $path = [string]$pr.Path } catch {} } else { $name = 'PID ' + $k }
        }
        $signed = $null; $signer = ''
        if ($path) {
            if (-not $sig.ContainsKey($path) -and $sigWatch.ElapsedMilliseconds -lt $sigBudget) {
                $v = @{ Ok = $null; By = '' }
                try {
                    $a = Get-AuthenticodeSignature -FilePath $path -ErrorAction Stop
                    $v.Ok = ([string]$a.Status -eq 'Valid')
                    if ($a.SignerCertificate) { if ([string]$a.SignerCertificate.Subject -match 'CN="?([^",]+)') { $v.By = $Matches[1] } }
                } catch {}
                $sig[$path] = $v
            }
            if ($sig.ContainsKey($path)) { $signed = $sig[$path].Ok; $signer = $sig[$path].By }
        }
        $services = if ($svc.ContainsKey([string]$k)) { @($svc[[string]$k]) } else { @() }
        $out += @{
            Pid = $k; Name = $name; Path = $path; Signed = $signed; Signer = $signer; Services = $services
            Est = $x.Est; Hosts = @($x.Hosts); Ports = @($x.Ports | Sort-Object); Listen = @($x.Listen | Sort-Object)
            IsWindows = (-not $path) -or $path.StartsWith($win, [StringComparison]::OrdinalIgnoreCase)
        }
    }
    # Правила брандмауэра PotatoPC перечитываются раз в 30 с (или сразу после запрета/разрешения).
    if (-not $Cache['FwTime'] -or ($now - $Cache['FwTime']).TotalSeconds -gt 30) {
        $bl = @()
        try {
            foreach ($r in @(Get-NetFirewallRule -Group 'PotatoPC' -ErrorAction Stop | Where-Object { $_.Name -like 'PotatoPC-block-*' -and $_.Name -notlike '*-in' })) {
                $bl += @{ Id = [string]$r.Name; Path = [string]$r.Description; Name = [System.IO.Path]::GetFileNameWithoutExtension([string]$r.Description) }
            }
        } catch {}
        $Cache['Fw'] = $bl; $Cache['FwTime'] = $now
    }
    $blocked = @($Cache['Fw'])
    return @{ Items = @($out | Sort-Object { - $_.Est }, { $_.Name }); Blocked = $blocked; Time = $now }
}

function Add-NetAppBlock {
    # Фон. Запрет доступа в сеть для программы: два правила брандмауэра (исходящие и входящие).
    param([string]$Path, [string]$Name)
    $id = Get-NetBlockId -Path $Path
    try {
        Remove-NetFirewallRule -Name $id, ($id + '-in') -ErrorAction SilentlyContinue
        New-NetFirewallRule -Name $id -DisplayName ('PotatoPC: запрет сети - ' + $Name) -Group 'PotatoPC' -Description $Path -Direction Outbound -Program $Path -Action Block -Profile Any -ErrorAction Stop | Out-Null
        New-NetFirewallRule -Name ($id + '-in') -DisplayName ('PotatoPC: запрет сети - ' + $Name) -Group 'PotatoPC' -Description $Path -Direction Inbound -Program $Path -Action Block -Profile Any -ErrorAction Stop | Out-Null
        Write-Log ('Запрещён доступ в интернет: ' + $Name + ' (' + $Path + ')') 'ok'
        Add-History -Kind 'firewall' -Name ('Запрещён доступ в интернет: ' + $Name) -Detail $Path -Ref $id
        return $true
    } catch {
        Write-Log ('Не удалось запретить доступ: ' + $_.Exception.Message) 'err'
        Add-History -Kind 'firewall' -Name ('Запрет доступа в интернет: ' + $Name) -Result 'error' -Detail $_.Exception.Message
        return $false
    }
}

function Remove-NetAppBlock {
    param([string]$Id)
    $r = Get-NetFirewallRule -Name $Id -ErrorAction SilentlyContinue
    $name = if ($r) { [System.IO.Path]::GetFileNameWithoutExtension([string]$r.Description) } else { $Id }
    Remove-NetFirewallRule -Name $Id, ($Id + '-in') -ErrorAction SilentlyContinue
    Write-Log ('Доступ в интернет снова разрешён: ' + $name) 'ok'
    Add-History -Kind 'firewall' -Name ('Доступ в интернет снова разрешён: ' + $name)
    return $true
}

# ---------- Интерфейс ----------

function Build-Page_network {
    $ui = @{ Tab = 'who'; TracePick = 'google.com' }
    $script:NetUi = $ui
    $diag = New-Button -Text 'Запустить диагностику' -Icon 'play' -OnClick { Start-NetDiagnostics }
    $ui.DiagBtn = $diag
    $refresh = New-Button -Text 'Обновить' -Icon 'refresh' -Kind Ghost -ToolTip 'Перечитать DNS и сведения внизу страницы' -OnClick { Update-NetDns; Update-NetInfoTab }
    $L = New-PageLayout -Title 'Сеть' -Subtitle 'Скорость, диагностика подключения и исправление неполадок' -HeaderRight @($refresh, $diag)

    # Спидтест
    $ui.Ring = New-ScoreRing -Size 96 -Thickness 9
    $ui.Ring.Tag.Num.Text = '—'
    $ui.Ring.Children[2].Children[1].Text = 'Мбит/с'
    $mk = {
        param($Label)
        $sp = New-Stack -Margin (0, 0, 18, 0)
        [void]$sp.Children.Add((New-Text -Text $Label -Size 12 -Color 'Muted'))
        $val = New-Text -Text '—' -Size 28 -Weight 'Bold'
        [void]$sp.Children.Add($val)
        $sub = New-Text -Text '' -Size 11 -Color 'Muted'
        [void]$sp.Children.Add($sub)
        return @{ Root = $sp; Value = $val; Sub = $sub }
    }
    $ui.SDown = & $mk 'Загрузка, Мбит/с'
    $ui.SUp = & $mk 'Отдача, Мбит/с'
    $ui.SPing = & $mk 'Пинг, мс'
    $ui.SJit = & $mk 'Разброс, мс'
    $nums = New-Object System.Windows.Controls.Primitives.UniformGrid
    $nums.Columns = 4; $nums.VerticalAlignment = 'Center'; $nums.Margin = New-Thickness 22, 0, 10, 0
    foreach ($x in @($ui.SDown, $ui.SUp, $ui.SPing, $ui.SJit)) { [void]$nums.Children.Add($x.Root) }
    $ui.SpeedBtn = New-Button -Text 'Измерить скорость' -Icon 'gauge' -Kind Primary -OnClick { Start-SpeedTest }
    $ui.SpeedInfo = New-Text -Text 'Замер через серверы Cloudflare, около 20 секунд' -Size 11 -Color 'Muted' -Margin (0, 8, 0, 0)
    $ui.SpeedInfo.HorizontalAlignment = 'Right'
    $rs = New-Stack -Children @($ui.SpeedBtn, $ui.SpeedInfo)
    $rs.VerticalAlignment = 'Center'
    $dp = New-Object System.Windows.Controls.DockPanel
    [System.Windows.Controls.DockPanel]::SetDock($ui.Ring, 'Left'); [void]$dp.Children.Add($ui.Ring)
    [System.Windows.Controls.DockPanel]::SetDock($rs, 'Right'); [void]$dp.Children.Add($rs)
    [void]$dp.Children.Add($nums)
    [void]$L.Body.Children.Add((New-Card -Child $dp -Padding (20, 16, 20, 16) -Margin (0, 0, 0, 16)))
    $last = Get-Setting 'NetSpeed'
    if ($last) { try { Set-SpeedResult -R $last -Old } catch {} }

    # Вердикт (появляется после диагностики)
    $ui.VIcon = New-Icon -Name 'warn' -Size 22 -Color 'Warn'
    $ui.VTitle = New-Text -Text '' -Size 15 -Weight 'Bold'
    $ui.VSub = New-Text -Text '' -Size 13 -Color 'Muted' -Wrap -Margin (0, 3, 0, 0)
    $ui.VFix = New-Button -Text 'Исправить' -Kind Primary -OnClick { Start-NetFix -Id $this.Tag }
    $vd = New-Object System.Windows.Controls.DockPanel
    [System.Windows.Controls.DockPanel]::SetDock($ui.VIcon, 'Left'); $ui.VIcon.Margin = New-Thickness 0, 0, 14, 0; [void]$vd.Children.Add($ui.VIcon)
    [System.Windows.Controls.DockPanel]::SetDock($ui.VFix, 'Right'); $ui.VFix.Margin = New-Thickness 14, 0, 0, 0; $ui.VFix.VerticalAlignment = 'Center'; [void]$vd.Children.Add($ui.VFix)
    [void]$vd.Children.Add((New-Stack -Children @($ui.VTitle, $ui.VSub)))
    $ui.Verdict = New-Card -Child $vd -Padding (16, 14, 16, 14) -Margin (0, 0, 0, 16)
    $ui.Verdict.Visibility = 'Collapsed'
    [void]$L.Body.Children.Add($ui.Verdict)

    # Шаги + быстрые исправления
    $ui.Steps = New-Section -Title 'Проверка по шагам' -Margin (0, 0, 0, 0)
    $ui.StepsTime = New-Text -Text '' -Size 12 -Color 'Muted'
    [void]$ui.Steps.Right.Children.Add($ui.StepsTime)
    [void]$ui.Steps.Body.Children.Add((New-Placeholder 'Нажмите «Запустить диагностику» - проверю адаптер, роутер, DNS, интернет, качество связи, Wi-Fi, прокси и hosts.'))
    $ui.Steps.Body.Children[0].TextWrapping = 'Wrap'
    $fx = New-Stack -Margin (14, 12, 14, 12)
    [void]$fx.Children.Add((New-Text -Text 'Быстрые исправления' -Size 14 -Weight 'Bold' -Margin (2, 0, 0, 8)))
    $fixes = @(
        @('flush', 'refresh', 'Сбросить кэш DNS', 'мгновенно'),
        @('adapter', 'wifi', 'Перезапустить адаптер', 'связь пропадёт на ~10 сек'),
        @('renew', 'globe', 'Получить адрес заново', 'release / renew'),
        @('proxy', 'shield', 'Сбросить прокси', 'если сайты не открываются'),
        @('hosts', 'save', 'Восстановить hosts', 'старый сохраняется копией'),
        @('winsock', 'wrench', 'Сброс Winsock и TCP/IP', 'нужна перезагрузка')
    )
    $ui.FixBtns = @()
    foreach ($f in $fixes) {
        $b = New-Button -Kind Secondary -Tag $f[0] -OnClick { Start-NetFix -Id $this.Tag }
        $b.HorizontalContentAlignment = 'Left'
        $b.Margin = New-Thickness 0, 0, 0, 8
        $row = New-Stack -Orientation Horizontal
        [void]$row.Children.Add((New-Icon -Name $f[1] -Size 17 -Color 'Accent'))
        [void]$row.Children.Add((New-Stack -Margin (10, 0, 0, 0) -Children @((New-Text -Text $f[2] -Size 13 -Weight 'SemiBold'), (New-Text -Text $f[3] -Size 11 -Color 'Muted'))))
        $b.Content = $row
        [void]$fx.Children.Add($b)
        $ui.FixBtns += $b
    }
    [void]$fx.Children.Add((New-Text -Text 'Все действия пишутся в «Историю».' -Size 11 -Color 'Muted' -Margin (2, 0, 0, 0)))
    $fxCard = New-Card -Child $fx -Padding 0
    $grid = New-Object System.Windows.Controls.Grid
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = New-Object System.Windows.GridLength 1.6, 'Star'
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength 14
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength 1, 'Star'
    foreach ($c in @($c0, $c1, $c2)) { [void]$grid.ColumnDefinitions.Add($c) }
    $ui.Steps.Root.VerticalAlignment = 'Top'; $fxCard.VerticalAlignment = 'Top'
    [void]$grid.Children.Add($ui.Steps.Root)
    [System.Windows.Controls.Grid]::SetColumn($fxCard, 2); [void]$grid.Children.Add($fxCard)
    $grid.Margin = New-Thickness 0, 0, 0, 16
    [void]$L.Body.Children.Add($grid)

    # DNS
    $ui.DnsSec = New-Section -Title 'DNS'
    $ui.DnsSec.Right.Children.Add((New-Text -Text 'защита от вредоносных сайтов и рекламы' -Size 12 -Color 'Muted')) | Out-Null
    [void]$ui.DnsSec.Body.Children.Add((New-Placeholder))
    [void]$L.Body.Children.Add($ui.DnsSec.Root)

    # Сведения
    $ui.Info = New-Section -Title 'Сведения'
    $tabs = New-Object System.Windows.Controls.WrapPanel
    $tabs.Margin = New-Thickness 16, 0, 16, 8
    $ui.Tabs = @{}
    New-NetWhoSection
    foreach ($t in @(@('who', 'Кто в сети'), @('adapters', 'Адаптеры'), @('wifi', 'Сохранённые Wi-Fi'), @('trace', 'Трассировка'))) {
        $b = New-Button -Text $t[1] -Kind Chip -Tag $t[0] -OnClick { $script:NetUi.Tab = $this.Tag; Update-NetInfoTab }
        $ui.Tabs[$t[0]] = $b
        [void]$tabs.Children.Add($b)
    }
    [void]$ui.Info.Body.Children.Add($tabs)
    $ui.InfoBody = New-Stack
    [void]$ui.Info.Body.Children.Add($ui.InfoBody)
    [void]$L.Body.Children.Add($ui.Info.Root)
    return $L.Root
}

function Show-Page_network {
    param($Arg)
    $ui = $script:NetUi
    if (-not $ui.Loaded) {
        $ui.Loaded = $true
        Update-NetDns
        Update-NetInfoTab
    }
    if ($ui.Tab -eq 'who') { Update-NetWho }
    if (-not $ui.WhoTimer) {
        # Живое обновление: только пока открыта страница «Сеть», не на паузе и не открыто меню «⋯».
        $ui.WhoTimer = New-Object System.Windows.Threading.DispatcherTimer
        $ui.WhoTimer.Interval = [TimeSpan]::FromSeconds(3)
        $ui.WhoTimer.Add_Tick({
            $ui = $script:NetUi
            if ($script:CurrentPage -ne 'network' -or $ui.Tab -ne 'who' -or $ui.WhoPaused -or $ui.WhoBusy -or $script:ActionMenuOpen) { return }
            if (-not $script:Window.IsActive) { return }
            Update-NetWho
        })
        $ui.WhoTimer.Start()
    }
}

# --- Кто сейчас в сети ---

function New-NetWhoSection {
    $ui = $script:NetUi
    $ui.WhoFilter = 'active'
    $ui.WhoCache = [hashtable]::Synchronized(@{})
    $live = New-Stack -Orientation Horizontal
    $live.VerticalAlignment = 'Center'
    $dot = New-Object System.Windows.Shapes.Ellipse; $dot.Width = 8; $dot.Height = 8; $dot.Fill = Get-Brush 'Ok'; $dot.VerticalAlignment = 'Center'
    [void]$live.Children.Add($dot)
    $ui.WhoLive = New-Text -Text 'обновляется каждые 3 с' -Size 12 -Color 'Ok' -Margin (6, 0, 12, 0)
    [void]$live.Children.Add($ui.WhoLive)
    $ui.WhoDot = $dot
    $pause = New-Button -Text 'Пауза' -Kind Small -OnClick {
        $ui = $script:NetUi
        $ui.WhoPaused = -not $ui.WhoPaused
        Set-ButtonText -Button $this -Text $(if ($ui.WhoPaused) { 'Продолжить' } else { 'Пауза' })
        $ui.WhoLive.Text = if ($ui.WhoPaused) { 'на паузе' } else { 'обновляется каждые 3 с' }
        $c = if ($ui.WhoPaused) { 'Muted' } else { 'Ok' }
        $ui.WhoLive.Foreground = Get-Brush $c; $ui.WhoDot.Fill = Get-Brush $c
        if (-not $ui.WhoPaused) { Update-NetWho }
    }
    # Живёт во вкладке «Сведения → Кто в сети»: панель создаётся один раз и подставляется при переключении.
    $panel = New-Stack
    $top = New-Object System.Windows.Controls.DockPanel
    $top.Margin = New-Thickness 16, 2, 12, 6
    $right = New-Stack -Orientation Horizontal -Children @($live, $pause)
    [System.Windows.Controls.DockPanel]::SetDock($right, 'Right'); [void]$top.Children.Add($right)
    $chips = New-Object System.Windows.Controls.WrapPanel
    $chips.VerticalAlignment = 'Center'
    $ui.WhoChips = @{}
    foreach ($f in @(@('active', 'Активные'), @('listen', 'Слушают порты'), @('all', 'Все'))) {
        $b = New-Button -Text $f[1] -Kind Chip -Tag $f[0] -OnClick { $script:NetUi.WhoFilter = [string]$this.Tag; Set-NetWho }
        $ui.WhoChips[$f[0]] = $b
        [void]$chips.Children.Add($b)
    }
    $ui.WhoStats = New-Text -Text '' -Size 12 -Color 'Muted' -Margin (8, 0, 0, 8)
    $ui.WhoStats.VerticalAlignment = 'Center'
    [void]$chips.Children.Add($ui.WhoStats)
    [void]$top.Children.Add($chips)
    [void]$panel.Children.Add($top)
    $ui.WhoBody = New-Stack
    [void]$ui.WhoBody.Children.Add((New-Placeholder))
    [void]$panel.Children.Add($ui.WhoBody)
    [void]$panel.Children.Add((New-Text -Text 'Запрет пишется правилом брандмауэра Windows и попадает в «Историю» - оттуда его можно снять одной кнопкой.' -Size 12 -Color 'Muted' -Wrap -Margin (16, 8, 16, 12)))
    $ui.WhoPanel = $panel
}

function Update-NetWho {
    $ui = $script:NetUi
    if ($ui.WhoBusy) { return }
    $ui.WhoBusy = $true
    Start-BgTask -Name 'Кто в сети' -Silent -Vars @{ C = $ui.WhoCache } -Script { Get-NetWhoOnline -Cache $C } -OnDone {
        param($r, $err)
        $ui = $script:NetUi
        $ui.WhoBusy = $false
        if (-not $r) { if ($err) { Write-Log ('Кто в сети: ' + $err) 'warn' }; return }
        $ui.WhoData = $r
        if (-not $script:ActionMenuOpen) { Set-NetWho }
    } | Out-Null
}

function Set-NetWho {
    $ui = $script:NetUi
    foreach ($k in $ui.WhoChips.Keys) { Set-ChipActive -Button $ui.WhoChips[$k] -Active ($k -eq $ui.WhoFilter) }
    $r = $ui.WhoData
    if (-not $r) { return }
    $all = @($r.Items)
    $apps = @($all | Where-Object { $_.Est -gt 0 })
    $conns = 0; foreach ($x in $apps) { $conns += $x.Est }
    $ports = 0; foreach ($x in $all) { $ports += @($x.Listen).Count }
    $uns = @($all | Where-Object { $_.Signed -eq $false }).Count
    $ui.WhoStats.Text = [string]$apps.Count + ' программ в сети · ' + $conns + ' соединений · ' + $ports + ' открытых портов' + $(if ($uns) { ' · без подписи: ' + $uns } else { '' })
    $list = switch ($ui.WhoFilter) { 'listen' { @($all | Where-Object { @($_.Listen).Count -gt 0 }) } 'all' { $all } default { $apps } }
    $b = $ui.WhoBody
    $b.Children.Clear()
    if (-not $list.Count) {
        [void]$b.Children.Add((New-Placeholder $(if ($ui.WhoFilter -eq 'listen') { 'Ни одна программа не ждёт подключений из сети.' } else { 'Сейчас ни одна программа не подключена к интернету.' })))
    }
    foreach ($x in $list) {
        $title = New-Stack -Orientation Horizontal
        $disp = $x.Name
        if ($x.Name -eq 'svchost' -and @($x.Services).Count) { $disp = 'Служба: ' + (@($x.Services)[0]) + $(if (@($x.Services).Count -gt 1) { ' и ещё ' + (@($x.Services).Count - 1) } else { '' }) }
        [void]$title.Children.Add((New-Text -Text $disp -Size 14 -Weight 'SemiBold'))
        if ($x.Signed -eq $false) {
            $bd = New-Badge 'без подписи' 'warn'; $bd.Margin = New-Thickness 8, 0, 0, 0
            $bd.ToolTip = 'У файла нет действующей цифровой подписи издателя. Само по себе это не вирус, но стоит проверить на VirusTotal (меню «⋯»).'
            [void]$title.Children.Add($bd)
        }
        $sub = @()
        if ($x.Est -gt 0) {
            $h = (@($x.Hosts) | Select-Object -First 4) -join ', '
            if (@($x.Hosts).Count -gt 4) { $h += ' и ещё ' + (@($x.Hosts).Count - 4) }
            $sub += $h
        }
        if (@($x.Listen).Count) {
            $lp = @($x.Listen | Select-Object -First 4 | ForEach-Object { if ($script:NetKnownPorts.ContainsKey([int]$_)) { [string]$_ + ' (' + $script:NetKnownPorts[[int]$_] + ')' } else { [string]$_ } })
            $sub += 'ждёт подключений: порт ' + ($lp -join ', ')
        }
        $meta = @()
        if ($x.Signer) { $meta += $x.Signer }
        if ($x.Path) { $meta += $x.Path }
        elseif ($x.Name -eq 'System') { $meta += 'ядро Windows' }
        elseif ($x.Name -ne 'svchost' -and @($x.Services).Count) { $meta += 'служба: ' + (@($x.Services) -join ', ') }
        else { $meta += 'путь к файлу недоступен' }
        $main = New-Stack
        [void]$main.Children.Add($title)
        [void]$main.Children.Add((New-Text -Text ($sub -join '  ·  ') -Size 12 -Color 'Text' -Margin (0, 2, 0, 0)))
        [void]$main.Children.Add((New-Text -Text ($meta -join '  ·  ') -Size 11 -Color 'Muted' -Margin (0, 1, 0, 0)))
        $right = @()
        if ($x.Est -gt 0) { $right += (New-Badge ([string]$x.Est + ' соедин.') 'info') }
        $more = New-Button -Text '⋯' -Kind Small -Tag $x -ToolTip 'Действия' -OnClick { Show-NetWhoMenu -Anchor $this -Item $this.Tag }
        $more.Padding = New-Thickness 10, 0, 10, 0
        $right += $more
        # Значок из exe программы; кэш - список перерисовывается каждые 3 секунды.
        if (-not $script:NetIconCache) { $script:NetIconCache = @{} }
        $png = $null
        if ($x.Path) {
            if (-not $script:NetIconCache.ContainsKey($x.Path)) { $script:NetIconCache[$x.Path] = ConvertTo-IconPng -Path $x.Path }
            $png = $script:NetIconCache[$x.Path]
        }
        $row = New-Row -Left (New-AppIcon -Name $x.Name -Png $png -Size 30) -Main $main -Right $right -Padding (16, 7, 12, 7)
        if ($x.Path) { $row.ToolTip = $x.Path + "`nPID " + $x.Pid }
        [void]$b.Children.Add($row)
    }
    # Программы, которым PotatoPC запретил сеть: они уже не в списке выше, поэтому - отдельно
    foreach ($bl in @($r.Blocked)) {
        $un = New-Button -Text 'Разрешить снова' -Kind Small -Tag $bl.Id -OnClick {
            $id = [string]$this.Tag
            Start-BgTask -Name 'Снятие запрета' -Vars @{ Id = $id } -Script { Remove-NetAppBlock -Id $Id } -OnDone { $script:NetUi.WhoCache['FwTime'] = $null; Update-NetWho } | Out-Null
        }
        [void]$b.Children.Add((New-Row -Left (New-IconTile -Icon 'ban' -Color 'Bad' -Size 30) -Main (New-TitleBlock -Title ($bl.Name + ' - доступ в интернет запрещён') -Sub $bl.Path) -Right @($un) -Padding (16, 7, 12, 7)))
    }
}

function Show-NetWhoMenu {
    param($Anchor, $Item)
    $items = @()
    $canTouch = $Item.Path -and -not $Item.IsWindows -and ($script:NetCriticalProcs -notcontains $Item.Name)
    if ($Item.Path) {
        $items += @{ Text = 'Открыть папку программы'; Tag = $Item; OnClick = { Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"' + $this.Tag.Path + '"') } }
        $items += @{ Text = 'Проверить на VirusTotal'; Tag = $Item; OnClick = {
            try {
                $h = (Get-FileHash -LiteralPath $this.Tag.Path -Algorithm SHA256 -ErrorAction Stop).Hash
                Start-Process ('https://www.virustotal.com/gui/file/' + $h)
            } catch { Write-Log ('Не удалось посчитать хэш файла: ' + $_.Exception.Message) 'warn' }
        } }
    }
    if ($canTouch) {
        $items += @{ Separator = $true }
        $items += @{ Text = 'Запретить доступ в интернет'; Tag = $Item; OnClick = {
            $x = $this.Tag
            if (-not (Show-Confirm -Message ('Запретить программе «' + $x.Name + '» доступ в интернет и локальную сеть?' + "`n`n" + $x.Path + "`n`nЗапрет снимается кнопкой «Разрешить снова» здесь или в «Истории».") -Title 'Запрет доступа')) { return }
            Start-BgTask -Name 'Запрет доступа' -Vars @{ P = $x.Path; N = $x.Name } -Script { Add-NetAppBlock -Path $P -Name $N } -OnDone { $script:NetUi.WhoCache['FwTime'] = $null; Update-NetWho } | Out-Null
        } }
        $items += @{ Text = 'Завершить программу'; Tag = $Item; Danger = $true; OnClick = {
            $x = $this.Tag
            if (-not (Show-Confirm -Message ('Завершить «' + $x.Name + '» (PID ' + $x.Pid + ')?' + "`n`nНесохранённые данные в этой программе пропадут.") -Title 'Завершить программу' -Warning)) { return }
            try {
                Stop-Process -Id $x.Pid -Force -ErrorAction Stop
                Write-Log ('Завершена программа ' + $x.Name + ' (PID ' + $x.Pid + ')') 'ok'
                Add-History -Kind 'network' -Name ('Завершена программа ' + $x.Name)
            } catch { Write-Log ('Не удалось завершить ' + $x.Name + ': ' + $_.Exception.Message) 'err' }
            Update-NetWho
        } }
    }
    if (-not $items.Count) { $items += @{ Text = 'Это часть Windows - действия недоступны'; Tag = $null } }
    Show-ActionMenu -Anchor $Anchor -Items $items
}

# --- Спидтест ---

function Initialize-PotatoNet {
    if ('PotatoNet' -as [type]) { return $true }
    try { Add-Type -TypeDefinition ([System.IO.File]::ReadAllText((Join-Path $AssetsFolder 'PotatoNet.cs'))) -ErrorAction Stop; return $true }
    catch { Write-Log ('Модуль замера скорости не загрузился: ' + $_.Exception.Message) 'err'; return $false }
}

function Start-SpeedTest {
    $ui = $script:NetUi
    if ($ui.SpeedRunning) { return }
    if (-not (Initialize-PotatoNet)) { return }
    [PotatoNet]::Cancel = $false
    [PotatoNet]::Live = 0
    [PotatoNet]::Phase = ''
    $ui.SpeedRunning = $true
    $ui.SpeedBtn.IsEnabled = $false
    Set-ButtonText -Button $ui.SpeedBtn -Text 'Измеряю…'
    foreach ($x in @($ui.SDown, $ui.SUp, $ui.SPing, $ui.SJit)) { $x.Value.Text = '—'; $x.Value.Foreground = Get-Brush 'Text'; $x.Sub.Text = '' }
    $ui.SpeedInfo.Text = 'Подключаюсь к Cloudflare…'
    # Живые цифры во время замера: читаем статические поля PotatoNet из UI-потока.
    $ui.SpeedTimer = New-Object System.Windows.Threading.DispatcherTimer
    $ui.SpeedTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $ui.SpeedTimer.Add_Tick({
        $ui = $script:NetUi
        $ph = [PotatoNet]::Phase
        $live = [double][PotatoNet]::Live
        switch ($ph) {
            'latency' { $ui.SpeedInfo.Text = 'Измеряю задержку…' }
            'down' { $ui.SpeedInfo.Text = 'Измеряю загрузку…'; $ui.SDown.Value.Text = Format-Mbps $live; Set-SpeedRing $live }
            'up' { $ui.SpeedInfo.Text = 'Измеряю отдачу…'; $ui.SUp.Value.Text = Format-Mbps $live; Set-SpeedRing $live }
        }
    })
    $ui.SpeedTimer.Start()
    Start-BgTask -Name 'Замер скорости' -Script {
        $r = @{ Colo = ''; Loc = ''; Ok = $false }
        try { $t = [PotatoNet]::Trace(); $r.Colo = [string]$t['colo']; $r.Loc = [string]$t['loc'] } catch { Write-Log ('Нет связи с сервером замера: ' + $_.Exception.Message) 'err'; return $r }
        $lat = @([PotatoNet]::Latency(12) | Where-Object { $_ -ge 0 })
        if ($lat.Count) {
            $sorted = @($lat | Sort-Object)
            $r.Ping = [Math]::Round($sorted[[int][Math]::Floor($sorted.Count / 2)])
            $d = 0; for ($i = 1; $i -lt $lat.Count; $i++) { $d += [Math]::Abs($lat[$i] - $lat[$i - 1]) }
            $r.Jitter = $(if ($lat.Count -gt 1) { [Math]::Round($d / ($lat.Count - 1)) } else { 0 })
        }
        if (Test-JobCancel) { return $r }
        $r.Down = [Math]::Round([PotatoNet]::Download(4, 8), 1)
        if (Test-JobCancel) { return $r }
        $r.Up = [Math]::Round([PotatoNet]::Upload(3, 6), 1)
        $r.Ok = $r.Down -gt 0
        $r.Time = (Get-Date).ToString('s')
        if ($r.Ok) {
            Write-Log ('Скорость: загрузка ' + $r.Down + ' Мбит/с, отдача ' + $r.Up + ' Мбит/с, пинг ' + $r.Ping + ' мс') 'ok'
            Add-History -Kind 'network' -Name ('Скорость интернета: ' + $r.Down + ' / ' + $r.Up + ' Мбит/с, пинг ' + $r.Ping + ' мс')
        }
        return $r
    } -OnDone {
        param($r)
        $ui = $script:NetUi
        try { $ui.SpeedTimer.Stop() } catch {}
        $ui.SpeedRunning = $false
        $ui.SpeedBtn.IsEnabled = $true
        Set-ButtonText -Button $ui.SpeedBtn -Text 'Измерить скорость'
        if ($r -and $r.Ok) {
            Set-SpeedResult -R $r
            Set-Setting 'NetSpeed' $r
        } else {
            $ui.SpeedInfo.Text = 'Замер не удался - подробности в журнале'
            Set-SpeedRing 0
            $ui.Ring.Tag.Num.Text = '—'
        }
    } | Out-Null
}

function Format-Mbps {
    param([double]$V)
    if ($V -ge 100) { return ([Math]::Round($V)).ToString() }
    return ([Math]::Round($V, 1)).ToString('0.0')
}

function Set-SpeedRing {
    param([double]$Mbps)
    $ui = $script:NetUi
    # шкала логарифмическая: 1 Мбит/с - почти пусто, 1000 Мбит/с - полный круг
    $pct = if ($Mbps -gt 0) { [Math]::Min(100, 100 * [Math]::Log10(1 + $Mbps) / 3) } else { 0 }
    Set-ScoreRing -Ring $ui.Ring -Value ([int]$pct) -Color 'Accent'
    $ui.Ring.Tag.Num.Text = $(if ($Mbps -gt 0) { [string][Math]::Round($Mbps) } else { '—' })
}

function Set-SpeedResult {
    param($R, [switch]$Old)
    $ui = $script:NetUi
    $down = [double]$R.Down; $up = [double]$R.Up
    Set-SpeedRing $down
    $ui.SDown.Value.Text = Format-Mbps $down
    $min = if ($down -gt 0) { 4 * 8 * 1024 / $down / 60 } else { 0 }
    $ui.SDown.Sub.Text = if ($down -le 0) { '' } elseif ($min -lt 1) { 'фильм 4 ГБ - меньше минуты' } else { 'фильм 4 ГБ ≈ ' + [Math]::Round($min) + ' мин' }
    $ui.SUp.Value.Text = Format-Mbps $up
    $ui.SUp.Sub.Text = if ($up -ge 10) { 'видеозвонки в HD - без проблем' } elseif ($up -ge 3) { 'звонки - нормально' } elseif ($up -gt 0) { 'мало для видеозвонков' } else { '' }
    if ($null -ne $R.Ping) {
        $p = [int]$R.Ping
        $ui.SPing.Value.Text = [string]$p
        $ui.SPing.Value.Foreground = Get-Brush $(if ($p -le 40) { 'Ok' } elseif ($p -le 100) { 'Warn' } else { 'Bad' })
        $ui.SPing.Sub.Text = if ($p -le 30) { 'игры - отлично' } elseif ($p -le 60) { 'игры - хорошо' } elseif ($p -le 120) { 'в играх заметно' } else { 'высокая задержка' }
        $j = [int]$R.Jitter
        $ui.SJit.Value.Text = [string]$j
        $ui.SJit.Value.Foreground = Get-Brush $(if ($j -le 10) { 'Ok' } elseif ($j -le 30) { 'Warn' } else { 'Bad' })
        $ui.SJit.Sub.Text = if ($j -le 10) { 'связь стабильная' } elseif ($j -le 30) { 'немного скачет' } else { 'нестабильно' }
    }
    $when = ''
    try { $when = ([datetime]$R.Time).ToString($(if ($Old) { 'dd.MM HH:mm' } else { 'HH:mm' })) } catch {}
    $ui.SpeedInfo.Text = 'Cloudflare' + $(if ($R.Colo) { ' · ' + (Get-ColoName $R.Colo) }) + $(if ($when) { ' · ' + $when }) + $(if ($Old) { ' (прошлый замер)' })
}

function Get-ColoName {
    param([string]$Code)
    $m = @{ DME = 'Москва'; SVO = 'Москва'; LED = 'Санкт-Петербург'; KJA = 'Красноярск'; SVX = 'Екатеринбург'; OVB = 'Новосибирск'; KHV = 'Хабаровск'; FRA = 'Франкфурт'; AMS = 'Амстердам'; WAW = 'Варшава'; HEL = 'Хельсинки'; ARN = 'Стокгольм'; RIX = 'Рига'; TLL = 'Таллин'; VNO = 'Вильнюс'; KIV = 'Кишинёв'; KBP = 'Киев'; IEV = 'Киев'; LWO = 'Львов'; ODS = 'Одесса'; HRK = 'Харьков'; DNK = 'Днепр'; ALA = 'Алматы'; NQZ = 'Астана'; TAS = 'Ташкент'; EVN = 'Ереван'; TBS = 'Тбилиси'; IST = 'Стамбул'; LHR = 'Лондон'; CDG = 'Париж'; VIE = 'Вена'; PRG = 'Прага'; BUD = 'Будапешт'; OTP = 'Бухарест'; SOF = 'София'; BEG = 'Белград'; DUS = 'Дюссельдорф'; HAM = 'Гамбург'; MUC = 'Мюнхен'; TXL = 'Берлин'; BER = 'Берлин' }
    $c = $Code.ToUpperInvariant()
    if ($m.ContainsKey($c)) { return $m[$c] }
    return $c
}

# --- Диагностика ---

function Start-NetDiagnostics {
    $ui = $script:NetUi
    if ($ui.DiagRunning) { return }
    $ui.DiagRunning = $true
    $ui.DiagBtn.IsEnabled = $false
    $ui.Steps.Body.Children.Clear()
    [void]$ui.Steps.Body.Children.Add((New-Placeholder 'Проверяю…'))
    Start-BgTask -Name 'Диагностика сети' -Script { Invoke-NetDiagnostics } -OnDone {
        param($r)
        $ui = $script:NetUi
        $ui.DiagRunning = $false
        $ui.DiagBtn.IsEnabled = $true
        if ($r) { Set-NetDiagnostics -R $r } else { $ui.Steps.Body.Children.Clear(); [void]$ui.Steps.Body.Children.Add((New-Placeholder 'Диагностика не завершилась - подробности в журнале.')) }
    } | Out-Null
}

function Set-NetDiagnostics {
    param($R)
    $ui = $script:NetUi
    $ui.StepsTime.Text = ([datetime]$R.Time).ToString('dd.MM · HH:mm')
    $body = $ui.Steps.Body
    $body.Children.Clear()
    foreach ($s in $R.Steps) {
        $map = @{ ok = @('check', 'Ok'); warn = @('warn', 'Warn'); bad = @('x', 'Bad'); na = @('info', 'Muted') }
        $m = $map[$s.State]; if (-not $m) { $m = $map.na }
        $tile = New-IconTile -Icon $m[0] -Color $m[1] -Size 28
        $tile.CornerRadius = New-Object System.Windows.CornerRadius 14
        $main = New-TitleBlock -Title $s.Title -Sub $s.Detail
        $main.ToolTip = $s.Detail
        $val = New-Text -Text $s.Value -Size 12 -Weight 'SemiBold' -Color $m[1]
        [void]$body.Children.Add((New-Row -Left $tile -Main $main -Right @($val) -Padding (16, 8, 16, 8)))
    }
    $v = $R.Verdict
    $ui.Verdict.Visibility = 'Visible'
    $col = switch ($v.Kind) { 'ok' { 'Ok' } 'bad' { 'Bad' } default { 'Warn' } }
    $ui.Verdict.BorderBrush = Get-Brush $col
    $ui.Verdict.BorderThickness = New-Thickness 3, 1, 1, 1
    $ui.VIcon.Child.Children[0].Stroke = Get-Brush $col
    $ui.VTitle.Text = $v.Title
    $ui.VSub.Text = $v.Sub
    if ($v.Fix) { $ui.VFix.Visibility = 'Visible'; $ui.VFix.Tag = $v.Fix; Set-ButtonText -Button $ui.VFix -Text $v.FixText }
    else { $ui.VFix.Visibility = 'Collapsed' }
}

function Start-NetFix {
    param([string]$Id)
    $ui = $script:NetUi
    if ($Id -eq 'portal') { Open-Path 'http://www.msftconnecttest.com/redirect'; return }
    $msg = switch ($Id) {
        'adapter' { 'Перезапустить сетевой адаптер? Связь пропадёт на 5-10 секунд.' }
        'renew' { 'Отпустить адрес и запросить новый у роутера? Связь пропадёт на несколько секунд.' }
        'proxy' { 'Выключить прокси-сервер в настройках Windows? Если прокси нужен для работы (настроил администратор) - не сбрасывайте.' }
        'hosts' { 'Восстановить стандартный файл hosts? Текущий сохранится копией в папке резервных копий PotatoPC. Блокировки рекламы через hosts тоже уберутся.' }
        'winsock' { 'Сбросить Winsock и TCP/IP? Это помогает, когда сеть сломана программами (VPN, антивирусы). Сбросятся и ручные настройки IP. Нужна перезагрузка.' }
        'dns' { 'Включить DNS Cloudflare (1.1.1.2, с защитой от вредоносных сайтов) на всех активных адаптерах?' }
        default { '' }
    }
    if ($msg -and -not (Show-Confirm -Message $msg -Title 'Сеть')) { return }
    foreach ($b in $ui.FixBtns) { $b.IsEnabled = $false }
    $ui.VFix.IsEnabled = $false
    Start-BgTask -Name 'Исправление сети' -Vars @{ FixId = $Id } -Script { Invoke-NetFix -Id $FixId; return $FixId } -OnDone {
        param($id)
        $ui = $script:NetUi
        foreach ($b in $ui.FixBtns) { $b.IsEnabled = $true }
        $ui.VFix.IsEnabled = $true
        if ($id -eq 'winsock') {
            if (Show-Confirm -Message 'Сброс выполнен. Перезагрузить компьютер сейчас?' -Title 'Сеть') { Request-Reboot -DelaySec 15 -Reason 'PotatoPC: сброс сети' }
            return
        }
        Update-NetDns
        Update-NetInfoTab
        if ($ui.Verdict.Visibility -eq 'Visible') { Start-NetDiagnostics }
    } | Out-Null
}

# --- DNS ---

function Update-NetDns {
    Start-BgTask -Name 'DNS' -Silent -Script { , @(Get-DnsState) } -OnDone { param($r) Set-NetDnsSection -Dns @($r) } | Out-Null
}

function Set-NetDnsSection {
    param($Dns)
    $body = $script:NetUi.DnsSec.Body
    $body.Children.Clear()
    $cur = @($Dns | Where-Object { $_ } | ForEach-Object { $_.Name + ': ' + $(if ($_.Servers.Count) { $_.Servers -join ', ' } else { 'автоматически' }) })
    [void]$body.Children.Add((New-Text -Text ('Сейчас: ' + $(if ($cur.Count) { $cur -join ' · ' } else { 'нет активных сетевых адаптеров' })) -Size 13 -Color 'Muted' -Wrap -Margin (16, 0, 16, 10)))
    $all = @($Dns | Where-Object { $_ } | ForEach-Object { $_.Servers } | Where-Object { $_ })
    foreach ($k in $script:DnsPresets.Keys) {
        $p = $script:DnsPresets[$k]
        $active = if ($k -eq 'auto') { $all.Count -eq 0 } else { $all.Count -gt 0 -and @($all | Where-Object { $p.V4 -notcontains $_ }).Count -eq 0 }
        $btn = if ($active) { New-Badge 'сейчас' 'ok' } else { New-Button -Text 'Включить' -Kind Small -Tag $k -OnClick { Set-DnsPreset -Key $this.Tag } }
        [void]$body.Children.Add((New-Row -Main (New-TitleBlock -Title $p.Name -Sub $(if ($p.V4.Count) { $p.V4 -join ', ' } else { 'DNS выдаёт роутер или провайдер' })) -Right @($btn) -Padding (16, 8, 12, 8)))
    }
}

function Set-DnsPreset {
    param([string]$Key)
    $p = $script:DnsPresets[$Key]
    Start-BgTask -Name 'Смена DNS' -Vars @{ V4 = $p.V4; N = $p.Name } -Script { Set-NetDnsServers -V4 $V4 -Name $N } -OnDone { Update-NetDns; Update-NetInfoTab } | Out-Null
}

# --- Сведения ---

function Update-NetInfoTab {
    $ui = $script:NetUi
    foreach ($k in $ui.Tabs.Keys) { Set-ChipActive -Button $ui.Tabs[$k] -Active ($k -eq $ui.Tab) }
    $b = $ui.InfoBody
    $b.Children.Clear()
    switch ($ui.Tab) {
        'who' {
            [void]$b.Children.Add($ui.WhoPanel)
            Update-NetWho
            return
        }
        'trace' {
            [void]$b.Children.Add((New-Text -Text 'Куда проверить путь:' -Size 13 -Color 'Muted' -Margin (16, 4, 16, 8)))
            $chips = New-Object System.Windows.Controls.WrapPanel
            $chips.Margin = New-Thickness 16, 0, 16, 8
            $ui.TraceChips = @()
            foreach ($p in ($script:TracePresets + , @('Свой адрес…', ''))) {
                $c = New-Button -Text $p[0] -Kind Chip -Tag $p[1] -OnClick {
                    $ui = $script:NetUi
                    $ui.TracePick = [string]$this.Tag
                    foreach ($x in $ui.TraceChips) { Set-ChipActive -Button $x -Active ([object]::ReferenceEquals($x, $this)) }
                    $ui.TraceIn.Text = [string]$this.Tag
                    if (-not $this.Tag) { [void]$ui.TraceIn.Focus() }
                }
                Set-ChipActive -Button $c -Active ($p[1] -eq $ui.TracePick)
                $ui.TraceChips += $c
                [void]$chips.Children.Add($c)
            }
            [void]$b.Children.Add($chips)
            $in = New-TextInput -Placeholder 'Сайт или IP, например google.com' -Width 320 -Text $ui.TracePick
            $go = New-Button -Text 'Проверить путь' -Icon 'play' -Kind Primary -OnClick { Start-NetTrace }
            $ui.TraceIn = $in; $ui.TraceBtn = $go
            $go.Margin = New-Thickness 10, 0, 0, 0
            [void]$b.Children.Add((New-Stack -Orientation Horizontal -Margin (16, 0, 16, 12) -Children @($in, $go)))
            $ui.TraceOut = New-Stack -Margin (16, 0, 16, 14)
            if ($ui.TraceLast) { Show-NetTrace -R $ui.TraceLast }
            else { [void]$ui.TraceOut.Children.Add((New-Text -Text 'Покажет путь от вашего ПК до сайта и на каком участке теряется связь или растёт задержка: у вас дома, у провайдера или дальше в интернете.' -Size 12 -Color 'Muted' -Wrap)) }
            [void]$b.Children.Add($ui.TraceOut)
            return
        }
    }
    [void]$b.Children.Add((New-Placeholder))
    $sb = switch ($ui.Tab) { 'wifi' { { Get-WifiProfiles } } default { { Get-NetAdaptersInfo } } }
    Start-BgTask -Name 'Сведения о сети' -Silent -Script $sb -OnDone {
        param($r, $err, $job)
        # пока грузилось, могли переключить вкладку - тогда результат уже не нужен
        if ($job.Context -ne $script:NetUi.Tab) { return }
        Set-NetInfo -Items @($r)
    } -Context $ui.Tab | Out-Null
}

function Set-NetInfo {
    param($Items)
    $ui = $script:NetUi
    $b = $ui.InfoBody
    $b.Children.Clear()
    $Items = @($Items | Where-Object { $_ })
    if (-not $Items.Count) {
        [void]$b.Children.Add((New-Placeholder $(switch ($ui.Tab) { 'wifi' { 'Сохранённых сетей Wi-Fi нет (или на ПК нет Wi-Fi).' } default { 'Адаптеров не найдено.' } })))
        return
    }
    foreach ($x in $Items) {
        switch ($ui.Tab) {
            'adapters' {
                $sub = @()
                $sub += $(switch ($x.Status) { 'Up' { 'подключён' } 'Disconnected' { 'не подключён' } 'Disabled' { 'выключен' } default { $x.Status } })
                if ($x.Status -eq 'Up' -and $x.Speed) { $sub += $x.Speed }
                if ($x.Ip) { $sub += $x.Ip }
                if ($x.Mac) { $sub += 'MAC ' + $x.Mac }
                $badge = if ($x.Virtual) { New-Badge 'виртуальный' 'muted' } elseif ($x.Status -eq 'Up') { New-Badge 'работает' 'ok' } else { New-Badge 'нет связи' 'muted' }
                [void]$b.Children.Add((New-Row -Left (New-IconTile -Icon $(if ($x.Desc -match '(?i)wi-?fi|wireless|802\.11|wlan') { 'wifi' } else { 'network' }) -Color $(if ($x.Status -eq 'Up') { 'Accent' } else { 'Muted' }) -Size 34) -Main (New-TitleBlock -Title ($x.Name + ' - ' + $x.Desc) -Sub ($sub -join ' · ')) -Right @($badge) -Padding (16, 8, 16, 8)))
            }
            'wifi' {
                $pw = New-Text -Text $(if ($x.Key) { '••••••••' } else { '—' }) -Size 13 -Mono
                $pw.Width = 170
                $right = @($pw)
                if ($x.Key) {
                    $show = New-Button -Text 'Показать' -Kind Small -Tag @{ T = $pw; K = $x.Key } -OnClick {
                        $t = $this.Tag
                        if ($t.T.Text -eq $t.K) { $t.T.Text = '••••••••'; Set-ButtonText -Button $this -Text 'Показать' } else { $t.T.Text = $t.K; Set-ButtonText -Button $this -Text 'Скрыть' }
                    }
                    $copy = New-Button -Text 'Копировать' -Kind Small -Tag $x.Key -OnClick { try { [System.Windows.Clipboard]::SetText([string]$this.Tag); Write-Log 'Пароль Wi-Fi скопирован' 'ok' } catch {} }
                    $right += $show; $right += $copy
                }
                $forget = New-Button -Text 'Забыть' -Kind SmallDanger -ToolTip 'Удалить эту сеть из Windows: ПК перестанет к ней подключаться' -OnClick {
                    $t = $this.Tag
                    $msg = 'Забыть сеть «' + $t.Name + '»?' + "`n`n" + 'Windows удалит её вместе с сохранённым паролем и больше не будет к ней подключаться.'
                    if ($t.Key) { $msg += "`n`n" + 'Пароль: ' + $t.Key + "`n" + '(запишите, если понадобится снова)' }
                    if (-not (Show-Confirm -Message $msg -Title 'Забыть сеть Wi-Fi' -Warning)) { return }
                    $null = & netsh.exe wlan delete profile ('name=' + $t.Name) 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        [void]$script:NetUi.InfoBody.Children.Remove($t.Row)
                        Write-Log ('Сеть Wi-Fi забыта: ' + $t.Name) 'ok'
                    } else {
                        Write-Log ('Не удалось забыть сеть Wi-Fi: ' + $t.Name) 'err'
                    }
                }
                $right += $forget
                $row = New-Row -Left (New-Icon -Name 'wifi' -Size 18 -Color 'Muted') -Main (New-TitleBlock -Title $x.Name -Sub $(if ($x.Auth) { $x.Auth } else { 'открытая сеть' })) -Right $right -Padding (16, 6, 12, 6)
                $forget.Tag = @{ Name = $x.Name; Key = $x.Key; Row = $row }
                [void]$b.Children.Add($row)
            }
        }
    }
    if ($ui.Tab -eq 'wifi') { [void]$b.Children.Add((New-Text -Text 'Пароли хранит сама Windows - PotatoPC их только показывает. Нужны права администратора (они у PotatoPC есть).' -Size 12 -Color 'Muted' -Wrap -Margin (16, 8, 16, 12))) }
}

# --- Трассировка ---

$script:TracePresets = @(
    @('Google', 'google.com'),
    @('YouTube', 'youtube.com'),
    @('Cloudflare 1.1.1.1', '1.1.1.1'),
    @('Discord', 'discord.com'),
    @('Steam', 'store.steampowered.com'),
    @('Microsoft', 'microsoft.com')
)

function Start-NetTrace {
    $ui = $script:NetUi
    $h = ([string]$ui.TraceIn.Text).Trim()
    if ($h -notmatch '^[A-Za-z0-9\.\-:]{1,253}$') { Show-Info 'Введите адрес сайта (например, google.com) или IP.'; return }
    $ui.TraceBtn.IsEnabled = $false
    $ui.TraceOut.Children.Clear()
    [void]$ui.TraceOut.Children.Add((New-Text -Text ('Проверяю путь до ' + $h + '… Обычно 10-40 секунд, если сайт не отвечает - до минуты.') -Size 13 -Color 'Muted' -Wrap))
    Start-BgTask -Name 'Трассировка' -Vars @{ H = $h } -Script {
        $r = Invoke-ProcessLive -FilePath (Join-Path $env:WINDIR 'System32\tracert.exe') -Arguments ('-d -4 -w 800 -h 20 ' + $H) -TimeoutSec 150 -Prefix '   tracert: '
        return [string]$r.Output
    } -Context $h -OnDone {
        param($t, $err, $job)
        $ui = $script:NetUi
        $ui.TraceBtn.IsEnabled = $true
        $r = ConvertFrom-Tracert -Text ([string]$t) -Target ([string]$job.Context)
        $ui.TraceLast = $r
        if ($ui.Tab -eq 'trace') { Show-NetTrace -R $r }
    } | Out-Null
}

function Test-NetPrivateIp {
    param([string]$Ip)
    return ($Ip -match '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.|169\.254\.)')
}

function ConvertFrom-Tracert {
    # Разбирает вывод tracert (русский или английский) в участки и вердикт.
    param([string]$Text, [string]$Target)
    $tip = if ($Target -match '^\d{1,3}(\.\d{1,3}){3}$') { $Target } else { '' }
    $hops = @()
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^\s*(\d{1,2})\s+(.*)$') {
            $n = [int]$Matches[1]; $rest = $Matches[2]; $times = @(); $ok = $true
            for ($i = 0; $i -lt 3; $i++) {
                if ($rest -match '^\*\s*(.*)$') { $times += -1; $rest = $Matches[1] }
                elseif ($rest -match '^<?(\d+)\s*\S+\s*(.*)$') { $times += [int]$Matches[1]; $rest = $Matches[2] }
                else { $ok = $false; break }
            }
            if (-not $ok) { continue }
            $ip = if ($rest -match '(\d{1,3}(?:\.\d{1,3}){3})') { $Matches[1] } else { '' }
            $got = @($times | Where-Object { $_ -ge 0 })
            $ms = if ($got.Count) { [int][Math]::Round((($got | Measure-Object -Average).Average)) } else { -1 }
            $hops += @{ N = $n; Ip = $ip; Ms = $ms; Lost = (3 - $got.Count) }
        } elseif (-not $tip -and $line -match '\[(\d{1,3}(?:\.\d{1,3}){3})\]') { $tip = $Matches[1] }
    }
    # Хвост из одних «*» сворачиваем в один участок
    $lastOk = -1
    for ($i = 0; $i -lt $hops.Count; $i++) { if ($hops[$i].Ms -ge 0) { $lastOk = $i } }
    if ($lastOk -ge 0 -and $lastOk -lt $hops.Count - 1) { $hops = @($hops[0..($lastOk + 1)]) }
    $reached = ($lastOk -ge 0 -and $tip -and $hops[$lastOk].Ip -eq $tip)

    # Подписи и группы: router -> isp -> net -> target
    $seenPublic = $false
    foreach ($h in $hops) {
        if ($h.Ms -lt 0) { $h.Kind = 'none'; $h.Label = 'Не отвечает'; continue }
        $priv = Test-NetPrivateIp $h.Ip
        if ($reached -and $h.Ip -eq $tip) { $h.Kind = 'target'; $h.Label = $Target }
        elseif ($h.N -eq 1 -and $priv) { $h.Kind = 'router'; $h.Label = 'Ваш роутер' }
        elseif ($priv -and -not $seenPublic) { $h.Kind = 'isp'; $h.Label = 'Провайдер' }
        elseif (-not $seenPublic) { $h.Kind = 'isp'; $h.Label = 'Сеть провайдера'; $seenPublic = $true }
        else { $h.Kind = 'net'; $h.Label = 'Интернет' }
    }
    $groups = @(@{ Kind = 'pc'; Title = 'Этот ПК'; Sub = 'старт'; Ms = 0; Icon = 'monitor' })
    foreach ($def in @(@('router', 'Роутер', 'router'), @('isp', 'Провайдер', 'building'), @('net', 'Интернет', 'network'), @('target', $Target, 'globe'))) {
        $in = @($hops | Where-Object { $_.Kind -eq $def[0] })
        if (-not $in.Count) { continue }
        $g = @{ Kind = $def[0]; Title = $def[1]; Icon = $def[2]; Ms = $in[-1].Ms }
        $g.Sub = if ($def[0] -eq 'target') { [string]$in[-1].Ms + ' мс' } elseif ($in.Count -gt 1) { [string]$in.Count + ' узла' } else { $in[0].Ip }
        if ($def[0] -eq 'net' -and $in.Count -ge 5) { $g.Sub = [string]$in.Count + ' узлов' }
        $groups += $g
    }
    if (-not $reached) { $groups += @{ Kind = 'nope'; Title = $Target; Sub = 'не ответил'; Ms = -1; Icon = 'globe' } }
    $prev = 0
    foreach ($g in $groups) {
        if ($g.Ms -ge 0) { $g.Delta = [Math]::Max(0, $g.Ms - $prev); $prev = [Math]::Max($prev, $g.Ms) } else { $g.Delta = -1 }
    }

    # Вердикт
    $v = @{ Level = 'ok'; Title = ''; Text = '' }
    $resp = @($hops | Where-Object { $_.Ms -ge 0 })
    $router = @($groups | Where-Object { $_.Kind -eq 'router' })
    $worst = $null
    foreach ($g in $groups) { if ($g.Kind -ne 'pc' -and $g.Delta -ge 50 -and (-not $worst -or $g.Delta -gt $worst.Delta)) { $worst = $g } }
    $tgtLost = if ($reached) { $hops[$lastOk].Lost } else { 0 }
    if (-not $hops.Count -or -not $resp.Count) {
        $v = @{ Level = 'bad'; Title = 'Нет ответа даже от первого узла'; Text = 'Похоже, интернета нет совсем или адрес не найден. Запустите диагностику выше - она проверит адаптер, роутер и DNS.' }
    } elseif ($router.Count -and $router[0].Ms -ge 20) {
        $v = @{ Level = 'bad'; Title = 'Медленно уже до роутера'; Text = ('Роутер отвечает за ' + $router[0].Ms + ' мс - для домашней сети это много. Причина у вас дома: слабый Wi-Fi, помехи или кабель. Подойдите ближе к роутеру или подключитесь кабелем.') }
    } elseif ($worst -and $worst.Kind -eq 'isp') {
        $v = @{ Level = 'bad'; Title = 'Задержка появляется у провайдера'; Text = ('Ваш ПК и роутер отвечают быстро. На участке «роутер → провайдер» задержка вырастает на ' + $worst.Delta + ' мс. Попробуйте перезагрузить роутер; если не поможет - звоните провайдеру.') }
    } elseif ($worst -and $worst.Kind -eq 'net') {
        $v = @{ Level = 'warn'; Title = 'Задержка растёт дальше в интернете'; Text = ('Дома и у провайдера всё быстро, задержка добавляется на ' + $worst.Delta + ' мс уже на дальних узлах. Это не у вас - так бывает с далёкими серверами.') }
    } elseif ($worst -and $worst.Kind -eq 'target') {
        $v = @{ Level = 'warn'; Title = 'Медленно отвечает сам сайт'; Text = ('Весь путь быстрый, а сам ' + $Target + ' отвечает на ' + $worst.Delta + ' мс дольше. Проблема на стороне сайта.') }
    } elseif (-not $reached) {
        $v = @{ Level = 'info'; Title = ($Target + ' не ответил на проверку'); Text = 'Многие сайты не отвечают на такие запросы ради защиты - это не обязательно поломка. Участки до него в порядке.' }
    } else {
        $v = @{ Level = 'ok'; Title = 'Путь в порядке'; Text = ('До ' + $Target + ' ' + $resp.Count + ' участков, ' + $hops[$lastOk].Ms + ' мс. Задержка растёт плавно.') }
    }
    if ($tgtLost -gt 0 -and $v.Level -eq 'ok') { $v.Level = 'warn'; $v.Text += ' Но ' + $tgtLost + ' из 3 ответов от сайта потерялись.' }
    return @{ Target = $Target; Hops = $hops; Groups = $groups; Verdict = $v; Raw = $Text; Reached = $reached }
}

function Get-NetMsColor {
    param([int]$Ms)
    if ($Ms -lt 0) { return 'Muted' } elseif ($Ms -lt 50) { return 'Ok' } elseif ($Ms -lt 150) { return 'Warn' } else { return 'Bad' }
}

function Show-NetTrace {
    param($R)
    $out = $script:NetUi.TraceOut
    $out.Children.Clear()
    $v = $R.Verdict
    $pal = @{ ok = @('Ok', 'OkDim', 'check'); warn = @('Warn', 'WarnDim', 'warn'); bad = @('Bad', 'BadDim', 'warn'); info = @('Info', 'InfoDim', 'info') }[$v.Level]

    # Вердикт
    $vd = New-Object System.Windows.Controls.DockPanel
    $ic = New-Icon -Name $pal[2] -Size 22 -Color $pal[0] -Stroke 2
    $ic.VerticalAlignment = 'Top'; $ic.Margin = New-Thickness 0, 0, 14, 0
    [System.Windows.Controls.DockPanel]::SetDock($ic, 'Left'); [void]$vd.Children.Add($ic)
    $cp = New-Button -Text 'Копировать отчёт' -Icon 'copy' -Kind Small -Tag $R -OnClick {
        $r = $this.Tag
        $txt = $r.Verdict.Title + "`r`n" + $r.Verdict.Text + "`r`n`r`n" + ([string]$r.Raw).Trim()
        try { [System.Windows.Clipboard]::SetText($txt); Write-Log 'Отчёт трассировки скопирован' 'ok' } catch {}
    }
    $cp.VerticalAlignment = 'Top'; $cp.Margin = New-Thickness 14, 0, 0, 0
    [System.Windows.Controls.DockPanel]::SetDock($cp, 'Right'); [void]$vd.Children.Add($cp)
    [void]$vd.Children.Add((New-Stack -Children @((New-Text -Text $v.Title -Size 15 -Weight 'Bold' -Color $pal[0]), (New-Text -Text $v.Text -Size 13 -Wrap -Margin (0, 3, 0, 0)))))
    [void]$out.Children.Add((New-Card -Child $vd -Padding (16, 14, 16, 14) -Margin (0, 0, 0, 12) -Background $pal[1] -Border $pal[0]))

    # Схема
    $gr = New-Object System.Windows.Controls.Grid
    $col = 0
    for ($i = 0; $i -lt $R.Groups.Count; $i++) {
        $g = $R.Groups[$i]
        if ($i -gt 0) {
            $cd = New-Object System.Windows.Controls.ColumnDefinition; $cd.Width = New-Object System.Windows.GridLength 1, 'Star'; $cd.MinWidth = 40
            [void]$gr.ColumnDefinitions.Add($cd)
            $lc = if ($g.Delta -lt 0) { 'Muted' } elseif ($g.Delta -ge 50) { 'Bad' } elseif ($g.Delta -ge 25) { 'Warn' } else { 'Ok' }
            $lt = if ($g.Delta -lt 0) { 'нет ответа' } elseif ($i -eq 1) { [string]$g.Delta + ' мс' } else { '+' + $g.Delta + ' мс' }
            $lab = New-Text -Text $lt -Size 12 -Weight 'SemiBold' -Color $lc -Mono
            $lab.HorizontalAlignment = 'Center'
            $bar = New-Object System.Windows.Controls.Border
            $bar.Height = $(if ($lc -eq 'Bad') { 5 } else { 3 }); $bar.CornerRadius = New-Object System.Windows.CornerRadius 2; $bar.Margin = New-Thickness 4, 4, 4, 0
            if ($lc -eq 'Muted') { $bar.Background = Get-Brush 'Line' } else { $bar.Background = Get-Brush $lc }
            $cn = New-Stack -Margin (0, 6, 0, 0) -Children @($lab, $bar)
            $cn.VerticalAlignment = 'Top'
            [System.Windows.Controls.Grid]::SetColumn($cn, $col); [void]$gr.Children.Add($cn); $col++
        }
        $cd = New-Object System.Windows.Controls.ColumnDefinition; $cd.Width = New-Object System.Windows.GridLength 96
        [void]$gr.ColumnDefinitions.Add($cd)
        $nc = switch ($g.Kind) { 'pc' { 'Accent' } 'target' { 'Accent' } 'nope' { 'Muted' } default { if ($g.Delta -ge 50) { 'Bad' } else { Get-NetMsColor $g.Ms } } }
        $dim = @{ Accent = 'AccentDim'; Ok = 'OkDim'; Warn = 'WarnDim'; Bad = 'BadDim'; Muted = '#262A33' }[$nc]
        $circ = New-Object System.Windows.Controls.Border
        $circ.Width = 46; $circ.Height = 46; $circ.CornerRadius = New-Object System.Windows.CornerRadius 23
        $circ.Background = Get-Brush $dim; $circ.BorderBrush = Get-Brush $nc; $circ.BorderThickness = New-Thickness 2
        $circ.Child = New-Icon -Name $g.Icon -Size 20 -Color $nc -Stroke 2
        $circ.Child.HorizontalAlignment = 'Center'
        $t1 = New-Text -Text $g.Title -Size 12 -Weight 'SemiBold' -Margin (0, 6, 0, 0)
        $t2 = New-Text -Text $g.Sub -Size 11 -Color 'Muted' -Mono
        foreach ($x in @($circ, $t1, $t2)) { $x.HorizontalAlignment = 'Center' }
        $nd = New-Stack -Children @($circ, $t1, $t2)
        $nd.ToolTip = $g.Title
        [System.Windows.Controls.Grid]::SetColumn($nd, $col); [void]$gr.Children.Add($nd); $col++
    }
    [void]$out.Children.Add((New-Card -Child $gr -Padding (14, 18, 14, 14) -Margin (0, 0, 0, 12) -Background 'Panel'))

    # Все участки
    $hd = New-Object System.Windows.Controls.DockPanel
    $hd.Margin = New-Thickness 0, 0, 0, 6
    $hr = New-Text -Text 'задержка от вашего ПК до узла' -Size 12 -Color 'Muted'
    [System.Windows.Controls.DockPanel]::SetDock($hr, 'Right'); [void]$hd.Children.Add($hr)
    [void]$hd.Children.Add((New-Text -Text 'Все участки' -Size 13 -Weight 'SemiBold'))
    [void]$out.Children.Add($hd)
    $max = 100
    foreach ($h in $R.Hops) { if ($h.Ms -gt $max) { $max = $h.Ms } }
    foreach ($h in $R.Hops) {
        $c = Get-NetMsColor $h.Ms
        $row = New-Object System.Windows.Controls.Grid
        foreach ($w in @(30, -1, 130, 220, 60)) {
            $cd = New-Object System.Windows.Controls.ColumnDefinition
            $cd.Width = $(if ($w -lt 0) { New-Object System.Windows.GridLength 1, 'Star' } else { New-Object System.Windows.GridLength $w })
            [void]$row.ColumnDefinitions.Add($cd)
        }
        $name = $h.Label
        if ($h.Kind -eq 'none') { $name = 'Не отвечает (это нормально, трафик идёт дальше)' }
        elseif ($h.Kind -eq 'target') { $name = $h.Label + ' · цель' }
        if ($h.Lost -gt 0 -and $h.Ms -ge 0) { $name += ' · потеряно ' + $h.Lost + ' из 3' }
        $cells = @(
            (New-Text -Text ([string]$h.N) -Size 13 -Color 'Muted' -Mono),
            (New-Text -Text $name -Size 13 -Color $(if ($h.Ms -lt 0) { 'Muted' } else { 'Text' }) -Weight $(if ($h.Kind -eq 'target') { 'SemiBold' } else { 'Normal' })),
            (New-Text -Text $(if ($h.Ip) { $h.Ip } else { '*' }) -Size 12 -Color 'Muted' -Mono -Margin (8, 0, 8, 0)),
            $null,
            (New-Text -Text $(if ($h.Ms -ge 0) { [string]$h.Ms } else { '*' }) -Size 13 -Weight 'SemiBold' -Color $c -Mono)
        )
        if ($h.Ms -ge 0) {
            $m = New-Meter -Height 8
            Set-Meter -Meter $m -Value ([Math]::Max(0.02, $h.Ms / $max)) -Color $c
            $cells[3] = $m
        }
        $cells[4].HorizontalAlignment = 'Right'
        for ($k = 0; $k -lt 5; $k++) { if ($cells[$k]) { [System.Windows.Controls.Grid]::SetColumn($cells[$k], $k); $cells[$k].VerticalAlignment = 'Center'; [void]$row.Children.Add($cells[$k]) } }
        $bd = New-Object System.Windows.Controls.Border
        $bd.BorderBrush = Get-Brush 'Line'; $bd.BorderThickness = New-Thickness 0, 1, 0, 0
        $bd.Padding = New-Thickness 0, 9, 0, 9
        $bd.Child = $row
        [void]$out.Children.Add($bd)
    }
}
