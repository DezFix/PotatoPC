# PotatoPC v6 — привязки новой оболочки.
# Старые модули НЕ тронуты: здесь только то, чего в v5 не было —
# кастомный хром, синхронизация страниц, общий поиск, дашборд, teal-акцент.
# Загружается в menu-v6.ps1 ПОСЛЕ Initialize-Controls, ДО ui-модулей.

# ── Teal-акцент поверх темы (только runtime v6, файлы темы не меняем) ──
try {
    $script:Theme.Accent       = Get-ThemeBrush "#14B8A6"
    $script:Theme.AccentBgBtn  = Get-ThemeBrush "#14B8A6"
    $script:Theme.TextHeader   = Get-ThemeBrush "#2DD4BF"
} catch {}

# ── Новые контролы в globals (рядом с картой Initialize-Controls) ──
foreach ($n in @('NavDashBtn','GlobalSearch','GlobalSearchClear','P_Potato','P_Office','P_Game','FixAllBtn',
                'DashCpuText','DashMemText','DashDiskText','DashUpText','HealthText','HealthSub','HealthBar',
                'TitleBar','MinBtn','MaxBtn','CloseBtn')) {
    try {
        $ctl = $window.FindName($n)
        Set-Variable -Name $n -Value $ctl -Scope Global
    } catch {}
}

# ── Иконки новым Image (файлы проверены в assets/icons) ──
try {
    $v6icons = @{
        NavDashIcon='apps/monitor'; TopSearchIcon='actions/search';
        DashCpuIcon='devices/hw_cpu'; DashMemIcon='devices/hw_memory'; DashDrvIcon='devices/drive';
        DashUpIcon='actions/power'; DashPPotatoIcon='apps/logo'; DashPOfficeIcon='apps/office';
        DashPGameIcon='apps/games'; DashGoPotatoIcon='actions/play'; DashGoOfficeIcon='actions/play';
        DashGoGameIcon='actions/play'; DashFixIcon='actions/power'
    }
    foreach ($kv in $v6icons.GetEnumerator()) {
        try {
            $img = $window.FindName($kv.Key)
            if ($img) { $src = Get-IconSource -Name $kv.Value; if ($src) { $img.Source = $src } }
        } catch {}
    }
} catch {}

# ── Кастомный хром (WindowStyle=None) ──
try { $TitleBar.Add_MouseLeftButtonDown({ param($s,$e) try { $window.DragMove() } catch {} }) } catch {}
try { $CloseBtn.Add_Click({ $window.Close() }) } catch {}
try { $MinBtn.Add_Click({ $window.WindowState = 'Minimized' }) } catch {}
try {
    $MaxBtn.Add_Click({
        if ($window.WindowState -eq 'Maximized') { $window.WindowState = 'Normal' } else { $window.WindowState = 'Maximized' }
    })
} catch {}

# ── Страницы v6: индекс -> панель + заголовок (9 = Дашборд, новое) ──
$script:V6Pages = @('PageMods','PageStart','PageUsers','PageApps','PageUpd','PageClean','PageProt','PageDiag','PageSys','PageDash')
$script:V6Titles = @(
    @{ Title = "Модули";       Sub = "Отмечай скрипты и запускай." },
    @{ Title = "Автозагрузка"; Sub = "Приложения и задачи планировщика." },
    @{ Title = "Пользователи"; Sub = "Локальные учётные записи." },
    @{ Title = "Приложения";   Sub = "Установка через winget." },
    @{ Title = "Обновления";   Sub = "Обновление программ через winget." },
    @{ Title = "Очистка";      Sub = "Мусор и кэши." },
    @{ Title = "Защита";       Sub = "Проверка на вирусы." },
    @{ Title = "Тест системы"; Sub = "Диагностика в фоне." },
    @{ Title = "О системе";    Sub = "Железо, ОС, диски." },
    @{ Title = "Дашборд";      Sub = "Коротко о системе и быстрые действия." }
)

function Sync-V6Page {
    # Показывает страницу по скрытому MainTabControl.SelectedIndex.
    # Только читает индекс — рекурсии с Set-ActiveNav нет.
    try {
        $idx = -1
        try { $idx = $MainTabControl.SelectedIndex } catch { return }
        if ($idx -lt 0 -or $idx -ge $script:V6Pages.Count) { return }
        for ($i = 0; $i -lt $script:V6Pages.Count; $i++) {
            try {
                $pg = $window.FindName($script:V6Pages[$i])
                if ($pg) { $pg.Visibility = if ($i -eq $idx) { 'Visible' } else { 'Collapsed' } }
            } catch {}
        }
        try {
            $HeaderTitleText.Text = $script:V6Titles[$idx].Title
            $HeaderSubtitleText.Text = $script:V6Titles[$idx].Sub
        } catch {}
        # Поиск работает только там, где модули умеют фильтровать (0/1/3) — иначе прячем
        try {
            $sw = $window.FindName("SearchBoxWrap")
            if ($sw) { $sw.Visibility = if ($idx -eq 0 -or $idx -eq 1 -or $idx -eq 3) { 'Visible' } else { 'Collapsed' } }
        } catch {}
        if ($idx -eq 9) { try { Update-DashStats } catch {} }
    } catch {}
}

try { $MainTabControl.Add_SelectionChanged({ try { Sync-V6Page } catch {} }) } catch {}
try {
    if ($NavDashBtn) { $NavDashBtn.Add_Click({ try { Set-ActiveNav -Index 9 } catch {} }) }
} catch {}

# ── Общий поиск: пишет в скрытый бокс активной вкладки, фильтруют модули ──
try {
    if ($GlobalSearch) {
        $GlobalSearch.Add_TextChanged({
            try {
                $q = $GlobalSearch.Text
                try { if ($GlobalSearchClear) { $GlobalSearchClear.Visibility = if ([string]::IsNullOrEmpty($q)) { "Collapsed" } else { "Visible" } } } catch {}
                $idx = -1
                try { $idx = $MainTabControl.SelectedIndex } catch {}
                if ($idx -eq 0 -and $ScriptSearchBox -and $ScriptSearchBox.Text -ne $q) { $ScriptSearchBox.Text = $q }
                elseif ($idx -eq 3 -and $AppSearchBox -and $AppSearchBox.Text -ne $q) { $AppSearchBox.Text = $q }
                elseif ($idx -eq 1 -and $StartupSearchBox -and $StartupSearchBox.Text -ne $q) { $StartupSearchBox.Text = $q }
            } catch {}
        })
    }
    if ($GlobalSearchClear) {
        $GlobalSearchClear.Add_Click({ try { $GlobalSearch.Text = "" } catch {} })
    }
} catch {}

# ── Дашборд: сбор цифр В ФОНЕ (UI не виснет), применение — в UI-потоке ──
$script:V6DashBusy  = $false
$script:V6DashStart = [DateTime]::MinValue
$script:V6DashCache = $null

function Update-DashStats {
    # Быстрый триггер: тяжёлые CIM/WMI-замеры уходят в фон. Кэш 30 сек.
    try {
        # Важно: до полной загрузки модулей фон НЕ трогаем, иначе снепшот
        # фоновых функций (Get-BgSessionState) навсегда закешируется без них —
        # отвалятся автозагрузка, обновления, фавиконки (было).
        if (-not $script:V6ModulesReady) { return }
        if ($script:V6DashBusy) {
            if (((Get-Date) - $script:V6DashStart).TotalSeconds -gt 60) { $script:V6DashBusy = $false }
            else { return }
        }
        if ($script:V6DashCache -and $script:V6DashCache.When -and ((Get-Date) - $script:V6DashCache.When).TotalSeconds -lt 30) { return }
        $script:V6DashBusy = $true
        $script:V6DashStart = Get-Date
        Start-Background {
            try {
                Write-Log "дашборд: считаю..."
                $d = @{ When = (Get-Date) }
                try {
                    $si = Get-SystemInfo
                    $d.Cpu = [string]$si.CPU
                    $d.Cpu = ($d.Cpu -replace '\s+(Processor|CPU).*$','').Trim()
                    if ($d.Cpu.Length -gt 26) { $d.Cpu = $d.Cpu.Substring(0, 25) + "…" }
                    $d.Disk = [string]$si.Disk
                    $d.Up   = [string]$si.Uptime
                } catch {}
                try {
                    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
                    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
                    $totalGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
                    $freeGB  = [math]::Round($os.FreePhysicalMemory / 1KB / 1024, 1)
                    $d.Mem = ("{0} / {1} ГБ" -f [math]::Round($totalGB - $freeGB, 1), $totalGB)
                } catch { Write-Log ("дашборд: память не посчиталась: " + $_.Exception.Message) -Color "Yellow" }
                $score = 100; $notes = @()
                try {
                    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
                    if ($disk.Size -gt 0) {
                        $freePct = [math]::Round($disk.FreeSpace / $disk.Size * 100)
                        if ($freePct -lt 10) { $score -= 25; $notes += "−25: диск C: забит ($freePct% свободно)" }
                        elseif ($freePct -lt 20) { $score -= 10; $notes += "−10: диск C: $freePct% свободно" }
                        else { $notes += "диск C: $freePct% свободно" }
                    }
                } catch { Write-Log ("дашборд: диск C: не прочитался: " + $_.Exception.Message) -Color "Yellow" }
                try {
                    $pr = @(Test-PendingReboot)
                    if ($pr.Count -gt 0) { $score -= 5; $notes += "−5: нужна перезагрузка" }
                } catch {}
                try {
                    $df = Get-DefenderStatus
                    if ($df -and $df.Ok) {
                        if ([string]$df.Mode -ne 'Normal') { $score -= 20; $notes += "−20: Defender не в норме" }
                        elseif ([int]$df.SigAge -gt 7) { $score -= 10; $notes += "−10: базы Defender старые" }
                        else { $notes += "Defender в норме" }
                    } else { $notes += "Defender: нет данных" }
                } catch { $notes += "Defender: нет данных" }
                if ($score -lt 0) { $score = 0 }
                $d.Score = $score; $d.Notes = $notes
                Write-Log ("дашборд: готово, здоровье " + $score + "/100")
                Set-BgResult -Key 'dashStats' -Value $d
            } catch {}
        }
    } catch { $script:V6DashBusy = $false }
}

function Apply-V6Dash {
    # СТРОГО UI-поток: раскладывает готовый набор по карточкам.
    param($Data)
    try {
        if (-not $Data) { return }
        if ($Data.Cpu -and $DashCpuText) { $DashCpuText.Text = [string]$Data.Cpu }
        if ($Data.Mem -and $DashMemText) { $DashMemText.Text = [string]$Data.Mem }
        if ($Data.Disk -and $DashDiskText) { $DashDiskText.Text = [string]$Data.Disk }
        if ($Data.Up -and $DashUpText) { $DashUpText.Text = [string]$Data.Up }
        $score = [int]$Data.Score
        if ($HealthText) { $HealthText.Text = "Здоровье системы — $score/100" }
        if ($HealthSub) {
            $HealthSub.Text = if (@($Data.Notes).Count -gt 0) { ((@($Data.Notes)) -join "  •  ") } else { "Проверок пока нет" }
        }
        if ($HealthBar) {
            $HealthBar.Value = $score
            $c = if ($score -ge 70) { "#2DD4BF" } elseif ($score -ge 40) { "#FBBF24" } else { "#F87171" }
            $HealthBar.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom($c)
        }
        $script:V6DashCache = $Data
    } catch {}
}

function Update-DashHealth {
    # Совместимость: здоровье считается вместе со статистикой в фоне.
    try { Update-DashStats } catch {}
}

# Поллер дашборда: живёт в UI-потоке, забирает готовое из шины.
try {
    if (-not $script:V6DashTimer) {
        $script:V6DashTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:V6DashTimer.Interval = [TimeSpan]::FromMilliseconds(500)
        $script:V6DashTimer.Add_Tick({
            try {
                $d = $null
                try { $d = Get-BgResult -Key 'dashStats' } catch {}
                if ($d) {
                    Set-BgResult -Key 'dashStats' -Value $null
                    $script:V6DashBusy = $false
                    Apply-V6Dash $d
                }
            } catch {}
        })
        $script:V6DashTimer.Start()
    } else { try { $script:V6DashTimer.Start() } catch {} }
} catch {}

# ── Дашборд: пресеты ведут в Модули, «Исправить всё» = пресет Potato + запуск ──
try {
    if ($P_Potato) { $P_Potato.Add_Click({ try { Select-ScriptPreset "potato"; Write-Log "Далее: глянь список и жми «▶ Запустить выбранные»" -Color "Cyan"; Set-ActiveNav -Index 0 } catch {} }) }
    if ($P_Office) { $P_Office.Add_Click({ try { Select-ScriptPreset "office"; Write-Log "Далее: глянь список и жми «▶ Запустить выбранные»" -Color "Cyan"; Set-ActiveNav -Index 0 } catch {} }) }
    if ($P_Game)   { $P_Game.Add_Click({ try { Select-ScriptPreset "game"; Write-Log "Далее: глянь список и жми «▶ Запустить выбранные»" -Color "Cyan"; Set-ActiveNav -Index 0 } catch {} }) }
} catch {}
try {
    if ($FixAllBtn) {
        $FixAllBtn.Add_Click({
            try {
                if (-not (Get-Command Select-ScriptPreset -ErrorAction SilentlyContinue)) { return }
                if ($script:BatchRunning) { Stop-SelectedScripts; return }
                Select-ScriptPreset "potato"
                Set-ActiveNav -Index 0
                Run-SelectedScripts
            } catch {}
        })
    }
} catch {}
