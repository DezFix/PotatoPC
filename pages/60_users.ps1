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
$script:SidGuests = 'S-1-5-32-546'
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
    $groupSid = @{}
    try { foreach ($lg in @(Get-LocalGroup -ErrorAction Stop)) { $groupSid[[string]$lg.Name] = [string]$lg.SID.Value } } catch {}
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
        $info.Description = [string]$u.Description
        $info.AccountExpires = $u.AccountExpires
        $info.MayChange = [bool]$u.UserMayChangePassword
        $info.MustChange = $false; $info.Hours = $null; $info.GroupSids = @()
        $info.NeverExpires = -not $u.PasswordExpires
        try {
            $ad = [ADSI]('WinNT://./' + $u.Name + ',user')
            try { $flags = [int]$ad.UserFlags.Value; $info.NeverExpires = (($flags -band 0x10000) -ne 0) } catch {}
            # PasswordExpired = 1: «сменить пароль при следующем входе».
            try { $info.MustChange = ([int]$ad.PasswordExpired.Value -eq 1) } catch {}
            try { $info.Hours = ConvertFrom-LoginHours ([byte[]]$ad.LoginHours.Value) } catch {}
            try {
                foreach ($gr in @($ad.Invoke('Groups'))) {
                    $gn = [string]$gr.GetType().InvokeMember('Name', 'GetProperty', $null, $gr, $null)
                    if ($groupSid[$gn]) { $info.GroupSids += $groupSid[$gn] }
                }
            } catch {}
        } catch {}
        $info.IsGuest = (-not $info.IsAdmin) -and ($info.GroupSids -contains $script:SidGuests) -and -not ($info.GroupSids -contains $script:SidUsers)
        $info.Type = if ($info.IsAdmin) { 'admin' } elseif ($info.IsGuest) { 'guest' } else { 'user' }
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

# ---------- Имя для входа, время входа ----------

function ConvertTo-UsLogin {
    # «Мария Ковалёва» -> «mariya»: первое слово латиницей, для имени входа (и папки).
    param([string]$Full)
    $w = @(([string]$Full).Trim() -split '\s+')[0]
    $map = @{ 'а' = 'a'; 'б' = 'b'; 'в' = 'v'; 'г' = 'g'; 'д' = 'd'; 'е' = 'e'; 'ё' = 'e'; 'ж' = 'zh'; 'з' = 'z'; 'и' = 'i'; 'й' = 'y'; 'к' = 'k'; 'л' = 'l'; 'м' = 'm'; 'н' = 'n'; 'о' = 'o'; 'п' = 'p'; 'р' = 'r'; 'с' = 's'; 'т' = 't'; 'у' = 'u'; 'ф' = 'f'; 'х' = 'h'; 'ц' = 'ts'; 'ч' = 'ch'; 'ш' = 'sh'; 'щ' = 'sch'; 'ъ' = ''; 'ы' = 'y'; 'ь' = ''; 'э' = 'e'; 'ю' = 'yu'; 'я' = 'ya'; 'і' = 'i'; 'ї' = 'yi'; 'є' = 'ye'; 'ґ' = 'g' }
    $sb = ''
    foreach ($ch in ([string]$w).ToLowerInvariant().ToCharArray()) {
        $k = [string]$ch
        if ($map.ContainsKey($k)) { $sb += $map[$k] } elseif ($k -match '^[a-z0-9._-]$') { $sb += $k }
    }
    if ($sb.Length -gt 20) { $sb = $sb.Substring(0, 20) }
    return $sb
}

function Test-UsLoginName {
    # Пустая строка - имя годится, иначе текст ошибки.
    param([string]$Name)
    if (-not $Name) { return 'Введите имя для входа' }
    if ($Name -match '[\\/\[\]:;|=,+*?<>"@%]' -or $Name.Length -gt 20) { return 'Имя для входа - до 20 символов, без \ / [ ] : ; | = , + * ? < > " @ %' }
    if ($Name.EndsWith('.')) { return 'Имя для входа не может кончаться точкой' }
    return ''
}

function Get-UsUtcBias {
    try { return [int][Math]::Round([TimeZoneInfo]::Local.GetUtcOffset([datetime]::Now).TotalHours) } catch { return 0 }
}

function ConvertFrom-LoginHours {
    # LoginHours: 21 байт = 168 часов недели от воскресенья 00:00 по UTC, младший бит первым.
    # Возвращает $null (ограничений нет) или @{ Days[0..6] (0 = вс); From; To; Simple; Never }.
    param([byte[]]$Bytes)
    if (-not $Bytes -or $Bytes.Count -lt 21) { return $null }
    if (@($Bytes | Where-Object { $_ -ne 255 }).Count -eq 0) { return $null }
    $bias = Get-UsUtcBias
    $days = New-Object bool[] 7
    $sets = @{}
    for ($d = 0; $d -lt 7; $d++) {
        $h = @()
        for ($x = 0; $x -lt 24; $x++) {
            $u = ((($d * 24 + $x) - $bias) % 168 + 168) % 168
            if ((($Bytes[[int][Math]::Floor($u / 8)] -shr ($u % 8)) -band 1) -eq 1) { $h += $x }
        }
        if ($h.Count) { $days[$d] = $true; $sets[($h -join ',')] = $h }
    }
    $r = @{ Days = $days; From = 8; To = 21; Simple = $false; Never = $false }
    if ($sets.Count -eq 0) { $r.Simple = $true; $r.Never = $true }
    elseif ($sets.Count -eq 1) {
        $h = @(@($sets.Values)[0])
        if (($h[-1] - $h[0] + 1) -eq $h.Count) { $r.From = $h[0]; $r.To = $h[-1] + 1; $r.Simple = $true }
    }
    return $r
}

function ConvertTo-LoginHours {
    param([bool[]]$Days, [int]$From, [int]$To)
    $bias = Get-UsUtcBias
    $b = New-Object byte[] 21
    for ($d = 0; $d -lt 7; $d++) {
        if (-not $Days[$d]) { continue }
        for ($x = $From; $x -lt $To; $x++) {
            $u = ((($d * 24 + $x) - $bias) % 168 + 168) % 168
            $i = [int][Math]::Floor($u / 8)
            $b[$i] = [byte]($b[$i] -bor (1 -shl ($u % 8)))
        }
    }
    return , $b
}

function Set-UserLoginHours {
    # $Bytes = $null - входить можно всегда.
    param([string]$Name, $Bytes)
    if ($null -eq $Bytes) { $Bytes = [byte[]](@(255) * 21) }
    $ad = [ADSI]('WinNT://./' + $Name + ',user')
    $ad.Put('LoginHours', [byte[]]$Bytes)
    $ad.SetInfo()
}

function Get-UsHoursText {
    param($H)
    if (-not $H) { return '' }
    if ($H.Never) { return 'вход запрещён в любое время' }
    if (-not $H.Simple) { return 'особое время входа' }
    $names = @('вс', 'пн', 'вт', 'ср', 'чт', 'пт', 'сб')
    $on = @(1, 2, 3, 4, 5, 6, 0 | Where-Object { $H.Days[$_] })
    $dt = if ($on.Count -eq 7) { '' } elseif (($on -join '') -eq '12345') { 'по будням ' } elseif (($on -join '') -eq '60') { 'по выходным ' } else { (@($on | ForEach-Object { $names[$_] }) -join ', ') + ' ' }
    return 'вход ' + $dt + 'с ' + $H.From + ':00 до ' + $H.To + ':00'
}

function Get-UsTypeText { param([string]$Type) switch ($Type) { 'admin' { 'Администратор' } 'guest' { 'Гость' } default { 'Обычный' } } }

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
    $ui.NewFull = New-TextInput -Placeholder 'Например, Мария Ковалёва'
    [void]$form.Children.Add((New-Field -Label 'Полное имя (ФИО)' -Control $ui.NewFull))
    $ui.NewName = New-TextInput -Placeholder 'Например, masha'
    [void]$form.Children.Add((Add-UsFieldHint (New-Field -Label 'Имя для входа' -Control $ui.NewName -Margin (0, 0, 0, 12)) 'Подставим сами из ФИО. Короткое, лучше латиницей - так будет называться папка пользователя'))
    # Имя для входа подставляется из ФИО, пока его не поменяли руками.
    $ui.NewFull.Add_TextChanged({
        $u = $script:UsUi
        if ($u.LoginTouched) { return }
        $u.LoginAuto = $true; $u.NewName.Text = ConvertTo-UsLogin $u.NewFull.Text; $u.LoginAuto = $false
    })
    $ui.NewName.Add_TextChanged({ $u = $script:UsUi; if (-not $u.LoginAuto) { $u.LoginTouched = [bool]$u.NewName.Text } })
    $ui.NewDesc = New-TextInput -Placeholder 'Например, «Дочь, учёба»'
    $ui.NewDesc.MaxLength = 48
    [void]$form.Children.Add((New-Field -Label 'Описание - необязательно' -Control $ui.NewDesc))
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
    $ui.NewNever.Margin = New-Thickness 0, 4, 0, 8
    [void]$form.Children.Add($ui.NewNever)
    $ui.NewMust = New-CheckBox -Text 'Попросить сменить пароль при первом входе'
    $ui.NewMust.Margin = New-Thickness 0, 0, 0, 12
    [void]$form.Children.Add($ui.NewMust)
    $ui.NewMust.Add_Checked({ $script:UsUi.NewNever.IsChecked = $false })
    $ui.NewNever.Add_Checked({ $script:UsUi.NewMust.IsChecked = $false })
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
        $nm = New-Text -Text $(if ($u.FullName) { $u.FullName } else { $u.Name }) -Size 15 -Weight 'SemiBold' -Color $(if ($u.Enabled) { 'Text' } else { 'Muted' })
        [void]$nameLine.Children.Add($nm)
        $badges = @()
        $badges += New-Badge (Get-UsTypeText $u.Type) $(if ($u.Type -eq 'admin') { 'accent' } else { 'muted' })
        if ($u.IsMe) { $badges += New-Badge 'это вы' 'muted' }
        if (-not $u.Enabled) { $badges += New-Badge 'выключен' 'muted' }
        if ($u.Source -eq 'MicrosoftAccount') { $badges += New-Badge 'учётка Microsoft' 'muted' }
        foreach ($b in $badges) { $b.Margin = New-Thickness 8, 0, 0, 0; [void]$nameLine.Children.Add($b) }

        # Имя для входа, описание, ограничения
        $info = @($(if ($u.FullName) { 'Вход: ' + $u.Name } else { 'Полное имя не задано' }))
        if ($u.Description) { $info += $u.Description }
        if ($d.Auto.On -and $d.Auto.User -ieq $u.Name) { $info += 'входит сам при включении' }
        if ($u.MustChange) { $info += 'сменит пароль при входе' }
        $ht = Get-UsHoursText $u.Hours
        if ($ht) { $info += $ht }
        if ($u.AccountExpires) {
            $ex = [datetime]$u.AccountExpires
            $info += $(if ($ex -lt (Get-Date)) { 'учётка истекла ' } else { 'действует до ' }) + $ex.ToString($(if ($ex.TimeOfDay.TotalMinutes -eq 0) { 'dd.MM.yyyy' } else { 'dd.MM.yyyy HH:mm' }))
        }
        if ($u.LastLogon) { $info += 'входил ' + ([datetime]$u.LastLogon).ToString('dd.MM.yyyy HH:mm') }
        $infoLine = New-Text -Text ($info -join ' · ') -Size 12 -Color 'Muted' -Margin (0, 3, 0, 0)
        $infoLine.ToolTip = $infoLine.Text

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
        $main = New-Stack -Children @($nameLine, $infoLine, $st)
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
        $right += New-Button -Text 'Настроить' -Kind Small -Tag $u -ToolTip 'Имя, тип учётной записи, пароль, время входа' -OnClick { Show-UserProps -User $this.Tag }
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
    if ($u.Source -ne 'MicrosoftAccount') { $items += @{ Text = 'Сменить пароль…'; Tag = @{ A = 'pwd'; U = $u } } }
    if (-not $u.IsMe) {
        $items += @{ Text = $(if ($u.IsAdmin) { 'Сделать обычным пользователем' } else { 'Сделать администратором' }); Tag = @{ A = 'admin'; U = $u } }
        $items += @{ Text = $(if ($u.Enabled) { 'Выключить учётную запись' } else { 'Включить учётную запись' }); Tag = @{ A = 'enable'; U = $u } }
    }
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

# ---------- Окно «Настроить пользователя» ----------

function New-UsHead { param([string]$Text) return (New-Text -Text $Text.ToUpperInvariant() -Size 12 -Weight 'Bold' -Color 'Accent' -Margin (0, 12, 0, 10)) }

function New-UsCols {
    # Элементы в равные колонки с промежутком.
    param([object[]]$Items, [double]$Gap = 12)
    $g = New-Object System.Windows.Controls.Grid
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition; $cd.Width = New-Object System.Windows.GridLength 1, 'Star'
        [void]$g.ColumnDefinitions.Add($cd)
        $it = $Items[$i]
        $it.Margin = New-Thickness $(if ($i) { $Gap / 2 } else { 0 }), 0, $(if ($i -lt $Items.Count - 1) { $Gap / 2 } else { 0 }), 0
        [System.Windows.Controls.Grid]::SetColumn($it, $i)
        [void]$g.Children.Add($it)
    }
    return $g
}

function New-UsToggleLine {
    param([string]$Title, [string]$Sub, $Toggle)
    $dp = New-Object System.Windows.Controls.DockPanel
    $dp.Margin = New-Thickness 0, 0, 0, 12
    $Toggle.VerticalAlignment = 'Center'; $Toggle.Margin = New-Thickness 12, 0, 0, 0
    [System.Windows.Controls.DockPanel]::SetDock($Toggle, 'Right')
    [void]$dp.Children.Add($Toggle)
    $tb = New-Stack -Children @((New-Text -Text $Title -Size 14 -Weight 'SemiBold'), (New-Text -Text $Sub -Size 12 -Color 'Muted' -Wrap -Margin (0, 2, 0, 0)))
    [void]$dp.Children.Add($tb)
    return $dp
}

function Add-UsFieldHint { param($Field, [string]$Text) [void]$Field.Children.Add((New-Text -Text $Text -Size 11 -Color 'Muted' -Wrap -Margin (0, 5, 0, 0))); return $Field }

# ---------- Выпадающие календарь и часы (в стиле приложения) ----------

$script:UsMonths = @('Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь')

function New-UsPickField {
    # Поле-кнопка «значение ⌄»: по клику выпадает выбор.
    param([double]$Width, [scriptblock]$OnClick)
    $b = New-Object System.Windows.Controls.Button
    $b.Style = $script:Window.FindResource('BtnSecondary')
    $b.Background = Get-Brush 'Panel'; $b.Width = $Width; $b.Padding = New-Thickness 12, 0, 10, 0
    $b.HorizontalContentAlignment = 'Stretch'; $b.FontWeight = 'Normal'
    $dp = New-Object System.Windows.Controls.DockPanel
    $ch = New-Text -Text '⌄' -Size 14 -Color 'Muted' -Margin (6, -6, 0, 0)
    [System.Windows.Controls.DockPanel]::SetDock($ch, 'Right')
    [void]$dp.Children.Add($ch)
    $t = New-Text -Text '' -Size 14
    [void]$dp.Children.Add($t)
    $b.Content = $dp; $b.Tag = $t
    $b.Add_Click($OnClick)
    return $b
}

function New-UsPopup {
    param($Anchor, $Child)
    $pp = New-Object System.Windows.Controls.Primitives.Popup
    $pp.PlacementTarget = $Anchor; $pp.Placement = 'Bottom'; $pp.VerticalOffset = 6
    $pp.StaysOpen = $false; $pp.AllowsTransparency = $true; $pp.PopupAnimation = 'Fade'
    $card = New-Card -Child $Child -Padding (12, 10, 12, 12) -Margin (0, 0, 12, 12) -Background 'Panel'
    $sh = New-Object System.Windows.Media.Effects.DropShadowEffect
    $sh.BlurRadius = 18; $sh.ShadowDepth = 4; $sh.Opacity = 0.5; $sh.Color = [System.Windows.Media.Colors]::Black
    $card.Effect = $sh
    $pp.Child = $card
    $pp.IsOpen = $true
    return $pp
}

function New-UsCell {
    # Ячейка календаря / часов: прозрачная, выбранная - акцентом.
    param([string]$Text, $Tag, [bool]$Selected, [scriptblock]$OnClick, [double]$W = 38, [double]$H = 34)
    $b = New-Button -Text $Text -Kind Ghost -Tag $Tag -OnClick $OnClick
    $b.Width = $W; $b.Height = $H; $b.MinHeight = 0; $b.Padding = New-Thickness 0; $b.Margin = New-Thickness 1
    $b.FontWeight = 'Normal'; $b.Foreground = Get-Brush 'Text'
    if ($Selected) { $b.Background = Get-Brush 'Accent'; $b.Foreground = Get-Brush 'OnAccent'; $b.FontWeight = 'Bold' }
    return $b
}

function Update-UsExpFields {
    $up = $script:UpUi
    $wd = @('вс', 'пн', 'вт', 'ср', 'чт', 'пт', 'сб')
    $d = [datetime]$up.ExpDay
    $up.ExpDate.Tag.Text = $d.ToString('dd.MM.yyyy') + ', ' + $wd[[int]$d.DayOfWeek]
    $up.ExpTime.Tag.Text = '{0:00}:{1:00}' -f [Math]::Floor($up.ExpMin / 60), ($up.ExpMin % 60)
}

function Show-UsCalendar {
    param($Anchor)
    $up = $script:UpUi
    $d = [datetime]$up.ExpDay
    $c = @{ Month = (New-Object datetime $d.Year, $d.Month, 1); Popup = $null }
    $root = New-Stack
    $head = New-Object System.Windows.Controls.DockPanel
    $head.Margin = New-Thickness 0, 0, 0, 6
    $c.Prev = New-Button -Text '‹' -Kind Ghost -OnClick { $k = $script:UsCal; $k.Month = $k.Month.AddMonths(-1); Update-UsCalendar }
    $c.Next = New-Button -Text '›' -Kind Ghost -OnClick { $k = $script:UsCal; $k.Month = $k.Month.AddMonths(1); Update-UsCalendar }
    foreach ($x in @($c.Prev, $c.Next)) { $x.FontSize = 20; $x.Foreground = Get-Brush 'Text'; $x.Width = 36; $x.Padding = New-Thickness 0 }
    [System.Windows.Controls.DockPanel]::SetDock($c.Prev, 'Left'); [System.Windows.Controls.DockPanel]::SetDock($c.Next, 'Right')
    $c.Title = New-Text -Text '' -Size 15 -Weight 'Bold'
    $c.Title.HorizontalAlignment = 'Center'
    [void]$head.Children.Add($c.Prev); [void]$head.Children.Add($c.Next); [void]$head.Children.Add($c.Title)
    [void]$root.Children.Add($head)
    $wg = New-Object System.Windows.Controls.Primitives.UniformGrid
    $wg.Columns = 7
    foreach ($n in @('Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс')) { $t = New-Text -Text $n -Size 12 -Color 'Muted' -Margin (0, 0, 0, 4); $t.HorizontalAlignment = 'Center'; [void]$wg.Children.Add($t) }
    [void]$root.Children.Add($wg)
    $c.Grid = New-Object System.Windows.Controls.Primitives.UniformGrid
    $c.Grid.Columns = 7
    [void]$root.Children.Add($c.Grid)
    # Быстрый выбор
    $q = New-Object System.Windows.Controls.WrapPanel
    $q.Margin = New-Thickness 0, 8, 0, 0
    $today = (Get-Date).Date
    foreach ($o in @(@('Завтра', $today.AddDays(1)), @('Через неделю', $today.AddDays(7)), @('Через месяц', $today.AddMonths(1)))) {
        $b = New-Button -Text $o[0] -Kind Chip -Tag $o[1] -OnClick { Set-UsExpDay $this.Tag }
        $b.Margin = New-Thickness 0, 0, 6, 0
        [void]$q.Children.Add($b)
    }
    [void]$root.Children.Add($q)
    $script:UsCal = $c
    Update-UsCalendar
    $c.Popup = New-UsPopup -Anchor $Anchor -Child $root
}

function Update-UsCalendar {
    $c = $script:UsCal
    $up = $script:UpUi
    $m = $c.Month
    $today = (Get-Date).Date
    $c.Title.Text = $script:UsMonths[$m.Month - 1] + ' ' + $m.Year
    $c.Prev.IsEnabled = ($m -gt (New-Object datetime $today.Year, $today.Month, 1))
    $c.Grid.Children.Clear()
    $sel = ([datetime]$up.ExpDay).Date
    $start = $m.AddDays(-(([int]$m.DayOfWeek + 6) % 7))
    for ($i = 0; $i -lt 42; $i++) {
        $d = $start.AddDays($i)
        $b = New-UsCell -Text ([string]$d.Day) -Tag $d -Selected ($d -eq $sel) -OnClick { Set-UsExpDay $this.Tag }
        if ($d -ne $sel -and $d -eq $today) { $b.BorderBrush = Get-Brush 'Accent'; $b.BorderThickness = New-Thickness 1 }
        if ($d.Month -ne $m.Month -and $d -ne $sel) { $b.Foreground = Get-Brush 'Muted' }
        if ($d -lt $today) { $b.IsEnabled = $false; $b.Opacity = 0.3 }
        [void]$c.Grid.Children.Add($b)
    }
}

function Set-UsExpDay {
    param($Day)
    $up = $script:UpUi
    $up.ExpDay = ([datetime]$Day).Date
    Update-UsExpFields
    if ($script:UsCal -and $script:UsCal.Popup) { $script:UsCal.Popup.IsOpen = $false }
}

function Show-UsTimePicker {
    param($Anchor)
    $root = New-Stack
    $t = @{ Popup = $null }
    [void]$root.Children.Add((New-Text -Text 'Часы' -Size 12 -Color 'Muted' -Margin (2, 0, 0, 4)))
    $t.H = New-Object System.Windows.Controls.Primitives.UniformGrid
    $t.H.Columns = 6
    [void]$root.Children.Add($t.H)
    [void]$root.Children.Add((New-Text -Text 'Минуты' -Size 12 -Color 'Muted' -Margin (2, 10, 0, 4)))
    $t.M = New-Object System.Windows.Controls.Primitives.UniformGrid
    $t.M.Columns = 4
    [void]$root.Children.Add($t.M)
    $script:UsTime = $t
    Update-UsTimePicker
    $t.Popup = New-UsPopup -Anchor $Anchor -Child $root
}

function Update-UsTimePicker {
    $t = $script:UsTime
    $up = $script:UpUi
    $h = [int][Math]::Floor($up.ExpMin / 60); $mi = $up.ExpMin % 60
    $t.H.Children.Clear()
    for ($i = 0; $i -lt 24; $i++) {
        [void]$t.H.Children.Add((New-UsCell -Text ('{0:00}' -f $i) -Tag $i -Selected ($i -eq $h) -W 44 -OnClick {
            $p = $script:UpUi; $p.ExpMin = [int]$this.Tag * 60 + ($p.ExpMin % 60); Update-UsExpFields; Update-UsTimePicker
        }))
    }
    $t.M.Children.Clear()
    foreach ($x in @(0, 15, 30, 45)) {
        [void]$t.M.Children.Add((New-UsCell -Text (':{0:00}' -f $x) -Tag $x -Selected ($x -eq $mi) -W 66 -OnClick {
            $p = $script:UpUi; $p.ExpMin = [int][Math]::Floor($p.ExpMin / 60) * 60 + [int]$this.Tag; Update-UsExpFields
            $script:UsTime.Popup.IsOpen = $false
        }))
    }
}

function Show-UserProps {
    param($User)
    $u = $User
    $script:UpUi = @{ User = $u; After = ''; DayBtns = @(); GroupChecks = @(); HoursDirty = $false; Changes = @() }
    $title = if ($u.FullName) { $u.FullName } else { $u.Name }
    $ok = Show-FormDialog -Title $title -OkText 'Сохранить' -Width 700 -Build {
        param($f)
        $up = $script:UpUi
        $u = $up.User
        $ms = ($u.Source -eq 'MicrosoftAccount')
        $last = if ($u.LastLogon) { 'последний вход ' + ([datetime]$u.LastLogon).ToString('dd.MM.yyyy HH:mm') } else { 'ещё не входил' }
        [void]$f.Children.Add((New-Text -Text ('Вход: ' + $u.Name + ' · ' + (Get-UsTypeText $u.Type) + ' · ' + $last) -Size 12 -Color 'Muted'))

        # --- Имя ---
        [void]$f.Children.Add((New-UsHead 'Имя'))
        $up.Full = New-TextInput -Text $u.FullName -Placeholder 'Например, Мария Ковалёва'
        $up.Login = New-TextInput -Text $u.Name
        $ff = Add-UsFieldHint (New-Field -Label 'Полное имя (ФИО)' -Control $up.Full -Margin (0, 0, 0, 0)) 'Так видно на экране входа и в «Пуске»'
        $lf = Add-UsFieldHint (New-Field -Label 'Имя для входа' -Control $up.Login -Margin (0, 0, 0, 0)) $(if ($u.Profile) { 'Папка ' + $u.Profile.Path + ' не переименуется' } else { 'Короткое, лучше латиницей' })
        if ($ms) { $up.Login.IsEnabled = $false; $lf.ToolTip = 'У учётной записи Microsoft имя для входа - адрес почты' }
        $cols = New-UsCols @($ff, $lf)
        $cols.Margin = New-Thickness 0, 0, 0, 12
        [void]$f.Children.Add($cols)
        $up.Desc = New-TextInput -Text $u.Description -Placeholder 'Например, «Дочь, учёба» - видно только здесь'
        $up.Desc.MaxLength = 48
        [void]$f.Children.Add((New-Field -Label 'Описание' -Control $up.Desc))

        # --- Тип ---
        [void]$f.Children.Add((New-UsHead 'Тип учётной записи'))
        $tg = New-Object System.Windows.Controls.Primitives.UniformGrid
        $tg.Columns = 3
        $up.TUser = New-UsRadio -Title 'Обычный' -Sub 'Программы, интернет, игры. Систему не меняет' -Group 'uptype' -Checked ($u.Type -eq 'user')
        $up.TAdm = New-UsRadio -Title 'Администратор' -Sub 'Ещё ставит программы и меняет настройки Windows' -Group 'uptype' -Checked ($u.Type -eq 'admin')
        $up.TGuest = New-UsRadio -Title 'Гость' -Sub 'Самый урезанный доступ - для чужих' -Group 'uptype' -Checked ($u.Type -eq 'guest')
        $up.TUser.Margin = New-Thickness 0, 0, 4, 0; $up.TAdm.Margin = New-Thickness 4, 0, 4, 0; $up.TGuest.Margin = New-Thickness 4, 0, 0, 0
        foreach ($r in @($up.TUser, $up.TAdm, $up.TGuest)) { [void]$tg.Children.Add($r) }
        if ($u.IsMe) {
            foreach ($r in @($up.TUser, $up.TAdm, $up.TGuest)) { $r.IsEnabled = $false }
            $tg.ToolTip = 'Свой тип менять нельзя - можно остаться без прав администратора'
        }
        [void]$f.Children.Add($tg)
        # Остальные группы Windows - свёрнуты.
        $groups = @()
        try { $groups = @(Get-LocalGroup -ErrorAction Stop | Where-Object { @($script:SidAdmins, $script:SidUsers, $script:SidGuests) -notcontains [string]$_.SID.Value } | Sort-Object Name) } catch {}
        if ($groups.Count) {
            $in = @($groups | Where-Object { $u.GroupSids -contains [string]$_.SID.Value }).Count
            $up.GroupsBox = New-Stack -Margin (0, 6, 0, 0)
            $up.GroupsBox.Visibility = 'Collapsed'
            foreach ($gr in $groups) {
                $c = New-CheckBox -Text ([string]$gr.Name) -Checked ($u.GroupSids -contains [string]$gr.SID.Value) -Tag ([string]$gr.SID.Value) -ToolTip ([string]$gr.Description)
                $c.Margin = New-Thickness 0, 0, 0, 6
                $up.GroupChecks += $c
                [void]$up.GroupsBox.Children.Add($c)
            }
            $gb = New-Button -Text ('Другие группы Windows · состоит в ' + $in + ' из ' + $groups.Count) -Kind Ghost -OnClick {
                $b = $script:UpUi.GroupsBox
                $b.Visibility = if ($b.Visibility -eq 'Visible') { 'Collapsed' } else { 'Visible' }
            }
            $gb.HorizontalAlignment = 'Left'; $gb.Margin = New-Thickness -8, 4, 0, 0
            [void]$f.Children.Add($gb)
            [void]$f.Children.Add($up.GroupsBox)
        }

        # --- Пароль ---
        [void]$f.Children.Add((New-UsHead 'Пароль'))
        if ($ms) {
            [void]$f.Children.Add((New-Hint -Text 'Пароль учётной записи Microsoft меняется на account.microsoft.com' -Kind 'info' -Margin (0, 0, 0, 4)))
        } else {
            $up.P1 = New-PasswordInput; $up.P2 = New-PasswordInput
            $cols = New-UsCols @((New-Field -Label 'Новый пароль - пусто, чтобы не менять' -Control $up.P1 -Margin (0, 0, 0, 0)), (New-Field -Label 'Ещё раз' -Control $up.P2 -Margin (0, 0, 0, 0)))
            $cols.Margin = New-Thickness 0, 0, 0, 10
            [void]$f.Children.Add($cols)
            $up.NoPwd = New-CheckBox -Text 'Убрать пароль - входить без него'
            $up.Never = New-CheckBox -Text 'Не заставлять менять пароль (иначе Windows попросит через 42 дня)' -Checked ([bool]$u.NeverExpires)
            $up.Must = New-CheckBox -Text 'Попросить сменить пароль при следующем входе' -Checked ([bool]$u.MustChange)
            $up.NoChange = New-CheckBox -Text 'Запретить самому менять пароль - меняет только администратор' -Checked (-not $u.MayChange)
            # «Сменить при входе» не сочетается с двумя другими - как в «Управлении компьютером».
            $up.Must.Add_Checked({ $p = $script:UpUi; $p.Never.IsChecked = $false; $p.NoChange.IsChecked = $false })
            $up.Never.Add_Checked({ $script:UpUi.Must.IsChecked = $false })
            $up.NoChange.Add_Checked({ $script:UpUi.Must.IsChecked = $false })
            $up.NoPwd.Add_Checked({ $p = $script:UpUi; $p.P1.Clear(); $p.P2.Clear(); $p.P1.IsEnabled = $false; $p.P2.IsEnabled = $false })
            $up.NoPwd.Add_Unchecked({ $p = $script:UpUi; $p.P1.IsEnabled = $true; $p.P2.IsEnabled = $true })
            foreach ($c in @($up.NoPwd, $up.Never, $up.Must, $up.NoChange)) { $c.Margin = New-Thickness 0, 0, 0, 8; [void]$f.Children.Add($c) }
        }

        # --- Вход ---
        [void]$f.Children.Add((New-UsHead 'Вход'))
        if (-not $u.IsMe) {
            $up.Enabled = New-Toggle -Checked ([bool]$u.Enabled)
            [void]$f.Children.Add((New-UsToggleLine -Title 'Учётная запись включена' -Sub 'Выключенная не видна на экране входа, файлы остаются' -Toggle $up.Enabled))
        }
        $up.ExpOn = New-Toggle -Checked ([bool]$u.AccountExpires)
        [void]$f.Children.Add((New-UsToggleLine -Title 'Действует до даты и времени' -Sub 'Например, дали компьютер до 15 числа - с 8:00 войти уже не получится' -Toggle $up.ExpOn))
        $ed = if ($u.AccountExpires) { [datetime]$u.AccountExpires } else { (Get-Date).Date.AddDays(7).AddHours(8) }
        $up.ExpDay = $ed.Date; $up.ExpMin = [int]$ed.TimeOfDay.TotalMinutes
        $up.ExpDate = New-UsPickField -Width 150 -OnClick { Show-UsCalendar -Anchor $this }
        $up.ExpTime = New-UsPickField -Width 100 -OnClick { Show-UsTimePicker -Anchor $this }
        Update-UsExpFields
        $up.ExpRow = New-Stack -Margin (0, -4, 0, 14)
        [void]$up.ExpRow.Children.Add((New-Stack -Orientation Horizontal -Children @((New-Text -Text 'Заблокировать' -Size 13 -Color 'Muted' -Margin (0, 0, 10, 0)), $up.ExpDate, (New-Text -Text 'в' -Size 13 -Color 'Muted' -Margin (10, 0, 10, 0)), $up.ExpTime)))
        [void]$up.ExpRow.Children.Add((New-Text -Text 'Кто в этот момент уже сидит за компьютером, продолжит работать до выхода - Windows не пустит только новый вход.' -Size 11 -Color 'Muted' -Wrap -Margin (0, 6, 0, 0)))
        $up.ExpRow.Visibility = if ($u.AccountExpires) { 'Visible' } else { 'Collapsed' }
        $up.ExpOn.Add_Click({ $p = $script:UpUi; $p.ExpRow.Visibility = if ($p.ExpOn.IsChecked) { 'Visible' } else { 'Collapsed' } })
        [void]$f.Children.Add($up.ExpRow)

        $h = $u.Hours
        $up.Days = New-Object bool[] 7
        if ($h) { for ($i = 0; $i -lt 7; $i++) { $up.Days[$i] = [bool]$h.Days[$i] } } else { for ($i = 0; $i -lt 7; $i++) { $up.Days[$i] = $true } }
        $up.HoursOn = New-Toggle -Checked ([bool]$h)
        [void]$f.Children.Add((New-UsToggleLine -Title 'Когда можно входить' -Sub 'Например, ребёнку - только днём. В остальное время Windows не пустит' -Toggle $up.HoursOn))
        $up.HoursBox = New-Stack -Margin (0, -4, 0, 10)
        $up.HoursBox.Visibility = if ($h) { 'Visible' } else { 'Collapsed' }
        $row = New-Stack -Orientation Horizontal
        $dn = @('Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб')
        foreach ($i in @(1, 2, 3, 4, 5, 6, 0)) {
            $b = New-Button -Text $dn[$i] -Kind Chip -Tag $i -OnClick {
                $p = $script:UpUi; $k = [int]$this.Tag
                $p.Days[$k] = -not $p.Days[$k]
                Set-ChipActive $this $p.Days[$k]
                $p.HoursDirty = $true
            }
            $b.Margin = New-Thickness 0, 0, 6, 0; $b.MinWidth = 40
            Set-ChipActive $b $up.Days[$i]
            [void]$row.Children.Add($b)
        }
        $up.HFrom = New-TextInput -Width 70 -Text $(if ($h) { '{0:00}' -f $h.From } else { '08' })
        $up.HTo = New-TextInput -Width 70 -Text $(if ($h) { '{0:00}' -f $h.To } else { '21' })
        $up.HFrom.Add_TextChanged({ $script:UpUi.HoursDirty = $true }); $up.HTo.Add_TextChanged({ $script:UpUi.HoursDirty = $true })
        [void]$row.Children.Add((New-Text -Text 'с' -Size 13 -Color 'Muted' -Margin (10, 0, 8, 0)))
        [void]$row.Children.Add($up.HFrom)
        [void]$row.Children.Add((New-Text -Text 'до' -Size 13 -Color 'Muted' -Margin (8, 0, 8, 0)))
        [void]$row.Children.Add($up.HTo)
        [void]$row.Children.Add((New-Text -Text 'часов' -Size 13 -Color 'Muted' -Margin (8, 0, 0, 0)))
        [void]$up.HoursBox.Children.Add($row)
        if ($h -and -not $h.Simple) { [void]$up.HoursBox.Children.Add((New-Hint -Text 'Сейчас задано сложное расписание (настроено не здесь). Если поменять дни или часы, оно заменится этим.' -Kind 'warn' -Margin (0, 8, 0, 0))) }
        $up.HoursOn.Add_Click({ $p = $script:UpUi; $p.HoursDirty = $true; $p.HoursBox.Visibility = if ($p.HoursOn.IsChecked) { 'Visible' } else { 'Collapsed' } })
        [void]$f.Children.Add($up.HoursBox)

        # --- Файлы ---
        [void]$f.Children.Add((New-UsHead 'Файлы'))
        $p = $u.Profile
        $ftxt = if ($u.Pending) { 'Перенос на другой диск пройдёт при следующей перезагрузке' } elseif (-not $p) { 'Ещё не входил - файлов пока нет' } else { $p.Path + ' · ' + (Get-UsSize $p.Path) }
        $fsub = if (-not $p -or $u.Pending) { '' } elseif ($p.OnSystem) { 'Сотрутся при переустановке Windows' } else { 'Переживут переустановку Windows' }
        $fr = @()
        if ($p) { $fr += New-Button -Text 'Открыть' -Kind Small -OnClick { $script:UpUi.After = 'open'; $script:DlgState.Window.Close() } }
        if ((Test-UsHasTargetDrive) -and -not $u.Pending -and (-not $p -or $p.OnSystem)) {
            $pb = New-Button -Text 'Защитить' -Kind Small -OnClick { $script:UpUi.After = 'protect'; $script:DlgState.Window.Close() }
            $pb.Foreground = Get-Brush 'Accent'; $pb.BorderBrush = Get-Brush '#5A4521'; $pb.Background = Get-Brush '#241F14'
            $fr += $pb
        }
        $fm = New-TitleBlock -Title $ftxt -Sub $fsub -SubColor $(if ($p -and $p.OnSystem) { 'Warn' } else { 'Ok' })
        $frow = New-Row -Main $fm -Right $fr -Padding (14, 10, 10, 10)
        $frow.BorderThickness = New-Thickness 1; $frow.CornerRadius = New-Object System.Windows.CornerRadius 10; $frow.Background = Get-Brush 'Card'
        [void]$f.Children.Add($frow)

        if (-not $u.IsMe) {
            $del = New-Button -Text 'Удалить пользователя…' -Kind SmallDanger -OnClick { $script:UpUi.After = 'delete'; $script:DlgState.Window.Close() }
            $del.HorizontalAlignment = 'Left'; $del.Margin = New-Thickness 0, 18, 0, 4
            [void]$f.Children.Add($del)
        }
    } -OnOk {
        return (Save-UserProps)
    }
    $up = $script:UpUi
    if ($up.Changes.Count) {
        $nm = if ($up.NewName) { $up.NewName } else { $u.Name }
        Write-Log ('Пользователь ' + $nm + ': ' + ($up.Changes -join ', ')) 'ok'
        Add-History -Kind 'users' -Name ('Изменён пользователь ' + $nm + ': ' + ($up.Changes -join ', '))
    }
    switch ($up.After) {
        'open' { if ($u.Profile) { Open-Path $u.Profile.Path } }
        'protect' { Show-ProtectDialog -User $u; return }
        'delete' { Invoke-UserAction -Spec @{ A = 'delete'; U = $u }; return }
    }
    if ($ok -or $up.Changes.Count) { Update-UsersPage }
}

function Save-UserProps {
    # Проверяем всё, потом применяем. Возвращает $true или текст ошибки для окна.
    $up = $script:UpUi
    $u = $up.User
    $sid = $u.Sid
    $full = ([string]$up.Full.Text).Trim()
    $login = ([string]$up.Login.Text).Trim()
    $desc = ([string]$up.Desc.Text).Trim()
    if ($login -ne $u.Name) {
        $e = Test-UsLoginName $login
        if ($e) { return $e }
        if (@($script:UsUi.Data.Users | Where-Object { $_.Name -ieq $login -and $_.Sid -ne $sid }).Count) { return ('Имя «' + $login + '» уже занято') }
    }
    $pwd = $null
    if ($up.P1) {
        if ($up.NoPwd.IsChecked) { $pwd = '' }
        elseif ($up.P1.Password) {
            if ($up.P1.Password -ne $up.P2.Password) { return 'Пароли не совпадают' }
            $pwd = $up.P1.Password
        }
    }
    $exp = $null
    if ($up.ExpOn.IsChecked) {
        # Ровно с этого момента учётка не действует.
        $exp = ([datetime]$up.ExpDay).Date.AddMinutes($up.ExpMin)
        if ($exp -le (Get-Date) -and -not ($u.AccountExpires -and ([datetime]$u.AccountExpires) -eq $exp)) { return 'Это время уже прошло' }
    }
    $hours = 'keep'
    if ($up.HoursDirty) {
        if ($up.HoursOn.IsChecked) {
            $a = 0; $b = 0
            if (-not [int]::TryParse(([string]$up.HFrom.Text).Trim(), [ref]$a) -or -not [int]::TryParse(([string]$up.HTo.Text).Trim(), [ref]$b) -or $a -lt 0 -or $b -gt 24 -or $a -ge $b) { return 'Часы входа - целые числа от 0 до 24, «с» меньше «до»' }
            if (-not ($up.Days -contains $true)) { return 'Отметьте хотя бы один день, когда можно входить' }
            $hours = ConvertTo-LoginHours -Days $up.Days -From $a -To $b
        } else { $hours = $null }
    }
    $type = if ($up.TAdm.IsChecked) { 'admin' } elseif ($up.TGuest.IsChecked) { 'guest' } else { 'user' }
    $enable = if ($up.Enabled) { [bool]$up.Enabled.IsChecked } else { [bool]$u.Enabled }
    if (($type -ne 'admin' -or -not $enable) -and $u.IsAdmin -and (Test-LastAdmin $u)) { return 'Это последний администратор - без него нельзя будет управлять компьютером' }

    $ch = $up.Changes
    try {
        $ad = [ADSI]('WinNT://./' + $u.Name + ',user')
        if ($full -cne [string]$u.FullName -or $desc -cne [string]$u.Description) {
            $ad.Put('FullName', $full); $ad.Put('Description', $desc); $ad.SetInfo()
            $ch += 'имя и описание'
        }
        if ($type -ne $u.Type) { Set-UserType -User $u -Type $type; $ch += ('тип: ' + (Get-UsTypeText $type)) }
        foreach ($c in $up.GroupChecks) {
            $g = [string]$c.Tag; $was = ($u.GroupSids -contains $g)
            if ($c.IsChecked -and -not $was) { Add-LocalGroupMember -SID $g -Member $sid -ErrorAction Stop; $ch += ('группа +' + [string]$c.Content.Text) }
            elseif (-not $c.IsChecked -and $was) { Remove-LocalGroupMember -SID $g -Member $sid -ErrorAction Stop; $ch += ('группа -' + [string]$c.Content.Text) }
        }
        if ($null -ne $pwd) {
            $sec = New-Object System.Security.SecureString
            foreach ($x in $pwd.ToCharArray()) { $sec.AppendChar($x) }
            Set-LocalUser -SID $sid -Password $sec -ErrorAction Stop
            $ch += $(if ($pwd) { 'новый пароль' } else { 'пароль убран' })
        }
        if ($up.Never) {
            if ([bool]$up.Never.IsChecked -ne [bool]$u.NeverExpires) { Set-LocalUser -SID $sid -PasswordNeverExpires ([bool]$up.Never.IsChecked) -ErrorAction Stop; $ch += $(if ($up.Never.IsChecked) { 'пароль бессрочный' } else { 'у пароля есть срок' }) }
            if ([bool]$up.NoChange.IsChecked -eq [bool]$u.MayChange) { Set-LocalUser -SID $sid -UserMayChangePassword (-not $up.NoChange.IsChecked) -ErrorAction Stop; $ch += $(if ($up.NoChange.IsChecked) { 'сам пароль не меняет' } else { 'сам меняет пароль' }) }
            # После смены пароля Windows сбрасывает «сменить при входе» - ставим заново.
            if ([bool]$up.Must.IsChecked -ne [bool]$u.MustChange -or ($up.Must.IsChecked -and $null -ne $pwd)) {
                $ad2 = [ADSI]('WinNT://./' + $u.Name + ',user')
                $ad2.Put('PasswordExpired', $(if ($up.Must.IsChecked) { 1 } else { 0 })); $ad2.SetInfo()
                $ch += $(if ($up.Must.IsChecked) { 'сменит пароль при входе' } else { 'без смены пароля при входе' })
            }
        }
        if ($enable -ne [bool]$u.Enabled) {
            if ($enable) { Enable-LocalUser -SID $sid -ErrorAction Stop; $ch += 'включён' } else { Disable-LocalUser -SID $sid -ErrorAction Stop; $ch += 'выключен' }
        }
        $oldExp = if ($u.AccountExpires) { [datetime]$u.AccountExpires } else { $null }
        if ($exp -and (-not $oldExp -or $oldExp -ne $exp)) { Set-LocalUser -SID $sid -AccountExpires $exp -ErrorAction Stop; $ch += ('действует до ' + $exp.ToString('dd.MM.yyyy HH:mm')) }
        elseif (-not $exp -and $oldExp) { Set-LocalUser -SID $sid -AccountNeverExpires -ErrorAction Stop; $ch += 'действует всегда' }
        if ($hours -isnot [string]) {
            Set-UserLoginHours -Name $u.Name -Bytes $hours
            $ch += $(if ($null -eq $hours) { 'входить можно всегда' } else { 'время входа' })
        }
        # Переименование - последним: всё выше находит учётку по старому имени.
        if ($login -cne $u.Name) {
            Rename-LocalUser -SID $sid -NewName $login -ErrorAction Stop
            $up.NewName = $login
            $ch += ('имя для входа: ' + $login)
            try {
                $wl = Get-ItemProperty -LiteralPath $script:WinlogonKey -ErrorAction Stop
                if ([string]$wl.DefaultUserName -ieq $u.Name) { Set-ItemProperty -LiteralPath $script:WinlogonKey -Name 'DefaultUserName' -Value $login -Type String -ErrorAction Stop }
            } catch {}
        }
    } catch {
        $up.Changes = $ch
        $done = if ($ch.Count) { "`nУже сохранено: " + ($ch -join ', ') } else { '' }
        return ('Не получилось: ' + $_.Exception.Message + $done)
    }
    $up.Changes = $ch
    return $true
}

function Set-UserType {
    # admin | user | guest - через группы, найденные по SID.
    param($User, [string]$Type)
    $u = $User
    $in = @{}
    foreach ($g in $u.GroupSids) { $in[$g] = $true }
    if ($u.IsAdmin) { $in[$script:SidAdmins] = $true }
    $want = switch ($Type) {
        'admin' { @{ $script:SidAdmins = $true; $script:SidUsers = $true; $script:SidGuests = $false } }
        'guest' { @{ $script:SidAdmins = $false; $script:SidUsers = $false; $script:SidGuests = $true } }
        default { @{ $script:SidAdmins = $false; $script:SidUsers = $true; $script:SidGuests = $false } }
    }
    # Сначала добавляем, потом убираем: на полпути учётка не останется без групп.
    foreach ($g in @($script:SidAdmins, $script:SidUsers, $script:SidGuests)) {
        if ($want[$g] -and -not $in[$g]) {
            try { Add-LocalGroupMember -SID $g -Member $u.Sid -ErrorAction Stop } catch { if ($_.FullyQualifiedErrorId -notlike 'MemberExists*') { throw } }
        }
    }
    foreach ($g in @($script:SidGuests, $script:SidUsers, $script:SidAdmins)) {
        if (-not $want[$g] -and $in[$g]) { Remove-LocalGroupMember -SID $g -Member $u.Sid -ErrorAction Stop }
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
                    Set-UserType -User $u -Type 'user'
                    Write-Log ($u.Name + ': теперь обычный пользователь') 'ok'
                } else {
                    if (-not (Show-Confirm ('Дать «' + $u.Name + '» права администратора?'))) { return }
                    Set-UserType -User $u -Type 'admin'
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
    $full = ([string]$ui.NewFull.Text).Trim()
    $desc = ([string]$ui.NewDesc.Text).Trim()
    $name = ([string]$ui.NewName.Text).Trim()
    if (-not $name -and $full) { $name = ConvertTo-UsLogin $full }
    if (-not $name -and -not $full) { $ui.NewErr.Text = 'Введите имя'; return }
    $e = Test-UsLoginName $name
    if ($e) { $ui.NewErr.Text = $e; return }
    if ($ui.NewPwd.Password -and $ui.NewPwd.Password -ne $ui.NewPwd2.Password) { $ui.NewErr.Text = 'Пароли не совпадают'; return }
    $drive = Get-NewUserDrive
    try {
        $np = @{ Name = $name; ErrorAction = 'Stop' }
        if ($full) { $np.FullName = $full }
        if ($desc) { $np.Description = $desc }
        if ($ui.NewPwd.Password) {
            $sec = New-Object System.Security.SecureString
            foreach ($ch in $ui.NewPwd.Password.ToCharArray()) { $sec.AppendChar($ch) }
            $np.Password = $sec
        } else { $np.NoPassword = $true }
        $u = New-LocalUser @np
        # SID строкой: объект SecurityIdentifier Add-LocalGroupMember на части систем не принимает
        # (ошибка разбора параметра, её не глушит даже -ErrorAction).
        $sidStr = [string]$u.SID.Value
        Set-LocalUser -SID $sidStr -PasswordNeverExpires ([bool]$ui.NewNever.IsChecked) -ErrorAction SilentlyContinue
        if ($ui.NewMust.IsChecked) {
            try { $ad = [ADSI]('WinNT://./' + $name + ',user'); $ad.Put('PasswordExpired', 1); $ad.SetInfo() }
            catch { Write-Log ('Не удалось попросить сменить пароль при входе: ' + $_.Exception.Message) 'warn' }
        }
        try { Add-LocalGroupMember -SID $script:SidUsers -Member $sidStr -ErrorAction Stop } catch { if ($_.FullyQualifiedErrorId -notlike 'MemberExists*') { Write-Log ('Не добавлен в группу «Пользователи»: ' + $_.Exception.Message) 'warn' } }
        if ($ui.NewAdm.IsChecked) {
            try { Add-LocalGroupMember -SID $script:SidAdmins -Member $sidStr -ErrorAction Stop }
            catch {
                # Не оставляем недоделанную учётку: удаляем и показываем ошибку.
                $msg = $_.Exception.Message
                try { Remove-LocalUser -SID $sidStr -ErrorAction Stop } catch {}
                throw ('Не удалось дать права администратора, пользователь не создан: ' + $msg)
            }
        }
        Write-Log ('Создан пользователь: ' + $name) 'ok'
        Add-History -Kind 'users' -Name ('Создан пользователь: ' + $name + $(if ($ui.NewAdm.IsChecked) { ' (администратор)' } else { '' }))
        $ui.NewFull.Text = ''; $ui.NewName.Text = ''; $ui.NewDesc.Text = ''; $ui.LoginTouched = $false
        $ui.NewPwd.Clear(); $ui.NewPwd2.Clear(); $ui.NewMust.IsChecked = $false
        # Файлы - сразу на выбранном диске: создаём профиль сейчас и переносим, пока он пустой.
        if ($drive -and $drive -ne ($env:SystemDrive).TrimEnd(':')) {
            Start-BgTask -Name ('Папка пользователя на ' + $drive + ':') -Vars @{ Sid = $sidStr; N = $name; D = $drive } -Script {
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
