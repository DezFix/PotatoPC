[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PotatoPC Optimizer" Height="780" Width="1100"
        MinHeight="600" MinWidth="900" WindowStartupLocation="CenterScreen" Background="#12121f">
    <Window.Resources>
        <Style x:Key="BtnPrimary" TargetType="Button">
            <Setter Property="Background" Value="#6c63ff"/>
            <Setter Property="Foreground" Value="#ffffff"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="8" Padding="12,7">
                            <ContentPresenter VerticalAlignment="Center" HorizontalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.85"/></Trigger>
                            <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.7"/></Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="BtnSecondary" TargetType="Button" BasedOn="{StaticResource BtnPrimary}">
            <Setter Property="Background" Value="#2a2a42"/><Setter Property="Foreground" Value="#c0c0dd"/>
        </Style>
        <Style x:Key="BtnGold" TargetType="Button" BasedOn="{StaticResource BtnPrimary}">
            <Setter Property="Background" Value="#d4a017"/>
        </Style>
        <Style x:Key="BtnDanger" TargetType="Button" BasedOn="{StaticResource BtnPrimary}">
            <Setter Property="Background" Value="#8b1a1a"/>
        </Style>
        <Style TargetType="TabItem">
            <Setter Property="Foreground" Value="#9090b0"/>
            <Setter Property="Background" Value="#1a1a2e"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="0"/>
            <Setter Property="Margin" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border x:Name="bd" Background="{TemplateBinding Background}" BorderThickness="0,0,0,3" BorderBrush="Transparent" Padding="14,10">
                            <ContentPresenter ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="bd" Property="BorderBrush" Value="#6c63ff"/>
                                <Setter TargetName="bd" Property="Background" Value="#1e1e35"/>
                                <Setter Property="Foreground" Value="#ffffff"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Foreground" Value="#d0d0f0"/>
                                <Setter TargetName="bd" Property="Background" Value="#1c1c30"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ScrollBar"><Setter Property="Width" Value="6"/><Setter Property="Background" Value="Transparent"/></Style>
    </Window.Resources>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="56"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="200"/>
        </Grid.RowDefinitions>
        <!-- ШАПКА -->
        <Border Grid.Row="0" Background="#16162a">
            <Border.Effect><DropShadowEffect Color="#000000" Opacity="0.4" BlurRadius="12" ShadowDepth="2" Direction="270"/></Border.Effect>
            <Grid Margin="20,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Text="🥔" FontSize="22" Foreground="#6c63ff" VerticalAlignment="Center" Margin="0,0,8,0"/>
                    <TextBlock Text="PotatoPC Optimizer" Foreground="#ffffff" FontSize="18" FontWeight="Bold" VerticalAlignment="Center"/>
                    <Border Background="#6c63ff" CornerRadius="4" Padding="5,2" Margin="8,0,0,0" VerticalAlignment="Center">
                        <TextBlock Text="v4.0" Foreground="#ffffff" FontSize="10" FontWeight="SemiBold"/>
                    </Border>
                </StackPanel>
                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                    <Button Content="🛠️ Панель инструментов" x:Name="ToolsBtn" Style="{StaticResource BtnSecondary}" Height="32" FontSize="11" Margin="0,0,6,0" Padding="10,0"/>
                    <Button Content="⚙️ Администрирование" x:Name="AdminBtn" Style="{StaticResource BtnSecondary}" Height="32" FontSize="11" Margin="0,0,12,0" Padding="10,0"/>
                    <Button Content="🛡️ Восстановление" x:Name="RestorePointBtn" Style="{StaticResource BtnSecondary}" Height="32" FontSize="12" Margin="0,0,12,0"/>
                    <TextBlock x:Name="HeaderOsText" Foreground="#9898c8" FontSize="11" VerticalAlignment="Center"/>
                </StackPanel>
            </Grid>
        </Border>
        <!-- ВКЛАДКИ -->
        <TabControl Grid.Row="1" x:Name="MainTabControl" Background="#12121f" BorderThickness="0">
            <!-- МОДУЛИ -->
            <TabItem>
                <TabItem.Header>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="🧩" FontSize="12" Margin="0,0,5,0" VerticalAlignment="Center"/>
                        <TextBlock Text="Модули" FontSize="12" VerticalAlignment="Center"/>
                    </StackPanel>
                </TabItem.Header>
                <Grid Background="#12121f">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <Border Grid.Row="0" Background="#1a1a2e" Padding="16,8">
                        <Grid>
                            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                            <Grid Grid.Row="0" Margin="0,0,0,8">
                                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                    <TextBlock Foreground="#b8b8e8" FontSize="11" VerticalAlignment="Center" Margin="0,0,10,0"><Run Text="📂 Папка: "/></TextBlock>
                                    <TextBlock x:Name="ScriptsFolderText" Foreground="#b0b0e0" FontSize="10" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" MaxWidth="500"/>
                                </StackPanel>
                                <StackPanel Grid.Column="1" Orientation="Horizontal">
                                    <Button Content="📂 Открыть" x:Name="OpenFolderBtn" Style="{StaticResource BtnSecondary}" Margin="0,0,6,0" Height="28" FontSize="11"/>
                                    <Button Content="🔄 Обновить" x:Name="RefreshBtn" Style="{StaticResource BtnSecondary}" Height="28" FontSize="11"/>
                                </StackPanel>
                            </Grid>
                            <Border Grid.Row="1" Background="#12121f" CornerRadius="6" BorderBrush="#2a2a45" BorderThickness="1">
                                <Grid>
                                    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                    <TextBlock Text="🔍" FontSize="13" Foreground="#8080b0" VerticalAlignment="Center" Margin="10,0,0,0"/>
                                    <TextBox x:Name="ScriptSearchBox" Grid.Column="1" Background="Transparent" Foreground="#c0c0e0" FontSize="12" BorderThickness="0" Padding="8,6" VerticalAlignment="Center" CaretBrush="#6c63ff"/>
                                    <TextBlock x:Name="ScriptSearchHint" Grid.Column="1" Text="Поиск по названию или описанию..." Foreground="#9898c8" FontSize="12" VerticalAlignment="Center" Margin="8,0,0,0" IsHitTestVisible="False"/>
                                    <Button x:Name="ScriptSearchClear" Grid.Column="2" Content="✕" Background="Transparent" Foreground="#8080b0" BorderThickness="0" FontSize="12" Cursor="Hand" Padding="8,4" Visibility="Collapsed"/>
                                </Grid>
                            </Border>
                        </Grid>
                    </Border>
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="0,0,4,0">
                        <StackPanel x:Name="ScriptsPanel" Margin="16,12,16,12"/>
                    </ScrollViewer>
                    <Border Grid.Row="2" Background="#16162a" Padding="12,10">
                        <Grid>
                            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock x:Name="SelectedCountText" Foreground="#b0b0e0" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,16,0"/>
                                <CheckBox x:Name="RebootAfterScriptsChk" VerticalAlignment="Center" Cursor="Hand">
                                    <CheckBox.Content><TextBlock Text="🔄 Перезагрузить после выполнения" Foreground="#b0b0e0" FontSize="11" VerticalAlignment="Center"/></CheckBox.Content>
                                </CheckBox>
                            </StackPanel>
                            <StackPanel Grid.Column="1" Orientation="Horizontal">
                                <Button Content="⭐ Рекомендованное" x:Name="SelectRecommendedBtn" Style="{StaticResource BtnGold}" Margin="0,0,5,0" Height="30" FontSize="11" Width="140"/>
                                <Button Content="✓ Все" x:Name="SelectAllBtn" Style="{StaticResource BtnSecondary}" Margin="0,0,5,0" Height="30" FontSize="11" Width="70"/>
                                <Button Content="✗ Снять" x:Name="DeselectAllBtn" Style="{StaticResource BtnSecondary}" Margin="0,0,10,0" Height="30" FontSize="11" Width="70"/>
                                <Button Content="▶ Запустить выбранные" x:Name="RunScriptsBtn" Style="{StaticResource BtnPrimary}" Height="30" FontSize="12" Padding="14,6"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                </Grid>
            </TabItem>
            <!-- АВТОЗАГРУЗКА -->
            <TabItem>
                <TabItem.Header>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="🚀" FontSize="12" Margin="0,0,5,0" VerticalAlignment="Center"/>
                        <TextBlock Text="Автозагрузка" FontSize="12" VerticalAlignment="Center"/>
                    </StackPanel>
                </TabItem.Header>
                <Grid Background="#12121f">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <!-- Панель фильтров + статистика -->
                    <Border Grid.Row="0" Background="#16162a" Padding="14,10">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <Button x:Name="StartupFilterAllBtn"  Content="📋 Все"              Height="28" FontSize="11" Margin="0,0,5,0" Style="{StaticResource BtnPrimary}"/>
                                <Button x:Name="StartupFilterAppBtn"  Content="📦 Приложения"       Height="28" FontSize="11" Margin="0,0,5,0" Style="{StaticResource BtnSecondary}"/>
                                <Button x:Name="StartupFilterTaskBtn" Content="🗓️ Задачи"           Height="28" FontSize="11" Style="{StaticResource BtnSecondary}"/>
                            </StackPanel>
                            <TextBlock x:Name="StartupCountText" Grid.Column="1"
                                       Foreground="#c0c0ee" FontSize="11" VerticalAlignment="Center"
                                       HorizontalAlignment="Center"/>
                            <Border Grid.Column="2" Background="#12121f" CornerRadius="6" BorderBrush="#2a2a45" BorderThickness="1" Width="220">
                                <Grid>
                                    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                    <TextBlock Text="🔍" FontSize="12" Foreground="#8080b0" VerticalAlignment="Center" Margin="8,0,0,0"/>
                                    <TextBox x:Name="StartupSearchBox" Grid.Column="1"
                                             Background="Transparent" Foreground="#c0c0e0" FontSize="11"
                                             BorderThickness="0" Padding="6,5" VerticalAlignment="Center"
                                             CaretBrush="#6c63ff"/>
                                    <TextBlock x:Name="StartupSearchHint" Grid.Column="1"
                                               Text="Поиск..." Foreground="#9898c8" FontSize="11"
                                               VerticalAlignment="Center" Margin="6,0,0,0" IsHitTestVisible="False"/>
                                    <Button x:Name="StartupSearchClear" Grid.Column="2" Content="✕"
                                            Background="Transparent" Foreground="#8080b0" BorderThickness="0"
                                            FontSize="11" Cursor="Hand" Padding="6,4" Visibility="Collapsed"/>
                                </Grid>
                            </Border>
                        </Grid>
                    </Border>
                    <!-- Заголовки колонок -->
                    <Border Grid.Row="1" Background="#0e0e1e" Padding="14,5,14,5">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="24"/>
                                <ColumnDefinition Width="28"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="110"/>
                                <ColumnDefinition Width="80"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="2" Text="ПРИЛОЖЕНИЕ" Foreground="#8888cc" FontSize="10" FontWeight="SemiBold" VerticalAlignment="Center"/>
                            <TextBlock Grid.Column="3" Text="ИСТОЧНИК"   Foreground="#8888cc" FontSize="10" FontWeight="SemiBold" VerticalAlignment="Center"/>
                            <TextBlock Grid.Column="4" Text="СТАТУС"     Foreground="#8888cc" FontSize="10" FontWeight="SemiBold" VerticalAlignment="Center" HorizontalAlignment="Center"/>
                        </Grid>
                    </Border>
                    <!-- Единый список -->
                    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" Padding="0,0,4,0">
                        <StackPanel x:Name="StartupAppsPanel" Margin="10,4,10,4"/>
                    </ScrollViewer>
                    <!-- Нижняя панель действий -->
                    <Border Grid.Row="3" Background="#16162a" Padding="14,10">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock x:Name="StartupSelectedText" Foreground="#b8b8e8" FontSize="11" VerticalAlignment="Center" Margin="0,0,16,0"/>
                                <Button Content="✓ Все" x:Name="SelectAllStartupBtn"    Style="{StaticResource BtnSecondary}" Height="28" Width="60"  FontSize="11" Margin="0,0,5,0"/>
                                <Button Content="✗ Снять" x:Name="DeselectAllStartupBtn" Style="{StaticResource BtnSecondary}" Height="28" Width="65"  FontSize="11"/>
                            </StackPanel>
                            <StackPanel Grid.Column="1" Orientation="Horizontal">
                                <Button Content="🔄 Обновить" x:Name="RefreshStartupBtn" Style="{StaticResource BtnSecondary}" Height="30" FontSize="11" Margin="0,0,8,0"/>
                                <Button Content="⏸ Отключить выбранные" x:Name="DisableStartupBtn" Style="{StaticResource BtnDanger}" Height="30" FontSize="11" Margin="0,0,6,0"/>
                                <Button Content="▶ Включить выбранные"  x:Name="EnableStartupBtn"  Style="{StaticResource BtnSecondary}" Height="30" FontSize="11"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                </Grid>
            </TabItem>
            <!-- ПОЛЬЗОВАТЕЛИ -->
            <TabItem>
                <TabItem.Header>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="👤" FontSize="12" Margin="0,0,5,0" VerticalAlignment="Center"/>
                        <TextBlock Text="Пользователи" FontSize="12" VerticalAlignment="Center"/>
                    </StackPanel>
                </TabItem.Header>
                <Grid Background="#12121f">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <Border Grid.Row="0" Background="#1a1a2e" Padding="14,8">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Foreground="#9898c8" FontSize="11" VerticalAlignment="Center"
                                       Text="👥 Локальные учётные записи Windows. Изменения требуют прав администратора."/>
                            <StackPanel Grid.Column="1" Orientation="Horizontal">
                                <Button Content="➕ Добавить пользователя" x:Name="AddUserBtn" Style="{StaticResource BtnPrimary}" Height="28" FontSize="11" Margin="0,0,8,0"/>
                                <Button Content="🔄 Обновить" x:Name="RefreshUsersBtn" Style="{StaticResource BtnSecondary}" Height="28" FontSize="11"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="0,0,4,0">
                        <StackPanel x:Name="UsersPanel" Margin="16,12,16,12"/>
                    </ScrollViewer>
                </Grid>
            </TabItem>
            <!-- ПРИЛОЖЕНИЯ -->
            <TabItem>
                <TabItem.Header>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="📦" FontSize="12" Margin="0,0,5,0" VerticalAlignment="Center"/>
                        <TextBlock Text="Приложения" FontSize="12" VerticalAlignment="Center"/>
                    </StackPanel>
                </TabItem.Header>
                <Grid Background="#12121f">
                    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                    <Border Grid.Row="0" Background="#1a1a2e" Padding="14,8">
                        <StackPanel>
                            <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                <TextBlock Foreground="#b8b8e8" FontSize="11" VerticalAlignment="Center" Margin="0,0,10,0"><Run Text="⚡ Пресеты:"/></TextBlock>
                                <Button Content="🏢 Офисный пакет" x:Name="PresetOfficeBtn" Style="{StaticResource BtnSecondary}" Margin="0,0,6,0" Height="28" FontSize="11"/>
                                <Button Content="🎮 Игровой пакет" x:Name="PresetGamesBtn" Style="{StaticResource BtnSecondary}" Height="28" FontSize="11"/>
                            </StackPanel>
                            <Border Background="#12121f" CornerRadius="6" BorderBrush="#2a2a45" BorderThickness="1">
                                <Grid>
                                    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                    <TextBlock Text="🔍" FontSize="13" Foreground="#8080b0" VerticalAlignment="Center" Margin="10,0,0,0"/>
                                    <TextBox x:Name="AppSearchBox" Grid.Column="1" Background="Transparent" Foreground="#c0c0e0" FontSize="12" BorderThickness="0" Padding="8,6" VerticalAlignment="Center" CaretBrush="#6c63ff"/>
                                    <TextBlock x:Name="AppSearchHint" Grid.Column="1" Text="Поиск по названию или описанию..." Foreground="#9898c8" FontSize="12" VerticalAlignment="Center" Margin="8,0,0,0" IsHitTestVisible="False"/>
                                    <Button x:Name="AppSearchClear" Grid.Column="2" Content="✕" Background="Transparent" Foreground="#8080b0" BorderThickness="0" FontSize="12" Cursor="Hand" Padding="8,4" Visibility="Collapsed"/>
                                </Grid>
                            </Border>
                        </StackPanel>
                    </Border>
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="0,0,4,0">
                        <StackPanel x:Name="AppsPanel" Margin="14,10,14,10"/>
                    </ScrollViewer>
                    <Border Grid.Row="2" Background="#16162a" Padding="12,10">
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                            <Button Content="✓ Все" x:Name="SelectAllAppsBtn" Style="{StaticResource BtnSecondary}" Margin="0,0,5,0" Height="30" Width="60" FontSize="11"/>
                            <Button Content="✗ Снять" x:Name="DeselectAllAppsBtn" Style="{StaticResource BtnSecondary}" Margin="0,0,10,0" Height="30" Width="65" FontSize="11"/>
                            <Button Content="📦 Установить выбранные" x:Name="InstallAppsBtn" Style="{StaticResource BtnPrimary}" Height="30" FontSize="12"/>
                        </StackPanel>
                    </Border>
                </Grid>
            </TabItem>
            <!-- ОБНОВЛЕНИЯ -->
            <TabItem>
                <TabItem.Header>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="🔄" FontSize="12" Margin="0,0,5,0" VerticalAlignment="Center"/>
                        <TextBlock Text="Обновления" FontSize="12" VerticalAlignment="Center"/>
                    </StackPanel>
                </TabItem.Header>
                <Grid Background="#12121f">
                    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                    <Border Grid.Row="0" Background="#1a1a2e" Padding="14,8">
                        <Grid>
                            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <TextBlock x:Name="UpdateStatusText" Foreground="#b8b8e8" FontSize="11" VerticalAlignment="Center" Text="Нажмите «Проверить обновления» для получения списка доступных обновлений."/>
                            <StackPanel Grid.Column="1" Orientation="Horizontal">
                                <Button Content="🔍 Проверить обновления" x:Name="CheckUpdatesBtn" Style="{StaticResource BtnSecondary}" Margin="0,0,6,0" Height="28" FontSize="11"/>
                                <Button Content="✓ Все" x:Name="SelectAllUpdatesBtn" Style="{StaticResource BtnSecondary}" Margin="0,0,6,0" Height="28" Width="55" FontSize="11"/>
                                <Button Content="✗ Снять" x:Name="DeselectAllUpdatesBtn" Style="{StaticResource BtnSecondary}" Height="28" Width="60" FontSize="11"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="0,0,4,0">
                        <StackPanel x:Name="UpdatesPanel" Margin="14,10,14,10">
                            <TextBlock Foreground="#c0c0ee" FontSize="12" TextAlignment="Center" Margin="0,60,0,0" Text="📋 Список обновлений появится после нажатия «Проверить обновления»"/>
                        </StackPanel>
                    </ScrollViewer>
                    <Border Grid.Row="2" Background="#16162a" Padding="12,10">
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                            <TextBlock x:Name="UpdateCountText" Foreground="#b0b0e0" FontSize="11" VerticalAlignment="Center" Margin="0,0,12,0"/>
                            <Button Content="⬆ Обновить выбранные" x:Name="InstallUpdatesBtn" Style="{StaticResource BtnPrimary}" Height="30" FontSize="12"/>
                        </StackPanel>
                    </Border>
                </Grid>
            </TabItem>
            <!-- ТЕСТ СИСТЕМЫ -->
            <TabItem>
                <TabItem.Header>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="🔬" FontSize="12" Margin="0,0,5,0" VerticalAlignment="Center"/>
                        <TextBlock Text="Тест системы" FontSize="12" VerticalAlignment="Center"/>
                    </StackPanel>
                </TabItem.Header>
                <Grid Background="#12121f">
                    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                    <Border Grid.Row="0" Background="#1a1a2e" Padding="14,8">
                        <TextBlock Foreground="#b8b8e8" FontSize="11" VerticalAlignment="Center"
                                   Text="⚠ Тесты запускаются в фоне — UI не блокируется. Результаты отображаются в консоли."/>
                    </Border>
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                        <StackPanel x:Name="DiagPanel" Margin="16,14,16,14"/>
                    </ScrollViewer>
                </Grid>
            </TabItem>
            <!-- О СИСТЕМЕ -->
            <TabItem>
                <TabItem.Header>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="💻" FontSize="12" Margin="0,0,5,0" VerticalAlignment="Center"/>
                        <TextBlock Text="О системе" FontSize="12" VerticalAlignment="Center"/>
                    </StackPanel>
                </TabItem.Header>
                <ScrollViewer Background="#12121f" VerticalScrollBarVisibility="Auto">
                    <StackPanel x:Name="SysPanel" Margin="24,20"/>
                </ScrollViewer>
            </TabItem>
        </TabControl>
        <!-- ЛОГ -->
        <Grid Grid.Row="2">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="220"/></Grid.ColumnDefinitions>
            <Border Background="#0c0c18" BorderBrush="#1e1e38" BorderThickness="0,1,0,0">
                <Grid>
                    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                    <Border Background="#12122a" Padding="10,5">
                        <TextBlock Text="  КОНСОЛЬ" Foreground="#9898c8" FontSize="10" FontWeight="SemiBold" FontFamily="Consolas" VerticalAlignment="Center"/>
                    </Border>
                    <TextBox x:Name="LogOutput" Grid.Row="1" Background="#0c0c18" Foreground="#50e050" FontFamily="Consolas" FontSize="12"
                             BorderThickness="0" Padding="10,6" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" AcceptsReturn="True"/>
                </Grid>
            </Border>
            <Border Grid.Column="1" Background="#16162a" BorderBrush="#1e1e38" BorderThickness="1,1,0,0" Padding="14,14">
                <StackPanel VerticalAlignment="Top">
                    <TextBlock Text="КОНСОЛЬ" Foreground="#9898c8" FontSize="10" FontWeight="SemiBold" Margin="0,0,0,12"/>
                    <Button Content="🗑️ Очистить лог" x:Name="ClearLogBtn" Style="{StaticResource BtnSecondary}" Height="34" Margin="0,0,0,8" FontSize="12"/>
                    <Button Content="📋 Копировать лог" x:Name="CopyLogBtn" Style="{StaticResource BtnSecondary}" Height="34" Margin="0,0,0,16" FontSize="12"/>
                </StackPanel>
            </Border>
        </Grid>
    </Grid>
</Window>
'@
