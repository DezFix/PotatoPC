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

function Get-NetConnectionsByApp {
    $out = @()
    $conns = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Where-Object { $_.RemoteAddress -notmatch '^(127\.|::1|0\.0\.0\.0)' })
    foreach ($g in @($conns | Group-Object OwningProcess | Sort-Object Count -Descending)) {
        $pr = Get-Process -Id ([int]$g.Name) -ErrorAction SilentlyContinue
        $remote = @($g.Group | ForEach-Object { [string]$_.RemoteAddress + ':' + $_.RemotePort } | Select-Object -Unique)
        $out += @{ Name = $(if ($pr) { [string]$pr.ProcessName } else { 'PID ' + $g.Name }); Pid = [int]$g.Name; Path = $(if ($pr) { try { [string]$pr.Path } catch { '' } } else { '' }); Count = $g.Count; Remote = $remote }
    }
    return , $out
}

# ---------- Интерфейс ----------

function Build-Page_network {
    $ui = @{ Tab = 'adapters' }
    $script:NetUi = $ui
    $diag = New-Button -Text 'Запустить диагностику' -Icon 'play' -OnClick { Start-NetDiagnostics }
    $ui.DiagBtn = $diag
    $L = New-PageLayout -Title 'Сеть' -Subtitle 'Скорость, диагностика подключения и исправление неполадок' -HeaderRight @($diag)

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
    foreach ($t in @(@('adapters', 'Адаптеры'), @('wifi', 'Сохранённые Wi-Fi'), @('conns', 'Соединения программ'), @('trace', 'Трассировка'))) {
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
    Start-BgTask -Name 'Смена DNS' -Vars @{ V4 = $p.V4; N = $p.Name } -Script { Set-NetDnsServers -V4 $V4 -Name $N } -OnDone { Update-NetDns } | Out-Null
}

# --- Сведения ---

function Update-NetInfoTab {
    $ui = $script:NetUi
    foreach ($k in $ui.Tabs.Keys) { Set-ChipActive -Button $ui.Tabs[$k] -Active ($k -eq $ui.Tab) }
    $b = $ui.InfoBody
    $b.Children.Clear()
    switch ($ui.Tab) {
        'trace' {
            $in = New-TextInput -Placeholder 'Сайт или адрес, например google.com' -Width 300 -Text 'google.com'
            $go = New-Button -Text 'Трассировать' -Kind Small -OnClick {
                $h = ([string]$script:NetUi.TraceIn.Text).Trim()
                if ($h -notmatch '^[A-Za-z0-9\.\-:]{1,253}$') { Show-Info 'Введите адрес сайта (например, google.com) или IP.'; return }
                $script:NetUi.TraceOut.Text = 'Трассирую ' + $h + '… (до минуты)'
                $this.IsEnabled = $false
                $script:NetUi.TraceBtn = $this
                Start-BgTask -Name 'Трассировка' -Vars @{ H = $h } -Script {
                    $r = Invoke-ProcessLive -FilePath (Join-Path $env:WINDIR 'System32\tracert.exe') -Arguments ('-d -w 800 -h 20 ' + $H) -TimeoutSec 150 -Prefix '   tracert: '
                    return [string]$r.Output
                } -OnDone { param($t) $script:NetUi.TraceBtn.IsEnabled = $true; $script:NetUi.TraceOut.Text = $(if ($t) { $t.Trim() } else { 'Нет данных' }) } | Out-Null
            }
            $ui.TraceIn = $in
            $go.Margin = New-Thickness 10, 0, 0, 0
            [void]$b.Children.Add((New-Stack -Orientation Horizontal -Margin (16, 4, 16, 10) -Children @($in, $go)))
            $ui.TraceOut = New-Text -Text 'Покажет, на каком участке пути до сайта теряется связь или растёт задержка: первые строки - ваш роутер и провайдер.' -Size 12 -Color 'Muted' -Wrap -Mono -Margin (16, 0, 16, 14)
            [void]$b.Children.Add($ui.TraceOut)
            return
        }
    }
    [void]$b.Children.Add((New-Placeholder))
    $sb = switch ($ui.Tab) { 'wifi' { { Get-WifiProfiles } } 'conns' { { Get-NetConnectionsByApp } } default { { Get-NetAdaptersInfo } } }
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
        [void]$b.Children.Add((New-Placeholder $(switch ($ui.Tab) { 'wifi' { 'Сохранённых сетей Wi-Fi нет (или на ПК нет Wi-Fi).' } 'conns' { 'Активных соединений нет.' } default { 'Адаптеров не найдено.' } })))
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
                [void]$b.Children.Add((New-Row -Left (New-Icon -Name 'wifi' -Size 18 -Color 'Muted') -Main (New-TitleBlock -Title $x.Name -Sub $(if ($x.Auth) { $x.Auth } else { 'открытая сеть' })) -Right $right -Padding (16, 6, 12, 6)))
            }
            'conns' {
                $sample = (@($x.Remote) | Select-Object -First 4) -join ', '
                if (@($x.Remote).Count -gt 4) { $sample += ' и ещё ' + (@($x.Remote).Count - 4) }
                $row = New-Row -Left (New-AppIcon -Name $x.Name -Size 30) -Main (New-TitleBlock -Title ($x.Name + '  (PID ' + $x.Pid + ')') -Sub $sample) -Right @((New-Badge ([string]$x.Count + ' соедин.') 'info')) -Padding (16, 6, 16, 6)
                if ($x.Path) { $row.ToolTip = $x.Path }
                [void]$b.Children.Add($row)
            }
        }
    }
    if ($ui.Tab -eq 'wifi') { [void]$b.Children.Add((New-Text -Text 'Пароли хранит сама Windows - PotatoPC их только показывает. Нужны права администратора (они у PotatoPC есть).' -Size 12 -Color 'Muted' -Wrap -Margin (16, 8, 16, 12))) }
}
