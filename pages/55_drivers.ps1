# PAGE: drivers
# TITLE: Драйверы
# ICON: chip
# ORDER: 55

$script:DrUi = $null
$script:DeviceErrorText = @{
    1 = 'Устройство настроено неправильно'; 3 = 'Драйвер повреждён или не хватает памяти'; 10 = 'Устройство не запускается'
    12 = 'Не хватает ресурсов'; 14 = 'Нужна перезагрузка'; 18 = 'Нужно переустановить драйвер'; 19 = 'Ошибка в реестре'
    21 = 'Устройство удаляется'; 22 = 'Устройство отключено'; 24 = 'Устройство отсутствует или работает неправильно'
    28 = 'Драйвер не установлен'; 31 = 'Драйвер не загрузился'; 37 = 'Драйвер не запустился'; 39 = 'Драйвер повреждён или отсутствует'
    43 = 'Устройство сообщило о сбое'; 48 = 'Драйвер заблокирован как несовместимый'; 52 = 'Нет цифровой подписи драйвера'
}

function Get-DriverScan {
    # Фон: проблемные устройства, обновления драйверов из Microsoft Update, установленные драйверы.
    $r = @{ Problems = @(); Updates = @(); Drivers = @(); WuError = ''; Backup = $null; Model = '' }
    Set-JobProgress -1 'Устройства...'
    try {
        $r.Problems = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object { $_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -ne 45 } | ForEach-Object {
            @{ Name = $(if ($_.Name) { [string]$_.Name } else { 'Неизвестное устройство' }); Id = [string]$_.PNPDeviceID; Code = [int]$_.ConfigManagerErrorCode; Class = [string]$_.PNPClass; HwIds = @($_.HardwareID) }
        })
    } catch {}
    try {
        $r.Drivers = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop | Where-Object { $_.DeviceName -and $_.DriverVersion } | ForEach-Object {
            @{ Name = [string]$_.DeviceName; Version = [string]$_.DriverVersion; Date = $(try { [datetime]$_.DriverDate } catch { $null }); Maker = [string]$_.Manufacturer
               Class = [string]$_.DeviceClass; HwId = ([string]$_.HardWareID).ToLowerInvariant(); Inf = [string]$_.InfName }
        })
    } catch {}
    Set-JobProgress -1 'Поиск в Microsoft Update (может занять пару минут)...'
    Write-Log 'Ищу драйверы в Microsoft Update - это может занять несколько минут...'
    try {
        $s = New-Object -ComObject Microsoft.Update.Session
        $s.ClientApplicationID = 'PotatoPC'
        $sr = $s.CreateUpdateSearcher()
        $res = $sr.Search("IsInstalled=0 and Type='Driver' and IsHidden=0")
        foreach ($u in $res.Updates) {
            $hw = ([string]$u.DriverHardwareID).ToLowerInvariant()
            $cur = $null
            foreach ($d in $r.Drivers) { if ($hw -and $d.HwId -and ($d.HwId -eq $hw -or $d.HwId.StartsWith($hw))) { $cur = $d; break } }
            $prob = $null
            foreach ($p in $r.Problems) { if ($hw -and $p.Id.ToLowerInvariant().Contains(($hw -split '\\')[-1])) { $prob = $p; break } }
            $r.Updates += @{
                Id = [string]$u.Identity.UpdateID; Title = [string]$u.Title; Maker = [string]$u.DriverManufacturer
                Model = [string]$u.DriverModel; Class = [string]$u.DriverClass; Date = $(try { [datetime]$u.DriverVerDate } catch { $null })
                Size = [double]$u.MaxDownloadSize; Current = $cur; ForProblem = [bool]$prob
            }
        }
    } catch { $r.WuError = $_.Exception.Message }
    try {
        $dir = Join-Path $BackupFolder 'drivers'
        $last = Get-ChildItem -LiteralPath $dir -Directory -ErrorAction Stop | Sort-Object Name -Descending | Select-Object -First 1
        if ($last) { $r.Backup = @{ Path = $last.FullName; Time = $last.CreationTime; Count = @(Get-ChildItem -LiteralPath $last.FullName -Directory -ErrorAction SilentlyContinue).Count } }
    } catch {}
    try { $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop; $r.Model = ([string]$cs.Manufacturer).Trim() + ' ' + ([string]$cs.Model).Trim(); $r.Laptop = ([int]$cs.PCSystemType -eq 2) } catch {}
    $r.Hw = Get-DriverSources
    return $r
}

function Backup-Drivers {
    $dir = Join-Path (Join-Path $BackupFolder 'drivers') (Get-Date -Format 'yyyyMMdd-HHmmss')
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-JobProgress -1 'Резервная копия драйверов...'
    Write-Log ('Резервная копия драйверов: ' + $dir)
    try {
        $n = @(Export-WindowsDriver -Online -Destination $dir -ErrorAction Stop).Count
        Write-Log ('Сохранено драйверов: ' + $n) 'ok'
        Add-History -Kind 'drivers' -Name ('Резервная копия драйверов (' + $n + ')') -Ref $dir
        return $dir
    } catch { Write-Log ('Резервная копия не удалась: ' + $_.Exception.Message) 'warn'; return $null }
}

function Install-DriverUpdates {
    param([string[]]$Ids, [bool]$Backup = $true)
    if ($Backup) { [void](Backup-Drivers) }
    [void](New-RestorePoint -Description 'PotatoPC: драйверы')
    $s = New-Object -ComObject Microsoft.Update.Session
    $s.ClientApplicationID = 'PotatoPC'
    Set-JobProgress -1 'Повторный поиск выбранных драйверов...'
    $res = $s.CreateUpdateSearcher().Search("IsInstalled=0 and Type='Driver' and IsHidden=0")
    $coll = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $res.Updates) { if ($Ids -contains [string]$u.Identity.UpdateID) { if (-not $u.EulaAccepted) { try { $u.AcceptEula() } catch {} }; [void]$coll.Add($u) } }
    if ($coll.Count -eq 0) { Write-Log 'Выбранные драйверы больше не предлагаются Windows Update' 'warn'; return @{ Ok = 0; Fail = 0; Reboot = $false } }
    Set-JobProgress -1 ('Загрузка драйверов: ' + $coll.Count)
    Write-Log ('Загружаю драйверов: ' + $coll.Count)
    $dl = $s.CreateUpdateDownloader(); $dl.Updates = $coll
    [void]$dl.Download()
    Set-JobProgress -1 'Установка драйверов...'
    Write-Log 'Устанавливаю...'
    $inst = $s.CreateUpdateInstaller(); $inst.Updates = $coll
    $ir = $inst.Install()
    $ok = 0; $fail = 0
    for ($i = 0; $i -lt $coll.Count; $i++) {
        $code = $ir.GetUpdateResult($i).ResultCode
        $t = $coll.Item($i).Title
        if ($code -eq 2 -or $code -eq 3) { $ok++; Write-Log ('Установлен: ' + $t) 'ok'; Add-History -Kind 'drivers' -Name ('Драйвер: ' + $t) }
        else { $fail++; Write-Log ('Не установлен: ' + $t + ' (код ' + $code + ')') 'err'; Add-History -Kind 'drivers' -Name ('Драйвер: ' + $t) -Result 'fail' }
    }
    if ($ir.RebootRequired) { Write-Log 'Для завершения нужна перезагрузка' 'warn' }
    return @{ Ok = $ok; Fail = $fail; Reboot = [bool]$ir.RebootRequired }
}

# --- Каталог Microsoft Update (catalog.update.microsoft.com) ---
# Тот же каталог, из которого берёт драйверы Windows Update, но в нём намного
# больше версий: туда выкладывают драйверы Intel, Realtek, AMD и др.

function Get-CatalogText {
    param([string]$Html)
    $t = [regex]::Replace([string]$Html, '<[^>]+>', ' ')
    $t = [System.Net.WebUtility]::HtmlDecode($t)
    return ([regex]::Replace($t, '\s+', ' ')).Trim()
}

function Search-DriverCatalog {
    # Фон. Ищет драйверы по ID оборудования. Возвращает список, новые сверху.
    param([string[]]$HardwareIds)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $queries = New-Object System.Collections.ArrayList
    foreach ($h in @($HardwareIds | Select-Object -First 3)) {
        $q = ([string]$h).Trim()
        if ($q -and -not $queries.Contains($q)) { [void]$queries.Add($q) }
        # Короткий вариант: VEN_xxxx&DEV_yyyy / VID_xxxx&PID_yyyy - находит больше.
        $m = [regex]::Match($q, '(VEN|VID)_[0-9A-Fa-f]{4}&(DEV|PID)_[0-9A-Fa-f]{4}')
        if ($m.Success -and -not $queries.Contains($m.Value)) { [void]$queries.Add($m.Value) }
        # ACPI\INT33A1 и подобные
        if ($q -match '^ACPI\\([A-Z0-9]{4,8})$' -and -not $queries.Contains($Matches[1])) { [void]$queries.Add($Matches[1]) }
    }
    $isArm = $env:PROCESSOR_ARCHITECTURE -match 'ARM'
    $found = @{}
    foreach ($q in $queries) {
        if (Test-JobCancel) { break }
        Write-Log ('Каталог Microsoft: ищу ' + $q)
        try {
            $url = 'https://www.catalog.update.microsoft.com/Search.aspx?q=' + [uri]::EscapeDataString($q)
            $html = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop).Content
        } catch { Write-Log ('Каталог не ответил: ' + $_.Exception.Message) 'warn'; continue }
        # Строки результатов: td[1] название, [2] продукты, [3] класс, [4] дата,
        # [5] версия, [6] размер, [7] кнопка «Download» с GUID обновления.
        foreach ($row in [regex]::Matches($html, '<tr[^>]*>([\s\S]*?)</tr>')) {
            $tds = @([regex]::Matches($row.Groups[1].Value, '<td[^>]*>([\s\S]*?)</td>') | ForEach-Object { $_.Groups[1].Value })
            if ($tds.Count -lt 8) { continue }
            $gm = [regex]::Match($tds[7], 'id="([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})"')
            if (-not $gm.Success) { $gm = [regex]::Match($row.Value, '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') }
            if (-not $gm.Success) { continue }
            $g = $gm.Groups[1].Value
            if ($found.ContainsKey($g)) { continue }
            $title = Get-CatalogText $tds[1]
            if (-not $title) { continue }
            if (-not $isArm -and $title -match '(?i)arm64') { continue }
            $date = $null
            try { $date = [datetime]::ParseExact((Get-CatalogText $tds[4]), 'M/d/yyyy', [System.Globalization.CultureInfo]::InvariantCulture) } catch {}
            $size = Get-CatalogText ([regex]::Match($tds[6], '<span[^>]*>([\s\S]*?)</span>').Groups[1].Value)
            if (-not $size) { $size = Get-CatalogText $tds[6] }
            $found[$g] = @{ Guid = $g; Title = $title; Products = (Get-CatalogText $tds[2]); Class = (Get-CatalogText $tds[3]); Date = $date; Version = (Get-CatalogText $tds[5]); Size = $size; Query = $q }
        }
        if ($found.Count -ge 25) { break }
    }
    return @($found.Values | Sort-Object { if ($_.Date) { $_.Date } else { [datetime]::MinValue } } -Descending)
}

function Get-CatalogDownloadUrls {
    param([string]$Guid)
    $post = @{ size = 0; updateID = $Guid; uidInfo = $Guid } | ConvertTo-Json -Compress
    $resp = Invoke-WebRequest -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method Post -Body @{ updateIDs = '[' + $post + ']' } -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    $text = $resp.Content.Replace('www.download.windowsupdate', 'download.windowsupdate')
    return @([regex]::Matches($text, "downloadInformation\[\d+\]\.files\[\d+\]\.url\s*=\s*'([^']+)'") | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
}

function Install-CatalogDriver {
    # Фон. Скачивает .cab из каталога, распаковывает и ставит через pnputil.
    param([string]$Guid, [string]$Title, [bool]$Backup = $true)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $urls = @(Get-CatalogDownloadUrls -Guid $Guid)
    if ($urls.Count -eq 0) { throw 'каталог не дал ссылку на скачивание' }
    $dir = Join-Path $WorkFolder ('catalog\' + $Guid)
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    $ext = Join-Path $dir 'files'
    New-Item -ItemType Directory -Path $ext -Force | Out-Null
    if ($Backup) { [void](Backup-Drivers) }
    [void](New-RestorePoint -Description 'PotatoPC: драйвер из каталога')
    foreach ($u in $urls) {
        if (Test-JobCancel) { return $false }
        $name = [System.IO.Path]::GetFileName(([uri]$u).AbsolutePath)
        $file = Join-Path $dir $name
        Set-JobProgress -1 ('Загрузка ' + $name)
        Write-Log ('Скачиваю ' + $name)
        $u = $u -replace '^http://', 'https://'
        $host_ = ([uri]$u).Host
        if ($host_ -notmatch '(?i)(^|\.)(windowsupdate\.com|microsoft\.com)$') { throw ('неожиданный адрес загрузки: ' + $host_) }
        Invoke-WebRequest -Uri $u -OutFile $file -UseBasicParsing -TimeoutSec 900 -ErrorAction Stop
        # Пакет качается по HTTPS с серверов Microsoft. Если у .cab есть подпись -
        # она обязана быть верной и от Microsoft. Сам драйвер Windows всё равно
        # проверит при установке: неподписанный pnputil не поставит.
        $sig = Get-AuthenticodeSignature -LiteralPath $file
        if ($sig.Status -ne 'NotSigned' -and ($sig.Status -ne 'Valid' -or [string]$sig.SignerCertificate.Subject -notmatch '(?i)Microsoft')) { throw ('подпись файла не прошла проверку: ' + $sig.Status) }
        if ($name -match '(?i)\.cab$') {
            $r = Invoke-ProcessLive -FilePath (Join-Path $env:WINDIR 'System32\expand.exe') -Arguments ('-F:* "' + $file + '" "' + $ext + '"') -TimeoutSec 600 -Quiet
            if ($r.Code -ne 0) { throw ('не распаковался ' + $name) }
        } else { Copy-Item -LiteralPath $file -Destination $ext }
    }
    $infs = @(Get-ChildItem -LiteralPath $ext -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue)
    if ($infs.Count -eq 0) { throw 'в пакете нет .inf - это не драйвер' }
    Set-JobProgress -1 'Установка драйвера...'
    $r = Invoke-ProcessLive -FilePath (Join-Path $env:WINDIR 'System32\pnputil.exe') -Arguments ('/add-driver "' + (Join-Path $ext '*.inf') + '" /subdirs /install') -TimeoutSec 900 -Encoding oem
    # 0 - установлен, 3010 - нужна перезагрузка, 259 - подходящих устройств нет (драйвер добавлен в хранилище)
    $ok = $r.Code -in @(0, 3010)
    if ($r.Code -eq 259) { Write-Log 'Драйвер добавлен в систему, но к устройствам не подошёл (возможно, выбран не тот вариант)' 'warn' }
    elseif ($ok) { Write-Log ('Драйвер установлен: ' + $Title + $(if ($r.Code -eq 3010) { '. Нужна перезагрузка' } else { '' })) 'ok' }
    else { Write-Log ('pnputil завершился с кодом ' + $r.Code) 'err' }
    Add-History -Kind 'drivers' -Name ('Драйвер из каталога Microsoft: ' + $Title) -Result $(if ($ok) { 'ok' } else { 'fail' }) -Ref $Guid
    try { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    return $ok
}

# --- Где скачать вручную ---

function Get-DriverSources {
    # Фон. Производитель, модель, серийный номер, плата и видеокарты - чтобы
    # отправить на нужный сайт поддержки.
    $r = @{ Maker = ''; Model = ''; Serial = ''; Board = ''; BoardMaker = ''; Gpus = @(); CpuMaker = '' }
    try { $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop; $r.Maker = ([string]$cs.Manufacturer).Trim(); $r.Model = ([string]$cs.Model).Trim() } catch {}
    try { $p = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop; if ($p.Version -and $r.Maker -match '(?i)lenovo') { $r.Model = ([string]$p.Version).Trim() } } catch {}
    try { $r.Serial = ([string](Get-CimInstance Win32_BIOS -ErrorAction Stop).SerialNumber).Trim() } catch {}
    try { $bb = Get-CimInstance Win32_BaseBoard -ErrorAction Stop; $r.Board = ([string]$bb.Product).Trim(); $r.BoardMaker = ([string]$bb.Manufacturer).Trim() } catch {}
    try { $r.Gpus = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object { [string]$_.Name }) } catch {}
    try { $r.CpuMaker = [string](Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).Manufacturer } catch {}
    if ($r.Serial -match '(?i)^(to be filled|default string|system serial|0+|none)$') { $r.Serial = '' }
    return $r
}

function Get-VendorLinks {
    param($Src)
    $links = @()
    $m = ([string]$Src.Maker).ToLowerInvariant()
    $vendors = @(
        @{ K = 'lenovo'; N = 'Lenovo'; U = 'https://pcsupport.lenovo.com/' }
        @{ K = 'hewlett|^hp'; N = 'HP'; U = 'https://support.hp.com/drivers' }
        @{ K = 'dell'; N = 'Dell'; U = 'https://www.dell.com/support/home/' }
        @{ K = 'asus'; N = 'ASUS'; U = 'https://www.asus.com/support/download-center/' }
        @{ K = 'acer'; N = 'Acer'; U = 'https://www.acer.com/support' }
        @{ K = 'micro-star|msi'; N = 'MSI'; U = 'https://www.msi.com/support/download' }
        @{ K = 'gigabyte'; N = 'Gigabyte'; U = 'https://www.gigabyte.com/Support' }
        @{ K = 'asrock'; N = 'ASRock'; U = 'https://www.asrock.com/support/index.asp' }
        @{ K = 'huawei'; N = 'Huawei'; U = 'https://consumer.huawei.com/support/' }
        @{ K = 'samsung'; N = 'Samsung'; U = 'https://www.samsung.com/support/' }
        @{ K = 'toshiba|dynabook'; N = 'Dynabook (Toshiba)'; U = 'https://support.dynabook.com/' }
        @{ K = 'microsoft'; N = 'Microsoft Surface'; U = 'https://support.microsoft.com/surface' }
    )
    $isOem = $false
    foreach ($v in $vendors) {
        if ($m -match $v.K) {
            $u = $v.U
            if ($v.N -eq 'Dell' -and $Src.Serial) { $u = 'https://www.dell.com/support/home/product-support/servicetag/' + [uri]::EscapeDataString($Src.Serial) + '/drivers' }
            $links += @{ Title = 'Сайт ' + $v.N + ' - драйверы для ' + $Src.Model; Sub = $(if ($Src.Serial) { 'Найдите модель по серийному номеру ' + $Src.Serial + ' (кнопка скопирует его)' } else { 'Найдите модель ' + $Src.Model }); Url = $u; Copy = $(if ($Src.Serial) { $Src.Serial } else { $Src.Model }); Main = $true }
            $isOem = $true; break
        }
    }
    # Самосборный ПК: драйверы - на сайте производителя материнской платы.
    $bm = ([string]$Src.BoardMaker).ToLowerInvariant()
    if (-not $isOem -and $Src.Board) {
        foreach ($v in $vendors) {
            if ($bm -match $v.K) { $links += @{ Title = 'Материнская плата ' + $v.N + ' ' + $Src.Board; Sub = 'Чипсет, сеть, звук и USB для этой платы'; Url = $v.U; Copy = $Src.Board; Main = $true }; break }
        }
    }
    $g = ($Src.Gpus -join ' ').ToLowerInvariant()
    if ($g -match 'nvidia|geforce|quadro') { $links += @{ Title = 'NVIDIA - драйвер видеокарты'; Sub = 'Официальный сайт: выберите свою модель GeForce'; Url = 'https://www.nvidia.com/en-us/drivers/'; Copy = '' } }
    if ($g -match 'radeon|amd') { $links += @{ Title = 'AMD - драйвер видео и чипсета'; Sub = 'AMD Software: Adrenalin Edition'; Url = 'https://www.amd.com/en/support/download/drivers.html'; Copy = '' } }
    if ($g -match 'intel' -or ([string]$Src.CpuMaker) -match '(?i)intel') { $links += @{ Title = 'Intel Driver & Support Assistant'; Sub = 'Сам находит драйверы Intel: графика, Wi-Fi, Bluetooth, чипсет'; Url = 'https://www.intel.com/content/www/us/en/support/detect.html'; Copy = '' } }
    if (-not $isOem -and -not $Src.Board) { $links += @{ Title = 'Поиск драйверов для ' + $Src.Maker + ' ' + $Src.Model; Sub = 'Производитель не распознан - откроется поиск'; Url = 'https://www.bing.com/search?q=' + [uri]::EscapeDataString($Src.Maker + ' ' + $Src.Model + ' drivers support'); Copy = '' } }
    $links += @{ Title = 'Каталог Центра обновления Майкрософт'; Sub = 'Ищите по ID оборудования из списка «Устройства с ошибками»'; Url = 'https://www.catalog.update.microsoft.com/'; Copy = '' }
    return $links
}

function Build-Page_drivers {
    $ui = @{ Checks = @{} }
    $scan = New-Button -Text 'Проверить' -Icon 'search' -OnClick { Update-DriverPage }
    $devmgmt = New-Button -Text 'Диспетчер устройств' -Kind Ghost -OnClick { Start-Process devmgmt.msc }
    $ab = New-ActionBar
    $ui.Bar = $ab
    $ui.BackupChk = New-CheckBox -Text 'Резервная копия драйверов' -Checked $true
    $ui.InstBtn = New-Button -Text 'Установить драйверы' -Icon 'play' -Kind Primary -OnClick { Start-DriverInstall }
    $ui.InstBtn.IsEnabled = $false
    foreach ($x in @($ui.BackupChk, $ui.InstBtn)) { $x.Margin = New-Thickness 22, 0, 0, 0; $x.VerticalAlignment = 'Center'; [void]$ab.Right.Children.Add($x) }
    $L = New-PageLayout -Title 'Драйверы' -Subtitle 'Только подписанные драйверы из каталога Microsoft Update' -HeaderRight @($devmgmt, $scan) -ActionBar $ab.Root
    $ui.Upd = New-StatCard -Label 'Можно обновить' -Value '…' -ValueColor 'Warn'
    $ui.Prob = New-StatCard -Label 'Проблемные устройства' -Value '…' -ValueColor 'Bad'
    $ui.Bk = New-StatCard -Label 'Резервная копия' -Value '…'
    [void]$L.Body.Children.Add((New-Grid -Columns 3 -Items @($ui.Upd.Root, $ui.Prob.Root, $ui.Bk.Root)))
    $restore = New-Button -Text 'Восстановить из копии' -Kind Ghost -OnClick { Start-DriverRestore }
    $ui.UpdSec = New-Section -Title 'Обновления драйверов'
    [void]$ui.UpdSec.Body.Children.Add((New-Placeholder 'Нажмите «Проверить». Поиск в Microsoft Update занимает 1-3 минуты.'))
    $ui.ProbSec = New-Section -Title 'Устройства с ошибками'
    $ui.ProbSec.Root.Visibility = 'Collapsed'
    $ui.AllSec = New-Section -Title 'Все драйверы' -Right @($restore)
    $ui.CatSec = New-Section -Title 'Каталог Microsoft'
    $ui.CatSec.Root.Visibility = 'Collapsed'
    $ui.ManSec = New-Section -Title 'Скачать вручную'
    [void]$ui.ManSec.Body.Children.Add((New-Placeholder 'Определяю производителя…'))
    [void]$L.Body.Children.Add($ui.UpdSec.Root)
    [void]$L.Body.Children.Add($ui.ProbSec.Root)
    [void]$L.Body.Children.Add($ui.CatSec.Root)
    [void]$L.Body.Children.Add($ui.ManSec.Root)
    [void]$L.Body.Children.Add((New-Hint -Text 'Перед установкой сохраняется резервная копия текущих драйверов и создаётся точка восстановления. Если драйвера нет в Microsoft Update, ищите его в каталоге Microsoft (кнопка у устройства) или на сайте производителя (раздел «Скачать вручную»).' -Kind 'ok'))
    [void]$L.Body.Children.Add($ui.AllSec.Root)
    $ui.AllSec.Root.Visibility = 'Collapsed'
    $script:DrUi = $ui
    return $L.Root
}

function Show-Page_drivers {
    param($Arg)
    if (-not $script:DrUi.Loaded) { Update-DriverPage }
}

function Update-DriverPage {
    $ui = $script:DrUi
    if ($ui.Busy) { return }
    $ui.Busy = $true; $ui.Loaded = $true
    $ui.UpdSec.Body.Children.Clear()
    [void]$ui.UpdSec.Body.Children.Add((New-Placeholder 'Ищу в Microsoft Update… (1-3 минуты)'))
    Start-BgTask -Name 'Поиск драйверов' -Script { Get-DriverScan } -OnDone {
        param($r, $err)
        $script:DrUi.Busy = $false
        if (-not $r) { Write-Log ('Поиск драйверов не удался: ' + $err) 'err'; return }
        Set-DriverData $r
    } | Out-Null
}

function Set-DriverData {
    param($r)
    $ui = $script:DrUi
    $ui.Model = $r.Model
    $ui.Problems = $r.Problems
    $ui.Checks = @{}
    $ui.Upd.Value.Text = [string]$r.Updates.Count
    $ui.Upd.Sub.Text = if ($r.WuError) { 'Microsoft Update недоступен' } else { 'из Microsoft Update' }
    $ui.Prob.Value.Text = [string]$r.Problems.Count
    $ui.Prob.Value.Foreground = if ($r.Problems.Count) { Get-Brush 'Bad' } else { Get-Brush 'Ok' }
    $ui.Prob.Sub.Text = if ($r.Problems.Count) { 'нет драйвера или ошибка' } else { 'всё работает' }
    if ($r.Backup) { $ui.Bk.Value.Text = $r.Backup.Time.ToString('dd.MM.yyyy'); $ui.Bk.Sub.Text = [string]$r.Backup.Count + ' драйверов'; $ui.BackupPath = $r.Backup.Path }
    else { $ui.Bk.Value.Text = 'нет'; $ui.Bk.Sub.Text = 'сделается перед установкой' }

    $ui.UpdSec.Body.Children.Clear()
    if ($r.WuError) { [void]$ui.UpdSec.Body.Children.Add((New-Placeholder ('Microsoft Update не ответил: ' + $r.WuError))) }
    elseif ($r.Updates.Count -eq 0) { [void]$ui.UpdSec.Body.Children.Add((New-Placeholder 'Новых драйверов в Microsoft Update нет.')) }
    foreach ($u in @($r.Updates | Sort-Object { -not $_.ForProblem }, { $_.Title })) {
        $chk = New-CheckBox -Checked $true -Tag $u.Id -OnChange { Update-DriverSelection }
        $cur = if ($u.Current) { 'Установлен: ' + $u.Current.Version + $(if ($u.Current.Date) { ' (' + $u.Current.Date.ToString('yyyy') + ')' } else { '' }) } else { 'Сейчас: нет драйвера' }
        $new = 'Доступен: ' + $(if ($u.Date) { $u.Date.ToString('dd.MM.yyyy') } else { '' }) + ' · ' + (Format-Size $u.Size)
        $main = New-Stack -Children @((New-Text -Text $u.Title -Size 14 -Weight 'SemiBold'), (New-Text -Text $cur -Size 12 -Color 'Muted' -Margin (0, 2, 0, 0)), (New-Text -Text $new -Size 12 -Margin (0, 2, 0, 0)))
        $badge = if ($u.ForProblem -or -not $u.Current) { New-Badge 'Нет драйвера' 'bad' } else { New-Badge 'Обновление' 'warn' }
        $icon = switch -Regex ($u.Class) { 'Display' { 'gpu' } 'Net' { 'network' } 'Audio|Media' { 'info' } 'HDC|SCSI|Disk' { 'disk' } default { 'chip' } }
        [void]$ui.UpdSec.Body.Children.Add((New-Row -Left (New-Stack -Orientation Horizontal -Children @($chk, (New-IconTile -Icon $icon -Color 'Warn'))) -Main $main -Right @($badge)))
        $ui.Checks[$u.Id] = @{ Check = $chk; Size = $u.Size; Title = $u.Title }
    }
    foreach ($row in $ui.UpdSec.Body.Children) { try { $row.Child.Children[0].Children[1].Margin = New-Thickness 12, 0, 0, 0 } catch {} }

    $ui.ProbSec.Body.Children.Clear()
    $ui.ProbSec.Root.Visibility = if ($r.Problems.Count) { 'Visible' } else { 'Collapsed' }
    foreach ($p in $r.Problems) {
        $why = $script:DeviceErrorText[[int]$p.Code]; if (-not $why) { $why = 'Ошибка устройства' }
        $main = New-TitleBlock -Title $p.Name -Sub ($p.Id + '  ·  код ' + $p.Code + ': ' + $why)
        $find = New-Button -Text 'Найти в каталоге' -Icon 'search' -Kind Small -Tag $p -OnClick { Start-CatalogSearch -Device $this.Tag }
        [void]$ui.ProbSec.Body.Children.Add((New-Row -Left (New-IconTile -Icon 'warn' -Color 'Bad') -Main $main -Right @((New-Badge $(if ($p.Code -eq 28) { 'Нет драйвера' } else { 'Ошибка' }) 'bad'), $find)))
    }

    $ui.AllSec.Body.Children.Clear()
    $ui.AllSec.Root.Visibility = 'Visible'
    $ui.AllSec.Header.Text = 'Все драйверы · ' + $r.Drivers.Count
    $toggle = New-Button -Text 'Показать список' -Kind Ghost -OnClick {
        $p = $script:DrUi.AllList
        $p.Visibility = if ($p.Visibility -eq 'Visible') { 'Collapsed' } else { 'Visible' }
        Set-ButtonText -Button $this -Text $(if ($p.Visibility -eq 'Visible') { 'Скрыть список' } else { 'Показать список' })
    }
    $toggle.HorizontalAlignment = 'Left'; $toggle.Margin = New-Thickness 10, 0, 0, 8
    [void]$ui.AllSec.Body.Children.Add($toggle)
    $ui.AllList = New-Stack
    $ui.AllList.Visibility = 'Collapsed'
    foreach ($d in @($r.Drivers | Where-Object { $_.Maker -notmatch '^\(Стандарт|^\(Standard|^Microsoft$' } | Sort-Object { $_.Class }, { $_.Name })) {
        $old = $d.Date -and ((Get-Date) - $d.Date).TotalDays -gt 5 * 365
        $sub = $d.Maker + ' · ' + $d.Version + $(if ($d.Date) { ' · ' + $d.Date.ToString('dd.MM.yyyy') } else { '' })
        $find = New-Button -Text 'Искать новее' -Kind Ghost -Tag @{ Name = $d.Name; HwIds = @($d.HwId); Current = $d } -OnClick { Start-CatalogSearch -Device $this.Tag }
        if (-not $d.HwId) { $find = $null }
        [void]$ui.AllList.Children.Add((New-Row -Main (New-TitleBlock -Title $d.Name -Sub $sub) -Right @($(if ($old) { New-Badge 'старше 5 лет' 'muted' } else { $null }), $find) -Padding (16, 4, 12, 4)))
    }
    [void]$ui.AllSec.Body.Children.Add($ui.AllList)
    Set-ManualSources -Src $r.Hw
    Update-DriverSelection
}

function Update-DriverSelection {
    $ui = $script:DrUi
    $sel = @($ui.Checks.Values | Where-Object { $_.Check.IsChecked })
    $size = 0.0; foreach ($s in $sel) { $size += $s.Size }
    $ui.Bar.Text.Text = [string]$sel.Count + ' выбрано · примерно ' + (Format-Size $size)
    $ui.InstBtn.IsEnabled = ($sel.Count -gt 0) -and -not $ui.Running
}

function Start-DriverInstall {
    $ui = $script:DrUi
    $sel = @($ui.Checks.Keys | Where-Object { $ui.Checks[$_].Check.IsChecked })
    if ($sel.Count -eq 0) { return }
    $msg = "Установить драйверы из Microsoft Update:`n  • " + (($sel | ForEach-Object { $ui.Checks[$_].Title }) -join "`n  • ") + "`n`nВо время установки экран может мигнуть, а сеть - пропасть на несколько секунд."
    if (-not (Show-Confirm -Message $msg -Title 'Драйверы')) { return }
    $ui.Running = $true; Update-DriverSelection
    Start-BgTask -Name 'Установка драйверов' -Vars @{ Ids = $sel; Bk = [bool]$ui.BackupChk.IsChecked } -Script { Install-DriverUpdates -Ids $Ids -Backup $Bk } -OnDone {
        param($r)
        $script:DrUi.Running = $false
        if ($r) {
            $m = 'Установлено: ' + $r.Ok + $(if ($r.Fail) { ', с ошибкой: ' + $r.Fail } else { '' })
            if ($r.Reboot) { $m += "`n`nНужна перезагрузка, чтобы драйверы заработали." }
            Show-Info -Message $m -Title 'Драйверы'
        }
        $script:DrUi.Loaded = $false
        Update-DriverPage
    } | Out-Null
}

function Start-DriverRestore {
    $ui = $script:DrUi
    if (-not $ui.BackupPath) { Show-Info 'Резервных копий драйверов пока нет.'; return }
    if (-not (Show-Confirm -Message ('Установить драйверы из копии ' + $ui.BackupPath + '?' + "`n`nWindows выберет подходящие версии для подключённых устройств.") -Title 'Восстановление драйверов' -Warning)) { return }
    Start-BgTask -Name 'Восстановление драйверов' -Vars @{ P = $ui.BackupPath } -Script {
        [void](New-RestorePoint -Description 'PotatoPC: восстановление драйверов')
        $r = Invoke-ProcessLive -FilePath (Join-Path $env:WINDIR 'System32\pnputil.exe') -Arguments ('/add-driver "' + (Join-Path $P '*.inf') + '" /subdirs /install') -TimeoutSec 1800 -Encoding oem
        Add-History -Kind 'drivers' -Name 'Восстановление драйверов из копии' -Ref $P -Result $(if ($r.Code -eq 0 -or $r.Code -eq 3010) { 'ok' } else { 'fail' })
        return $r.Code
    } | Out-Null
}

function Set-ManualSources {
    param($Src)
    $body = $script:DrUi.ManSec.Body
    $body.Children.Clear()
    if (-not $Src) { return }
    foreach ($l in (Get-VendorLinks -Src $Src)) {
        $open = New-Button -Text 'Открыть' -Icon 'globe' -Kind Small -Tag $l.Url -OnClick { Open-Path $this.Tag }
        $copy = $null
        if ($l.Copy) {
            $copy = New-Button -Text 'Скопировать' -Kind Ghost -Tag $l.Copy -ToolTip ('Скопировать «' + $l.Copy + '»') -OnClick { try { [System.Windows.Clipboard]::SetText([string]$this.Tag); Write-Log ('Скопировано: ' + $this.Tag) 'ok' } catch {} }
        }
        [void]$body.Children.Add((New-Row -Left (New-IconTile -Icon $(if ($l.Main) { 'globe' } else { 'chip' }) -Color $(if ($l.Main) { 'Accent' } else { 'Muted' })) -Main (New-TitleBlock -Title $l.Title -Sub $l.Sub) -Right @($copy, $open)))
    }
    [void]$body.Children.Add((New-Text -Text 'Скачивайте драйверы только с официальных сайтов. «Сборники драйверов» с неизвестных сайтов - частая причина синих экранов и вирусов.' -Size 12 -Color 'Muted' -Wrap -Margin (16, 8, 16, 12)))
}

function Start-CatalogSearch {
    param($Device)
    $ui = $script:DrUi
    $ui.CatSec.Root.Visibility = 'Visible'
    $ui.CatSec.Header.Text = 'Каталог Microsoft: ' + $Device.Name
    $ui.CatSec.Body.Children.Clear()
    [void]$ui.CatSec.Body.Children.Add((New-Placeholder ('Ищу драйверы для «' + $Device.Name + '»…')))
    $ui.CatSec.Root.BringIntoView()
    Start-BgTask -Name 'Поиск в каталоге Microsoft' -Vars @{ Ids = @($Device.HwIds) } -Context $Device -Script { , @(Search-DriverCatalog -HardwareIds $Ids) } -OnDone {
        param($res, $err, $job)
        Set-CatalogResults -Device $job.Context -Results @($res) -Err $err
    } | Out-Null
}

function Set-CatalogResults {
    param($Device, $Results, $Err)
    $body = $script:DrUi.CatSec.Body
    $body.Children.Clear()
    $q = @($Device.HwIds)[0]
    $web = New-Button -Text 'Открыть в браузере' -Kind Ghost -Tag ('https://www.catalog.update.microsoft.com/Search.aspx?q=' + [uri]::EscapeDataString([string]$q)) -OnClick { Open-Path $this.Tag }
    $web.HorizontalAlignment = 'Left'; $web.Margin = New-Thickness 8, 0, 0, 4
    $list = @($Results | Where-Object { $_ -and $_.Guid })
    if ($Err -and $list.Count -eq 0) { [void]$body.Children.Add((New-Placeholder ('Каталог недоступен: ' + $Err))) }
    elseif ($list.Count -eq 0) { [void]$body.Children.Add((New-Placeholder ('Ничего не найдено по ' + (@($Device.HwIds) -join ', ') + '. Попробуйте сайт производителя ниже.'))) }
    $cur = $Device.Current
    foreach ($x in ($list | Select-Object -First 15)) {
        $sub = @()
        if ($x.Date) { $sub += $x.Date.ToString('dd.MM.yyyy') }
        if ($x.Version) { $sub += 'версия ' + $x.Version }
        if ($x.Size) { $sub += $x.Size }
        if ($x.Products) { $sub += $x.Products }
        $badge = $null
        if ($cur -and $cur.Version -and $x.Version) {
            try { if ([version]$x.Version -gt [version]$cur.Version) { $badge = New-Badge 'новее' 'ok' } elseif ([version]$x.Version -eq [version]$cur.Version) { $badge = New-Badge 'установлен' 'muted' } } catch {}
        }
        $inst = New-Button -Text 'Установить' -Kind Small -Tag $x -OnClick { Start-CatalogInstall -Item $this.Tag }
        [void]$body.Children.Add((New-Row -Main (New-TitleBlock -Title $x.Title -Sub ($sub -join ' · ')) -Right @($badge, $inst) -Padding (16, 8, 12, 8)))
    }
    if ($list.Count) { [void]$body.Children.Add((New-Text -Text 'Сверху - самые свежие. Смотрите на «Products»: нужен вариант для вашей версии Windows. Перед установкой делается резервная копия драйверов и точка восстановления.' -Size 12 -Color 'Muted' -Wrap -Margin (16, 8, 16, 4))) }
    [void]$body.Children.Add($web)
}

function Start-CatalogInstall {
    param($Item)
    if (-not (Show-Confirm -Message ('Скачать и установить из каталога Microsoft:' + "`n`n" + $Item.Title + "`n`nПеред установкой будет резервная копия драйверов и точка восстановления.") -Title 'Драйвер')) { return }
    Start-BgTask -Name 'Установка драйвера из каталога' -Vars @{ G = $Item.Guid; T = $Item.Title; Bk = [bool]$script:DrUi.BackupChk.IsChecked } -Script { Install-CatalogDriver -Guid $G -Title $T -Backup $Bk } -OnDone {
        param($ok, $err)
        if ($err) { Show-Info ('Не получилось: ' + $err) -Icon 'Warning' }
        elseif ($ok) { Show-Info 'Драйвер установлен. Если устройство не заработало - перезагрузите компьютер.' }
        $script:DrUi.Loaded = $false
        Update-DriverPage
    } | Out-Null
}
