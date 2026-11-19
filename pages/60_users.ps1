# PAGE: users
# TITLE: Пользователи
# ICON: users
# ORDER: 60

# Учётные записи без оснастки lusrmgr.msc - работает и в Windows Home.
# Группы ищутся по SID, а не по имени: на русской Windows «Администраторы»,
# на английской «Administrators».
#
# Файлы пользователя можно держать на другом диске (D:): тогда Windows можно
# переустановить, а документы, фото и настройки программ останутся. Движок -
# core\Profiles.ps1, здесь только экран.

$script:UsUi = $null
$script:SidAdmins = 'S-1-5-32-544'
$script:SidUsers = 'S-1-5-32-545'
$script:WinlogonKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

function Get-AdminMemberSids {
    $sids = @{}
    try {
        foreach ($m in @(Get-LocalGroupMember -SID $script:SidAdmins -ErrorAction Stop)) { $sids[[string]$m.SID.Value] = $true }
        return $sids
    } catch {}
    # Get-LocalGroupMember падает, если в группе есть «осиротевший» SID. Запасной путь через ADSI.
    try {
        $gname = (Get-LocalGroup -SID $script:SidAdmins -ErrorAction Stop).Name
        $g = [ADSI]("WinNT://./" + $gname + ",group")
        foreach ($mem in @($g.Invoke('Members'))) {
            try {
                $bytes = $mem.GetType().InvokeMember('objectSid', 'GetProperty', $null, $mem, $null)
                $sid = (New-Object System.Security.Principal.SecurityIdentifier($bytes, 0)).Value
                $sids[$sid] = $true
            } catch {}
        }
    } catch {}
    return $sids
}

function Get-LocalUsersInfo {
    $admins = Get-AdminMemberSids
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $auto = @{ On = $false; User = '' }
    try {
        $wl = Get-ItemProperty -LiteralPath $script:WinlogonKey -ErrorAction Stop
        $auto.On = ([string]$wl.AutoAdminLogon -eq '1'); $auto.User = [string]$wl.DefaultUserName
    } catch {}
    $states = @{}; $pending = @{}; $moves = @()
    try { $states = Get-UserProfileStates } catch {}
    try { $pending = Get-PendingProfileMoves } catch {}
    try { $moves = @((Get-ProfileState).Moves) } catch {}
    $list = @()
    $builtin = @{}
    foreach ($u in @(Get-LocalUser -ErrorAction Stop)) {
        $sid = [string]$u.SID.Value
        $rid = ($sid -split '-')[-1]
        if ($rid -in @('503', '504')) { continue }
        $info = @{
            Name = [string]$u.Name; FullName = [string]$u.FullName; Sid = $sid; Enabled = [bool]$u.Enabled
            IsAdmin = [bool]$admins[$sid]; IsMe = ($sid -eq $me); LastLogon = $u.LastLogon; PwdSet = $u.PasswordLastSet; PwdExpires = $u.PasswordExpires
            Source = [string]$u.PrincipalSource; Rid = $rid
            Profile = $states[$sid]; Pending = $pending.ContainsKey($sid); OldCopy = ''
        }
        if ($info.Profile -and -not $info.Profile.Exists) { $info.Profile = $null }
        foreach ($m in $moves) {
            if ([string]$m.Sid -eq $sid -and $info.Profile -and [string]$m.Old -ine $info.Profile.Path -and (Test-Path -LiteralPath ([string]$m.Old))) { $info.OldCopy = [string]$m.Old }
        }
        $info.NeverExpires = -not $u.PasswordExpires
        try { $flags = [int]([ADSI]('WinNT://./' + $u.Name + ',user')).UserFlags.Value; $info.NeverExpires = (($flags -band 0x10000) -ne 0) } catch {}
        if ($rid -eq '500' -or $rid -eq '501') { $builtin[$rid] = $info; continue }
        $list += $info
    }
    return @{ Users = $list; Builtin = $builtin; Auto = $auto; Me = $me; Sys = ($env:SystemDrive).TrimEnd(':').ToUpperInvariant() }
}

# ---------- Мелкие строительные блоки ----------

function New-UsRadio {
    # Радиокарточка с меткой справа от заголовка («рекомендуем»).
    param([string]$Title, [string]$Sub = '', [string]$Group, [bool]$Checked = $false, $Tag = $null, [string]$Badge = '', [string]$BadgeKind = 'ok', [string]$SubColor = 'Muted')
    $r = New-Radio -Title $Title -Group $Group -Checked $Checked -Tag $Tag
    $line = New-Stack -Orientation Horizontal -Children @((New-Text -Text $Title -Size 14 -Weight 'SemiBold'))
    if ($Badge) { $b = New-Badge $Badge $BadgeKind; $b.Margin = New-Thickness 8, 0, 0, 0; [void]$line.Children.Add($b) }
    $sp = New-Stack -Children @($line)
    if ($Sub) { [void]$sp.Children.Add((New-Text -Text $Sub -Size 12 -Color $SubColor -Wrap -Margin (0, 3, 0, 0))) }
    $r.Content = $sp
    return $r
}

function New-UsCheckLine {
    # Строка проверки: ok | warn | bad | info.
    param([string]$Text, [string]$Kind = 'ok')
    $m = @{ ok = @('check', 'Ok', 'OkDim'); warn = @('warn', 'Warn', 'WarnDim'); bad = @('x', 'Bad', 'BadDim'); info = @('info', 'Info', 'InfoDim') }[$Kind]
    $dot = New-Object System.Windows.Controls.Border
    $dot.Width = 22; $dot.Height = 22; $dot.CornerRadius = New-Object System.Windows.CornerRadius 11
    $dot.Background = Get-Brush $m[2]
    $i = New-Icon -Name $m[0] -Size 13 -Color $m[1] -Stroke 2.6; $i.HorizontalAlignment = 'Center'
    $dot.Child = $i
    $t = New-Text -Text $Text -Size 13 -Wrap -Margin (10, 0, 0, 0)
    if ($Kind -eq 'bad') { $t.Foreground = Get-Brush 'Bad' }
    $g = New-Object System.Windows.Controls.DockPanel
    $g.Margin = New-Thickness 0, 0, 0, 8
    [System.Windows.Controls.DockPanel]::SetDock($dot, 'Left')
    [void]$g.Children.Add($dot); [void]$g.Children.Add($t)
    return $g
}

function New-UsLabel { param([string]$Text, $Margin = (0, 6, 0, 8)) return (New-Text -Text $Text -Size 13 -Color 'Muted' -Margin $Margin) }

function Get-UsSize {
    # Размер папки из кэша фонового подсчёта, или «…» пока считается.
    param([string]$Path)
    $ui = $script:UsUi
    if ($Path -and $ui -and $ui.Sizes -and $ui.Sizes.ContainsKey($Path.ToLowerInvariant())) { return (Format-Size $ui.Sizes[$Path.ToLowerInvariant()]) }
    return '…'
}

function Get-UsDriveText {
    param($Drive)
    return ([string]$Drive.Letter + ': · ' + [string]$Drive.Label)
}

# ---------- Страница ----------

function Build-Page_users {
    $ui = @{ Sizes = @{}; Scan = $null; Seq = 0; NewDrive = '' }
    $refresh = New-Button -Text 'Обновить' -Icon 'refresh' -OnClick { $script:UsUi.Sizes = @{}; Update-UsersPage }
    $classic = New-Button -Text 'Настройки Windows' -Kind Ghost -OnClick { Start-Process 'ms-settings:otherusers' }
    $L = New-PageLayout -Title 'Пользователи' -Subtitle 'Кто пользуется этим компьютером и где хранятся их файлы' -HeaderRight @($classic, $refresh)
    $g = New-Object System.Windows.Controls.Grid
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength 1, 'Star'
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength 360
    [void]$g.ColumnDefinitions.Add($c1); [void]$g.ColumnDefinitions.Add($c2)
    $left = New-Stack -Margin (0, 0, 16, 0)
    $ui.StatusHost = New-Stack
    [void]$left.Children.Add($ui.StatusHost)
    $ui.OldHost = New-Stack
    [void]$left.Children.Add($ui.OldHost)
    $ui.List = New-Section -Title 'Пользователи этого компьютера'
    [void]$ui.List.Body.Children.Add((New-Placeholder))
    [void]$left.Children.Add($ui.List.Root)

    # «Вход и безопасность» - редкие настройки, свёрнуты.
    $sec = New-Object System.Windows.Controls.Button
    $sec.Style = $script:Window.FindResource('BtnSecondary')
    $sec.HorizontalContentAlignment = 'Stretch'; $sec.Padding = New-Thickness 16, 12, 16, 12; $sec.Margin = New-Thickness 0, 0, 0, 16
    $sg = New-Object System.Windows.Controls.DockPanel
    $chev = New-Text -Text '›' -Size 20 -Color 'Muted'
    [System.Windows.Controls.DockPanel]::SetDock($chev, 'Right')
    $lk = New-Icon -Name 'lock' -Size 18 -Color 'Muted'; $lk.Margin = New-Thickness 0, 0, 12, 0
    [System.Windows.Controls.DockPanel]::SetDock($lk, 'Left')
    [void]$sg.Children.Add($chev); [void]$sg.Children.Add($lk)
    [void]$sg.Children.Add((New-TitleBlock -Title 'Вход и безопасность' -Sub 'Вход без пароля, гостевой доступ, скрытый администратор'))
    $sec.Content = $sg
    $ui.SecChevron = $chev
    $sec.Add_Click({
        $u = $script:UsUi
        $open = $u.Sec.Root.Visibility -ne 'Visible'
        $u.Sec.Root.Visibility = if ($open) { 'Visible' } else { 'Collapsed' }
        $u.SecChevron.Text = if ($open) { '⌄' } else { '›' }
    })
    [void]$left.Children.Add($sec)
    $ui.Sec = New-Section -Title 'Вход и безопасность'
    $ui.Sec.Root.Visibility = 'Collapsed'
    [void]$left.Children.Add($ui.Sec.Root)
    [void]$g.Children.Add($left)

    # Форма нового пользователя
    $form = New-Stack
    [void]$form.Children.Add((New-Text -Text 'Добавить пользователя' -Size 16 -Weight 'Bold' -Margin (0, 0, 0, 14)))
    $ui.NewName = New-TextInput -Placeholder 'Например, Маша'
    [void]$form.Children.Add((New-Field -Label 'Как зовут' -Control $ui.NewName))
    $ui.NewPwd = New-PasswordInput
    [void]$form.Children.Add((New-Field -Label 'Пароль - если не нужен, оставьте пустым' -Control $ui.NewPwd))
    $ui.NewPwd2 = New-PasswordInput
    $ui.NewPwd2Field = New-Field -Label 'Пароль ещё раз' -Control $ui.NewPwd2
    $ui.NewPwd2Field.Visibility = 'Collapsed'
    [void]$form.Children.Add($ui.NewPwd2Field)
    $ui.NewPwd.Add_PasswordChanged({ $u = $script:UsUi; $u.NewPwd2Field.Visibility = if ($u.NewPwd.Password) { 'Visible' } else { 'Collapsed' } })
    [void]$form.Children.Add((New-UsLabel 'Что сможет делать' (0, 0, 0, 6)))
    $ui.NewStd = New-UsRadio -Title 'Обычный' -Sub 'Программы, интернет, игры' -Group 'newtype' -Checked $true
    $ui.NewAdm = New-UsRadio -Title 'Администратор' -Sub 'Ещё ставит программы и меняет систему' -Group 'newtype'
    $ui.NewStd.Margin = New-Thickness 0, 0, 4, 0; $ui.NewAdm.Margin = New-Thickness 4, 0, 0, 0
    $rg = New-Object System.Windows.Controls.Primitives.UniformGrid
    $rg.Columns = 2; $rg.Margin = New-Thickness 0, 0, 0, 12
    [void]$rg.Children.Add($ui.NewStd); [void]$rg.Children.Add($ui.NewAdm)
    [void]$form.Children.Add($rg)
    [void]$form.Children.Add((New-UsLabel 'Где хранить его файлы' (0, 0, 0, 6)))
    $ui.DriveHost = New-Stack
    [void]$ui.DriveHost.Children.Add((New-Text -Text 'Проверяем диски…' -Size 12 -Color 'Muted' -Margin (0, 0, 0, 10)))
    [void]$form.Children.Add($ui.DriveHost)
    $ui.NewNever = New-CheckBox -Text 'Не заставлять менять пароль' -Checked $true -ToolTip 'Иначе Windows через 42 дня потребует сменить пароль'
    $ui.NewNever.Margin = New-Thickness 0, 4, 0, 12
    [void]$form.Children.Add($ui.NewNever)
    $ui.NewErr = New-Text -Text '' -Size 12 -Color 'Bad' -Wrap -Margin (0, 0, 0, 8)
    [void]$form.Children.Add($ui.NewErr)
    $create = New-Button -Text 'Создать пользователя' -Icon 'plus' -Kind Primary -OnClick { New-UserFromForm }
    $create.HorizontalAlignment = 'Stretch'
    [void]$form.Children.Add($create)
    $fc = New-Card -Child $form
    $fc.VerticalAlignment = 'Top'
    [System.Windows.Controls.Grid]::SetColumn($fc, 1)
    [void]$g.Children.Add($fc)
    [void]$L.Body.Children.Add($g)
    $script:UsUi = $ui
    return $L.Root
}

function Show-Page_users { param($Arg) Update-UsersPage }

function Update-UsersPage {
    $ui = $script:UsUi
    # Итоги переносов, которые прошли при загрузке Windows.
    try {
        foreach ($r in @(Read-ProfileMoveResults)) {
            if ($r.Ok) { Write-Log ('Перенос при загрузке выполнен: ' + $r.New) 'ok' }
            else { Write-Log ('Перенос при загрузке не выполнен: ' + $r.Message) 'warn'; Show-Info ('Перенос файлов при загрузке не выполнен.' + "`n`n" + $r.Message + "`n`nНичего не пропало - всё осталось на старом месте.") -Icon 'Warning' }
        }
    } catch {}
    try { $d = Get-LocalUsersInfo } catch { Write-Log ('Пользователи не прочитались: ' + $_.Exception.Message) 'err'; return }
    $ui.Data = $d
    Update-UsersList
    Update-UsersSecurity
    Update-UsersExtras
    Start-UsersScan
}

function Start-UsersScan {
    # Диски и старые профили - быстро; размеры папок - отдельной задачей, дольше.
    $ui = $script:UsUi
    $ui.Seq++
    $seq = $ui.Seq
    Start-BgTask -Name 'Пользователи: диски' -Silent -Context $seq -Script {
        $r = @{ Drives = @(); Old = @(); Err = '' }
        try { $r.Drives = @(Get-ProfileDrives) } catch { $r.Err = 'Диски не проверились: ' + $_.Exception.Message + ' (' + $_.InvocationInfo.ScriptLineNumber + ')' }
        try { $r.Old = @(Find-OldProfiles) } catch { $r.Err += ' Старые профили не найдены: ' + $_.Exception.Message }
        # В журнал - вердикт по каждому диску: так видно, почему диск не предложен.
        foreach ($d in $r.Drives) {
            Write-Log ('Диск ' + $d.Letter + ': ' + $d.Label + ', ' + (Format-Size $d.Free) + ' свободно, ' + $d.FileSystem + ', тип ' + $d.DriveType + $(if ($d.BusType) { ', ' + $d.BusType } else { '' }) + ' - ' + $(if ($d.Suitable) { 'подходит' } else { 'не подходит: ' + $d.Reason }))
        }
        return $r
    } -OnDone {
        param($r, $e, $job)
        $ui = $script:UsUi
        if ($e) { Write-Log ('Пользователи: проверка дисков не удалась - ' + $e) 'warn' }
        if ($r -and $r.Err) { Write-Log ('Пользователи: ' + $r.Err) 'warn' }
        if ($job.Context -ne $ui.Seq -or -not $r) { return }
        $ui.Scan = $r
        Update-UsersList
        Update-UsersExtras
        Update-NewUserDrives
        # Размеры: профили, старые копии, старые профили. Уже посчитанные не считаем заново.
        $paths = @()
        foreach ($u in $ui.Data.Users) {
            if ($u.Profile) { $paths += $u.Profile.Path }
            if ($u.OldCopy) { $paths += $u.OldCopy }
        }
        foreach ($o in $r.Old) { $paths += $o.Path }
        $paths = @($paths | Where-Object { $_ -and -not $ui.Sizes.ContainsKey($_.ToLowerInvariant()) } | Select-Object -Unique)
        if ($paths.Count -eq 0) { return }
        Start-BgTask -Name 'Пользователи: размеры' -Silent -Context $job.Context -Vars @{ Paths = $paths } -Script {
            $out = @{}
            foreach ($p in $Paths) { $out[$p.ToLowerInvariant()] = Get-FolderBytes $p }
            return $out
        } -OnDone {
            param($r2, $e2, $job2)
            $ui = $script:UsUi
            if (-not $r2) { return }
            foreach ($k in $r2.Keys) { $ui.Sizes[$k] = $r2[$k] }
            if ($job2.Context -ne $ui.Seq) { return }
            Update-UsersList
            Update-UsersExtras
        } | Out-Null
    } | Out-Null
}

function Get-UsAtRisk {
    # Пользователи, чьи файлы лежат на системном диске.
    $ui = $script:UsUi
    return @($ui.Data.Users | Where-Object { $_.Profile -and $_.Profile.OnSystem -and -not $_.Pending })
}

function Test-UsHasTargetDrive {
    $ui = $script:UsUi
    if (-not $ui.Scan) { return $false }
    return (@($ui.Scan.Drives | Where-Object { $_.Suitable }).Count -gt 0)
}

function Update-UsersExtras {
    # Карточка «защищены ли файлы» и плашка «нашли файлы со старой Windows».
    $ui = $script:UsUi
    $ui.StatusHost.Children.Clear()
    $ui.OldHost.Children.Clear()
    if (-not $ui.Scan) { return }
    $withFiles = @($ui.Data.Users | Where-Object { $_.Profile })
    $risk = @(Get-UsAtRisk)
    $hasDrive = Test-UsHasTargetDrive
    if ($withFiles.Count -gt 0) {
        $g = New-Object System.Windows.Controls.Grid
        foreach ($w in @('Auto', '*', 'Auto')) { $cd = New-Object System.Windows.Controls.ColumnDefinition; $cd.Width = $w; [void]$g.ColumnDefinitions.Add($cd) }
        $ok = ($risk.Count -eq 0)
        $tile = New-Object System.Windows.Controls.Border
        $tile.Width = 48; $tile.Height = 48; $tile.CornerRadius = New-Object System.Windows.CornerRadius 12
        $tile.Background = Get-Brush $(if ($ok) { 'OkDim' } elseif ($hasDrive) { '#3A2E14' } else { 'Panel' })
        $tile.Margin = New-Thickness 0, 0, 16, 0; $tile.VerticalAlignment = 'Center'
        $ic = New-Icon -Name $(if ($ok) { 'shield' } else { 'warn' }) -Size 26 -Color $(if ($ok) { 'Ok' } elseif ($hasDrive) { 'Accent' } else { 'Muted' }); $ic.HorizontalAlignment = 'Center'
        $tile.Child = $ic
        [void]$g.Children.Add($tile)
        $tx = New-Stack
        if ($ok) {
            $title = 'Файлы всех пользователей переживут переустановку Windows'
            $sub = 'Документы, фото и настройки программ лежат не на системном диске'
        } elseif (-not $hasDrive) {
            $title = 'Файлы пропадут при переустановке Windows'
            $sub = 'Чтобы их защитить, нужен второй диск или раздел (например, D:). Сейчас подходящего нет'
        } else {
            $n = $withFiles.Count
            $word = if ($n % 10 -eq 1 -and $n % 100 -ne 11) { 'пользователя' } else { 'пользователей' }
            $title = if ($risk.Count -eq $n -and $n -eq 1) { 'Файлы пропадут при переустановке Windows' } else { 'Файлы ' + $risk.Count + ' из ' + $n + ' ' + $word + ' пропадут при переустановке Windows' }
            $sub = 'Перенесите их на другой диск - тогда Windows можно переустанавливать, а документы, фото и настройки останутся на месте'
        }
        [void]$tx.Children.Add((New-Text -Text $title -Size 15 -Weight 'SemiBold' -Wrap))
        [void]$tx.Children.Add((New-Text -Text $sub -Size 13 -Color 'Muted' -Wrap -Margin (0, 4, 0, 0)))
        $seg = New-Object System.Windows.Controls.Primitives.UniformGrid
        $seg.Rows = 1; $seg.Margin = New-Thickness 0, 10, 0, 0
        foreach ($u in ($withFiles | Sort-Object { -not ($_.Profile.OnSystem) } -Descending)) {
            $b = New-Object System.Windows.Controls.Border
            $b.Height = 6; $b.CornerRadius = New-Object System.Windows.CornerRadius 3; $b.Margin = New-Thickness 0, 0, 4, 0
            $b.Background = Get-Brush $(if ($u.Profile.OnSystem -and -not $u.Pending) { '#3A404C' } else { 'Ok' })
            $b.ToolTip = $u.Name
            [void]$seg.Children.Add($b)
        }
        [void]$tx.Children.Add($seg)
        [System.Windows.Controls.Grid]::SetColumn($tx, 1)
        [void]$g.Children.Add($tx)
        if (-not $ok -and $hasDrive) {
            $first = @($risk | Sort-Object { $_.IsMe }, { -not $_.Enabled })[0]
            $btn = New-Button -Text 'Защитить файлы' -Kind Primary -Tag $first -OnClick { Show-ProtectDialog -User $this.Tag }
            $btn.Margin = New-Thickness 16, 0, 0, 0; $btn.VerticalAlignment = 'Center'
            [System.Windows.Controls.Grid]::SetColumn($btn, 2)
            [void]$g.Children.Add($btn)
        }
        [void]$ui.StatusHost.Children.Add((New-Card -Child $g -Padding (18, 16, 18, 16) -Margin (0, 0, 0, 14)))
    }
    $old = @($ui.Scan.Old)
    if ($old.Count -gt 0) {
        $g = New-Object System.Windows.Controls.DockPanel
        $ic = New-Icon -Name 'folder' -Size 22 -Color 'Info'; $ic.Margin = New-Thickness 0, 0, 14, 0
        [System.Windows.Controls.DockPanel]::SetDock($ic, 'Left')
        $rp = New-Stack -Orientation Horizontal
        [System.Windows.Controls.DockPanel]::SetDock($rp, 'Right')
        $back = New-Button -Text 'Вернуть файлы' -Kind Small -OnClick { Show-RestoreDialog }
        $back.Foreground = Get-Brush 'Info'; $back.BorderBrush = Get-Brush '#24496B'; $back.Background = Get-Brush '#1B2E42'
        $hide = New-Button -Text 'Скрыть' -Kind Ghost -OnClick {
            if (-not (Show-Confirm 'Больше не показывать эти папки? Сами файлы никуда не денутся.')) { return }
            foreach ($o in @($script:UsUi.Scan.Old)) { Hide-OldProfile -Path $o.Path }
            Update-UsersPage
        }
        $hide.Foreground = Get-Brush 'Muted'; $hide.Margin = New-Thickness 6, 0, 0, 0
        [void]$rp.Children.Add($back); [void]$rp.Children.Add($hide)
        $names = @($old | ForEach-Object { $_.Name + ' - ' + (Get-UsSize $_.Path) }) -join ', '
        $t = New-Stack
        [void]$t.Children.Add((New-Text -Text 'Нашли файлы со старой Windows' -Size 14 -Weight 'SemiBold'))
        [void]$t.Children.Add((New-Text -Text $names -Size 12 -Color '#B9D7EF' -Wrap -Margin (0, 2, 0, 0)))
        [void]$g.Children.Add($ic); [void]$g.Children.Add($rp); [void]$g.Children.Add($t)
        [void]$ui.OldHost.Children.Add((New-Card -Child $g -Padding (16, 12, 12, 12) -Margin (0, 0, 0, 14) -Background '#152536' -Border '#24496B'))
    }
}

function Update-UsersList {
    $ui = $script:UsUi
    $d = $ui.Data
    $body = $ui.List.Body
    $body.Children.Clear()
    $ui.List.Header.Text = 'Пользователи этого компьютера · ' + $d.Users.Count
    $hasDrive = Test-UsHasTargetDrive
    foreach ($u in @($d.Users | Sort-Object { -not $_.IsMe }, { -not $_.Enabled }, { $_.Name })) {
        # Имя, метки и короткая роль
        $nameLine = New-Stack -Orientation Horizontal
        $nm = New-Text -Text $(if ($u.FullName -and $u.FullName -ne $u.Name) { $u.FullName + ' (' + $u.Name + ')' } else { $u.Name }) -Size 15 -Weight 'SemiBold' -Color $(if ($u.Enabled) { 'Text' } else { 'Muted' })
        $nm.ToolTip = if ($u.LastLogon) { 'Последний вход: ' + ([datetime]$u.LastLogon).ToString('dd.MM.yyyy HH:mm') } else { 'Ещё не входил' }
        [void]$nameLine.Children.Add($nm)
        $badges = @()
        if ($u.IsMe) { $badges += New-Badge 'это вы' 'muted' }
        if (-not $u.Enabled) { $badges += New-Badge 'выключен' 'muted' }
        if ($u.Source -eq 'MicrosoftAccount') { $badges += New-Badge 'учётка Microsoft' 'muted' }
        foreach ($b in $badges) { $b.Margin = New-Thickness 8, 0, 0, 0; [void]$nameLine.Children.Add($b) }
        $role = @($(if ($u.IsAdmin) { 'может всё' } else { 'обычный доступ' }))
        if ($d.Auto.On -and $d.Auto.User -ieq $u.Name) { $role += 'входит без пароля' }
        [void]$nameLine.Children.Add((New-Text -Text ('  · ' + ($role -join ' · ')) -Size 12 -Color 'Muted'))

        # Где файлы
        $st = New-Stack -Orientation Horizontal -Margin (0, 5, 0, 0)
        $p = $u.Profile
        if ($u.Pending) {
            $icon = 'clock'; $col = 'Info'; $txt = 'Перенос на другой диск запланирован - пройдёт при следующей перезагрузке'
        } elseif (-not $p) {
            $icon = 'info'; $col = 'Muted'; $txt = 'Ещё не входил - файлов пока нет'
        } elseif ($p.OnSystem) {
            $icon = 'warn'; $col = 'Warn'; $txt = 'Файлы на диске ' + $p.Letter + ': · ' + (Get-UsSize $p.Path) + ' · сотрутся при переустановке'
        } else {
            $icon = 'shield'; $col = 'Ok'; $txt = 'Файлы на диске ' + $p.Letter + ': · ' + (Get-UsSize $p.Path) + ' · переживут переустановку'
        }
        [void]$st.Children.Add((New-Icon -Name $icon -Size 14 -Color $col -Stroke 2))
        $tt = New-Text -Text $txt -Size 12 -Color $col -Margin (6, 0, 0, 0)
        if ($p) { $tt.ToolTip = $p.Path }
        [void]$st.Children.Add($tt)
        $main = New-Stack -Children @($nameLine, $st)
        if ($u.OldCopy) {
            [void]$main.Children.Add((New-Text -Text ('Старая копия: ' + $u.OldCopy + ' · ' + (Get-UsSize $u.OldCopy) + ' - когда убедитесь, что всё на месте, удалите её в меню «⋯»') -Size 12 -Color 'Muted' -Wrap -Margin (20, 3, 0, 0)))
        }

        $right = @()
        if ($hasDrive -and -not $u.Pending -and (-not $p -or $p.OnSystem)) {
            $pb = New-Button -Text 'Защитить' -Kind Small -Tag $u -OnClick { Show-ProtectDialog -User $this.Tag }
            $pb.Foreground = Get-Brush 'Accent'; $pb.BorderBrush = Get-Brush '#5A4521'; $pb.Background = Get-Brush '#241F14'
            $pb.ToolTip = 'Перенести файлы на другой диск, чтобы они пережили переустановку Windows'
            $right += $pb
        }
        $pw = New-Button -Text 'Пароль' -Kind Small -Tag @{ A = 'pwd'; U = $u } -OnClick { Invoke-UserAction -Spec $this.Tag }
        if ($u.Source -eq 'MicrosoftAccount') { $pw.IsEnabled = $false; $pw.ToolTip = 'Пароль учётной записи Microsoft меняется на account.microsoft.com' }
        $right += $pw
        $more = New-Button -Text '⋯' -Kind Small -Tag $u -OnClick { Show-UserMenu -Anchor $this -User $this.Tag }
        $more.Padding = New-Thickness 0; $more.Width = 36
        $more.ToolTip = 'Ещё действия'
        $right += $more
        $row = New-Row -Left (New-AppIcon -Name $u.Name -Size 44) -Main $main -Right $right -Padding (16, 14, 16, 14)
        $row.Child.Children[0].CornerRadius = New-Object System.Windows.CornerRadius 22
        if (-not $u.Enabled) { $row.Child.Children[0].Opacity = 0.5 }
        [void]$body.Children.Add($row)
    }
}

function Show-UserMenu {
    param($Anchor, $User)
    $u = $User
    $items = @()
    if (-not $u.IsMe) {
        $items += @{ Text = $(if ($u.IsAdmin) { 'Сделать обычным пользователем' } else { 'Сделать администратором' }); Tag = @{ A = 'admin'; U = $u } }
        $items += @{ Text = $(if ($u.Enabled) { 'Выключить учётную запись' } else { 'Включить учётную запись' }); Tag = @{ A = 'enable'; U = $u } }
    }
    if ($u.Source -ne 'MicrosoftAccount') { $items += @{ Text = 'Не заставлять менять пароль'; Tag = @{ A = 'never'; U = $u }; Checked = [bool]$u.NeverExpires } }
    $items += @{ Separator = $true }
    if ($u.Profile) { $items += @{ Text = 'Открыть папку с файлами'; Tag = @{ A = 'open'; U = $u } } }
    if ($u.Profile -and -not $u.Profile.OnSystem -and -not $u.Pending -and (Test-UsHasTargetDrive)) { $items += @{ Text = 'Перенести файлы на другой диск…'; Tag = @{ A = 'protect'; U = $u } } }
    if ($u.OldCopy) { $items += @{ Text = 'Удалить старую копию (' + (Get-UsSize $u.OldCopy) + ')'; Tag = @{ A = 'oldcopy'; U = $u } } }
    if ($u.Pending) { $items += @{ Text = 'Отменить перенос при перезагрузке'; Tag = @{ A = 'unpending'; U = $u } } }
    if (-not $u.IsMe) {
        $items += @{ Separator = $true }
        $items += @{ Text = 'Удалить пользователя…'; Tag = @{ A = 'delete'; U = $u }; Danger = $true }
    }
    while ($items.Count -and $items[-1].Separator) { $items = @($items | Select-Object -SkipLast 1) }
    foreach ($i in $items) { if (-not $i.Separator) { $i.OnClick = { Invoke-UserAction -Spec $this.Tag } } }
    Show-ActionMenu -Anchor $Anchor -Items $items
}

function Update-UsersSecurity {
    $ui = $script:UsUi
    $d = $ui.Data
    $sec = $ui.Sec.Body
    $sec.Children.Clear()
    $mkT = {
        param($title, $sub, $on, $tag)
        $t = New-Toggle -Checked $on -Tag $tag -OnClick { Invoke-UserToggle -Spec $this.Tag -On ([bool]$this.IsChecked) }
        [void]$sec.Children.Add((New-Row -Main (New-TitleBlock -Title $title -Sub $sub) -Right @($t)))
    }
    $autoSub = if ($d.Auto.On) { 'Сейчас: сразу входить как «' + $d.Auto.User + '». Удобно на домашнем ПК, небезопасно на ноутбуке' } else { 'Сразу входить в выбранную учётку при включении. Удобно на домашнем ПК, небезопасно на ноутбуке' }
    & $mkT 'Вход без пароля' $autoSub $d.Auto.On 'auto'
    $g = $d.Builtin['501']
    if ($g) { & $mkT ('Гостевая запись «' + $g.Name + '»') 'Рекомендуем держать выключенной' $g.Enabled 'guest' }
    $a = $d.Builtin['500']
    if ($a) { & $mkT ('Скрытый «' + $a.Name + '»') 'Встроенная учётка Windows. Включайте только для ремонта и обязательно задайте пароль' $a.Enabled 'admin500' }
}

function Update-NewUserDrives {
    # «Где хранить его файлы» в форме: рекомендуемый диск, системный и «другой диск».
    $ui = $script:UsUi
    $h = $ui.DriveHost
    $h.Children.Clear()
    $ui.DriveRadios = @()
    $drives = @($ui.Scan.Drives)
    $sys = @($drives | Where-Object { $_.IsSystem })[0]
    $ok = @($drives | Where-Object { $_.Suitable })
    if ($ok.Count -eq 0) {
        # Не просто «нет диска», а почему: какой диск нашли и чем он не подошёл.
        $other = @($drives | Where-Object { -not $_.IsSystem })
        $msg = if ($drives.Count -eq 0) { 'Не удалось проверить диски - подробности в «Журнале» внизу окна. Пока файлы будут на диске ' + $env:SystemDrive }
               elseif ($other.Count -eq 0) { 'Файлы будут на диске ' + $env:SystemDrive + ' - другого диска с буквой нет. Новый диск сначала нужно разметить в «Управлении дисками»' }
               else { 'Файлы будут на диске ' + $env:SystemDrive + '. Другие диски не подходят:' }
        [void]$h.Children.Add((New-Text -Text $msg -Size 12 -Color 'Muted' -Wrap -Margin (0, 0, 0, 6)))
        foreach ($dr in $other) { [void]$h.Children.Add((New-Text -Text ((Get-UsDriveText $dr) + ' - ' + $dr.Reason) -Size 12 -Color 'Warn' -Wrap -Margin (0, 0, 0, 4))) }
        return
    }
    $best = Select-BestProfileDrive -Drives $ok -NeedBytes 0
    if (-not $best) { $best = [string]$ok[0].Letter }
    $pick = if ($ui.NewDrive) { $ui.NewDrive } else { $best }
    $show = @($ok | Where-Object { $_.Letter -eq $best -or $_.Letter -eq $pick })
    foreach ($dr in $show) {
        $r = New-UsRadio -Title ('Диск ' + $dr.Letter + ':') -Sub ('Файлы останутся, даже если переустановить Windows · ' + (Format-Size $dr.Free) + ' свободно') -Group 'newdrive' -Checked ($dr.Letter -eq $pick) -Tag $dr.Letter -Badge $(if ($dr.Letter -eq $best) { 'рекомендуем' } else { '' })
        $ui.DriveRadios += $r
        [void]$h.Children.Add($r)
    }
    if ($sys) {
        $r = New-UsRadio -Title ('Диск ' + $sys.Letter + ':') -Sub ('Как обычно в Windows. Сотрутся вместе с системой · ' + (Format-Size $sys.Free) + ' свободно') -Group 'newdrive' -Checked ($pick -eq $sys.Letter) -Tag $sys.Letter
        $ui.DriveRadios += $r
        [void]$h.Children.Add($r)
    }
    $rest = @($ok | Where-Object { $show -notcontains $_ })
    if ($rest.Count -gt 0) {
        $lnk = New-Button -Text ('Другой диск - ещё ' + $rest.Count + ' подходят') -Kind Ghost -OnClick { Show-DrivePicker }
        $lnk.HorizontalAlignment = 'Left'; $lnk.Margin = New-Thickness -8, -4, 0, 4
        [void]$h.Children.Add($lnk)
    }
}

function Get-NewUserDrive {
    $ui = $script:UsUi
    $sel = @($ui.DriveRadios | Where-Object { $_.IsChecked })
    if ($sel.Count) { return [string]$sel[0].Tag }
    return ($env:SystemDrive).TrimEnd(':')
}

function Add-UsDriveList {
    # Список дисков для окна: подходящие - радиокарточками, остальные - серым с причиной.
    param($Panel, [string]$Group, [double]$NeedBytes = 0, [string]$Exclude = '', [string]$Pick = '')
    $drives = @($script:UsUi.Scan.Drives)
    $ok = @($drives | Where-Object { $_.Suitable -and $_.Letter -ne $Exclude })
    $best = Select-BestProfileDrive -Drives $ok -NeedBytes $NeedBytes
    if (-not $Pick) { $Pick = $best }
    $radios = @()
    foreach ($dr in $ok) {
        $left = [double]$dr.Free - $NeedBytes
        $sub = (Format-Size $dr.Free) + ' свободно из ' + (Format-Size $dr.Size) + $(if ($dr.Media) { ' · ' + $dr.Media } else { '' })
        $subColor = 'Muted'
        $note = [string]$dr.Note
        if ($NeedBytes -gt 0 -and $left -lt 2GB) { $note = 'Не хватит места: нужно ' + (Format-Size $NeedBytes); $subColor = 'Bad' }
        elseif ($NeedBytes -gt 0 -and $left -lt [Math]::Max(10GB, [double]$dr.Size * 0.05)) { $note = 'Поместится, но после переноса останется всего ' + (Format-Size $left); $subColor = 'Warn' }
        $r = New-UsRadio -Title (Get-UsDriveText $dr) -Sub ($sub + "`n" + $note) -Group $Group -Checked ($dr.Letter -eq $Pick) -Tag $dr.Letter -Badge $(if ($dr.Letter -eq $best) { 'рекомендуем' } else { '' }) -SubColor $subColor
        if ($subColor -eq 'Bad') { $r.IsEnabled = $false; $r.Opacity = 0.55; $r.IsChecked = $false }
        $radios += $r
        [void]$Panel.Children.Add($r)
    }
    $bad = @($drives | Where-Object { -not $_.Suitable -or $_.Letter -eq $Exclude })
    if ($bad.Count) {
        [void]$Panel.Children.Add((New-UsLabel 'Не подходят' (0, 6, 0, 6)))
        foreach ($dr in $bad) {
            $why = if ($dr.Letter -eq $Exclude) { 'Файлы уже здесь' } else { [string]$dr.Reason }
            $row = New-Object System.Windows.Controls.DockPanel
            $row.Margin = New-Thickness 0, 0, 0, 6
            $n = New-Text -Text (Get-UsDriveText $dr) -Size 13 -Weight 'SemiBold' -Color 'Muted'
            $n.Width = 150
            [System.Windows.Controls.DockPanel]::SetDock($n, 'Left')
            [void]$row.Children.Add($n)
            [void]$row.Children.Add((New-Text -Text $why -Size 12 -Color 'Muted' -Wrap))
            [void]$Panel.Children.Add($row)
        }
    }
    return $radios
}

function Show-DrivePicker {
    $ui = $script:UsUi
    if (-not $ui.Scan) { return }
    $script:DpRadios = @()
    $ok = Show-FormDialog -Title 'Где хранить файлы нового пользователя' -OkText 'Выбрать' -Width 560 -Build {
        param($f)
        [void]$f.Children.Add((New-Text -Text 'Мы уже выбрали лучший вариант - можно просто нажать «Выбрать».' -Size 13 -Color 'Muted' -Wrap -Margin (0, 0, 0, 12)))
        $script:DpRadios = @(Add-UsDriveList -Panel $f -Group 'dp' -Pick $script:UsUi.NewDrive)
    } -OnOk {
        $sel = @($script:DpRadios | Where-Object { $_.IsChecked })
        if (-not $sel.Count) { return 'Выберите диск' }
        $script:UsUi.NewDrive = [string]$sel[0].Tag
        return $true
    }
    if ($ok) { Update-NewUserDrives }
}

# ---------- Окно «Защитить файлы» ----------

function Show-ProtectDialog {
    param($User)
    $ui = $script:UsUi
    if (-not $ui.Scan) { Show-Info 'Ещё проверяем диски - попробуйте через пару секунд.'; return }
    $u = $User
    $p = $u.Profile
    $need = 0.0
    if ($p -and $ui.Sizes.ContainsKey($p.Path.ToLowerInvariant())) { $need = [double]$ui.Sizes[$p.Path.ToLowerInvariant()] }
    $script:PrUi = @{ User = $u; Need = $need; Radios = @(); To = $null; Space = $null }
    $from = if ($p) { $p.Letter } else { ($env:SystemDrive).TrimEnd(':') }
    $best = Select-BestProfileDrive -Drives @($ui.Scan.Drives | Where-Object { $_.Suitable -and $_.Letter -ne $from }) -NeedBytes $need
    $okText = if ($best) { 'Перенести на ' + $best + ':' } else { 'Перенести' }
    $ok = Show-FormDialog -Title ('Защитить файлы пользователя ' + $u.Name) -OkText $okText -Width 640 -Build {
        param($f)
        $pr = $script:PrUi
        $u = $pr.User
        $sub = if ($u.Profile) { 'Перенесём всё, что есть у ' + $u.Name + ' - рабочий стол, документы, фото, настройки программ - на другой диск. Пользоваться компьютером он будет как раньше, ничего не заметит.' }
               else { 'У ' + $u.Name + ' ещё нет файлов. Создадим его папку сразу на выбранном диске - всё, что он сохранит, переживёт переустановку Windows.' }
        [void]$f.Children.Add((New-Text -Text $sub -Size 13 -Color 'Muted' -Wrap -Margin (0, 0, 0, 14)))

        # Было -> будет
        $g = New-Object System.Windows.Controls.Grid
        foreach ($w in @('*', 'Auto', '*')) { $cd = New-Object System.Windows.Controls.ColumnDefinition; $cd.Width = $w; [void]$g.ColumnDefinitions.Add($cd) }
        $l = if ($u.Profile) { New-Stack -Children @((New-Text -Text 'Сейчас' -Size 12 -Color 'Muted'), (New-Text -Text ('Диск ' + $from + ':') -Size 16 -Weight 'SemiBold' -Margin (0, 2, 0, 2)), (New-Text -Text 'сотрётся при переустановке' -Size 12 -Color 'Warn')) }
             else { New-Stack -Children @((New-Text -Text 'Сейчас' -Size 12 -Color 'Muted'), (New-Text -Text 'Файлов нет' -Size 16 -Weight 'SemiBold' -Margin (0, 2, 0, 2)), (New-Text -Text 'появятся при первом входе' -Size 12 -Color 'Muted')) }
        $mid = New-Stack -Margin (14, 0, 14, 0)
        $mid.VerticalAlignment = 'Center'
        $sz = New-Text -Text $(if ($pr.Need -gt 0) { Format-Size $pr.Need } elseif ($u.Profile) { 'размер считается' } else { 'пусто' }) -Size 13 -Weight 'Bold' -Color 'Accent'
        $sz.HorizontalAlignment = 'Center'
        $arr = New-Text -Text '⟶' -Size 22 -Color 'Accent'; $arr.HorizontalAlignment = 'Center'
        [void]$mid.Children.Add($sz); [void]$mid.Children.Add($arr)
        [System.Windows.Controls.Grid]::SetColumn($mid, 1)
        $pr.To = New-Text -Text 'Диск ?' -Size 16 -Weight 'SemiBold' -Margin (0, 2, 0, 2)
        $pr.To.HorizontalAlignment = 'Right'
        $will = New-Text -Text 'Будет' -Size 12 -Color 'Muted'; $will.HorizontalAlignment = 'Right'
        $okT = New-Text -Text 'переживёт переустановку' -Size 12 -Color 'Ok'; $okT.HorizontalAlignment = 'Right'
        $r = New-Stack -Children @($will, $pr.To, $okT)
        [System.Windows.Controls.Grid]::SetColumn($r, 2)
        [void]$g.Children.Add($l); [void]$g.Children.Add($mid); [void]$g.Children.Add($r)
        [void]$f.Children.Add((New-Card -Child $g -Padding 16 -Background 'Panel' -Margin (0, 0, 0, 14)))

        [void]$f.Children.Add((New-UsLabel 'Куда перенести' (0, 0, 0, 8)))
        $pr.Radios = @(Add-UsDriveList -Panel $f -Group 'pr' -NeedBytes $pr.Need -Exclude $from)
        foreach ($x in $pr.Radios) { $x.Add_Checked({ Update-ProtectTarget }) }

        [void]$f.Children.Add((New-UsLabel 'Перед началом проверим' (0, 10, 0, 8)))
        if ($u.IsMe) { [void]$f.Children.Add((New-UsCheckLine 'Вы сейчас в этой учётной записи - перенос пройдёт при следующей перезагрузке, до входа в Windows' 'warn')) }
        elseif ($u.Profile -and $u.Profile.Loaded) { [void]$f.Children.Add((New-UsCheckLine ($u.Name + ' сейчас в системе - пусть выйдет из учётной записи (Пуск → значок пользователя → Выход)') 'bad')) }
        else { [void]$f.Children.Add((New-UsCheckLine ($u.Name + ' сейчас не за компьютером'))) }
        $pr.Space = New-UsCheckLine 'Место на диске проверим перед началом' 'info'
        [void]$f.Children.Add($pr.Space)
        [void]$f.Children.Add((New-UsCheckLine 'Только встроенные диски - не флешки и не сеть'))
        [void]$f.Children.Add((New-UsCheckLine 'Сохраним копию настроек - вернуть всё назад можно в «Истории»'))
        if ($u.Profile) { [void]$f.Children.Add((New-Hint -Text ('Старые файлы на ' + $from + ': пока не удаляем. Зайдите под ' + $u.Name + ', убедитесь, что всё на месте, - и освободите место через меню «⋯».') -Kind 'info' -Margin (0, 8, 0, 4))) }
        if ($u.IsMe) { [void]$f.Children.Add((New-Hint -Text 'После перезагрузки подождите несколько минут, прежде чем входить. Если войти раньше - перенос просто отменится, ничего не пропадёт.' -Kind 'warn' -Margin (0, 8, 0, 4))) }
        $script:PrUi = $pr
        Update-ProtectTarget
    } -OnOk {
        $pr = $script:PrUi
        $sel = @($pr.Radios | Where-Object { $_.IsChecked })
        if (-not $sel.Count) { return 'Выберите диск' }
        $pr.Drive = [string]$sel[0].Tag
        if (-not $pr.User.IsMe -and $pr.User.Profile -and $pr.User.Profile.Loaded) { return ($pr.User.Name + ' сейчас в системе - пусть сначала выйдет') }
        return $true
    }
    if (-not $ok) { return }
    Start-ProtectUser -User $u -Drive $script:PrUi.Drive
}

function Update-ProtectTarget {
    $pr = $script:PrUi
    if (-not $pr) { return }
    $sel = @($pr.Radios | Where-Object { $_.IsChecked })
    if (-not $sel.Count) { return }
    $L = [string]$sel[0].Tag
    $pr.To.Text = 'Диск ' + $L + ':'
    try { Set-ButtonText $script:DlgState.Ok ('Перенести на ' + $L + ':') } catch {}
    $dr = @($script:UsUi.Scan.Drives | Where-Object { $_.Letter -eq $L })[0]
    if ($pr.Need -gt 0 -and $dr) {
        $pr.Space.Children[1].Text = 'На диске ' + $L + ': хватит места - нужно ' + (Format-Size $pr.Need) + ', свободно ' + (Format-Size $dr.Free)
    }
}

function Start-ProtectUser {
    param($User, [string]$Drive)
    $u = $User
    if ($u.IsMe) {
        try { [void](Register-ProfileMoveAtBoot -Sid $u.Sid -Drive $Drive) } catch { Show-Info ('Не удалось запланировать перенос: ' + $_.Exception.Message) -Icon 'Error'; return }
        Update-UsersPage
        if (Show-Confirm -Message ('Перенос запланирован. Он пройдёт при следующей перезагрузке, до входа в Windows.' + "`n`n" + 'После перезагрузки подождите несколько минут, прежде чем входить.' + "`n`n" + 'Перезагрузить компьютер сейчас?')) {
            Restart-Computer -Force
        }
        return
    }
    Start-BgTask -Name ('Перенос файлов: ' + $u.Name) -Vars @{ U = $u; D = $Drive } -Script {
        if (-not $U.Profile) {
            Write-Log ('Создаём папку пользователя ' + $U.Name + '…')
            try { [void](New-UserProfileNow -Sid $U.Sid -Name $U.Name) } catch { return @{ Ok = $false; Message = $_.Exception.Message } }
        }
        return (Move-UserProfile -Sid $U.Sid -Drive $D)
    } -OnDone {
        param($r, $e)
        if ($r -and $r.Ok) {
            Show-Info ('Готово: файлы теперь на ' + $r.New + "`n`n" + $(if ($r.Old) { 'Старая папка ' + $r.Old + ' пока осталась. Когда убедитесь, что всё на месте, удалите её в меню «⋯».' } else { '' }))
        } elseif ($r) {
            Write-Log ('Перенос не выполнен: ' + $r.Message) 'warn'
            Show-Info ('Перенос не выполнен.' + "`n`n" + $r.Message) -Icon 'Warning'
        }
        $script:UsUi.Sizes = @{}
        Update-UsersPage
    } | Out-Null
}

# ---------- Окно «Вернуть файлы» ----------

function Show-RestoreDialog {
    $ui = $script:UsUi
    $old = @($ui.Scan.Old)
    if ($old.Count -eq 0) { return }
    $users = @($ui.Data.Users | Where-Object { $_.Enabled })
    $script:RsUi = @{ Old = $old; Users = $users; Src = @(); Dst = @(); Items = @(); Checks = @(); Seq = 0 }
    $ok = Show-FormDialog -Title 'Вернуть файлы со старой Windows' -OkText 'Вернуть файлы' -Width 760 -Build {
        param($f)
        $rs = $script:RsUi
        [void]$f.Children.Add((New-Text -Text 'На других дисках остались файлы пользователей, которые были до переустановки. Выберите, чьи файлы и кому вернуть.' -Size 13 -Color 'Muted' -Wrap -Margin (0, 0, 0, 12)))
        [void]$f.Children.Add((New-UsLabel 'Чьи файлы' (0, 0, 0, 8)))
        $g = New-Object System.Windows.Controls.Primitives.UniformGrid
        $g.Columns = [Math]::Min(2, $rs.Old.Count)
        $i = 0
        foreach ($o in $rs.Old) {
            $r = New-UsRadio -Title $o.Name -Sub ((Get-UsSize $o.Path) + ' · ' + $o.Path + ' · последний раз ' + ([datetime]$o.LastWrite).ToString('dd.MM.yyyy')) -Group 'rsrc' -Checked ($i -eq 0) -Tag $o
            $r.Margin = New-Thickness 0, 0, 8, 8
            $r.Add_Checked({ Update-RestoreItems })
            $rs.Src += $r
            [void]$g.Children.Add($r)
            $i++
        }
        [void]$f.Children.Add($g)
        [void]$f.Children.Add((New-UsLabel 'Кому вернуть' (0, 4, 0, 8)))
        $rs.DstHost = New-Object System.Windows.Controls.Primitives.UniformGrid
        $rs.DstHost.Columns = 2
        [void]$f.Children.Add($rs.DstHost)
        [void]$f.Children.Add((New-UsLabel 'Что вернуть' (0, 4, 0, 8)))
        $rs.ItemsHost = New-Stack
        [void]$f.Children.Add($rs.ItemsHost)
        $rs.Cache = New-CheckBox -Text 'Кэш браузеров не переносить - браузер сам скачает его заново' -Checked $true
        $rs.Cache.Margin = New-Thickness 0, 10, 0, 6
        $rs.Cache.Add_Checked({ Update-RestoreTotal }); $rs.Cache.Add_Unchecked({ Update-RestoreTotal })
        [void]$f.Children.Add($rs.Cache)
        $rs.Bm = New-CheckBox -Text 'Закладки браузеров сохранить ещё и отдельными файлами в «Документы»' -Checked $true
        $rs.Bm.Margin = New-Thickness 0, 0, 0, 10
        [void]$f.Children.Add($rs.Bm)
        [void]$f.Children.Add((New-UsLabel 'Способ' (0, 4, 0, 8)))
        $mg = New-Object System.Windows.Controls.Primitives.UniformGrid
        $mg.Columns = 2
        $rs.Move = New-UsRadio -Title 'Переместить' -Sub 'Файлы переедут, старая папка опустеет' -Group 'rsmode' -Checked $true
        $rs.Copy = New-UsRadio -Title 'Копировать' -Sub 'Старая папка останется нетронутой' -Group 'rsmode'
        $rs.Move.Margin = New-Thickness 0, 0, 8, 0
        $rs.Move.Add_Checked({ Update-RestoreTotal }); $rs.Copy.Add_Checked({ Update-RestoreTotal })
        [void]$mg.Children.Add($rs.Move); [void]$mg.Children.Add($rs.Copy)
        [void]$f.Children.Add($mg)
        $rs.Total = New-Text -Text '' -Size 13 -Color 'Muted' -Wrap -Margin (0, 12, 0, 0)
        [void]$f.Children.Add($rs.Total)
        $script:RsUi = $rs
        Update-RestoreItems
    } -OnOk {
        $rs = $script:RsUi
        $src = @($rs.Src | Where-Object { $_.IsChecked })[0]
        $dst = @($rs.Dst | Where-Object { $_.IsChecked })[0]
        if (-not $src -or -not $dst) { return 'Выберите, чьи файлы и кому' }
        $items = @($rs.Checks | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
        if ($items.Count -eq 0) { return 'Отметьте, что вернуть' }
        $procs = @($items | Where-Object { $_.Proc } | ForEach-Object { $_.Proc } | Select-Object -Unique)
        if ($items | Where-Object { $_.Id -eq 'app:telegram desktop' }) { $procs += 'Telegram' }
        if ($items | Where-Object { $_.Id -eq 'app:discord' }) { $procs += 'Discord' }
        $running = @($procs | Where-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue })
        if ($running.Count) { return ('Сначала закройте: ' + ($running -join ', ') + ' - иначе их данные не перенесутся') }
        $rs.Run = @{ Src = $src.Tag; Dst = $dst.Tag; Items = $items; Mode = $(if ($rs.Copy.IsChecked) { 'copy' } else { 'move' }); SkipCache = [bool]$rs.Cache.IsChecked; Bm = [bool]$rs.Bm.IsChecked }
        return $true
    }
    if (-not $ok) { return }
    $run = $script:RsUi.Run
    Start-BgTask -Name ('Возврат файлов: ' + $run.Src.Name) -Vars @{ R = $run } -Script {
        Restore-OldProfileItems -Source $R.Src.Path -TargetSid $R.Dst.Sid -TargetName $R.Dst.Name -Items $R.Items -Mode $R.Mode -SkipCache $R.SkipCache -ExportBookmarks $R.Bm
    } -OnDone {
        param($r, $e, $job)
        $run = $job.Context
        $msg = if ($r) { $r.Message } else { 'Не получилось: ' + $e }
        if ($r -and $r.Ok) { Write-Log ('Файлы возвращены: ' + $r.Target) 'ok' }
        $q = $msg + "`n`n" + 'В старой папке ' + $run.Src.Path + ' осталось то, что вы не выбрали (и кэш браузеров). Удалить её?' + "`n`n" + '«Нет» - папка останется, её можно удалить позже вручную.'
        if ($r -and $r.Done -gt 0 -and (Show-Confirm -Message $q -Title 'Готово' -Warning)) {
            Start-BgTask -Name 'Удаление старой папки' -Vars @{ P = $run.Src.Path } -Script { Remove-OldProfileCopy -Path $P } -OnDone { Update-UsersPage } | Out-Null
        } elseif (-not ($r -and $r.Done -gt 0)) { Show-Info $msg -Icon 'Warning' }
        $script:UsUi.Sizes = @{}
        Update-UsersPage
    } -Context $run | Out-Null
}

function Update-RestoreItems {
    # Новый источник: «кому» по умолчанию - тот, у кого то же имя; список - в фоне.
    $rs = $script:RsUi
    $src = @($rs.Src | Where-Object { $_.IsChecked })[0]
    if (-not $src) { return }
    $o = $src.Tag
    $rs.DstHost.Children.Clear()
    $rs.Dst = @()
    $pick = @($rs.Users | Where-Object { $_.Name -ieq $o.Name -or ($_.FullName -and $_.FullName -ieq $o.Name) })[0]
    if (-not $pick) { $pick = @($rs.Users | Where-Object { $_.IsMe })[0] }
    foreach ($u in $rs.Users) {
        $where = if ($u.Profile) { 'файлы на ' + $u.Profile.Letter + ':' } else { 'ещё не входил' }
        $r = New-UsRadio -Title ($u.Name + $(if ($u.IsMe) { ' - это вы' } else { '' })) -Sub $where -Group 'rsdst' -Checked ($u -eq $pick) -Tag $u
        $r.Margin = New-Thickness 0, 0, 8, 8
        $r.Add_Checked({ Update-RestoreTotal })
        $rs.Dst += $r
        [void]$rs.DstHost.Children.Add($r)
    }
    $rs.ItemsHost.Children.Clear()
    $rs.Checks = @()
    [void]$rs.ItemsHost.Children.Add((New-Text -Text 'Смотрим, что внутри… (на больших папках это может занять минуту)' -Size 13 -Color 'Muted' -Margin (0, 4, 0, 4)))
    $rs.Seq++
    Start-BgTask -Name 'Старые файлы: что внутри' -Silent -Context $rs.Seq -Vars @{ P = $o.Path } -Script { @{ Items = @(Get-OldProfileItems -Path $P) } } -OnDone {
        param($r, $e, $job)
        $rs = $script:RsUi
        if (-not $rs -or $job.Context -ne $rs.Seq) { return }
        $rs.Items = if ($r) { @($r.Items) } else { @() }
        Show-RestoreItemList
    } | Out-Null
    Update-RestoreTotal
}

function Show-RestoreItemList {
    $rs = $script:RsUi
    $h = $rs.ItemsHost
    $h.Children.Clear()
    $rs.Checks = @()
    if ($rs.Items.Count -eq 0) { [void]$h.Children.Add((New-Text -Text 'В этой папке нечего возвращать.' -Size 13 -Color 'Muted')); return }
    $mk = {
        param($it, $content)
        $c = New-CheckBox -Checked $true -Tag $it
        $c.Content = $content
        $c.Add_Checked({ Update-RestoreTotal }); $c.Add_Unchecked({ Update-RestoreTotal })
        $script:RsUi.Checks += $c
        return $c
    }
    # Папки - сеткой
    $fg = New-Object System.Windows.Controls.Primitives.UniformGrid
    $fg.Columns = 3
    foreach ($it in @($rs.Items | Where-Object { $_.Kind -eq 'folder' })) {
        $content = New-Stack -Orientation Horizontal -Children @((New-Text -Text $it.Title -Size 13), (New-Text -Text ('  ' + (Format-Size $it.Bytes)) -Size 12 -Color 'Muted'))
        $c = & $mk $it $content
        $card = New-Card -Child $c -Padding (12, 10, 12, 10) -Margin (0, 0, 8, 8) -Background 'Panel'
        [void]$fg.Children.Add($card)
    }
    [void]$h.Children.Add($fg)
    # Браузеры и программы - списком, в прокрутке
    $apps = @($rs.Items | Where-Object { $_.Kind -ne 'folder' } | Sort-Object @{ Expression = { $_.Kind -ne 'browser' } }, @{ Expression = { [double]$_.Bytes }; Descending = $true })
    if ($apps.Count) {
        [void]$h.Children.Add((New-UsLabel 'Браузеры и программы' (0, 8, 0, 8)))
        $list = New-Stack
        $n = 0
        $rs.More = @()
        foreach ($it in $apps) {
            $n++
            $tx = New-Stack
            [void]$tx.Children.Add((New-Text -Text $it.Title -Size 14 -Weight 'SemiBold'))
            if ($it.Details) { [void]$tx.Children.Add((New-Text -Text $it.Details -Size 12 -Color 'Muted' -Wrap -Margin (0, 2, 0, 0))) }
            if ($it.Note) { [void]$tx.Children.Add((New-Text -Text $it.Note -Size 12 -Color $(switch ($it.NoteKind) { 'ok' { 'Ok' } 'warn' { 'Warn' } default { 'Muted' } }) -Wrap -Margin (0, 2, 0, 0))) }
            $c = & $mk $it $tx
            $dp = New-Object System.Windows.Controls.DockPanel
            $sz = New-Text -Text (Format-Size $it.Bytes) -Size 12 -Color 'Muted' -Margin (12, 0, 0, 0)
            [System.Windows.Controls.DockPanel]::SetDock($sz, 'Right')
            [void]$dp.Children.Add($sz); [void]$dp.Children.Add($c)
            $card = New-Card -Child $dp -Padding (12, 10, 12, 10) -Margin (0, 0, 0, 6) -Background 'Panel'
            if ($n -gt 6) { $card.Visibility = 'Collapsed'; $rs.More += $card }
            [void]$list.Children.Add($card)
        }
        if ($rs.More.Count) {
            $mb = New-Button -Text ('Показать остальные программы · ' + $rs.More.Count) -Kind Ghost -OnClick {
                foreach ($x in $script:RsUi.More) { $x.Visibility = 'Visible' }
                $this.Visibility = 'Collapsed'
            }
            $mb.HorizontalAlignment = 'Left'
            [void]$list.Children.Add($mb)
        }
        $sv = New-Object System.Windows.Controls.ScrollViewer
        $sv.MaxHeight = 220; $sv.VerticalScrollBarVisibility = 'Auto'
        $sv.Content = $list
        [void]$h.Children.Add($sv)
    }
    Update-RestoreTotal
}

function Update-RestoreTotal {
    $rs = $script:RsUi
    if (-not $rs -or -not $rs.Total) { return }
    $src = @($rs.Src | Where-Object { $_.IsChecked })[0]
    $dst = @($rs.Dst | Where-Object { $_.IsChecked })[0]
    $sum = 0.0
    $cacheAll = 0.0
    foreach ($c in @($rs.Checks | Where-Object { $_.IsChecked })) {
        $sum += [double]$c.Tag.Bytes
        if ($rs.Cache.IsChecked) { $sum -= [double]$c.Tag.CacheBytes }
    }
    foreach ($it in @($rs.Items | Where-Object { $_.Kind -eq 'browser' })) { $cacheAll += [double]$it.CacheBytes }
    $rs.Cache.Content.Text = 'Кэш браузеров не переносить - браузер сам скачает его заново' + $(if ($cacheAll -gt 0) { ' (' + (Format-Size $cacheAll) + ')' } else { '' })
    $same = $false
    if ($src -and $dst) {
        $sl = $src.Tag.Letter
        $same = if ($dst.Tag.Profile) { $dst.Tag.Profile.Letter -eq $sl } else { $true }
    }
    $rs.Move.Content.Children[1].Text = if ($same) { 'Мгновенно: файлы уже на этом диске, место не удваивается' } else { 'Файлы переедут на диск ' + $(if ($dst -and $dst.Tag.Profile) { $dst.Tag.Profile.Letter } else { '?' }) + ':, со старого места исчезнут' }
    $speed = if ($rs.Move.IsChecked -and $same) { 'займёт несколько секунд' } else { 'займёт какое-то время - файлы копируются' }
    $rs.Total.Text = if ($rs.Checks.Count) { 'Выбрано ' + (Format-Size $sum) + ' · ' + $speed + ' · права на файлы выдадим новой учётной записи' } else { '' }
    if ($dst -and $dst.Tag.Profile -and $dst.Tag.Profile.OnSystem -and $src) {
        $rs.Total.Text += "`nСовет: у " + $dst.Tag.Name + ' файлы на диске ' + $dst.Tag.Profile.Letter + ': - сначала защитите их (кнопка «Защитить»), тогда возврат будет мгновенным и файлы переживут следующую переустановку.'
    }
}

# ---------- Действия ----------

function Test-LastAdmin {
    param($User)
    $d = $script:UsUi.Data
    $others = @($d.Users | Where-Object { $_.IsAdmin -and $_.Enabled -and $_.Sid -ne $User.Sid })
    return ($others.Count -eq 0)
}

function Invoke-UserAction {
    param($Spec)
    $u = $Spec.U
    try {
        switch ($Spec.A) {
            'pwd' {
                $script:DlgUser = $u
                $ok = Show-FormDialog -Title ('Пароль для «' + $u.Name + '»') -OkText 'Сохранить' -Build {
                    param($f)
                    $script:DlgP1 = New-PasswordInput; $script:DlgP2 = New-PasswordInput
                    [void]$f.Children.Add((New-Field -Label 'Новый пароль (пусто = вход без пароля)' -Control $script:DlgP1))
                    [void]$f.Children.Add((New-Field -Label 'Ещё раз' -Control $script:DlgP2))
                } -OnOk {
                    if ($script:DlgP1.Password -ne $script:DlgP2.Password) { return 'Пароли не совпадают' }
                    $sec = New-Object System.Security.SecureString
                    foreach ($ch in $script:DlgP1.Password.ToCharArray()) { $sec.AppendChar($ch) }
                    Set-LocalUser -SID $script:DlgUser.Sid -Password $sec -ErrorAction Stop
                    return $true
                }
                if ($ok) { Write-Log ('Пароль изменён: ' + $u.Name) 'ok'; Add-History -Kind 'users' -Name ('Смена пароля: ' + $u.Name) }
            }
            'admin' {
                if ($u.IsAdmin) {
                    if (Test-LastAdmin $u) { Show-Info 'Это последний администратор - без него нельзя будет управлять компьютером.' -Icon 'Warning'; return }
                    Remove-LocalGroupMember -SID $script:SidAdmins -Member $u.Sid -ErrorAction Stop
                    try { Add-LocalGroupMember -SID $script:SidUsers -Member $u.Sid -ErrorAction Stop } catch {}
                    Write-Log ($u.Name + ': теперь обычный пользователь') 'ok'
                } else {
                    if (-not (Show-Confirm ('Дать «' + $u.Name + '» права администратора?'))) { return }
                    Add-LocalGroupMember -SID $script:SidAdmins -Member $u.Sid -ErrorAction Stop
                    Write-Log ($u.Name + ': теперь администратор') 'ok'
                }
                Add-History -Kind 'users' -Name ('Права изменены: ' + $u.Name)
            }
            'enable' {
                if ($u.Enabled) {
                    if ($u.IsAdmin -and (Test-LastAdmin $u)) { Show-Info 'Нельзя выключить последнего администратора.' -Icon 'Warning'; return }
                    Disable-LocalUser -SID $u.Sid -ErrorAction Stop; Write-Log ('Выключен: ' + $u.Name) 'ok'
                } else { Enable-LocalUser -SID $u.Sid -ErrorAction Stop; Write-Log ('Включён: ' + $u.Name) 'ok' }
                Add-History -Kind 'users' -Name ($(if ($u.Enabled) { 'Выключен: ' } else { 'Включён: ' }) + $u.Name)
            }
            'never' { Set-UserPasswordNeverExpires -User $u -Never (-not $u.NeverExpires); return }
            'open' { if ($u.Profile) { Open-Path $u.Profile.Path }; return }
            'protect' { Show-ProtectDialog -User $u; return }
            'unpending' {
                Unregister-ProfileMoveAtBoot -Sid $u.Sid
                Add-History -Kind 'users' -Name ('Отменён перенос при перезагрузке: ' + $u.Name)
            }
            'oldcopy' {
                $q = 'Удалить старую копию файлов ' + $u.Name + '?' + "`n`n" + $u.OldCopy + ' (' + (Get-UsSize $u.OldCopy) + ')' + "`n`n" + 'Сейчас Windows работает с ' + $u.Profile.Path + '. Удаляйте, если уже заходили под ' + $u.Name + ' и всё на месте: после удаления откатить перенос будет нельзя.'
                if (-not (Show-Confirm -Message $q -Warning)) { return }
                Start-BgTask -Name 'Удаление старой копии' -Vars @{ P = $u.OldCopy } -Script { Remove-OldProfileCopy -Path $P } -OnDone { $script:UsUi.Sizes = @{}; Update-UsersPage } | Out-Null
                return
            }
            'delete' {
                if ($u.IsAdmin -and (Test-LastAdmin $u)) { Show-Info 'Нельзя удалить последнего администратора.' -Icon 'Warning'; return }
                if (-not (Show-Confirm -Message ('Удалить учётную запись «' + $u.Name + '»?') -Warning)) { return }
                $prof = $null
                try { $prof = Get-CimInstance Win32_UserProfile -Filter ("SID='" + $u.Sid + "'") -ErrorAction Stop } catch {}
                $delProf = $false
                if ($prof) { $delProf = Show-Confirm -Message ('Удалить и папку с файлами ' + $prof.LocalPath + '?' + "`n`n" + 'Там документы, рабочий стол и загрузки этого пользователя. «Нет» - папка останется на диске.') -Warning }
                Remove-LocalUser -SID $u.Sid -ErrorAction Stop
                if ($delProf -and $prof) { try { Remove-CimInstance -InputObject $prof -ErrorAction Stop } catch { Write-Log ('Папка не удалена: ' + $_.Exception.Message) 'warn' } }
                if ($u.Pending) { Unregister-ProfileMoveAtBoot -Sid $u.Sid }
                Write-Log ('Удалён: ' + $u.Name) 'ok'
                Add-History -Kind 'users' -Name ('Удалён пользователь: ' + $u.Name)
            }
        }
    } catch { Write-Log ('Не получилось: ' + $_.Exception.Message) 'err'; Show-Info $_.Exception.Message -Icon 'Error' }
    Update-UsersPage
}

function Invoke-UserToggle {
    param([string]$Spec, [bool]$On)
    $d = $script:UsUi.Data
    try {
        switch ($Spec) {
            'guest' {
                if ($On) { Enable-LocalUser -SID $d.Builtin['501'].Sid -ErrorAction Stop } else { Disable-LocalUser -SID $d.Builtin['501'].Sid -ErrorAction Stop }
            }
            'admin500' {
                if ($On -and -not (Show-Confirm -Message 'Включить встроенного администратора? Он не защищён UAC. Сразу задайте ему пароль и выключите после ремонта.' -Warning)) { Update-UsersPage; return }
                if ($On) { Enable-LocalUser -SID $d.Builtin['500'].Sid -ErrorAction Stop } else { Disable-LocalUser -SID $d.Builtin['500'].Sid -ErrorAction Stop }
            }
            'auto' {
                if (-not $On) {
                    Set-ItemProperty -LiteralPath $script:WinlogonKey -Name 'AutoAdminLogon' -Value '0' -Type String -ErrorAction Stop
                    Remove-ItemProperty -LiteralPath $script:WinlogonKey -Name 'DefaultPassword' -ErrorAction SilentlyContinue
                    Write-Log 'Вход без пароля выключен' 'ok'
                } else {
                    $users = @($d.Users | Where-Object { $_.Enabled -and $_.Source -ne 'MicrosoftAccount' })
                    if ($users.Count -eq 0) { Show-Info 'Нет подходящих локальных учётных записей.'; Update-UsersPage; return }
                    $script:AutoUsers = $users
                    $ok = Show-FormDialog -Title 'Вход без пароля' -OkText 'Включить' -Build {
                        param($f)
                        $script:AutoRadios = @()
                        foreach ($u in $script:AutoUsers) { $r = New-Radio -Title $u.Name -Group 'auto' -Checked ($script:AutoRadios.Count -eq 0) -Tag $u.Name; [void]$f.Children.Add($r); $script:AutoRadios += $r }
                        $script:DlgP1 = New-PasswordInput
                        [void]$f.Children.Add((New-Field -Label 'Пароль этой учётки (пусто, если пароля нет)' -Control $script:DlgP1 -Margin (0, 6, 0, 8)))
                        [void]$f.Children.Add((New-Text -Text 'Пароль хранится в реестре открытым текстом - на ноутбуке, который носят с собой, это лучше не включать.' -Size 12 -Color 'Warn' -Wrap))
                    } -OnOk {
                        $sel = @($script:AutoRadios | Where-Object { $_.IsChecked })[0]
                        Set-ItemProperty -LiteralPath $script:WinlogonKey -Name 'AutoAdminLogon' -Value '1' -Type String -ErrorAction Stop
                        Set-ItemProperty -LiteralPath $script:WinlogonKey -Name 'DefaultUserName' -Value ([string]$sel.Tag) -Type String -ErrorAction Stop
                        Set-ItemProperty -LiteralPath $script:WinlogonKey -Name 'DefaultDomainName' -Value $env:COMPUTERNAME -Type String -ErrorAction Stop
                        Set-ItemProperty -LiteralPath $script:WinlogonKey -Name 'DefaultPassword' -Value $script:DlgP1.Password -Type String -ErrorAction Stop
                        return $true
                    }
                    if ($ok) { Write-Log 'Вход без пароля включён' 'ok' }
                }
            }
        }
        Add-History -Kind 'users' -Name ('Переключено: ' + $Spec + ' = ' + $On)
    } catch { Write-Log ('Не получилось: ' + $_.Exception.Message) 'err' }
    Update-UsersPage
}

function New-UserFromForm {
    $ui = $script:UsUi
    $ui.NewErr.Text = ''
    $name = ([string]$ui.NewName.Text).Trim()
    if (-not $name) { $ui.NewErr.Text = 'Введите имя'; return }
    if ($name -match '[\\/\[\]:;|=,+*?<>"@]' -or $name.Length -gt 20) { $ui.NewErr.Text = 'Имя до 20 символов, без \ / [ ] : ; | = , + * ? < > " @'; return }
    if ($ui.NewPwd.Password -and $ui.NewPwd.Password -ne $ui.NewPwd2.Password) { $ui.NewErr.Text = 'Пароли не совпадают'; return }
    $drive = Get-NewUserDrive
    try {
        if ($ui.NewPwd.Password) {
            $sec = New-Object System.Security.SecureString
            foreach ($ch in $ui.NewPwd.Password.ToCharArray()) { $sec.AppendChar($ch) }
            $u = New-LocalUser -Name $name -Password $sec -ErrorAction Stop
        } else {
            $u = New-LocalUser -Name $name -NoPassword -ErrorAction Stop
        }
        Set-LocalUser -SID $u.SID -PasswordNeverExpires ([bool]$ui.NewNever.IsChecked) -ErrorAction SilentlyContinue
        Add-LocalGroupMember -SID $script:SidUsers -Member $u.SID -ErrorAction SilentlyContinue
        if ($ui.NewAdm.IsChecked) { Add-LocalGroupMember -SID $script:SidAdmins -Member $u.SID -ErrorAction Stop }
        Write-Log ('Создан пользователь: ' + $name) 'ok'
        Add-History -Kind 'users' -Name ('Создан пользователь: ' + $name + $(if ($ui.NewAdm.IsChecked) { ' (администратор)' } else { '' }))
        $ui.NewName.Text = ''; $ui.NewPwd.Clear(); $ui.NewPwd2.Clear()
        # Файлы - сразу на выбранном диске: создаём профиль сейчас и переносим, пока он пустой.
        if ($drive -and $drive -ne ($env:SystemDrive).TrimEnd(':')) {
            Start-BgTask -Name ('Папка пользователя на ' + $drive + ':') -Vars @{ Sid = [string]$u.SID.Value; N = $name; D = $drive } -Script {
                try { [void](New-UserProfileNow -Sid $Sid -Name $N) } catch { return @{ Ok = $false; Message = $_.Exception.Message } }
                return (Move-UserProfile -Sid $Sid -Drive $D)
            } -OnDone {
                param($r)
                if ($r -and -not $r.Ok) { Write-Log ('Папка пользователя осталась на системном диске: ' + $r.Message) 'warn' }
                Update-UsersPage
            } | Out-Null
        }
    } catch { $ui.NewErr.Text = $_.Exception.Message }
    Update-UsersPage
}

function Set-UserPasswordNeverExpires {
    param($User, [bool]$Never)
    try {
        Set-LocalUser -SID $User.Sid -PasswordNeverExpires $Never -ErrorAction Stop
        Write-Log ($User.Name + ': ' + $(if ($Never) { 'пароль бессрочный' } else { 'у пароля включён срок действия' })) 'ok'
        Add-History -Kind 'users' -Name ($User.Name + ': ' + $(if ($Never) { 'пароль бессрочный' } else { 'срок действия пароля включён' }))
    } catch { Write-Log ('Не получилось: ' + $_.Exception.Message) 'err' }
    Update-UsersPage
}
