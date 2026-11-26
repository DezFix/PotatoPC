# PotatoPC v7 - установка и обновление программ через winget.

function Test-TrustedWingetPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
        $root = [System.IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'WindowsApps')).TrimEnd('\')
        $localApps = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps')).TrimEnd('\')
        if (-not ($full.StartsWith($root + '\', 'OrdinalIgnoreCase') -or $full.StartsWith($localApps + '\', 'OrdinalIgnoreCase'))) { return $false }
        if ($full.StartsWith($localApps + '\', 'OrdinalIgnoreCase')) { return $true }  # псевдоним App Execution Alias
        $sig = Get-AuthenticodeSignature -LiteralPath $full -ErrorAction Stop
        return ($sig.Status -eq 'Valid' -and [string]$sig.SignerCertificate.Subject -match '(?i)Microsoft')
    } catch { return $false }
}

function Get-WingetPath {
    $cands = @()
    try { $c = Get-Command winget.exe -ErrorAction SilentlyContinue; if ($c) { $cands += $c.Source } } catch {}
    try {
        foreach ($pkg in @(Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction Stop)) {
            if ($pkg.InstallLocation) { $cands += (Join-Path ([string]$pkg.InstallLocation) 'winget.exe') }
        }
    } catch {}
    try { $cands += @(Get-ChildItem -Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | ForEach-Object { $_.FullName }) } catch {}
    foreach ($p in $cands) { if ($p -and (Test-Path -LiteralPath $p) -and (Test-TrustedWingetPath -Path $p)) { return $p } }
    return ''
}

function Invoke-Winget {
    param([string]$Arguments, [int]$TimeoutSec = 900, [switch]$Quiet)
    $exe = Get-WingetPath
    if (-not $exe) { return @{ Code = -1; Output = ''; Missing = $true } }
    $r = Invoke-ProcessLive -FilePath $exe -Arguments ($Arguments + ' --accept-source-agreements') -TimeoutSec $TimeoutSec -Encoding utf8 -Quiet
    if (-not $Quiet) {
        foreach ($l in ($r.Output -split "`r?`n")) {
            $t = $l.Trim()
            if (-not $t) { continue }
            if ($t -match '^[\-\\\|/ ]+$' -or $t -match '[█▒]' -or $t -match '^\d+(\.\d+)?\s*(KB|MB|GB|КБ|МБ|ГБ)\s*/') { continue }
            # Шаблонные строки про лицензию winget печатает для каждого пакета - только шум.
            if ($t -match '^(Лицензия на это приложение|Корпорация Майкрософт не несет|This application is licensed|Microsoft is not responsible)') { continue }
            Write-Log ('     ' + $t)
        }
    }
    $r.Missing = $false
    return $r
}

function ConvertFrom-WingetTable {
    # Разбор табличного вывода winget (search/upgrade). Имя берём по позиции
    # колонки «Id» из заголовка (имена бывают с пробелами), остальное - по словам:
    # Id, версия, [доступная версия], [источник].
    param([string]$Text)
    $rows = @()
    $lines = @($Text -split "`r?`n" | ForEach-Object { ($_ -split "`r")[-1] })
    $sep = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^-{10,}\s*$') { $sep = $i; break } }
    if ($sep -lt 1) { return @() }
    $cols = @([regex]::Matches($lines[$sep - 1], '\S+'))
    if ($cols.Count -lt 3) { return @() }
    $idStart = $cols[1].Index
    for ($i = $sep + 1; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l.Length -le $idStart -or [string]::IsNullOrWhiteSpace($l)) { continue }
        # Если имя залезло в колонку Id, начало Id - первый пробел перед ней.
        $st = $idStart
        if ($st -gt 0 -and $l[$st - 1] -ne ' ') { $sp = $l.IndexOf(' ', $st); if ($sp -lt 0) { continue }; $st = $sp + 1 }
        $name = $l.Substring(0, [Math]::Min($st, $l.Length)).Trim()
        $tok = @($l.Substring($st).Trim() -split '\s+' | Where-Object { $_ })
        $merged = @()
        for ($t = 0; $t -lt $tok.Count; $t++) { if ($tok[$t] -in @('<', '>') -and $t + 1 -lt $tok.Count) { $merged += ($tok[$t] + ' ' + $tok[$t + 1]); $t++ } else { $merged += $tok[$t] } }
        if ($merged.Count -gt 2 -and $merged[-1] -match '^(winget|msstore)$') { $merged = @($merged[0..($merged.Count - 2)]) }
        if ($merged.Count -lt 2) { continue }
        $rows += , (@($name) + $merged)
    }
    return $rows
}

function Get-WingetUpgrades {
    $r = Invoke-Winget -Arguments 'upgrade --include-unknown' -TimeoutSec 180 -Quiet
    if ($r.Missing) { return $null }
    $out = @()
    foreach ($cells in (ConvertFrom-WingetTable -Text $r.Output)) {
        if ($cells.Count -lt 4) { continue }
        $id = $cells[1]
        if ($id -notmatch '\.' -or $id -match '\s') { continue }
        $out += @{ Name = $cells[0]; Id = $id; Version = $cells[2]; Available = $cells[3] }
    }
    return $out
}

function Get-WingetInstalled {
    # Через export: надёжнее разбора таблицы, только пакеты, известные winget.
    $tmp = Join-Path $WorkFolder ('winget-export-' + [guid]::NewGuid().ToString('N') + '.json')
    $r = Invoke-Winget -Arguments ('export -o "' + $tmp + '" --include-versions') -TimeoutSec 180 -Quiet
    if ($r.Missing) { return $null }
    $out = @()
    try {
        $j = Get-Content -LiteralPath $tmp -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        foreach ($src in @($j.Sources)) {
            foreach ($p in @($src.Packages)) { $out += @{ Id = [string]$p.PackageIdentifier; Version = [string]$p.Version } }
        }
    } catch {}
    try { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } catch {}
    return $out
}

function Search-Winget {
    param([string]$Query)
    $q = $Query.Replace('"', '')
    $r = Invoke-Winget -Arguments ('search "' + $q + '" --source winget') -TimeoutSec 120 -Quiet
    if ($r.Missing) { return $null }
    $out = @()
    foreach ($cells in (ConvertFrom-WingetTable -Text $r.Output)) {
        if ($cells.Count -lt 3) { continue }
        if ($cells[1] -notmatch '\.' -or $cells[1] -match '\s') { continue }
        $out += @{ Name = $cells[0]; Id = $cells[1]; Version = $cells[2] }
    }
    return @($out | Select-Object -First 40)
}

function Install-WingetPackages {
    param([string[]]$Ids, [ValidateSet('install','upgrade','uninstall')][string]$Mode = 'install')
    $ok = 0; $fail = @()
    $i = 0
    foreach ($id in $Ids) {
        if (Test-JobCancel) { break }
        $i++
        Set-JobProgress (($i - 1) / [Math]::Max(1, $Ids.Count)) $id
        $verb = switch ($Mode) { 'install' { 'Установка' } 'upgrade' { 'Обновление' } default { 'Удаление' } }
        Write-Log ('[' + $i + '/' + $Ids.Count + '] ' + $verb + ': ' + $id)
        $argLine = switch ($Mode) {
            'install'   { 'install --id "' + $id + '" -e --silent --accept-package-agreements --source winget' }
            'upgrade'   { 'upgrade --id "' + $id + '" -e --silent --accept-package-agreements --include-unknown' }
            'uninstall' { 'uninstall --id "' + $id + '" -e --silent' }
        }
        $r = Invoke-Winget -Arguments $argLine -TimeoutSec 1800
        if ($r.Missing) { Write-Log 'winget не найден' 'err'; break }
        if ($Mode -eq 'upgrade' -and -not (Test-JobCancel)) {
            if ($r.Code -eq -1978335090) {
                # Новая версия ставится другим типом установщика: winget сам удалит старую и поставит новую.
                Write-Log '     Другой тип установщика - пробую заменить: удалить старую версию и поставить новую...' 'warn'
                $r = Invoke-Winget -Arguments ($argLine + ' --uninstall-previous') -TimeoutSec 1800
            } elseif ($r.Code -eq -1978335212) {
                # Пакет был в списке обновлений, но точный поиск по Id его не нашёл - пробуем без -e.
                Write-Log '     Не найден по точному Id - пробую ещё раз без точного совпадения...' 'warn'
                $r = Invoke-Winget -Arguments ('upgrade --id "' + $id + '" --silent --accept-package-agreements --include-unknown') -TimeoutSec 1800
            }
        }
        # 0 = успех; -1978335189 = нет применимого обновления; -1978335135 = уже установлено.
        if ($r.Code -eq 0 -or $r.Code -eq -1978335135) {
            $ok++; Write-Log ($verb + ' завершено: ' + $id) 'ok'
            Add-History -Kind 'app' -Name ($verb + ': ' + $id)
        } elseif ($r.Code -eq -1978335189) {
            $ok++; Write-Log ($verb + ': ' + $id + ' - подходящего обновления для этой системы нет, пропущено') 'warn'
        } else {
            $fail += $id
            $why = Get-WingetErrorHint -Code $r.Code -Output ([string]$r.Output)
            Write-Log ($verb + ' не удалось: ' + $id + ' (код ' + $r.Code + ')' + $(if ($why) { ' - ' + $why } else { '' })) 'err'
            Add-History -Kind 'app' -Name ($verb + ': ' + $id) -Result 'fail' -Detail $why
        }
    }
    Set-JobProgress 1 ''
    return @{ Ok = $ok; Fail = $fail }
}

function Get-WingetErrorHint {
    # Понятная причина ошибки winget для журнала.
    param([int]$Code, [string]$Output = '')
    if ($Output -match '\b1603\b' -or $Output -match '\b1618\b') {
        if ($Output -match '\b1618\b') { return 'сейчас идёт другая установка Windows, повторите позже' }
        return 'установщик программы завершился с ошибкой; закройте программу (и её значок в трее) и повторите'
    }
    switch ($Code) {
        -1978335215 { return 'файл на сайте изменился, а каталог winget ещё не обновлён; повторите через день-два' }
        -1978335090 { return 'нужна переустановка: удалите программу и установите заново' }
        -1978335212 { return 'winget не нашёл установленную копию; обновите программу вручную или переустановите' }
        -2145844845 { return 'сайт программы отказал в скачивании (403); повторите позже' }
        -2145844844 { return 'файл на сайте программы не найден (404); каталог winget устарел' }
        -1978335216 { return 'нет подходящего установщика для этой системы' }
        -1978334975 { return 'программа сейчас запущена; закройте её и повторите' }
        -1978334974 { return 'сейчас идёт другая установка; повторите позже' }
        -1978334967 { return 'нужна перезагрузка, потом повторите' }
        -1978334972 { return 'не хватает места на диске' }
    }
    if ($Output -match '(?i)Forbidden|403') { return 'сайт программы отказал в скачивании; повторите позже' }
    return ''
}

function Get-AppCatalog {
    # apps.json: { Categories: { "Имя": [ {Name, Id, Description} ] }, Kits: [ {Name, Desc, Ids} ] }
    # Старый формат (ManualCategories / Presets) тоже понимаем.
    $cat = @{ Categories = [ordered]@{}; Kits = @() }
    try {
        $j = Get-Content -LiteralPath $AppsJsonPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $cats = if ($j.Categories) { $j.Categories } else { $j.ManualCategories }
        foreach ($p in $cats.PSObject.Properties) {
            $cat.Categories[$p.Name] = @($p.Value | ForEach-Object { @{ Name = [string]$_.Name; Id = [string]$_.Id; Desc = [string]$_.Description; Site = [string]$_.Site } })
        }
        if ($j.Kits) { $cat.Kits = @($j.Kits | ForEach-Object { @{ Name = [string]$_.Name; Desc = [string]$_.Desc; Ids = @($_.Ids) } }) }
        elseif ($j.Presets) { foreach ($p in $j.Presets.PSObject.Properties) { $cat.Kits += @{ Name = $p.Name; Desc = ''; Ids = @($p.Value) } } }
    } catch {}
    return $cat
}

function Get-CatalogIcons {
    <#
      Фон. Значки программ из каталога (apps.json, поле Site): favicon сайта программы через
      сервис значков Google, 64 px. Скачиваются один раз и лежат в data\icons; не нашлось -
      пустой файл .none, повтор через неделю. Возвращает Id -> PNG-байты.
    #>
    param([object[]]$Apps)
    $dir = Join-Path $DataRoot 'icons'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $out = @{}
    $todo = @()
    foreach ($a in $Apps) {
        if (-not $a.Site -or -not $a.Id) { continue }
        $safe = ($a.Id -replace '[^A-Za-z0-9._-]', '_')
        $f = Join-Path $dir ($safe + '.png')
        $none = Join-Path $dir ($safe + '.none')
        if (Test-Path -LiteralPath $f) { try { $out[$a.Id] = [System.IO.File]::ReadAllBytes($f) } catch {}; continue }
        if ((Test-Path -LiteralPath $none) -and ((Get-Item -LiteralPath $none).LastWriteTime -gt (Get-Date).AddDays(-7))) { continue }
        $todo += @{ Id = $a.Id; Site = $a.Site; File = $f; None = $none }
    }
    if ($todo.Count) {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
        foreach ($t in $todo) {
            if ($Job -and $Job.Cancel) { break }
            $u = 'https://www.google.com/s2/favicons?sz=64&domain_url=' + [uri]::EscapeDataString('https://' + $t.Site)
            try {
                $wc = New-Object System.Net.WebClient
                $b = $wc.DownloadData($u); $wc.Dispose()
                # Должна быть картинка (PNG 89 50, JPEG FF D8, GIF 47 49, ICO 00 00), а не страница с ошибкой.
                if ($b.Length -gt 100 -and (($b[0] -eq 0x89 -and $b[1] -eq 0x50) -or ($b[0] -eq 0xFF -and $b[1] -eq 0xD8) -or ($b[0] -eq 0x47 -and $b[1] -eq 0x49) -or ($b[0] -eq 0 -and $b[1] -eq 0))) {
                    [System.IO.File]::WriteAllBytes($t.File, $b); $out[$t.Id] = $b
                } else { [System.IO.File]::WriteAllText($t.None, '') }
            } catch {
                # 404 - у сайта значка нет, не спрашиваем неделю. Нет интернета и т.п. - попробуем в следующий раз.
                $code = 0; try { $code = [int]$_.Exception.InnerException.Response.StatusCode } catch {}
                if ($code -eq 404) { try { [System.IO.File]::WriteAllText($t.None, '') } catch {} }
            }
        }
        Write-Log ('Значки каталога: скачано ' + @($todo | Where-Object { $out.ContainsKey($_.Id) }).Count + ' из ' + $todo.Count)
    }
    return $out
}

function Get-ProgramIconIndex {
    # Фон. Значки установленных программ по имени (для списков winget, где есть только имя и Id).
    $map = @{}
    foreach ($p in @(Get-InstalledPrograms -WithIcons)) {
        if (-not $p.Icon) { continue }
        $k = Get-ProgramNameKey $p.Name
        if ($k -and -not $map.ContainsKey($k)) { $map[$k] = $p.Icon }
    }
    return $map
}

function Find-ProgramIconByName {
    # Сначала точное совпадение ключа имени, потом «начинается с» (не короче 5 букв).
    param([hashtable]$Index, [string[]]$Names)
    $keys = @($Names | ForEach-Object { Get-ProgramNameKey $_ } | Where-Object { $_.Length -ge 3 })
    foreach ($k in $keys) { if ($Index.ContainsKey($k)) { return , $Index[$k] } }
    foreach ($k in $keys) {
        if ($k.Length -lt 5) { continue }
        foreach ($rk in $Index.Keys) { if ($rk.StartsWith($k) -or ($rk.Length -ge 5 -and $k.StartsWith($rk))) { return , $Index[$rk] } }
    }
    return $null
}

function Get-ProgramNameKey {
    # «Mozilla Firefox (x64 ru)» -> «mozillafirefox»: без скобок, версий и знаков.
    param([string]$Name)
    $n = ([string]$Name).ToLowerInvariant() -replace '\(.*?\)', '' -replace '\b(x64|x86|64-bit|32-bit|amd64)\b', '' -replace '\d+(\.\d+)+', ''
    return ($n -replace '[^a-zа-яё0-9]', '')
}

function Install-WingetClient {
    <#
      Фон. Ставит winget (App Installer) на этот ПК:
        1) регистрирует уже лежащий в системе App Installer (частый случай на чистой Windows);
        2) иначе качает с официального GitHub Microsoft (winget-cli): зависимости и
           Microsoft.DesktopAppInstaller.msixbundle, проверяет подпись Microsoft и ставит.
      Возвращает $true, если winget после этого найден.
    #>
    if (Get-WingetPath) { Write-Log 'winget уже установлен' 'ok'; return $true }
    Write-Log 'Пробую зарегистрировать встроенный App Installer...'
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction Stop
        Start-Sleep -Seconds 2
        if (Get-WingetPath) { Write-Log 'winget готов' 'ok'; Add-History -Kind 'app' -Name 'Установлен winget (регистрация App Installer)'; return $true }
    } catch { Write-Log ('Встроенного App Installer нет: ' + $_.Exception.Message) }

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $dir = Join-Path $WorkFolder 'winget-setup'
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
    $base = 'https://github.com/microsoft/winget-cli/releases/latest/download/'
    $arch = switch -Regex ($env:PROCESSOR_ARCHITECTURE) { 'ARM64' { 'arm64' } 'x86' { if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' } } default { 'x64' } }
    $check = {
        param($f)
        $sig = Get-AuthenticodeSignature -LiteralPath $f
        if ($sig.Status -ne 'Valid' -or [string]$sig.SignerCertificate.Subject -notmatch '(?i)O=Microsoft Corporation') { throw ('подпись ' + [System.IO.Path]::GetFileName($f) + ' не прошла проверку: ' + $sig.Status) }
    }
    try {
        Set-JobProgress -1 'Загрузка зависимостей winget...'
        Write-Log 'Скачиваю winget с GitHub Microsoft (microsoft/winget-cli)...'
        $depZip = Join-Path $dir 'deps.zip'
        Invoke-WebRequest -Uri ($base + 'DesktopAppInstaller_Dependencies.zip') -OutFile $depZip -UseBasicParsing -TimeoutSec 300 -ErrorAction Stop
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($depZip, (Join-Path $dir 'deps'))
        $deps = @(Get-ChildItem -LiteralPath (Join-Path $dir 'deps') -Recurse -Filter '*.appx' -ErrorAction Stop | Where-Object { $_.FullName -match ('(?i)[\\_]' + $arch + '[\\_.]') })
        foreach ($d in $deps) {
            & $check $d.FullName
            Write-Log ('Зависимость: ' + $d.Name)
            try { Add-AppxPackage -Path $d.FullName -ErrorAction Stop } catch { if ($_.Exception.Message -notmatch '0x80073D06|более поздняя|higher version') { Write-Log ('   ' + $_.Exception.Message) 'warn' } }
        }
        Set-JobProgress -1 'Загрузка App Installer...'
        $bundle = Join-Path $dir 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
        Invoke-WebRequest -Uri ($base + 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle') -OutFile $bundle -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop
        & $check $bundle
        Set-JobProgress -1 'Установка winget...'
        Write-Log 'Устанавливаю App Installer...'
        Add-AppxPackage -Path $bundle -ErrorAction Stop
        Start-Sleep -Seconds 3
    } catch {
        Write-Log ('Установка winget не удалась: ' + $_.Exception.Message) 'err'
        Write-Log 'Можно поставить вручную: Microsoft Store → «Установщик приложений» (App Installer).' 'warn'
        Add-History -Kind 'app' -Name 'Установка winget' -Result 'fail' -Detail $_.Exception.Message
        return $false
    } finally {
        try { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
    if (Get-WingetPath) {
        Write-Log 'winget установлен' 'ok'
        Add-History -Kind 'app' -Name 'Установлен winget с GitHub Microsoft'
        try { [void](Invoke-Winget -Arguments 'source update' -TimeoutSec 180 -Quiet) } catch {}
        return $true
    }
    Write-Log 'App Installer установлен, но winget пока не виден. Перезапустите PotatoPC или войдите в систему заново.' 'warn'
    return $false
}
