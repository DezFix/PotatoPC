# PAGE: history
# TITLE: История и откаты
# ICON: history
# ORDER: 95
# NAV: footer

$script:HiUi = $null
$script:HistoryIcons = @{ plugin = 'bolt'; clean = 'broom'; startup = 'power'; app = 'box'; drivers = 'chip'; users = 'users'; protect = 'shield'; service = 'wrench'; maintenance = 'clock'; test = 'gauge'; report = 'report'; restore = 'flag'; optimize = 'play'; network = 'network'; uninstall = 'trash'; firewall = 'ban' }

function Build-Page_history {
    $ui = @{}
    $rp = New-Button -Text 'Создать точку восстановления' -Icon 'flag' -OnClick { Start-BgTask -Name 'Точка восстановления' -Script { New-RestorePoint -Description 'PotatoPC: вручную' } -OnDone { Update-RestorePoints } | Out-Null }
    $rs = New-Button -Text 'Восстановление системы' -Kind Ghost -OnClick { Start-Process (Join-Path $env:WINDIR 'System32\rstrui.exe') }
    $L = New-PageLayout -Title 'История и откаты' -Subtitle 'Что и когда менял PotatoPC, как вернуть всё назад' -HeaderRight @($rs, (New-Button -Text 'Обновить' -Icon 'refresh' -OnClick { Show-Page_history }), $rp)
    $ui.Points = New-Section -Title 'Точки восстановления Windows'
    [void]$L.Body.Children.Add($ui.Points.Root)
    $ui.Undo = New-Section -Title 'Откаты по разделам'
    [void]$L.Body.Children.Add($ui.Undo.Root)
    $rep = New-Button -Text 'Отчёт о проделанной работе' -Kind Ghost -OnClick {
        $f = Join-Path $ReportFolder 'test-last.json'
        if (-not (Test-Path -LiteralPath $f)) { Show-Info 'Отчёт строится вместе с результатами теста. Откройте «Тест ПК» и запустите тест - в отчёт попадут и выполненные работы.'; return }
        try { $t = Get-Content -LiteralPath $f -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop; $file = New-MasterReport -Test $t; Open-Path $file } catch { Write-Log ('Отчёт: ' + $_.Exception.Message) 'err' }
    }
    $ui.Log = New-Section -Title 'Журнал действий' -Right @($rep)
    [void]$L.Body.Children.Add($ui.Log.Root)
    $script:HiUi = $ui
    return $L.Root
}

function Show-Page_history {
    param($Arg)
    $ui = $script:HiUi
    # Откаты
    $ui.Undo.Body.Children.Clear()
    # Одна строка на раздел: все откаты его твиков разом. Откатить отдельный
    # твик можно кнопкой у самого твика на странице «Твики».
    $cats = @{}
    foreach ($p in @(Get-Plugins | Where-Object { -not $_.IsUndo })) { $cats[$p.CatNum] = $p.Category }
    $all = @(Get-UndoPlugins)
    foreach ($num in @($all | ForEach-Object { $_.UndoFor } | Where-Object { $_ } | Sort-Object -Unique)) {
        $list = @($all | Where-Object { $_.UndoFor -contains $num })
        $cat = if ($cats[$num]) { $cats[$num] } else { $num }
        $sub = 'Откатов: ' + $list.Count + '. ' + ((@($list | ForEach-Object { $_.Name -replace '^Откат:\s*', '' }) | Select-Object -First 4) -join '; ') + $(if ($list.Count -gt 4) { '…' } else { '' })
        $b = New-Button -Text 'Откатить раздел' -Icon 'undo' -Kind Small -Tag @{ Cat = $cat; List = $list } -OnClick {
            $t = $this.Tag
            $msg = 'Вернуть настройки раздела «' + $t.Cat + '» к заводским?' + "`n`n" + (($t.List | ForEach-Object { '  • ' + $_.Name }) -join "`n")
            if (-not (Show-Confirm -Message $msg -Title 'Откат' -Warning)) { return }
            Start-BgTask -Name ('Откат: ' + $t.Cat) -Vars @{ P = $t.List } -Script { Invoke-PluginBatch -Plugins @($P) -RestorePoint $true -Title 'Откат' } -OnDone { Show-Page_history } | Out-Null
        }
        [void]$ui.Undo.Body.Children.Add((New-Row -Left (New-IconTile -Icon 'undo' -Color 'Info') -Main (New-TitleBlock -Title ('Раздел «' + $cat + '»') -Sub $sub) -Right @($b)))
    }
    # Журнал
    $ui.Log.Body.Children.Clear()
    $h = @(Get-History -Last 300)
    $ui.Log.Header.Text = 'Журнал действий · ' + $h.Count
    if ($h.Count -eq 0) { [void]$ui.Log.Body.Children.Add((New-Placeholder 'PotatoPC пока ничего не менял на этом компьютере.')) }
    $lastDay = ''
    foreach ($x in ($h | Select-Object -First 150)) {
        $t = [datetime]$x.Time
        $day = $t.ToString('dd MMMM yyyy')
        if ($day -ne $lastDay) {
            [void]$ui.Log.Body.Children.Add((New-Text -Text $day -Size 12 -Color 'Muted' -Weight 'SemiBold' -Margin (16, 12, 16, 4)))
            $lastDay = $day
        }
        $icon = $script:HistoryIcons[[string]$x.Kind]; if (-not $icon) { $icon = 'info' }
        $ok = $x.Result -eq 'ok'
        $right = @((New-Text -Text $t.ToString('HH:mm') -Size 12 -Color 'Muted'))
        if (-not $ok) { $right = @((New-Badge 'ошибка' 'bad')) + $right }
        # Исправления реестра и остатки программ сохраняют копию - их можно откатить
        if ($ok -and $x.Ref -and [string]$x.Kind -in @('registry', 'uninstall', 'users') -and [string]$x.Name -notlike 'Откат*' -and (Test-Path -LiteralPath ([string]$x.Ref) -PathType Container)) {
            if (@(Get-ChildItem -LiteralPath ([string]$x.Ref) -Include '*.reg', 'tasks.json' -Recurse -ErrorAction SilentlyContinue).Count) {
                $rb = New-Button -Text 'Откатить' -Icon 'undo' -Kind Small -Tag ([string]$x.Ref) -OnClick {
                    if (-not (Show-Confirm -Message ('Вернуть ключи реестра (и задачи) из копии?' + "`n`n" + $this.Tag) -Title 'Откат' -Warning)) { return }
                    Start-BgTask -Name 'Откат реестра' -Vars @{ F = $this.Tag } -Script { Restore-RegistryBackup -Folder $F } -OnDone { Show-Page_history } | Out-Null
                }
                $right = @($rb) + $right
            }
        }
        # Запрет доступа в интернет (страница «Сеть») снимается одной кнопкой, пока правило ещё есть
        if ($ok -and [string]$x.Kind -eq 'firewall' -and $x.Ref -and (Get-NetFirewallRule -Name ([string]$x.Ref) -ErrorAction SilentlyContinue)) {
            $fb = New-Button -Text 'Разрешить снова' -Icon 'undo' -Kind Small -Tag ([string]$x.Ref) -OnClick {
                $id = [string]$this.Tag
                Start-BgTask -Name 'Снятие запрета' -Vars @{ Id = $id } -Script { Remove-NetAppBlock -Id $Id } -OnDone { Show-Page_history } | Out-Null
            }
            $right = @($fb) + $right
        }
        $main = New-Text -Text ([string]$x.Name) -Size 13
        if ($x.Detail) { $main.ToolTip = [string]$x.Detail }
        [void]$ui.Log.Body.Children.Add((New-Row -Left (New-Icon -Name $icon -Size 16 -Color $(if ($ok) { 'Muted' } else { 'Bad' })) -Main $main -Right $right -Padding (16, 6, 16, 6)))
    }
    Update-RestorePoints
}

function Update-RestorePoints {
    $ui = $script:HiUi
    $ui.Points.Body.Children.Clear()
    [void]$ui.Points.Body.Children.Add((New-Placeholder))
    Start-BgTask -Name 'Точки восстановления' -Silent -Script {
        $pts = @()
        try { $pts = @(Get-ComputerRestorePoint -ErrorAction Stop | Sort-Object SequenceNumber -Descending | Select-Object -First 8 | ForEach-Object { @{ Desc = [string]$_.Description; Time = $_.ConvertToDateTime($_.CreationTime) } }) } catch {}
        $disabled = $false
        try { $v = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore' -Name DisableSR -ErrorAction Stop; $disabled = ($v.DisableSR -eq 1) } catch {}
        return @{ Points = $pts; Disabled = $disabled }
    } -OnDone {
        param($r)
        $ui = $script:HiUi
        $ui.Points.Body.Children.Clear()
        if (-not $r) { return }
        if ($r.Points.Count -eq 0) {
            $en = New-Button -Text 'Включить защиту системы' -Kind Small -OnClick {
                Start-BgTask -Name 'Защита системы' -Script {
                    Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction Stop
                    [void](Invoke-ProcessLive -FilePath (Join-Path $env:WINDIR 'System32\vssadmin.exe') -Arguments ('resize shadowstorage /for=' + $env:SystemDrive + ' /on=' + $env:SystemDrive + ' /maxsize=5%') -TimeoutSec 60 -Quiet)
                    Write-Log ('Защита системы включена для ' + $env:SystemDrive + ' (до 5% диска)') 'ok'
                    Add-History -Kind 'restore' -Name 'Включена защита системы'
                    [void](New-RestorePoint -Description 'PotatoPC: первая точка')
                } -OnDone { Update-RestorePoints } | Out-Null
            }
            $msg = if ($r.Disabled) { 'Защита системы запрещена политикой - точки восстановления не создаются.' } else { 'Точек восстановления нет. Скорее всего, защита системы выключена - без неё откатить Windows целиком не получится.' }
            [void]$ui.Points.Body.Children.Add((New-Row -Left (New-Icon -Name 'warn' -Size 18 -Color 'Warn') -Main (New-Text -Text $msg -Size 13 -Wrap) -Right @($en)))
            return
        }
        foreach ($p in $r.Points) {
            [void]$ui.Points.Body.Children.Add((New-Row -Left (New-Icon -Name 'flag' -Size 16 -Color 'Muted') -Main (New-Text -Text $p.Desc -Size 13) -Right @((New-Text -Text $p.Time.ToString('dd.MM.yyyy HH:mm') -Size 12 -Color 'Muted')) -Padding (16, 6, 16, 6)))
        }
    } | Out-Null
}
