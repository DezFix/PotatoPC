# PAGE: users
# TITLE: Пользователи
# ICON: users
# ORDER: 60

# Учётные записи без оснастки lusrmgr.msc - работает и в Windows Home.
# Группы ищутся по SID, а не по имени: на русской Windows «Администраторы»,
# на английской «Administrators».

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
        $gname = (Get-LocalGroup -SID $script:SidAdmins).Name
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
        }
        $info.NeverExpires = -not $u.PasswordExpires
        try { $flags = [int]([ADSI]('WinNT://./' + $u.Name + ',user')).UserFlags.Value; $info.NeverExpires = (($flags -band 0x10000) -ne 0) } catch {}
        if ($rid -eq '500' -or $rid -eq '501') { $builtin[$rid] = $info; continue }
        $list += $info
    }
    return @{ Users = $list; Builtin = $builtin; Auto = $auto; Me = $me }
}

function Build-Page_users {
    $ui = @{}
    $refresh = New-Button -Text 'Обновить' -Icon 'refresh' -OnClick { Update-UsersPage }
    $classic = New-Button -Text 'Учётные записи Windows' -Kind Ghost -OnClick { Start-Process 'ms-settings:otherusers' }
    $L = New-PageLayout -Title 'Пользователи' -Subtitle 'Учётные записи на этом компьютере' -HeaderRight @($classic, $refresh)
    $g = New-Object System.Windows.Controls.Grid
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength 1, 'Star'
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength 360
    [void]$g.ColumnDefinitions.Add($c1); [void]$g.ColumnDefinitions.Add($c2)
    $left = New-Stack -Margin (0, 0, 16, 0)
    $ui.List = New-Section -Title 'Учётные записи'
    [void]$ui.List.Body.Children.Add((New-Placeholder))
    [void]$left.Children.Add($ui.List.Root)
    $ui.Sec = New-Section -Title 'Вход и безопасность'
    [void]$left.Children.Add($ui.Sec.Root)
    [void]$g.Children.Add($left)

    # Форма нового пользователя
    $form = New-Stack
    [void]$form.Children.Add((New-Text -Text 'Новый пользователь' -Size 16 -Weight 'Bold' -Margin (0, 0, 0, 14)))
    $ui.NewName = New-TextInput -Placeholder 'Например, User'
    [void]$form.Children.Add((New-Field -Label 'Имя' -Control $ui.NewName))
    $ui.NewPwd = New-PasswordInput
    [void]$form.Children.Add((New-Field -Label 'Пароль (можно оставить пустым)' -Control $ui.NewPwd))
    $ui.NewPwd2 = New-PasswordInput
    [void]$form.Children.Add((New-Field -Label 'Пароль ещё раз' -Control $ui.NewPwd2))
    $ui.NewNever = New-CheckBox -Text 'Пароль никогда не истекает' -Checked $true -ToolTip 'Иначе Windows через 42 дня потребует сменить пароль'
    $ui.NewNever.Margin = New-Thickness 0, 0, 0, 12
    [void]$form.Children.Add($ui.NewNever)
    $ui.NewStd = New-Radio -Title 'Обычный' -Sub 'Может работать, но не ставит программы и не меняет систему' -Group 'newtype' -Checked $true
    $ui.NewAdm = New-Radio -Title 'Администратор' -Sub 'Полный доступ к компьютеру' -Group 'newtype'
    [void]$form.Children.Add($ui.NewStd); [void]$form.Children.Add($ui.NewAdm)
    $ui.NewErr = New-Text -Text '' -Size 12 -Color 'Bad' -Wrap -Margin (0, 0, 0, 8)
    [void]$form.Children.Add($ui.NewErr)
    $create = New-Button -Text 'Создать' -Icon 'plus' -Kind Primary -OnClick { New-UserFromForm }
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
    try { $d = Get-LocalUsersInfo } catch { Write-Log ('Пользователи не прочитались: ' + $_.Exception.Message) 'err'; return }
    $ui.Data = $d
    $body = $ui.List.Body
    $body.Children.Clear()
    $ui.List.Header.Text = 'Учётные записи · ' + $d.Users.Count
    foreach ($u in @($d.Users | Sort-Object { -not $_.IsMe }, { -not $_.Enabled }, { $_.Name })) {
        $badges = @()
        $badges += if ($u.IsAdmin) { New-Badge 'Администратор' 'accent' } else { New-Badge 'Обычный' 'info' }
        if ($u.Source -eq 'MicrosoftAccount') { $badges += New-Badge 'Учётка Microsoft' 'muted' }
        if (-not $u.Enabled) { $badges += New-Badge 'Отключён' 'muted' }
        if ($d.Auto.On -and $d.Auto.User -ieq $u.Name) { $badges += New-Badge 'Автовход' 'warn' }
        $title = New-Stack -Orientation Horizontal -Children (@((New-Text -Text $(if ($u.FullName) { $u.FullName + ' (' + $u.Name + ')' } else { $u.Name }) -Size 15 -Weight 'SemiBold')) + $badges)
        foreach ($b in $badges) { $b.Margin = New-Thickness 8, 0, 0, 0 }
        $parts = @()
        if ($u.IsMe) { $parts += 'это вы' }
        if ($u.LastLogon) { $parts += 'последний вход: ' + ([datetime]$u.LastLogon).ToString('dd.MM.yyyy HH:mm') } else { $parts += 'ещё не входил' }
        if ($u.PwdSet) { $parts += 'пароль менялся ' + ([datetime]$u.PwdSet).ToString('dd.MM.yyyy') }
        if ($u.Source -ne 'MicrosoftAccount' -and -not $u.NeverExpires -and $u.PwdExpires) { $parts += 'пароль истекает ' + ([datetime]$u.PwdExpires).ToString('dd.MM.yyyy') }
        $info = New-Stack -Children @($title, (New-Text -Text ($parts -join ' · ') -Size 12 -Color 'Muted' -Margin (0, 3, 0, 0)))
        $acts = New-Object System.Windows.Controls.WrapPanel
        $acts.Margin = New-Thickness 0, 10, 0, 0
        $mk = { param($t, $tag, $kind = 'Small') $b = New-Button -Text $t -Kind $kind -Tag $tag -OnClick { Invoke-UserAction -Spec $this.Tag }; $b.Margin = New-Thickness 0, 0, 8, 0; [void]$acts.Children.Add($b); $b }
        $pw = & $mk 'Сменить пароль' @{ A = 'pwd'; U = $u }
        if ($u.Source -eq 'MicrosoftAccount') { $pw.IsEnabled = $false; $pw.ToolTip = 'Пароль учётной записи Microsoft меняется на account.microsoft.com' }
        else {
            $tg = New-Toggle -Checked ([bool]$u.NeverExpires) -Tag $u -OnClick { Set-UserPasswordNeverExpires -User $this.Tag -Never ([bool]$this.IsChecked) }
            $tg.ToolTip = 'Включено - Windows не будет требовать сменить пароль. Выключено - через срок из политики (обычно 42 дня) пароль придётся сменить'
            $tl = New-Text -Text 'Пароль бессрочный' -Size 13 -Color 'Muted' -Margin (8, 0, 18, 0)
            $box = New-Stack -Orientation Horizontal -Children @($tg, $tl) -Margin (0, 0, 10, 8)
            $box.VerticalAlignment = 'Center'
            [void]$acts.Children.Insert(0, $box)
        }
        if (-not $u.IsMe) {
            [void](& $mk $(if ($u.IsAdmin) { 'Сделать обычным' } else { 'Сделать админом' }) @{ A = 'admin'; U = $u })
            [void](& $mk $(if ($u.Enabled) { 'Отключить' } else { 'Включить' }) @{ A = 'enable'; U = $u })
            [void](& $mk 'Удалить' @{ A = 'delete'; U = $u } 'SmallDanger')
        }
        $sp = New-Stack -Children @($info, $acts)
        [void]$body.Children.Add((New-Row -Left (New-AppIcon -Name $u.Name -Size 44) -Main $sp -Padding (16, 14, 16, 14)))
        $body.Children[$body.Children.Count - 1].Child.Children[0].CornerRadius = New-Object System.Windows.CornerRadius 22
    }

    $sec = $ui.Sec.Body
    $sec.Children.Clear()
    $mkT = {
        param($title, $sub, $on, $tag)
        $t = New-Toggle -Checked $on -Tag $tag -OnClick { Invoke-UserToggle -Spec $this.Tag -On ([bool]$this.IsChecked) }
        [void]$sec.Children.Add((New-Row -Main (New-TitleBlock -Title $title -Sub $sub) -Right @($t)))
    }
    $autoSub = if ($d.Auto.On) { 'Сейчас: сразу входить как «' + $d.Auto.User + '». Удобно на домашнем ПК, небезопасно на ноутбуке' } else { 'Сразу входить в выбранную учётку при включении. Удобно на домашнем ПК, небезопасно на ноутбуке' }
    & $mkT 'Автовход без ввода пароля' $autoSub $d.Auto.On 'auto'
    $g = $d.Builtin['501']
    if ($g) { & $mkT ('Гостевая запись «' + $g.Name + '»') 'Рекомендуем держать выключенной' $g.Enabled 'guest' }
    $a = $d.Builtin['500']
    if ($a) { & $mkT ('Скрытый «' + $a.Name + '»') 'Встроенная учётка Windows. Включайте только для ремонта и обязательно задайте пароль' $a.Enabled 'admin500' }
}

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
                    if ($u.IsAdmin -and (Test-LastAdmin $u)) { Show-Info 'Нельзя отключить последнего администратора.' -Icon 'Warning'; return }
                    Disable-LocalUser -SID $u.Sid -ErrorAction Stop; Write-Log ('Отключён: ' + $u.Name) 'ok'
                } else { Enable-LocalUser -SID $u.Sid -ErrorAction Stop; Write-Log ('Включён: ' + $u.Name) 'ok' }
                Add-History -Kind 'users' -Name ($(if ($u.Enabled) { 'Отключён: ' } else { 'Включён: ' }) + $u.Name)
            }
            'delete' {
                if ($u.IsAdmin -and (Test-LastAdmin $u)) { Show-Info 'Нельзя удалить последнего администратора.' -Icon 'Warning'; return }
                if (-not (Show-Confirm -Message ('Удалить учётную запись «' + $u.Name + '»?') -Warning)) { return }
                $prof = $null
                try { $prof = Get-CimInstance Win32_UserProfile -Filter ("SID='" + $u.Sid + "'") -ErrorAction Stop } catch {}
                $delProf = $false
                if ($prof) { $delProf = Show-Confirm -Message ('Удалить и папку профиля ' + $prof.LocalPath + '?' + "`n`nТам документы, рабочий стол и загрузки этого пользователя. «Нет» - папка останется на диске.") -Warning }
                Remove-LocalUser -SID $u.Sid -ErrorAction Stop
                if ($delProf -and $prof) { try { Remove-CimInstance -InputObject $prof -ErrorAction Stop } catch { Write-Log ('Папка профиля не удалена: ' + $_.Exception.Message) 'warn' } }
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
                    Set-ItemProperty -LiteralPath $script:WinlogonKey -Name 'AutoAdminLogon' -Value '0' -Type String
                    Remove-ItemProperty -LiteralPath $script:WinlogonKey -Name 'DefaultPassword' -ErrorAction SilentlyContinue
                    Write-Log 'Автовход выключен' 'ok'
                } else {
                    $users = @($d.Users | Where-Object { $_.Enabled -and $_.Source -ne 'MicrosoftAccount' })
                    if ($users.Count -eq 0) { Show-Info 'Нет подходящих локальных учётных записей.'; Update-UsersPage; return }
                    $script:AutoUsers = $users
                    $ok = Show-FormDialog -Title 'Автовход' -OkText 'Включить' -Build {
                        param($f)
                        $script:AutoRadios = @()
                        foreach ($u in $script:AutoUsers) { $r = New-Radio -Title $u.Name -Group 'auto' -Checked ($script:AutoRadios.Count -eq 0) -Tag $u.Name; [void]$f.Children.Add($r); $script:AutoRadios += $r }
                        $script:DlgP1 = New-PasswordInput
                        [void]$f.Children.Add((New-Field -Label 'Пароль этой учётки (пусто, если пароля нет)' -Control $script:DlgP1 -Margin (0, 6, 0, 8)))
                        [void]$f.Children.Add((New-Text -Text 'Пароль хранится в реестре открытым текстом - на ноутбуке, который носят с собой, автовход лучше не включать.' -Size 12 -Color 'Warn' -Wrap))
                    } -OnOk {
                        $sel = @($script:AutoRadios | Where-Object { $_.IsChecked })[0]
                        Set-ItemProperty -LiteralPath $script:WinlogonKey -Name 'AutoAdminLogon' -Value '1' -Type String
                        Set-ItemProperty -LiteralPath $script:WinlogonKey -Name 'DefaultUserName' -Value ([string]$sel.Tag) -Type String
                        Set-ItemProperty -LiteralPath $script:WinlogonKey -Name 'DefaultDomainName' -Value $env:COMPUTERNAME -Type String
                        Set-ItemProperty -LiteralPath $script:WinlogonKey -Name 'DefaultPassword' -Value $script:DlgP1.Password -Type String
                        return $true
                    }
                    if ($ok) { Write-Log 'Автовход включён' 'ok' }
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
    if ($ui.NewPwd.Password -ne $ui.NewPwd2.Password) { $ui.NewErr.Text = 'Пароли не совпадают'; return }
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
