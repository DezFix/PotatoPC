# PAGE: test
# TITLE: Тест ПК
# ICON: gauge
# ORDER: 90

# Режим мастера: одна кнопка - проверка железа и оценка 0-100.
# 100 = средний новый ноутбук 2025 года. Опорные значения - в Get-TestReference;
# их можно уточнить под свой «эталонный» компьютер в assets\test-reference.json.

$script:TeUi = $null

function Get-TestReference {
    $ref = @{ CpuSingle = 280e6; CpuMulti = 2.0e9; MemCopy = 14000; DiskSeq = 3000; DiskRand = 50 }
    try {
        $f = Join-Path $AssetsFolder 'test-reference.json'
        if (Test-Path -LiteralPath $f) { $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $ref[$p.Name] = [double]$p.Value } }
    } catch {}
    return $ref
}

function Get-TestSteps {
    return @('Сведения о железе', 'Процессор: один поток', 'Процессор под нагрузкой и нагрев', 'Память', 'Диск: скорость', 'Диск: здоровье (SMART)', 'Батарея', 'Видео и драйверы')
}

function Get-RelScore {
    param([double]$Value, [double]$Ref, [double]$Pow = 0.6)
    if ($Value -le 0 -or $Ref -le 0) { return 0 }
    return [int][Math]::Min(100, [Math]::Round(100 * [Math]::Pow($Value / $Ref, $Pow)))
}

function Get-DiskSmart {
    # SMART через WMI (root\wmi) + счётчики надёжности Storage.
    $out = @()
    $pred = @{}
    try { foreach ($p in @(Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop)) { $pred[[string]$p.InstanceName] = [bool]$p.PredictFailure } } catch {}
    $attrs = @{}
    try {
        foreach ($d in @(Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictData -ErrorAction Stop)) {
            $vs = [byte[]]$d.VendorSpecific
            $a = @{}
            for ($o = 2; $o + 11 -lt $vs.Length; $o += 12) {
                $id = $vs[$o]
                if ($id -eq 0) { continue }
                $raw = [long]0
                for ($b = 5; $b -ge 0; $b--) { $raw = ($raw -shl 8) + $vs[$o + 5 + $b] }
                $a[[int]$id] = $raw
            }
            $attrs[[string]$d.InstanceName] = $a
        }
    } catch {}
    foreach ($pd in @(Get-PhysicalDisk -ErrorAction SilentlyContinue)) {
        $rc = $null
        try { $rc = $pd | Get-StorageReliabilityCounter -ErrorAction Stop } catch {}
        $key = $null
        $prod = ([string]$pd.FriendlyName -replace '\s+', '_').ToUpperInvariant()
        foreach ($k in $attrs.Keys) { if ($k.ToUpperInvariant().Contains($prod.Substring(0, [Math]::Min(10, $prod.Length)))) { $key = $k; break } }
        if (-not $key -and $attrs.Count -eq 1) { $key = @($attrs.Keys)[0] }
        $a = if ($key) { $attrs[$key] } else { @{} }
        $out += @{
            Name = [string]$pd.FriendlyName; Media = [string]$pd.MediaType; Bus = [string]$pd.BusType; Size = [double]$pd.Size
            Health = [string]$pd.HealthStatus; Predict = $(if ($key -and $pred.ContainsKey($key)) { $pred[$key] } else { $false })
            Realloc = $a[5]; Pending = $a[197]; Uncorr = $a[198]; Hours = $(if ($a[9]) { $a[9] } elseif ($rc) { $rc.PowerOnHours } else { $null })
            Temp = $(if ($rc -and $rc.Temperature) { $rc.Temperature } else { $null }); Wear = $(if ($rc) { $rc.Wear } else { $null })
        }
    }
    return $out
}

function Get-BatteryReport {
    $f = Join-Path $WorkFolder ('battery-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.xml')
    try {
        $r = Invoke-ProcessLive -FilePath (Join-Path $env:WINDIR 'System32\powercfg.exe') -Arguments ('/batteryreport /xml /output "' + $f + '"') -TimeoutSec 60 -Quiet
        if (-not (Test-Path -LiteralPath $f)) { return $null }
        [xml]$x = Get-Content -LiteralPath $f -Raw
        $b = @($x.BatteryReport.Batteries.Battery)[0]
        if (-not $b) { return $null }
        return @{ Design = [double]$b.DesignCapacity; Full = [double]$b.FullChargeCapacity; Cycles = [int]$b.CycleCount; Name = ([string]$b.Manufacturer + ' ' + [string]$b.Id).Trim() }
    } catch { return $null } finally { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
}

function Invoke-PcTest {
    # Фон. Весь тест. $Full - длинный режим (5 минут нагрева, 1 ГБ на диск).
    param([bool]$Full = $false)
    $ref = Get-TestReference
    $R = [ordered]@{ Time = (Get-Date).ToString('s'); Full = $Full; Pc = $env:COMPUTERNAME; Parts = [ordered]@{}; Issues = @(); Advice = @() }
    $step = 0
    $next = { param($n) $script:__s = $n; Set-JobProgress -1 ([string]$n + '|' + (Get-TestSteps)[$n]); Write-Log ('Тест: ' + (Get-TestSteps)[$n]) }

    & $next 0
    $sum = Get-SystemSummary
    $R.Summary = $sum
    try { $bios = Get-CimInstance Win32_BIOS; $R.Bios = ([string]$bios.SMBIOSBIOSVersion) } catch {}
    if (-not ('PotatoBench' -as [type])) { Add-Type -TypeDefinition ([System.IO.File]::ReadAllText((Join-Path $AssetsFolder 'PotatoBench.cs'))) -ErrorAction Stop }
    [PotatoBench]::Cancel = $false

    if (Test-JobCancel) { return $null }
    & $next 1
    $single = [PotatoBench]::CpuSingle(3000)

    if (Test-JobCancel) { return $null }
    & $next 2
    $secs = if ($Full) { 300 } else { 40 }
    $t0 = $null; $tMax = $null
    try { $t0 = Get-CpuTemperature } catch {}
    $samples = @([PotatoBench]::CpuMultiSamples($secs, [Environment]::ProcessorCount))
    try { $tMax = Get-CpuTemperature } catch {}
    $samples = @($samples | Where-Object { $_ -gt 0 })
    $multi = 0; $thr = 0.0
    if ($samples.Count -ge 5) {
        $head = @($samples | Select-Object -Skip 1 -First ([Math]::Max(2, [int]($samples.Count * 0.15))))
        $tail = @($samples | Select-Object -Last ([Math]::Max(2, [int]($samples.Count * 0.3))))
        $peak = ($head | Measure-Object -Average).Average
        $end = ($tail | Measure-Object -Average).Average
        $multi = $peak
        if ($peak -gt 0) { $thr = [Math]::Max(0, 1 - $end / $peak) }
    }
    $cpuScore = [int](0.5 * (Get-RelScore $single $ref.CpuSingle) + 0.5 * (Get-RelScore $multi $ref.CpuMulti))
    $R.Parts.cpu = @{ Title = 'Процессор'; Icon = 'cpu'; Score = $cpuScore; Hw = ($sum.Cpu + ' · ' + $sum.Cores + ' ядер / ' + $sum.Threads + ' потоков')
        Result = ('Один поток: ' + [int]($single / 1e6) + ' млн оп/с · все потоки: ' + [int]($multi / 1e6) + ' млн оп/с') }
    $thermScore = [int][Math]::Max(0, [Math]::Min(100, 100 - $thr * 250))
    $tText = 'Снижение производительности под нагрузкой за ' + $secs + ' с: ' + [int]($thr * 100) + '%'
    if ($tMax) { $tText += ' · температура: ' + $tMax + ' °C' } else { $tText += ' · датчик температуры Windows недоступен' }
    $R.Parts.thermal = @{ Title = 'Нагрев и стабильность'; Icon = 'clock'; Score = $thermScore; Hw = ('нагрузка ' + $secs + ' с на все потоки'); Result = $tText }
    if ($thr -gt 0.2) { $R.Issues += 'Процессор сбрасывает частоту под нагрузкой (' + [int]($thr * 100) + '%)'; $R.Advice += 'Почистить систему охлаждения от пыли и заменить термопасту' }

    if (Test-JobCancel) { return $null }
    & $next 3
    $mem = [PotatoBench]::MemCopy(64, 2500)
    $mods = @(); $slots = 0
    try { $mods = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop) } catch {}
    try { $slots = [int]((Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction Stop | Measure-Object MemoryDevices -Sum).Sum) } catch {}
    $types = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 34 = 'DDR5'; 35 = 'LPDDR5'; 30 = 'LPDDR4' }
    $mt = ''; $spd = 0
    if ($mods.Count) { $mt = $types[[int]$mods[0].SMBIOSMemoryType]; $spd = [int]$mods[0].ConfiguredClockSpeed; if (-not $spd) { $spd = [int]$mods[0].Speed } }
    $gb = [Math]::Round($sum.RamTotal / 1GB)
    $sizeScore = [int][Math]::Max(5, [Math]::Min(100, 30 * [Math]::Log([Math]::Max(1, $gb) / 2, 2)))
    $memScore = [int](0.6 * $sizeScore + 0.4 * (Get-RelScore $mem $ref.MemCopy))
    $chan = if ($mods.Count -eq 1) { '1 планка' } elseif ($mods.Count) { [string]$mods.Count + ' планки' } else { '' }
    $memLast = Get-MemoryDiagResult
    $R.Parts.mem = @{ Title = 'Оперативная память'; Icon = 'mem'; Score = $memScore
        Hw = ([string]$gb + ' ГБ' + $(if ($mt) { ' ' + $mt } else { '' }) + $(if ($spd) { '-' + $spd } else { '' }) + $(if ($chan) { ' · ' + $chan } else { '' }) + $(if ($slots) { ' из ' + $slots + ' слотов' } else { '' }))
        Result = ('Копирование: ' + [Math]::Round($mem / 1024, 1) + ' ГБ/с' + $(if ($memLast) { ' · проверка памяти Windows: ' + $memLast } else { ' · проверку на ошибки можно запустить кнопкой ниже' })) }
    if ($gb -lt 8) { $R.Advice += 'Добавить оперативной памяти до 8 ГБ - заметно ускорит работу' }
    if ($mods.Count -eq 1 -and $slots -gt 1) { $R.Advice += 'Поставить вторую планку памяти такой же частоты: двухканальный режим быстрее' }
    if ($memLast -like '*ошибк*') { $R.Issues += 'Проверка памяти Windows нашла ошибки'; $R.Advice += 'Заменить неисправную планку памяти' }

    if (Test-JobCancel) { return $null }
    & $next 4
    $dsize = if ($Full) { 1024 } else { 256 }
    $dfile = Join-Path ($env:SystemDrive + '\') ('PotatoPC-disktest-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.tmp')
    $d = @(0, 0, 0, 0)
    $freeMb = $sum.Disk.Free / 1MB
    if ($freeMb -gt ($dsize + 2048)) {
        try { $d = [PotatoBench]::Disk($dfile, $dsize, $(if ($Full) { 15000 } else { 6000 })) } catch { Write-Log ('Тест диска: ' + $_.Exception.Message) 'warn' }
    } else { Write-Log 'Мало места для теста диска - пропускаю замер скорости' 'warn' }

    if (Test-JobCancel) { return $null }
    & $next 5
    $smart = @(Get-DiskSmart)
    $sys = $sum.Disk
    $diskScore = [int](0.5 * (Get-RelScore $d[1] $ref.DiskSeq 0.5) + 0.5 * (Get-RelScore $d[2] $ref.DiskRand 0.5))
    $hp = @()
    foreach ($s in $smart) {
        $bad = $false
        if ($s.Predict) { $hp += $s.Name + ': SMART предсказывает отказ'; $bad = $true }
        if ([long]$s.Realloc -gt 0) { $hp += $s.Name + ': переназначенных секторов ' + $s.Realloc; $bad = $true }
        if ([long]$s.Pending -gt 0) { $hp += $s.Name + ': нестабильных секторов ' + $s.Pending; $bad = $true }
        if ($s.Wear -ge 80) { $hp += $s.Name + ': ресурс SSD израсходован на ' + $s.Wear + '%'; $bad = $true }
        if ($s.Health -and $s.Health -ne 'Healthy') { $hp += $s.Name + ': состояние ' + $s.Health; $bad = $true }
        if ($bad) { $diskScore = [Math]::Min($diskScore, 20) }
    }
    $dText = 'Чтение ' + [int]$d[1] + ' МБ/с · запись ' + [int]$d[0] + ' МБ/с · случайное 4К: ' + [Math]::Round($d[2], 1) + ' МБ/с (' + [int]$d[3] + ' IOPS)'
    $hText = if ($hp.Count) { $hp -join '; ' } else { 'SMART: ошибок нет' }
    $hours = @($smart | Where-Object { $_.Hours } | ForEach-Object { $_.Name + ': ' + $_.Hours + ' ч работы' })
    $R.Parts.disk = @{ Title = 'Диск'; Icon = 'disk'; Score = $diskScore; Hw = ($sys.Media + ' ' + (Format-Size $sys.Total) + $(if ($sys.Model) { ' · ' + $sys.Model } else { '' }))
        Result = ($dText + "`n" + $hText + $(if ($hours.Count) { ' · ' + ($hours -join ', ') } else { '' })) }
    if ($hp.Count) { $R.Issues += 'Диск: ' + ($hp -join '; '); $R.Advice += 'Срочно сохранить важные данные и заменить диск' }
    if ($sys.Media -eq 'HDD' -or ($d[2] -gt 0 -and $d[2] -lt 3)) { $R.Advice += 'Заменить жёсткий диск на SSD - самое заметное ускорение для этого ПК' }

    if (Test-JobCancel) { return $null }
    & $next 6
    if ($sum.HasBattery) {
        $bat = Get-BatteryReport
        if ($bat -and $bat.Design -gt 0) {
            $health = [Math]::Min(100, 100 * $bat.Full / $bat.Design)
            $R.Parts.battery = @{ Title = 'Батарея'; Icon = 'battery'; Score = [int]$health
                Hw = ('Заводская ' + [Math]::Round($bat.Design / 1000, 1) + ' Вт·ч → сейчас ' + [Math]::Round($bat.Full / 1000, 1) + ' Вт·ч')
                Result = ('Износ ' + [int](100 - $health) + '%' + $(if ($bat.Cycles) { ' · циклов заряда: ' + $bat.Cycles } else { '' })) }
            if ($health -lt 60) { $R.Issues += 'Батарея изношена на ' + [int](100 - $health) + '%'; $R.Advice += 'Заменить батарею' }
        }
    }

    & $next 7
    $g = @($sum.Gpus)
    if ($g.Count) {
        $main = @($g | Where-Object { $_.Discrete })[0]; if (-not $main) { $main = $g[0] }
        $gs = if ($main.Discrete) { 75 } elseif ($main.Name -match '(?i)iris|radeon|arc') { 45 } else { 30 }
        $old = $main.Date -and ((Get-Date) - $main.Date).TotalDays -gt 3 * 365
        if ($old) { $gs -= 10; $R.Advice += 'Обновить драйвер видеокарты (страница «Драйверы»)' }
        $R.Parts.gpu = @{ Title = 'Видео'; Icon = 'gpu'; Score = $gs; Hw = (($g | ForEach-Object { $_.Name }) -join ' + ')
            Result = ('Драйвер ' + $main.Driver + $(if ($main.Date) { ' от ' + $main.Date.ToString('dd.MM.yyyy') } else { '' }) + ' · оценка по типу видеокарты, без 3D-теста') }
    }
    try {
        $probs = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object { $_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -ne 45 -and $_.ConfigManagerErrorCode -ne 22 })
        if ($probs.Count) { $R.Issues += 'Устройств без драйвера или с ошибкой: ' + $probs.Count; $R.Advice += 'Установить драйверы (страница «Драйверы»)' }
    } catch {}

    $w = @{ cpu = 30; mem = 20; disk = 30; battery = 8; gpu = 7; thermal = 5 }
    $tot = 0.0; $ws = 0.0
    foreach ($k in $R.Parts.Keys) { $tot += $w[$k] * $R.Parts[$k].Score; $ws += $w[$k] }
    $R.Score = [int][Math]::Round($tot / [Math]::Max(1, $ws))
    $R.Verdict = if ($R.Score -ge 75) { 'Быстрый ПК' } elseif ($R.Score -ge 50) { 'Средний ПК' } elseif ($R.Score -ge 30) { 'Слабый ПК' } else { 'Очень слабый ПК' }
    if ($R.Issues.Count) { $R.Verdict += ', есть неисправности' }
    $R.Usage = if ($R.Score -ge 85) { 'Подходит для любых задач, включая современные игры и монтаж.' } elseif ($R.Score -ge 65) { 'Подходит для работы с фото и видео, игр на средних настройках.' } elseif ($R.Score -ge 40) { 'Подходит для офиса, учёбы, видео и лёгких игр.' } else { 'Подходит для браузера, почты и документов.' }
    $R.Advice = @($R.Advice | Select-Object -Unique)
    try { ($R | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $ReportFolder 'test-last.json') -Encoding UTF8 } catch {}
    Add-History -Kind 'test' -Name ('Тест ПК: ' + $R.Score + '/100 - ' + $R.Verdict)
    Set-JobProgress 1 '8|Готово'
    return $R
}

function Get-CpuTemperature {
    $t = @(Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | ForEach-Object { [Math]::Round($_.CurrentTemperature / 10 - 273.15) } | Where-Object { $_ -gt 10 -and $_ -lt 120 })
    if ($t.Count) { return ($t | Measure-Object -Maximum).Maximum }
    return $null
}

function Get-MemoryDiagResult {
    try {
        $e = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results' } -MaxEvents 1 -ErrorAction Stop
        $when = $e.TimeCreated.ToString('dd.MM.yyyy')
        if ($e.Id -eq 1201) { return 'ошибок нет (' + $when + ')' }
        if ($e.Id -eq 1202) { return 'найдены ошибки (' + $when + ')' }
    } catch {}
    return $null
}

function Build-Page_test {
    $ui = @{ StepRows = @() }
    $ui.QuickR = New-Radio -Title 'Быстрый · ~2 мин' -Group 'testmode' -Checked $true
    $ui.FullR = New-Radio -Title 'Полный · ~8 мин' -Group 'testmode'
    foreach ($r in @($ui.QuickR, $ui.FullR)) { $r.Margin = New-Thickness 0; $r.Padding = New-Thickness 0 }
    $ui.RunBtn = New-Button -Text 'Запустить тест' -Icon 'play' -Kind Primary -OnClick { Start-PcTest }
    $L = New-PageLayout -Title 'Тест ПК' -Subtitle 'Одна кнопка: проверка железа и отчёт для клиента. Закройте программы - они искажают результат.' -HeaderRight @($ui.QuickR, $ui.FullR, $ui.RunBtn)

    $g = New-Object System.Windows.Controls.Grid
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength 1, 'Star'
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength 300
    [void]$g.ColumnDefinitions.Add($c1); [void]$g.ColumnDefinitions.Add($c2)
    $vs = New-Stack
    $top = New-Object System.Windows.Controls.DockPanel
    $ui.Ring = New-ScoreRing -Size 128
    $ui.Ring.Margin = New-Thickness 0, 0, 22, 0
    [System.Windows.Controls.DockPanel]::SetDock($ui.Ring, 'Left')
    [void]$top.Children.Add($ui.Ring)
    $ts = New-Stack; $ts.VerticalAlignment = 'Center'
    $ui.Model = New-Text -Text 'Тест ещё не запускался' -Size 13 -Color 'Muted'
    $ui.Verdict = New-Text -Text 'Нажмите «Запустить тест»' -Size 22 -Weight 'Bold' -Wrap -Margin (0, 4, 0, 0)
    $ui.Usage = New-Text -Text 'Проверим процессор, память, диск, батарею и нагрев, поставим оценку и подскажем, что улучшить.' -Size 14 -Color 'Muted' -Wrap -Margin (0, 6, 0, 0)
    [void]$ts.Children.Add($ui.Model); [void]$ts.Children.Add($ui.Verdict); [void]$ts.Children.Add($ui.Usage)
    [void]$top.Children.Add($ts)
    [void]$vs.Children.Add($top)
    $bw = New-Stack -Orientation Horizontal -Margin (0, 16, 0, 0)
    $ui.ReportBtn = New-Button -Text 'Сохранить отчёт' -Icon 'save' -Kind Primary -OnClick { Save-MasterReport }
    $ui.ReportBtn.IsEnabled = $false
    $mem = New-Button -Text 'Проверить память на ошибки' -Icon 'mem' -OnClick {
        if (Show-Confirm -Message 'Windows проверит оперативную память при следующей перезагрузке (10-20 минут). Результат появится здесь после теста. Открыть средство проверки?') { Start-Process (Join-Path $env:WINDIR 'System32\mdsched.exe') }
    }
    $mem.Margin = New-Thickness 10, 0, 0, 0
    [void]$bw.Children.Add($ui.ReportBtn); [void]$bw.Children.Add($mem)
    [void]$vs.Children.Add($bw)
    $vc = New-Card -Child $vs -Margin (0, 0, 16, 0)
    [void]$g.Children.Add($vc)
    $steps = New-Stack
    $ui.StepTitle = New-Text -Text 'Ход теста' -Size 14 -Weight 'Bold' -Margin (0, 0, 0, 8)
    [void]$steps.Children.Add($ui.StepTitle)
    foreach ($s in (Get-TestSteps)) {
        $ic = New-Icon -Name 'clock' -Size 15 -Color 'Line'
        $t = New-Text -Text $s -Size 13 -Color 'Muted' -Margin (10, 0, 0, 0)
        $row = New-Stack -Orientation Horizontal -Children @($ic, $t) -Margin (0, 5, 0, 5)
        [void]$steps.Children.Add($row)
        $ui.StepRows += , @{ Icon = $ic; Text = $t }
    }
    $sc = New-Card -Child $steps
    [System.Windows.Controls.Grid]::SetColumn($sc, 1)
    [void]$g.Children.Add($sc)
    $g.Margin = New-Thickness 0, 0, 0, 16
    [void]$L.Body.Children.Add($g)
    $ui.Results = New-Section -Title 'Результаты по узлам' -Right @((New-Text -Text '100 = средний новый ноутбук 2025 года' -Size 12 -Color 'Muted'))
    [void]$L.Body.Children.Add($ui.Results.Root)
    $ui.AdviceSec = New-Section -Title 'Что улучшить'
    $ui.AdviceSec.Root.Visibility = 'Collapsed'
    [void]$L.Body.Children.Add($ui.AdviceSec.Root)
    $script:TeUi = $ui
    return $L.Root
}

function Show-Page_test {
    param($Arg)
    $ui = $script:TeUi
    if (-not $ui.Result) {
        try {
            $f = Join-Path $ReportFolder 'test-last.json'
            if (Test-Path -LiteralPath $f) { $ui.Result = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json; Set-TestResult $ui.Result -FromFile }
        } catch {}
    }
}

function Set-StepState {
    param([int]$Current)
    $ui = $script:TeUi
    for ($i = 0; $i -lt $ui.StepRows.Count; $i++) {
        $r = $ui.StepRows[$i]
        $path = $r.Icon.Child.Children[0]
        if ($i -lt $Current) { $path.Data = [System.Windows.Media.Geometry]::Parse($script:IconPaths.check); $path.Stroke = Get-Brush 'Ok'; $r.Text.Foreground = Get-Brush 'Text' }
        elseif ($i -eq $Current) { $path.Data = [System.Windows.Media.Geometry]::Parse($script:IconPaths.play); $path.Stroke = Get-Brush 'Accent'; $r.Text.Foreground = Get-Brush 'Accent' }
        else { $path.Data = [System.Windows.Media.Geometry]::Parse($script:IconPaths.clock); $path.Stroke = Get-Brush 'Line'; $r.Text.Foreground = Get-Brush 'Muted' }
    }
}

function Start-PcTest {
    $ui = $script:TeUi
    if ($ui.Job) { return }
    $full = [bool]$ui.FullR.IsChecked
    $ui.RunBtn.IsEnabled = $false; $ui.ReportBtn.IsEnabled = $false
    $ui.Verdict.Text = 'Идёт тест…'; $ui.Usage.Text = 'Не пользуйтесь компьютером до окончания - так результат будет честнее.'
    $ui.Started = Get-Date
    Set-StepState 0
    $ui.Job = Start-BgTask -Name 'Тест ПК' -Vars @{ Full = $full } -Script { Invoke-PcTest -Full $Full } -OnDone {
        param($r, $err)
        $ui = $script:TeUi
        $ui.Job = $null
        try { $ui.Timer.Stop() } catch {}
        $ui.RunBtn.IsEnabled = $true
        if (-not $r) {
            $ui.Verdict.Text = 'Тест прерван'
            $ui.Usage.Text = $(if ($err) { [string]$err } else { 'Остановлено пользователем' })
            return
        }
        $ui.Result = $r
        Set-StepState 99
        $ui.StepTitle.Text = 'Ход теста · ' + (Format-Duration ((Get-Date) - $ui.Started).TotalSeconds)
        Set-TestResult $r
    }
    $ui.Timer = New-Object System.Windows.Threading.DispatcherTimer
    $ui.Timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $ui.Timer.Add_Tick({
        $j = $script:TeUi.Job
        if (-not $j) { return }
        $st = [string]$j.Status
        if ($st -match '^(\d+)\|') { Set-StepState ([int]$Matches[1]) }
        $script:TeUi.StepTitle.Text = 'Ход теста · ' + (Format-Duration ((Get-Date) - $script:TeUi.Started).TotalSeconds)
    })
    $ui.Timer.Start()
}

function Set-TestResult {
    param($r, [switch]$FromFile)
    $ui = $script:TeUi
    Set-ScoreRing -Ring $ui.Ring -Value ([int]$r.Score)
    $model = (([string]$r.Summary.Manufacturer) + ' ' + ([string]$r.Summary.Model)).Trim()
    $ui.Model.Text = 'Итог · ' + $model + $(if ($FromFile) { ' · тест от ' + ([datetime]$r.Time).ToString('dd.MM.yyyy HH:mm') } else { '' })
    $ui.Verdict.Text = $r.Verdict
    $u = [string]$r.Usage
    if (@($r.Issues).Count) { $u += ' Проблемы: ' + (@($r.Issues) -join '; ') + '.' }
    $ui.Usage.Text = $u
    $ui.ReportBtn.IsEnabled = $true
    $body = $ui.Results.Body
    $body.Children.Clear()
    $parts = $r.Parts
    $keys = if ($parts -is [System.Collections.IDictionary]) { @($parts.Keys) } else { @($parts.PSObject.Properties | ForEach-Object { $_.Name }) }
    foreach ($k in $keys) {
        $p = if ($parts -is [System.Collections.IDictionary]) { $parts[$k] } else { $parts.$k }
        $s = [int]$p.Score
        $col = if ($s -ge 70) { 'Ok' } elseif ($s -ge 40) { 'Warn' } else { 'Bad' }
        $word = if ($s -ge 85) { 'Отлично' } elseif ($s -ge 70) { 'Хорошо' } elseif ($s -ge 40) { 'Средне' } elseif ($s -ge 20) { 'Слабо' } else { 'Плохо' }
        $main = New-Stack
        $tt = New-Text -Text ($p.Title + '  ·  ' + $p.Hw) -Size 14 -Weight 'SemiBold'
        [void]$main.Children.Add($tt)
        [void]$main.Children.Add((New-Text -Text ([string]$p.Result) -Size 12 -Color 'Muted' -Wrap -Margin (0, 3, 0, 0)))
        $meterBox = New-Stack
        $meterBox.Width = 170
        $hd = New-Object System.Windows.Controls.DockPanel
        $sv = New-Text -Text ([string]$s + '/100') -Size 12 -Color 'Muted'
        [System.Windows.Controls.DockPanel]::SetDock($sv, 'Right')
        [void]$hd.Children.Add($sv); [void]$hd.Children.Add((New-Text -Text $word -Size 12 -Weight 'Bold' -Color $col))
        $m = New-Meter -Height 8; $m.Margin = New-Thickness 0, 6, 0, 0
        [void]$meterBox.Children.Add($hd); [void]$meterBox.Children.Add($m)
        [void]$body.Children.Add((New-Row -Left (New-IconTile -Icon $p.Icon -Color $col -Size 40) -Main $main -Right @($meterBox) -Padding (16, 12, 16, 12)))
        Set-Meter -Meter $m -Value ($s / 100) -Color $col
    }
    $adv = @($r.Advice)
    $ui.AdviceSec.Body.Children.Clear()
    $ui.AdviceSec.Root.Visibility = if ($adv.Count) { 'Visible' } else { 'Collapsed' }
    foreach ($a in $adv) { [void]$ui.AdviceSec.Body.Children.Add((New-Row -Left (New-Icon -Name 'bolt' -Size 16 -Color 'Accent') -Main (New-Text -Text $a -Size 13 -Wrap) -Padding (16, 8, 16, 8))) }
}

function Save-MasterReport {
    $r = $script:TeUi.Result
    if (-not $r) { return }
    try {
        $file = New-MasterReport -Test $r
        Write-Log ('Отчёт сохранён: ' + $file) 'ok'
        Open-Path $file
    } catch { Write-Log ('Отчёт не сохранился: ' + $_.Exception.Message) 'err' }
}

function ConvertTo-HtmlText {
    param([string]$s)
    return [System.Net.WebUtility]::HtmlEncode([string]$s)
}

function New-MasterReport {
    # HTML-отчёт для клиента: результаты теста, что сделано PotatoPC за 30 дней, рекомендации.
    param($Test)
    $s = $Test.Summary
    $model = (([string]$s.Manufacturer) + ' ' + ([string]$s.Model)).Trim()
    $parts = $Test.Parts
    $keys = if ($parts -is [System.Collections.IDictionary]) { @($parts.Keys) } else { @($parts.PSObject.Properties | ForEach-Object { $_.Name }) }
    $rows = foreach ($k in $keys) {
        $p = if ($parts -is [System.Collections.IDictionary]) { $parts[$k] } else { $parts.$k }
        $sc = [int]$p.Score
        $col = if ($sc -ge 70) { '#16a34a' } elseif ($sc -ge 40) { '#d97706' } else { '#dc2626' }
        "<tr><td><b>$(ConvertTo-HtmlText $p.Title)</b><br><span class='m'>$(ConvertTo-HtmlText $p.Hw)</span></td><td>$((ConvertTo-HtmlText $p.Result) -replace "`n", '<br>')</td><td class='s' style='color:$col'>$sc</td></tr>"
    }
    $hist = @(Get-History -Last 400 -Days 30 | Where-Object { $_.Kind -ne 'test' } | Select-Object -First 60)
    $hrows = foreach ($h in $hist) { "<tr><td class='m'>$(([datetime]$h.Time).ToString('dd.MM HH:mm'))</td><td>$(ConvertTo-HtmlText $h.Name)</td><td>$(if ($h.Result -eq 'ok') { '✓' } else { '✗' })</td></tr>" }
    $issues = (@($Test.Issues) | ForEach-Object { '<li>' + (ConvertTo-HtmlText $_) + '</li>' }) -join ''
    $advice = (@($Test.Advice) | ForEach-Object { '<li>' + (ConvertTo-HtmlText $_) + '</li>' }) -join ''
    $date = ([datetime]$Test.Time).ToString('dd.MM.yyyy HH:mm')
    $html = @"
<!doctype html><html lang="ru"><head><meta charset="utf-8"><title>Отчёт о проверке ПК - $(ConvertTo-HtmlText $model)</title>
<style>
body{font-family:'Segoe UI',Arial,sans-serif;color:#1f2937;max-width:860px;margin:32px auto;padding:0 24px;line-height:1.45}
h1{font-size:26px;margin:0}h2{font-size:18px;margin:28px 0 10px;border-bottom:2px solid #f5b544;padding-bottom:4px}
.m{color:#6b7280;font-size:13px}.score{display:flex;gap:24px;align-items:center;margin:20px 0;padding:18px;border:1px solid #e5e7eb;border-radius:12px}
.big{font-size:56px;font-weight:700;color:#b7791f}table{width:100%;border-collapse:collapse}td{padding:9px 8px;border-bottom:1px solid #eee;vertical-align:top;font-size:14px}
td.s{font-size:22px;font-weight:700;text-align:right;width:60px}.grid td{width:50%}li{margin:4px 0}.foot{margin-top:36px;font-size:12px;color:#9ca3af}
@media print{body{margin:0}}
</style></head><body>
<h1>Отчёт о проверке компьютера</h1>
<div class="m">$date · PotatoPC $AppVersion</div>
<div class="score"><div class="big">$([int]$Test.Score)</div><div><div style="font-size:20px;font-weight:700">$(ConvertTo-HtmlText $Test.Verdict)</div><div>$(ConvertTo-HtmlText $Test.Usage)</div><div class="m">Оценка из 100, где 100 - средний новый ноутбук 2025 года.</div></div></div>
<h2>Компьютер</h2>
<table class="grid">
<tr><td class="m">Модель</td><td>$(ConvertTo-HtmlText $model)</td></tr>
<tr><td class="m">Серийный номер</td><td>$(ConvertTo-HtmlText $s.Serial)</td></tr>
<tr><td class="m">Процессор</td><td>$(ConvertTo-HtmlText $s.Cpu)</td></tr>
<tr><td class="m">Память</td><td>$(Format-Size $s.RamTotal)</td></tr>
<tr><td class="m">Системный диск</td><td>$(ConvertTo-HtmlText ($s.Disk.Media + ' ' + (Format-Size $s.Disk.Total) + ', свободно ' + (Format-Size $s.Disk.Free)))</td></tr>
<tr><td class="m">Windows</td><td>$(ConvertTo-HtmlText ($s.Os + ' (сборка ' + $s.Build + ')'))</td></tr>
</table>
<h2>Результаты тестов</h2><table>$($rows -join '')</table>
$(if ($issues) { "<h2>Найденные проблемы</h2><ul>$issues</ul>" })
$(if ($advice) { "<h2>Рекомендации</h2><ul>$advice</ul>" })
$(if ($hist.Count) { "<h2>Выполненные работы (последние 30 дней)</h2><table>$($hrows -join '')</table>" })
<div class="foot">Отчёт сформирован автоматически. Чтобы сохранить в PDF: Ctrl+P → «Сохранить как PDF».</div>
</body></html>
"@
    $safe = ($model -replace '[\\/:*?"<>|]', '').Trim()
    if (-not $safe) { $safe = $env:COMPUTERNAME }
    $name = 'PotatoPC-отчёт-' + $safe + '-' + (Get-Date -Format 'yyyyMMdd-HHmm') + '.html'
    $desk = [Environment]::GetFolderPath('Desktop')
    $file = Join-Path $(if ($desk -and (Test-Path -LiteralPath $desk)) { $desk } else { $ReportFolder }) $name
    [System.IO.File]::WriteAllText($file, $html, (New-Object System.Text.UTF8Encoding($true)))
    try { Copy-Item -LiteralPath $file -Destination (Join-Path $ReportFolder $name) -Force } catch {}
    Add-History -Kind 'report' -Name ('Отчёт мастера: ' + $name) -Ref $file
    return $file
}
