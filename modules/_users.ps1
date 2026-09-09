function New-RandomPassword {
    param([int]$Length = 14)
    $chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%^&*'.ToCharArray()
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $buf = New-Object byte[] $Length
        $rng.GetBytes($buf)
        return -join ($buf | ForEach-Object { $chars[$_ % $chars.Length] })
    } finally { try { $rng.Dispose() } catch {} }
}

function New-EasyPassword {
    # Простой пароль из словаря (для тестовых/временных учёток)
    $easy = @('admin','user','root','guest','123456','12345','1234','qwerty','password','admin123','user123','root123','qwerty123','12345678')
    return $easy[(Get-Random -Maximum $easy.Count)]
}

function Copy-TextToClipboard {
    param([string]$Text)
    try {
        [System.Windows.Clipboard]::SetText($Text)
        return $true
    } catch { return $false }
}

function Set-DialogButtonIcon {
    # Текст + PNG-иконка из assets (фолбэк — просто текст, если иконки нет).
    # -Property: Content для кнопок, Header для вкладок.
    param($Button, [string]$Text, [string]$Icon = '', [int]$Size = 13, [string]$Property = 'Content')
    try {
        if ($Icon) {
            $c = New-IconButtonContent -Text $Text -Icon $Icon -Size $Size
            if ($c) { $Button.$Property = $c; return }
        }
        if ($Text) { $Button.$Property = $Text }
    } catch { try { if ($Text) { $Button.$Property = $Text } } catch {} }
}

function Get-RdpGroupName {
    foreach ($g in @('Remote Desktop Users', 'Пользователи удалённого рабочего стола')) {
        if (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue) { return $g }
    }
    return $null
}

function Test-UserInGroup {
    param([string]$User, [string]$Group)
    try { return [bool](Get-LocalGroupMember -Group $Group -Member $User -ErrorAction Stop) }
    catch { return $false }
}

function Get-UserRoleLabel {    param($LocalUser)
    try {
        if ($null -eq $script:AdminGroupMembers) {
            $g = Get-LocalGroupMember -Group "Администраторы" -ErrorAction SilentlyContinue
            if (-not $g) { $g = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue }
            $script:AdminGroupMembers = @($g)
        }
        return (@($script:AdminGroupMembers | Where-Object { $_.SID -eq $LocalUser.SID }).Count -gt 0)
    } catch { return $false }
}

function Build-UsersPanel {
    if ($null -eq $usersPanel) { [Console]::WriteLine('PotatoPC: этот файл — часть приложения. Запускай menu.ps1'); return }
    $usersPanel.Children.Clear()
    $script:AdminGroupMembers = $null
    $users = @()
    try {
        $users = @(Get-LocalUser -ErrorAction Stop | Sort-Object { -([int]$_.Enabled) }, Name)
    } catch {
        Write-Log "✗ Не удалось получить список пользователей: $_" -Color "Red"
    }
    if ($users.Count -eq 0) {
        $lbl = [System.Windows.Controls.TextBlock]::new()
        $lbl.Text = "Пользователи не найдены или нет доступа к Get-LocalUser"
        $lbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#9898b8")
        $lbl.FontSize = 13; $lbl.TextAlignment = "Center"; $lbl.Margin = "0,60,0,0"
        $usersPanel.Children.Add($lbl) | Out-Null
        return
    }
    $currentUserName = $env:USERNAME
    foreach ($u in $users) {
        $isAdmin   = Get-UserRoleLabel -LocalUser $u
        $isCurrent = ($u.Name -eq $currentUserName)
        $card = New-Card -Dimmed:(-not $u.Enabled)
        $card.CornerRadius = [System.Windows.CornerRadius]::new(10)
        $card.Margin = [System.Windows.Thickness]::new(0,3,0,3)
        $card.Padding = [System.Windows.Thickness]::new(12,9,12,9)
        if (-not $u.Enabled) { $card.Opacity = 0.7 }
        Add-CardFx -Card $card
        $g = [System.Windows.Controls.Grid]::new()
        $c1 = [System.Windows.Controls.ColumnDefinition]::new(); $c1.Width = [System.Windows.GridLength]::new(44)
        $c2 = [System.Windows.Controls.ColumnDefinition]::new(); $c2.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
        $c3 = [System.Windows.Controls.ColumnDefinition]::new(); $c3.Width = [System.Windows.GridLength]::Auto
        $c4 = [System.Windows.Controls.ColumnDefinition]::new(); $c4.Width = [System.Windows.GridLength]::Auto
        $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2); $g.ColumnDefinitions.Add($c3); $g.ColumnDefinitions.Add($c4)
        $avatarBorder = [System.Windows.Controls.Border]::new()
        $avatarBorder.Width = 38; $avatarBorder.Height = 38
        $avatarBorder.CornerRadius = [System.Windows.CornerRadius]::new(19)
        $avatarBorder.VerticalAlignment = "Center"; $avatarBorder.HorizontalAlignment = "Center"
        $avatarBgColor = if ($isAdmin) { "#3a2a6a" } else { "#33333f" }
        $avatarBorder.Background = [Windows.Media.BrushConverter]::new().ConvertFrom($avatarBgColor)
        $avatarImg = Get-IconImage -Name $(if ($isAdmin) { 'status/password' } else { 'apps/nav_users' }) -Size 20
        if ($avatarImg) {
            $avatarImg.HorizontalAlignment = "Center"; $avatarImg.VerticalAlignment = "Center"
            $avatarBorder.Child = $avatarImg
        } else {
            $avatarTxt = [System.Windows.Controls.TextBlock]::new()
            $avatarTxt.Text = $u.Name.Substring(0,1).ToUpper()
            $avatarTxt.FontSize = 17; $avatarTxt.FontWeight = "Bold"
            $avatarTxt.HorizontalAlignment = "Center"; $avatarTxt.VerticalAlignment = "Center"
            $avatarBorder.Child = $avatarTxt
        }
        [System.Windows.Controls.Grid]::SetColumn($avatarBorder, 0)
        $infoStack = [System.Windows.Controls.StackPanel]::new()
        $infoStack.VerticalAlignment = "Center"
        $infoStack.Margin = [System.Windows.Thickness]::new(12,0,12,0)
        $nameRow = [System.Windows.Controls.StackPanel]::new()
        $nameRow.Orientation = "Horizontal"; $nameRow.VerticalAlignment = "Center"
        $nameTxt = [System.Windows.Controls.TextBlock]::new()
        $nameTxt.Text = $u.Name; $nameTxt.FontSize = 14; $nameTxt.FontWeight = "SemiBold"
        $nameFgColor = if ($u.Enabled) { "#e8e8ff" } else { "#808090" }
        $nameTxt.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom($nameFgColor)
        $nameRow.Children.Add($nameTxt) | Out-Null
        if ($isCurrent) {
            $curB = [System.Windows.Controls.Border]::new()
            $curB.CornerRadius = [System.Windows.CornerRadius]::new(4)
            $curB.Padding = [System.Windows.Thickness]::new(5,1,5,1)
            $curB.Margin = [System.Windows.Thickness]::new(7,0,0,0)
            $curB.VerticalAlignment = "Center"
            $curB.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#0d2d2d")
            $curB.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a6b6b")
            $curB.BorderThickness = [System.Windows.Thickness]::new(1)
            $curT = [System.Windows.Controls.TextBlock]::new()
            $curT.Text = "● текущий"; $curT.FontSize = 10; $curT.FontWeight = "SemiBold"
            $curT.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#2ecccc")
            $curB.Child = $curT
            $nameRow.Children.Add($curB) | Out-Null
        }
        $roleB = [System.Windows.Controls.Border]::new()
        $roleB.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $roleB.Padding = [System.Windows.Thickness]::new(5,1,5,1)
        $roleB.Margin = [System.Windows.Thickness]::new(7,0,0,0)
        $roleB.VerticalAlignment = "Center"
        $roleB.BorderThickness = [System.Windows.Thickness]::new(1)
        $roleT = [System.Windows.Controls.TextBlock]::new()
        $roleT.FontSize = 10; $roleT.FontWeight = "SemiBold"
        if ($isAdmin) {
            $roleB.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#2d2200")
            $roleB.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#a07800")
            $roleT.Text = "Администратор"
            $roleT.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#f0c040")
        } else {
            $roleB.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#14142a")
            $roleB.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#2a2a50")
            $roleT.Text = "Пользователь"
            $roleT.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#a8a8d0")
        }
        $roleB.Child = $roleT
        $nameRow.Children.Add($roleB) | Out-Null
        $stB = [System.Windows.Controls.Border]::new()
        $stB.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $stB.Padding = [System.Windows.Thickness]::new(5,1,5,1)
        $stB.Margin = [System.Windows.Thickness]::new(7,0,0,0)
        $stB.VerticalAlignment = "Center"
        $stB.BorderThickness = [System.Windows.Thickness]::new(1)
        $stT = [System.Windows.Controls.TextBlock]::new()
        $stT.FontSize = 10; $stT.FontWeight = "SemiBold"
        if ($u.Enabled) {
            $stB.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#0d2d1a")
            $stB.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a6b35")
            $stT.Text = "● активен"; $stT.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#2ecc71")
        } else {
            $stB.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#2d0d0d")
            $stB.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#6b1a1a")
            $stT.Text = "● отключен"; $stT.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#e74c3c")
        }
        $stB.Child = $stT
        $nameRow.Children.Add($stB) | Out-Null
        $infoStack.Children.Add($nameRow) | Out-Null
        $detailParts = @()
        try {
            if ($u.PasswordExpires) {
                if ($u.PasswordExpires -lt (Get-Date)) { $detailParts += "Пароль истёк!" }
                else { $detailParts += "Пароль истекает: $($u.PasswordExpires.ToString('dd.MM.yyyy'))" }
            }
            else { $detailParts += "Пароль без срока действия" }
        } catch { $detailParts += "Срок пароля: неизвестно" }
        if ($u.LastLogon) { $detailParts += "Вход: $(Get-RelativeTime -Dt $u.LastLogon) ($($u.LastLogon.ToString('dd.MM.yyyy HH:mm')))" }
        else { $detailParts += "Входа не было" }
        if ($u.Description) { $detailParts += $u.Description }
        $detailTxt = [System.Windows.Controls.TextBlock]::new()
        $detailTxt.Text = ($detailParts -join "  •  ")
        $detailTxt.FontSize = 10; $detailTxt.Margin = [System.Windows.Thickness]::new(0,3,0,0)
        $detailTxt.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#8a8aa5")
        $detailTxt.TextTrimming = "CharacterEllipsis"
        $infoStack.Children.Add($detailTxt) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($infoStack, 1)
        $cfgBtn = [System.Windows.Controls.Button]::new()
        $cfgBtn.Content = (New-IconButtonContent -Text 'Настроить' -Icon 'actions/admin_gear' -Size 12)
        $cfgBtn.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#2d2d35")
        $cfgBtn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#d4d4e0")
        $cfgBtn.BorderThickness = [System.Windows.Thickness]::new(0)
        $cfgBtn.Cursor = [System.Windows.Input.Cursors]::Hand
        $cfgBtn.FontSize = 11; $cfgBtn.FontWeight = "SemiBold"
        $cfgBtn.Padding = [System.Windows.Thickness]::new(12,7,12,7)
        $cfgBtn.VerticalAlignment = "Center"
        $cfgBtn.Tag = $u.Name
        $cfgBtn.Add_MouseEnter({ $this.Opacity = 0.8 })
        $cfgBtn.Add_MouseLeave({ $this.Opacity = 1.0 })
        $cfgBtn.Add_Click({
            $userName = $this.Tag
            Show-UserSettingsDialog -UserName $userName
        })
        [System.Windows.Controls.Grid]::SetColumn($cfgBtn, 2)
        $g.Children.Add($avatarBorder) | Out-Null
        $g.Children.Add($infoStack) | Out-Null
        $g.Children.Add($cfgBtn) | Out-Null
        $tglBtn = [System.Windows.Controls.Button]::new()
        if ($u.Enabled) {
            $tglBtn.Content = "Отключить"
            $tglBtn.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#8b1a1a")
            $tglBtn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#ffffff")
        } else {
            $tglBtn.Content = "Включить"
            $tglBtn.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#2d2d35")
            $tglBtn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#d4d4e0")
        }
        $tglBtn.BorderThickness = [System.Windows.Thickness]::new(0)
        $tglBtn.Cursor = [System.Windows.Input.Cursors]::Hand
        $tglBtn.FontSize = 11; $tglBtn.FontWeight = "SemiBold"
        $tglBtn.Padding = [System.Windows.Thickness]::new(12,7,12,7)
        $tglBtn.VerticalAlignment = "Center"
        $tglBtn.Margin = [System.Windows.Thickness]::new(8,0,0,0)
        $tglBtn.Tag = $u.Name
        $tglBtn.ToolTip = "Быстро включить/отключить без диалога"
        $tglBtn.Add_Click({
            $nm = $this.Tag
            try { $lu = Get-LocalUser -Name $nm -ErrorAction Stop }
            catch { Write-Log ("Нет пользователя: " + $nm) -Color "Red"; return }
            try {
                if ($lu.Enabled) {
                    $msg = "Отключить учётную запись '$nm'?"
                    if ($nm -eq $env:USERNAME) { $msg += "`nВНИМАНИЕ: это ваша текущая учётная запись!" }
                    if ([System.Windows.MessageBox]::Show($msg, "Отключить", "YesNo", "Warning") -ne "Yes") { return }
                    Disable-LocalUser -Name $nm -ErrorAction Stop
                    Write-Log ("Отключён: " + $nm) -Color "Yellow"
                } else {
                    if ([System.Windows.MessageBox]::Show("Включить учётную запись '$nm'?", "Включить", "YesNo", "Question") -ne "Yes") { return }
                    Enable-LocalUser -Name $nm -ErrorAction Stop
                    Write-Log ("Включён: " + $nm) -Color "Green"
                }
                Build-UsersPanel
            } catch { Write-Log ("Не удалось: " + $_) -Color "Red" }
        })
        [System.Windows.Controls.Grid]::SetColumn($tglBtn,3)
        $g.Children.Add($tglBtn) | Out-Null
        $card.Child = $g
        if ($u.Enabled) {
            $card.Add_MouseEnter({ $this.Background = $script:Theme.CardBgHover })
            $card.Add_MouseLeave({ $this.Background = $script:Theme.CardBg })
        }
        $usersPanel.Children.Add($card) | Out-Null
    }
    Write-Log "Пользователи: найдено $($users.Count) (активных: $(($users | Where-Object {$_.Enabled}).Count))"
}

function Show-UserSettingsDialog {
    param([string]$UserName)
    $user = $null
    try { $user = Get-LocalUser -Name $UserName -ErrorAction Stop } catch {
        Write-Log "✗ Не удалось загрузить пользователя $UserName : $_" -Color "Red"; return
    }
    $isAdminNow = Get-UserRoleLabel -LocalUser $user
    $dialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Настройка: USERNAME" Width="720" SizeToContent="Height" MaxHeight="780"
        WindowStartupLocation="CenterScreen" Background="#202020" ResizeMode="NoResize">
    <Window.Resources>
        <Style x:Key="DlgBtn" TargetType="Button">
            <Setter Property="Background" Value="#6c63ff"/>
            <Setter Property="Foreground" Value="#ffffff"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="DlgBtnSecondary" TargetType="Button" BasedOn="{StaticResource DlgBtn}">
            <Setter Property="Background" Value="#2d2d35"/>
            <Setter Property="Foreground" Value="#d4d4e0"/>
        </Style>
        <Style x:Key="DlgTextInput" TargetType="TextBox">
            <Setter Property="Background" Value="#1a1a20"/>
            <Setter Property="Foreground" Value="#e0e0ff"/>
            <Setter Property="BorderBrush" Value="#33333f"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="CaretBrush" Value="#6c63ff"/>
        </Style>
        <Style x:Key="DlgTextBox" TargetType="PasswordBox">
            <Setter Property="Background" Value="#1a1a20"/>
            <Setter Property="Foreground" Value="#e0e0ff"/>
            <Setter Property="BorderBrush" Value="#33333f"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="CaretBrush" Value="#6c63ff"/>
        </Style>
    </Window.Resources>
    <StackPanel Margin="22">
        <TextBlock Text="Настройки пользователя" Foreground="White" FontSize="15" FontWeight="Bold" Margin="0,0,0,2"/>
        <TextBlock Text="USERNAME" Foreground="#6c63ff" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,14"/>
        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Margin="0,0,6,0">
        <Border Background="#26262e" CornerRadius="8" Padding="14,12" Margin="0,0,0,10">
            <StackPanel>
                <TextBlock Text="Новый пароль" Foreground="#c4c4ee" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,8"/>
                <PasswordBox x:Name="NewPasswordBox" Style="{StaticResource DlgTextBox}" Margin="0,0,0,8"/>
                <TextBlock Text="Подтверждение пароля" Foreground="#8a8aa5" FontSize="10" Margin="0,0,0,4"/>
                <PasswordBox x:Name="ConfirmPasswordBox" Style="{StaticResource DlgTextBox}"/>
                <Button Content="Изменить пароль" x:Name="ChangePasswordBtn" Style="{StaticResource DlgBtn}" Margin="0,10,0,0" HorizontalAlignment="Left"/>
            </StackPanel>
        </Border>
        <Border Background="#26262e" CornerRadius="8" Padding="14,12" Margin="0,0,0,10">
            <StackPanel>
                <TextBlock Text="Сгенерировать пароль" Foreground="#c4c4ee" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,8"/>
                <TextBox x:Name="GenPassView2" Style="{StaticResource DlgTextInput}" IsReadOnly="True" Margin="0,0,0,8"/>
                <StackPanel Orientation="Horizontal">
                    <Button Content="Стандарт" x:Name="GenPasswordBtn2" Style="{StaticResource DlgBtnSecondary}" Margin="0,0,8,0" ToolTip="Случайный пароль 14 символов, сразу копируется в буфер"/>
                    <Button Content="Простой" x:Name="GenEasyBtn2" Style="{StaticResource DlgBtnSecondary}" Margin="0,0,8,0" ToolTip="Простой пароль (admin, 123456...), сразу копируется в буфер"/>
                    <Button Content="Копировать" x:Name="CopyPassBtn2" Style="{StaticResource DlgBtnSecondary}" ToolTip="Скопировать пароль в буфер обмена"/>
                </StackPanel>
            </StackPanel>
        </Border>
        <Border Background="#26262e" CornerRadius="8" Padding="14,12" Margin="0,0,0,10">
            <StackPanel>
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel>
                        <TextBlock Text="Пароль без срока действия" Foreground="#c4c4ee" FontSize="12" FontWeight="SemiBold"/>
                        <TextBlock Text="Отключает обязательную смену пароля по истечении срока" Foreground="#8a8aa5" FontSize="10" Margin="0,3,0,0" TextWrapping="Wrap" MaxWidth="240"/>
                    </StackPanel>
                    <CheckBox x:Name="NoExpireChk" Grid.Column="1" VerticalAlignment="Center"/>
                </Grid>
                <TextBlock Text="Учётка действительна до (дд.мм.гггг, пусто — бессрочно)" Foreground="#8a8aa5" FontSize="10" Margin="0,10,0,4"/>
                <TextBox x:Name="ExpireBox" Style="{StaticResource DlgTextInput}"/>
            </StackPanel>
        </Border>
            </StackPanel>
            <StackPanel Grid.Column="1" Margin="6,0,0,0">
        <Border Background="#26262e" CornerRadius="8" Padding="14,12" Margin="0,0,0,10">
            <StackPanel>
                <TextBlock Text="Роль учётной записи" Foreground="#c4c4ee" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,8"/>
                <StackPanel Orientation="Horizontal">
                    <RadioButton x:Name="RoleAdminRadio" Content="Администратор" GroupName="Role" Foreground="#c4c4ee" FontSize="12" Margin="0,0,20,0"/>
                    <RadioButton x:Name="RoleUserRadio" Content="Пользователь" GroupName="Role" Foreground="#c4c4ee" FontSize="12"/>
                </StackPanel>
            </StackPanel>
        </Border>
        <Border Background="#26262e" CornerRadius="8" Padding="14,12" Margin="0,0,0,10">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel>
                    <TextBlock Text="Доступ по RDP" Foreground="#c4c4ee" FontSize="12" FontWeight="SemiBold"/>
                    <TextBlock Text="Членство в группе пользователей удалённого рабочего стола" Foreground="#8a8aa5" FontSize="10" Margin="0,3,0,0" TextWrapping="Wrap" MaxWidth="240"/>
                </StackPanel>
                <CheckBox x:Name="RdpChk" Grid.Column="1" VerticalAlignment="Center"/>
            </Grid>
        </Border>
        <Border Background="#26262e" CornerRadius="8" Padding="14,12" Margin="0,0,0,16">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Text="Учётная запись активна" Foreground="#c4c4ee" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
                <CheckBox x:Name="EnabledChk" Grid.Column="1" VerticalAlignment="Center"/>
            </Grid>
        </Border>
            </StackPanel>
        </Grid>
        <TextBlock x:Name="DialogStatusText" Foreground="#8a8aa5" FontSize="11" Margin="0,0,0,10" TextWrapping="Wrap"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Content="Закрыть" x:Name="CloseDialogBtn" Style="{StaticResource DlgBtnSecondary}" Margin="0,0,8,0"/>
            <Button Content="Сохранить изменения" x:Name="SaveChangesBtn" Style="{StaticResource DlgBtn}"/>
        </StackPanel>
    </StackPanel>
</Window>
'@
    $dialogXaml = $dialogXaml.Replace('USERNAME', [System.Security.SecurityElement]::Escape($UserName))
    $dReader = [System.Xml.XmlNodeReader]::new(([xml]$dialogXaml))
    $dlg = [Windows.Markup.XamlReader]::Load($dReader)
    $newPasswordBox     = $dlg.FindName("NewPasswordBox")
    $confirmPasswordBox = $dlg.FindName("ConfirmPasswordBox")
    $changePasswordBtn  = $dlg.FindName("ChangePasswordBtn")
    $noExpireChk        = $dlg.FindName("NoExpireChk")
    $roleAdminRadio     = $dlg.FindName("RoleAdminRadio")
    $roleUserRadio      = $dlg.FindName("RoleUserRadio")
    $enabledChk         = $dlg.FindName("EnabledChk")
    $dialogStatusText   = $dlg.FindName("DialogStatusText")
    $closeDialogBtn     = $dlg.FindName("CloseDialogBtn")
    $saveChangesBtn     = $dlg.FindName("SaveChangesBtn")
    $expireBox          = $dlg.FindName("ExpireBox")
    $rdpChk             = $dlg.FindName("RdpChk")
    $genPasswordBtn     = $dlg.FindName("GenPasswordBtn2")
    try { $noExpireChk.IsChecked = ($null -eq $user.PasswordExpires) } catch { $noExpireChk.IsChecked = $false }
    $enabledChk.IsChecked = $user.Enabled
    if ($isAdminNow) { $roleAdminRadio.IsChecked = $true } else { $roleUserRadio.IsChecked = $true }
    try {
        if ($null -eq $user.AccountExpires -or ([DateTime]$user.AccountExpires).Year -ge 9999) { $expireBox.Text = "" }
        else { $expireBox.Text = ([DateTime]$user.AccountExpires).ToString("dd.MM.yyyy") }
    } catch { try { $expireBox.Text = "" } catch {} }
    try {
        $rdpGroupName = Get-RdpGroupName
        $rdpChk.IsChecked = ($null -ne $rdpGroupName -and (Test-UserInGroup -User $UserName -Group $rdpGroupName))
        if ($rdpGroupName) { $rdpChk.ToolTip = $rdpGroupName } else { $rdpChk.ToolTip = "Группа RDP не найдена" }
    } catch {}
    try { Enable-DarkTitleBar -Window $dlg } catch {}
    $genEasyBtn2 = $dlg.FindName("GenEasyBtn2")
    $copyPassBtn2 = $dlg.FindName("CopyPassBtn2")
    $genPassView2 = $dlg.FindName("GenPassView2")
    Set-DialogButtonIcon -Button $genPasswordBtn -Text 'Стандарт' -Icon 'actions/refresh'
    Set-DialogButtonIcon -Button $genEasyBtn2 -Text 'Простой' -Icon 'devices/keyboard'
    $copyImg2 = Get-IconImage -Name 'actions/copy' -Size 14
    if ($copyImg2) { $copyPassBtn2.Content = $copyImg2 } else { $copyPassBtn2.Content = 'Копировать' }
    $genPasswordBtn.Add_Click({
        $np = New-RandomPassword -Length 14
        $newPasswordBox.Password = $np; $confirmPasswordBox.Password = $np
        $genPassView2.Text = $np
        if (Copy-TextToClipboard -Text $np) {
            $dialogStatusText.Text = "✓ Стандартный пароль скопирован в буфер"
        } else {
            $dialogStatusText.Text = "⚠ Пароль в поле выше, скопируйте вручную"
        }
        $dialogStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#f0c040")
    })
    $genEasyBtn2.Add_Click({
        $np = New-EasyPassword
        $newPasswordBox.Password = $np; $confirmPasswordBox.Password = $np
        $genPassView2.Text = $np
        if (Copy-TextToClipboard -Text $np) {
            $dialogStatusText.Text = "✓ Простой пароль скопирован в буфер"
        } else {
            $dialogStatusText.Text = "⚠ Пароль в поле выше, скопируйте вручную"
        }
        $dialogStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#f0c040")
    })
    $copyPassBtn2.Add_Click({
        $cur = $genPassView2.Text
        if ([string]::IsNullOrEmpty($cur)) { $cur = $newPasswordBox.Password }
        if ([string]::IsNullOrEmpty($cur)) {
            $dialogStatusText.Text = "⚠ Пароль пустой — нечего копировать"
        } elseif (Copy-TextToClipboard -Text $cur) {
            $dialogStatusText.Text = "✓ Пароль скопирован в буфер обмена"
        } else {
            $dialogStatusText.Text = "✗ Не удалось скопировать в буфер"
        }
        $dialogStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#f0c040")
    })
    $changePasswordBtn.Add_Click({
        $p1 = $newPasswordBox.Password
        $p2 = $confirmPasswordBox.Password
        if ([string]::IsNullOrWhiteSpace($p1)) {
            $dialogStatusText.Text = "⚠ Введите новый пароль"
            $dialogStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#f0c040")
            return
        }
        if ($p1 -ne $p2) {
            $dialogStatusText.Text = "✗ Пароли не совпадают"
            $dialogStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#e74c3c")
            return
        }
        try {
            $secure = ConvertTo-SecureString $p1 -AsPlainText -Force
            Set-LocalUser -Name $UserName -Password $secure -ErrorAction Stop
            $dialogStatusText.Text = "✓ Пароль успешно изменён"
            $dialogStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#2ecc71")
            $newPasswordBox.Password = ""; $confirmPasswordBox.Password = ""
            Write-Log "✓ Пароль изменён для $UserName" -Color "Green"
        } catch {
            $dialogStatusText.Text = "✗ Ошибка: $_"
            $dialogStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#e74c3c")
            Write-Log "✗ Смена пароля для $UserName : $_" -Color "Red"
        }
    })
    $saveChangesBtn.Add_Click({
        $messages = @()
        $hasError = $false
        try {
            Set-LocalUser -Name $UserName -PasswordNeverExpires ([bool]($noExpireChk.IsChecked -eq $true)) -ErrorAction Stop
            $messages += if ($noExpireChk.IsChecked -eq $true) { "Пароль: без срока действия" } else { "Пароль: со сроком действия" }
        } catch {
            $messages += "Ошибка срока пароля: $_"; $hasError = $true
        }
        try {
            $isEnabled = [bool]($enabledChk.IsChecked -eq $true)
            if ($isEnabled) { Enable-LocalUser -Name $UserName -ErrorAction Stop }
            else { Disable-LocalUser -Name $UserName -ErrorAction Stop }
            $messages += if ($isEnabled) { "Учётная запись: активна" } else { "Учётная запись: отключена" }
        } catch {
            $messages += "Ошибка активности: $_"; $hasError = $true
        }
        try {
            $wantsAdmin = $roleAdminRadio.IsChecked
            $adminGroupName = "Администраторы"
            $userGroupName  = "Пользователи"
            if (-not (Get-LocalGroup -Name $adminGroupName -ErrorAction SilentlyContinue)) { $adminGroupName = "Administrators" }
            if (-not (Get-LocalGroup -Name $userGroupName -ErrorAction SilentlyContinue))  { $userGroupName  = "Users" }
            $currentlyAdmin = Get-UserRoleLabel -LocalUser (Get-LocalUser -Name $UserName)
            if ($wantsAdmin -and -not $currentlyAdmin) {
                Add-LocalGroupMember -Group $adminGroupName -Member $UserName -ErrorAction Stop
                $messages += "Роль: повышен до Администратора"
            } elseif (-not $wantsAdmin -and $currentlyAdmin) {
                Remove-LocalGroupMember -Group $adminGroupName -Member $UserName -ErrorAction Stop
                $messages += "Роль: понижен до Пользователя"
            } else {
                $messages += "Роль: без изменений"
            }
        } catch {
            $messages += "Ошибка смены роли: $_"; $hasError = $true
        }
        try {
            $expText = $expireBox.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($expText)) {
                Set-LocalUser -Name $UserName -AccountNeverExpires -ErrorAction Stop
                $messages += "Срок учётки: бессрочно"
            } else {
                $expDt = [DateTime]::MinValue
                if ([DateTime]::TryParseExact($expText, "dd.MM.yyyy", $null, "None", [ref]$expDt)) {
                    Set-LocalUser -Name $UserName -AccountExpires $expDt -ErrorAction Stop
                    $messages += ("Срок учётки: до " + $expDt.ToString("dd.MM.yyyy"))
                } else { $messages += "Срок учётки: неверный формат даты"; $hasError = $true }
            }
        } catch {
            $messages += "Ошибка срока учётки: $_"; $hasError = $true
        }
        try {
            $rdpGroupName = Get-RdpGroupName
            if (-not $rdpGroupName) { $messages += "RDP: группа не найдена" }
            else {
                $inRdp = Test-UserInGroup -User $UserName -Group $rdpGroupName
                $wantRdp = [bool]$rdpChk.IsChecked
                if ($wantRdp -and -not $inRdp) {
                    Add-LocalGroupMember -Group $rdpGroupName -Member $UserName -ErrorAction Stop
                    $messages += "RDP: доступ выдан"
                } elseif (-not $wantRdp -and $inRdp) {
                    Remove-LocalGroupMember -Group $rdpGroupName -Member $UserName -ErrorAction Stop
                    $messages += "RDP: доступ убран"
                } else { $messages += "RDP: без изменений" }
            }
        } catch {
            $messages += "Ошибка RDP: $_"; $hasError = $true
        }
        $dialogStatusText.Text = ($messages -join "  •  ")
        $statusFgColor = if ($hasError) { "#e74c3c" } else { "#2ecc71" }
        $dialogStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom($statusFgColor)
        foreach ($m in $messages) {
            Write-Log "$(if($hasError){'⚠'}else{'✓'}) $UserName : $m" -Color $(if($hasError){"Yellow"}else{"Green"})
        }
        if (-not $hasError) { Build-UsersPanel }
    })
    $closeDialogBtn.Add_Click({ $dlg.Close() })
    $dlg.ShowDialog() | Out-Null
}

function Show-CreateUserDialog {
    $dialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Новый пользователь" Width="720" SizeToContent="Height" MaxHeight="780"
        WindowStartupLocation="CenterScreen" Background="#202020" ResizeMode="NoResize">
    <Window.Resources>
        <Style x:Key="DlgBtn" TargetType="Button">
            <Setter Property="Background" Value="#6c63ff"/>
            <Setter Property="Foreground" Value="#ffffff"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="DlgBtnSecondary" TargetType="Button" BasedOn="{StaticResource DlgBtn}">
            <Setter Property="Background" Value="#2d2d35"/>
            <Setter Property="Foreground" Value="#d4d4e0"/>
        </Style>
        <Style x:Key="DlgTextBox" TargetType="TextBox">
            <Setter Property="Background" Value="#1a1a20"/>
            <Setter Property="Foreground" Value="#e0e0ff"/>
            <Setter Property="BorderBrush" Value="#33333f"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="CaretBrush" Value="#6c63ff"/>
        </Style>
        <Style x:Key="DlgPasswordBox" TargetType="PasswordBox">
            <Setter Property="Background" Value="#1a1a20"/>
            <Setter Property="Foreground" Value="#e0e0ff"/>
            <Setter Property="BorderBrush" Value="#33333f"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="CaretBrush" Value="#6c63ff"/>
        </Style>
    </Window.Resources>
    <StackPanel Margin="22">
        <TextBlock Text="Новый пользователь" Foreground="White" FontSize="15" FontWeight="Bold" Margin="0,0,0,14"/>
        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Margin="0,0,6,0">
        <Border Background="#26262e" CornerRadius="8" Padding="14,12" Margin="0,0,0,10">
            <StackPanel>
                <TextBlock Text="Имя пользователя" Foreground="#c4c4ee" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,8"/>
                <TextBox x:Name="NewUserNameBox" Style="{StaticResource DlgTextBox}"/>
                <TextBlock Text="Описание (необязательно)" Foreground="#8a8aa5" FontSize="10" Margin="0,8,0,4"/>
                <TextBox x:Name="NewUserDescBox" Style="{StaticResource DlgTextBox}"/>
            </StackPanel>
        </Border>
        <Border Background="#26262e" CornerRadius="8" Padding="14,12" Margin="0,0,0,10">
            <StackPanel>
                <TextBlock Text="Пароль" Foreground="#c4c4ee" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,8"/>
                <PasswordBox x:Name="NewUserPasswordBox" Style="{StaticResource DlgPasswordBox}" Margin="0,0,0,8"/>
                <TextBlock Text="Подтверждение пароля" Foreground="#8a8aa5" FontSize="10" Margin="0,0,0,4"/>
                <PasswordBox x:Name="NewUserConfirmBox" Style="{StaticResource DlgPasswordBox}"/>
            </StackPanel>
        </Border>
        <Border Background="#26262e" CornerRadius="8" Padding="14,12" Margin="0,0,0,10">
            <StackPanel>
                <TextBlock Text="Сгенерировать пароль" Foreground="#c4c4ee" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,8"/>
                <TextBox x:Name="GenPassView" Style="{StaticResource DlgTextBox}" IsReadOnly="True" Margin="0,0,0,8"/>
                <StackPanel Orientation="Horizontal">
                    <Button Content="Стандарт" x:Name="GenPasswordBtn" Style="{StaticResource DlgBtnSecondary}" Margin="0,0,8,0" ToolTip="Случайный пароль 14 символов, сразу копируется в буфер"/>
                    <Button Content="Простой" x:Name="GenEasyBtn" Style="{StaticResource DlgBtnSecondary}" Margin="0,0,8,0" ToolTip="Простой пароль (admin, 123456...), сразу копируется в буфер"/>
                    <Button Content="Копировать" x:Name="CopyPassBtn" Style="{StaticResource DlgBtnSecondary}" ToolTip="Скопировать пароль в буфер обмена"/>
                </StackPanel>
            </StackPanel>
        </Border>
            </StackPanel>
            <StackPanel Grid.Column="1" Margin="6,0,0,0">
        <Border Background="#26262e" CornerRadius="8" Padding="14,12" Margin="0,0,0,10">
            <StackPanel>
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel>
                        <TextBlock Text="Срок действия учётной записи" Foreground="#c4c4ee" FontSize="12" FontWeight="SemiBold"/>
                        <TextBlock Text="Дата в формате дд.мм.гггг, выключено — бессрочно" Foreground="#8a8aa5" FontSize="10" Margin="0,3,0,0" TextWrapping="Wrap" MaxWidth="240"/>
                    </StackPanel>
                    <CheckBox x:Name="NewUserExpireChk" Grid.Column="1" VerticalAlignment="Center"/>
                </Grid>
                <TextBox x:Name="NewUserExpireBox" Style="{StaticResource DlgTextBox}" Margin="0,8,0,0" IsEnabled="False" Text=""/>
            </StackPanel>
        </Border>
        <Border Background="#26262e" CornerRadius="8" Padding="14,12" Margin="0,0,0,16">
            <StackPanel>
                <TextBlock Text="Роль учётной записи" Foreground="#c4c4ee" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,8"/>
                <StackPanel Orientation="Horizontal">
                    <RadioButton x:Name="NewUserRoleAdminRadio" Content="Администратор" GroupName="NewRole" Foreground="#c4c4ee" FontSize="12" Margin="0,0,20,0"/>
                    <RadioButton x:Name="NewUserRoleUserRadio" Content="Пользователь" GroupName="NewRole" Foreground="#c4c4ee" FontSize="12" IsChecked="True"/>
                </StackPanel>
            </StackPanel>
        </Border>
        <Border Background="#26262e" CornerRadius="8" Padding="14,12" Margin="0,0,0,10">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel>
                    <TextBlock Text="Доступ по RDP" Foreground="#c4c4ee" FontSize="12" FontWeight="SemiBold"/>
                    <TextBlock Text="Добавляет в группу пользователей удалённого рабочего стола" Foreground="#8a8aa5" FontSize="10" Margin="0,3,0,0" TextWrapping="Wrap" MaxWidth="240"/>
                </StackPanel>
                <CheckBox x:Name="NewUserRdpChk" Grid.Column="1" VerticalAlignment="Center"/>
            </Grid>
        </Border>
            </StackPanel>
        </Grid>
        <TextBlock x:Name="CreateUserStatusText" Foreground="#8a8aa5" FontSize="11" Margin="0,0,0,10" TextWrapping="Wrap"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Content="Отмена" x:Name="CancelCreateUserBtn" Style="{StaticResource DlgBtnSecondary}" Margin="0,0,8,0"/>
            <Button Content="Создать пользователя" x:Name="ConfirmCreateUserBtn" Style="{StaticResource DlgBtn}"/>
        </StackPanel>
    </StackPanel>
</Window>
'@
    $dReader = [System.Xml.XmlNodeReader]::new(([xml]$dialogXaml))
    $dlg = [Windows.Markup.XamlReader]::Load($dReader)
    $newUserNameBox        = $dlg.FindName("NewUserNameBox")
    $newUserDescBox        = $dlg.FindName("NewUserDescBox")
    $newUserPasswordBox    = $dlg.FindName("NewUserPasswordBox")
    $newUserConfirmBox     = $dlg.FindName("NewUserConfirmBox")
    $newUserExpireChk      = $dlg.FindName("NewUserExpireChk")
    $newUserExpireBox      = $dlg.FindName("NewUserExpireBox")
    $newUserRdpChk         = $dlg.FindName("NewUserRdpChk")
    $genCreateBtn          = $dlg.FindName("GenPasswordBtn")
    $newUserRoleAdminRadio = $dlg.FindName("NewUserRoleAdminRadio")
    $newUserRoleUserRadio  = $dlg.FindName("NewUserRoleUserRadio")
    $createUserStatusText  = $dlg.FindName("CreateUserStatusText")
    $cancelCreateUserBtn   = $dlg.FindName("CancelCreateUserBtn")
    $confirmCreateUserBtn  = $dlg.FindName("ConfirmCreateUserBtn")
    $newUserExpireChk.Add_Checked({ $newUserExpireBox.IsEnabled = $true })
    $newUserExpireChk.Add_Unchecked({ $newUserExpireBox.IsEnabled = $false; $newUserExpireBox.Text = "" })
    $genEasyBtn = $dlg.FindName("GenEasyBtn")
    $copyPassBtn = $dlg.FindName("CopyPassBtn")
    $genPassView = $dlg.FindName("GenPassView")
    Set-DialogButtonIcon -Button $genCreateBtn -Text 'Стандарт' -Icon 'actions/refresh'
    Set-DialogButtonIcon -Button $genEasyBtn -Text 'Простой' -Icon 'devices/keyboard'
    $copyImg = Get-IconImage -Name 'actions/copy' -Size 14
    if ($copyImg) { $copyPassBtn.Content = $copyImg } else { $copyPassBtn.Content = 'Копировать' }
    $genCreateBtn.Add_Click({
        $np = New-RandomPassword -Length 14
        $newUserPasswordBox.Password = $np; $newUserConfirmBox.Password = $np
        $genPassView.Text = $np
        if (Copy-TextToClipboard -Text $np) {
            $createUserStatusText.Text = "✓ Стандартный пароль скопирован в буфер"
        } else {
            $createUserStatusText.Text = "⚠ Пароль в поле выше, скопируйте вручную"
        }
        $createUserStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#f0c040")
    })
    $genEasyBtn.Add_Click({
        $np = New-EasyPassword
        $newUserPasswordBox.Password = $np; $newUserConfirmBox.Password = $np
        $genPassView.Text = $np
        if (Copy-TextToClipboard -Text $np) {
            $createUserStatusText.Text = "✓ Простой пароль скопирован в буфер"
        } else {
            $createUserStatusText.Text = "⚠ Пароль в поле выше, скопируйте вручную"
        }
        $createUserStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#f0c040")
    })
    $copyPassBtn.Add_Click({
        $cur = $genPassView.Text
        if ([string]::IsNullOrEmpty($cur)) { $cur = $newUserPasswordBox.Password }
        if ([string]::IsNullOrEmpty($cur)) {
            $createUserStatusText.Text = "⚠ Пароль пустой — нечего копировать"
        } elseif (Copy-TextToClipboard -Text $cur) {
            $createUserStatusText.Text = "✓ Пароль скопирован в буфер обмена"
        } else {
            $createUserStatusText.Text = "✗ Не удалось скопировать в буфер"
        }
        $createUserStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#f0c040")
    })
    try { Enable-DarkTitleBar -Window $dlg } catch {}
    $cancelCreateUserBtn.Add_Click({ $dlg.Close() })
    $confirmCreateUserBtn.Add_Click({
        $name = $newUserNameBox.Text.Trim()
        $desc = $newUserDescBox.Text.Trim()
        $p1   = $newUserPasswordBox.Password
        $p2   = $newUserConfirmBox.Password
        if ([string]::IsNullOrWhiteSpace($name)) {
            $createUserStatusText.Text = "⚠ Введите имя пользователя"
            $createUserStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#f0c040")
            return
        }
        if ($name -match '[\\/:\*\?"<>\|]') {
            $createUserStatusText.Text = '⚠ Имя содержит недопустимые символы: \ / : * ? " < > |'
            $createUserStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#f0c040")
            return
        }
        if (Get-LocalUser -Name $name -ErrorAction SilentlyContinue) {
            $createUserStatusText.Text = "✗ Пользователь '$name' уже существует"
            $createUserStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#e74c3c")
            return
        }
        if ([string]::IsNullOrWhiteSpace($p1)) {
            $createUserStatusText.Text = "⚠ Введите пароль"
            $createUserStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#f0c040")
            return
        }
        if ($p1 -ne $p2) {
            $createUserStatusText.Text = "✗ Пароли не совпадают"
            $createUserStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#e74c3c")
            return
        }
        try {
            $secure = ConvertTo-SecureString $p1 -AsPlainText -Force
            $params = @{
                Name     = $name
                Password = $secure
            }
            if ([bool]$newUserExpireChk.IsChecked) {
                $expText = $newUserExpireBox.Text.Trim()
                if ([string]::IsNullOrWhiteSpace($expText)) { throw "Включите срок: укажите дату (дд.мм.гггг) или снимите галочку" }
                $expDt = [DateTime]::MinValue
                if (-not [DateTime]::TryParseExact($expText, "dd.MM.yyyy", $null, "None", [ref]$expDt)) { throw "Неверный формат даты (нужно дд.мм.гггг)" }
                $params.AccountExpires = $expDt
            } else {
                $params.AccountNeverExpires = $true
            }
            if (-not [string]::IsNullOrWhiteSpace($desc)) { $params.Description = $desc }
            New-LocalUser @params -ErrorAction Stop | Out-Null
            Write-Log "✓ Пользователь '$name' создан" -Color "Green"
            $wantsAdmin = [bool]$newUserRoleAdminRadio.IsChecked
            $groupName = if ($wantsAdmin) { "Администраторы" } else { "Пользователи" }
            if (-not (Get-LocalGroup -Name $groupName -ErrorAction SilentlyContinue)) {
                $groupName = if ($wantsAdmin) { "Administrators" } else { "Users" }
            }
            try {
                Add-LocalGroupMember -Group $groupName -Member $name -ErrorAction Stop
                Write-Log "✓ '$name' добавлен в группу '$groupName'" -Color "Green"
            } catch {
                Write-Log "⚠ Не удалось добавить '$name' в группу '$groupName': $_" -Color "Yellow"
            }
            if ([bool]$newUserRdpChk.IsChecked) {
                try {
                    $rdpGroup = Get-RdpGroupName
                    if ($rdpGroup) {
                        Add-LocalGroupMember -Group $rdpGroup -Member $name -ErrorAction Stop
                        Write-Log "'$name': RDP доступ выдан ($rdpGroup)" -Color "Green"
                    } else { Write-Log "RDP группа не найдена" -Color "Yellow" }
                } catch { Write-Log ("RDP: " + $_) -Color "Yellow" }
            }
            $createUserStatusText.Text = "✓ Пользователь '$name' успешно создан"
            $createUserStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#2ecc71")
            Build-UsersPanel
            Start-Sleep -Milliseconds 600
            $dlg.Close()
        } catch {
            $createUserStatusText.Text = "✗ Ошибка создания: $_"
            $createUserStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#e74c3c")
            Write-Log "✗ Создание пользователя '$name': $_" -Color "Red"
        }
    })
    $dlg.ShowDialog() | Out-Null
}
