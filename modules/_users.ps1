function Get-UserRoleLabel {
    param($LocalUser)
    try {
        $isAdmin = $false
        $adminGroup = Get-LocalGroupMember -Group "Администраторы" -ErrorAction SilentlyContinue
        if (-not $adminGroup) { $adminGroup = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue }
        if ($adminGroup) {
            $isAdmin = @($adminGroup | Where-Object { $_.SID -eq $LocalUser.SID }).Count -gt 0
        }
        return $isAdmin
    } catch { return $false }
}

function Build-UsersPanel {
    $usersPanel.Children.Clear()
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
        $card = [System.Windows.Controls.Border]::new()
        $card.CornerRadius = [System.Windows.CornerRadius]::new(10)
        $card.Margin = [System.Windows.Thickness]::new(0,5,0,5)
        $card.Padding = [System.Windows.Thickness]::new(16,14,16,14)
        $card.BorderThickness = [System.Windows.Thickness]::new(0,0,0,1)
        if ($u.Enabled) {
            $card.Background  = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e")
            $card.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#1e1e38")
        } else {
            $card.Background  = [Windows.Media.BrushConverter]::new().ConvertFrom("#15151f")
            $card.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a25")
            $card.Opacity = 0.7
        }
        $g = [System.Windows.Controls.Grid]::new()
        $c1 = [System.Windows.Controls.ColumnDefinition]::new(); $c1.Width = [System.Windows.GridLength]::new(44)
        $c2 = [System.Windows.Controls.ColumnDefinition]::new(); $c2.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
        $c3 = [System.Windows.Controls.ColumnDefinition]::new(); $c3.Width = [System.Windows.GridLength]::Auto
        $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2); $g.ColumnDefinitions.Add($c3)
        $avatarBorder = [System.Windows.Controls.Border]::new()
        $avatarBorder.Width = 38; $avatarBorder.Height = 38
        $avatarBorder.CornerRadius = [System.Windows.CornerRadius]::new(19)
        $avatarBorder.VerticalAlignment = "Center"; $avatarBorder.HorizontalAlignment = "Center"
        $avatarBgColor = if ($isAdmin) { "#3a2a6a" } else { "#2a2a45" }
        $avatarBorder.Background = [Windows.Media.BrushConverter]::new().ConvertFrom($avatarBgColor)
        $avatarTxt = [System.Windows.Controls.TextBlock]::new()
        $avatarTxt.Text = if ($isAdmin) { "👑" } else { "👤" }
        $avatarTxt.FontSize = 17; $avatarTxt.HorizontalAlignment = "Center"; $avatarTxt.VerticalAlignment = "Center"
        $avatarBorder.Child = $avatarTxt
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
            $roleT.Text = "👑 Администратор"
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
            if ($u.PasswordExpires) { $detailParts += "Пароль истекает: $($u.PasswordExpires.ToString('dd.MM.yyyy'))" }
            else { $detailParts += "Пароль без срока действия" }
        } catch { $detailParts += "Срок пароля: неизвестно" }
        if ($u.LastLogon) { $detailParts += "Вход: $($u.LastLogon.ToString('dd.MM.yyyy HH:mm'))" }
        if ($u.Description) { $detailParts += $u.Description }
        $detailTxt = [System.Windows.Controls.TextBlock]::new()
        $detailTxt.Text = ($detailParts -join "  •  ")
        $detailTxt.FontSize = 10; $detailTxt.Margin = [System.Windows.Thickness]::new(0,3,0,0)
        $detailTxt.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#7070a0")
        $detailTxt.TextTrimming = "CharacterEllipsis"
        $infoStack.Children.Add($detailTxt) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($infoStack, 1)
        $cfgBtn = [System.Windows.Controls.Button]::new()
        $cfgBtn.Content = "⚙ Настроить"
        $cfgBtn.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#2a2a4a")
        $cfgBtn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#b8b8e8")
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
        $card.Child = $g
        if ($u.Enabled) {
            $card.Add_MouseEnter({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#20203a") })
            $card.Add_MouseLeave({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e") })
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
    [xml]$dialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Настройка: USERNAME" Width="440" Height="650"
        WindowStartupLocation="CenterScreen" Background="#12121f" ResizeMode="NoResize">
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
            <Setter Property="Background" Value="#2a2a42"/>
            <Setter Property="Foreground" Value="#c0c0dd"/>
        </Style>
        <Style x:Key="DlgTextBox" TargetType="PasswordBox">
            <Setter Property="Background" Value="#1a1a2e"/>
            <Setter Property="Foreground" Value="#e0e0ff"/>
            <Setter Property="BorderBrush" Value="#2a2a45"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="CaretBrush" Value="#6c63ff"/>
        </Style>
    </Window.Resources>
    <StackPanel Margin="22">
        <TextBlock Text="⚙ Настройки пользователя" Foreground="White" FontSize="15" FontWeight="Bold" Margin="0,0,0,2"/>
        <TextBlock Text="USERNAME" Foreground="#6c63ff" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,16"/>
        <Border Background="#1a1a2e" CornerRadius="8" Padding="14,12" Margin="0,0,0,10">
            <StackPanel>
                <TextBlock Text="🔑 Новый пароль" Foreground="#c0c0e0" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,8"/>
                <PasswordBox x:Name="NewPasswordBox" Style="{StaticResource DlgTextBox}" Margin="0,0,0,8"/>
                <TextBlock Text="Подтверждение пароля" Foreground="#7070a0" FontSize="10" Margin="0,0,0,4"/>
                <PasswordBox x:Name="ConfirmPasswordBox" Style="{StaticResource DlgTextBox}"/>
                <Button Content="Изменить пароль" x:Name="ChangePasswordBtn" Style="{StaticResource DlgBtn}" Margin="0,10,0,0" HorizontalAlignment="Left"/>
            </StackPanel>
        </Border>
        <Border Background="#1a1a2e" CornerRadius="8" Padding="14,12" Margin="0,0,0,10">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel>
                    <TextBlock Text="♾️ Пароль без срока действия" Foreground="#c0c0e0" FontSize="12" FontWeight="SemiBold"/>
                    <TextBlock Text="Отключает обязательную смену пароля по истечении срока" Foreground="#7070a0" FontSize="10" Margin="0,3,0,0" TextWrapping="Wrap" MaxWidth="240"/>
                </StackPanel>
                <CheckBox x:Name="NoExpireChk" Grid.Column="1" VerticalAlignment="Center"/>
            </Grid>
        </Border>
        <Border Background="#1a1a2e" CornerRadius="8" Padding="14,12" Margin="0,0,0,10">
            <StackPanel>
                <TextBlock Text="👑 Роль учётной записи" Foreground="#c0c0e0" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,8"/>
                <StackPanel Orientation="Horizontal">
                    <RadioButton x:Name="RoleAdminRadio" Content="Администратор" GroupName="Role" Foreground="#c0c0e0" FontSize="12" Margin="0,0,20,0"/>
                    <RadioButton x:Name="RoleUserRadio" Content="Пользователь" GroupName="Role" Foreground="#c0c0e0" FontSize="12"/>
                </StackPanel>
            </StackPanel>
        </Border>
        <Border Background="#1a1a2e" CornerRadius="8" Padding="14,12" Margin="0,0,0,16">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Text="✅ Учётная запись активна" Foreground="#c0c0e0" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
                <CheckBox x:Name="EnabledChk" Grid.Column="1" VerticalAlignment="Center"/>
            </Grid>
        </Border>
        <TextBlock x:Name="DialogStatusText" Foreground="#9898c8" FontSize="11" Margin="0,0,0,10" TextWrapping="Wrap"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Content="Закрыть" x:Name="CloseDialogBtn" Style="{StaticResource DlgBtnSecondary}" Margin="0,0,8,0"/>
            <Button Content="💾 Сохранить изменения" x:Name="SaveChangesBtn" Style="{StaticResource DlgBtn}"/>
        </StackPanel>
    </StackPanel>
</Window>
'@
    $dialogXaml = $dialogXaml.Replace('USERNAME', $UserName)
    $dReader = [System.Xml.XmlNodeReader]::new($dialogXaml)
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
    try { $noExpireChk.IsChecked = ($null -eq $user.PasswordExpires) } catch { $noExpireChk.IsChecked = $false }
    $enabledChk.IsChecked = $user.Enabled
    if ($isAdminNow) { $roleAdminRadio.IsChecked = $true } else { $roleUserRadio.IsChecked = $true }
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
    [xml]$dialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Новый пользователь" Width="440" Height="620"
        WindowStartupLocation="CenterScreen" Background="#12121f" ResizeMode="NoResize">
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
            <Setter Property="Background" Value="#2a2a42"/>
            <Setter Property="Foreground" Value="#c0c0dd"/>
        </Style>
        <Style x:Key="DlgTextBox" TargetType="TextBox">
            <Setter Property="Background" Value="#1a1a2e"/>
            <Setter Property="Foreground" Value="#e0e0ff"/>
            <Setter Property="BorderBrush" Value="#2a2a45"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="CaretBrush" Value="#6c63ff"/>
        </Style>
        <Style x:Key="DlgPasswordBox" TargetType="PasswordBox">
            <Setter Property="Background" Value="#1a1a2e"/>
            <Setter Property="Foreground" Value="#e0e0ff"/>
            <Setter Property="BorderBrush" Value="#2a2a45"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="CaretBrush" Value="#6c63ff"/>
        </Style>
    </Window.Resources>
    <StackPanel Margin="22">
        <TextBlock Text="➕ Новый пользователь" Foreground="White" FontSize="15" FontWeight="Bold" Margin="0,0,0,16"/>
        <Border Background="#1a1a2e" CornerRadius="8" Padding="14,12" Margin="0,0,0,10">
            <StackPanel>
                <TextBlock Text="👤 Имя пользователя" Foreground="#c0c0e0" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,8"/>
                <TextBox x:Name="NewUserNameBox" Style="{StaticResource DlgTextBox}"/>
                <TextBlock Text="Описание (необязательно)" Foreground="#9898c8" FontSize="10" Margin="0,8,0,4"/>
                <TextBox x:Name="NewUserDescBox" Style="{StaticResource DlgTextBox}"/>
            </StackPanel>
        </Border>
        <Border Background="#1a1a2e" CornerRadius="8" Padding="14,12" Margin="0,0,0,10">
            <StackPanel>
                <TextBlock Text="🔑 Пароль" Foreground="#c0c0e0" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,8"/>
                <PasswordBox x:Name="NewUserPasswordBox" Style="{StaticResource DlgPasswordBox}" Margin="0,0,0,8"/>
                <TextBlock Text="Подтверждение пароля" Foreground="#9898c8" FontSize="10" Margin="0,0,0,4"/>
                <PasswordBox x:Name="NewUserConfirmBox" Style="{StaticResource DlgPasswordBox}"/>
            </StackPanel>
        </Border>
        <Border Background="#1a1a2e" CornerRadius="8" Padding="14,12" Margin="0,0,0,10">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel>
                    <TextBlock Text="♾️ Пароль без срока действия" Foreground="#c0c0e0" FontSize="12" FontWeight="SemiBold"/>
                    <TextBlock Text="Отключает обязательную смену пароля по истечении срока" Foreground="#9898c8" FontSize="10" Margin="0,3,0,0" TextWrapping="Wrap" MaxWidth="240"/>
                </StackPanel>
                <CheckBox x:Name="NewUserNoExpireChk" Grid.Column="1" VerticalAlignment="Center" IsChecked="True"/>
            </Grid>
        </Border>
        <Border Background="#1a1a2e" CornerRadius="8" Padding="14,12" Margin="0,0,0,16">
            <StackPanel>
                <TextBlock Text="👑 Роль учётной записи" Foreground="#c0c0e0" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,8"/>
                <StackPanel Orientation="Horizontal">
                    <RadioButton x:Name="NewUserRoleAdminRadio" Content="Администратор" GroupName="NewRole" Foreground="#c0c0e0" FontSize="12" Margin="0,0,20,0"/>
                    <RadioButton x:Name="NewUserRoleUserRadio" Content="Пользователь" GroupName="NewRole" Foreground="#c0c0e0" FontSize="12" IsChecked="True"/>
                </StackPanel>
            </StackPanel>
        </Border>
        <TextBlock x:Name="CreateUserStatusText" Foreground="#9898c8" FontSize="11" Margin="0,0,0,10" TextWrapping="Wrap"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Content="Отмена" x:Name="CancelCreateUserBtn" Style="{StaticResource DlgBtnSecondary}" Margin="0,0,8,0"/>
            <Button Content="➕ Создать пользователя" x:Name="ConfirmCreateUserBtn" Style="{StaticResource DlgBtn}"/>
        </StackPanel>
    </StackPanel>
</Window>
'@
    $dReader = [System.Xml.XmlNodeReader]::new($dialogXaml)
    $dlg = [Windows.Markup.XamlReader]::Load($dReader)
    $newUserNameBox        = $dlg.FindName("NewUserNameBox")
    $newUserDescBox        = $dlg.FindName("NewUserDescBox")
    $newUserPasswordBox    = $dlg.FindName("NewUserPasswordBox")
    $newUserConfirmBox     = $dlg.FindName("NewUserConfirmBox")
    $newUserNoExpireChk    = $dlg.FindName("NewUserNoExpireChk")
    $newUserRoleAdminRadio = $dlg.FindName("NewUserRoleAdminRadio")
    $newUserRoleUserRadio  = $dlg.FindName("NewUserRoleUserRadio")
    $createUserStatusText  = $dlg.FindName("CreateUserStatusText")
    $cancelCreateUserBtn   = $dlg.FindName("CancelCreateUserBtn")
    $confirmCreateUserBtn  = $dlg.FindName("ConfirmCreateUserBtn")
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
                Name                 = $name
                Password             = $secure
                PasswordNeverExpires = [bool]$newUserNoExpireChk.IsChecked
                AccountNeverExpires  = $true
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
