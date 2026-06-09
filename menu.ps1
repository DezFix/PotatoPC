#Requires -RunAsAdministrator
<#
.SYNOPSIS
PotatoPC Optimizer - Modular Edition
.DESCRIPTION
Запуск: irm https://raw.githubusercontent.com/DezFix/PotatoPC/main/potatopc.ps1 | iex
Модульная система: скрипты и конфигурации загружаются из GitHub в папку %TEMP%\PotatoPC
#>

# ═══ Проверка прав администратора ═══
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Требуются права администратора. Перезапуск..." -ForegroundColor Yellow
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# ═══ Настройка рабочих папок (Temp) ═══
$script:WorkFolder    = Join-Path $env:TEMP "PotatoPC"
$script:ScriptsFolder = Join-Path $script:WorkFolder "scripts"
$script:AppsJsonPath  = Join-Path $script:WorkFolder "apps.json"

# URL вашего репозитория GitHub
$script:RepoZipUrl = "https://github.com/DezFix/PotatoPC/archive/refs/heads/main.zip"
$script:AppsJsonUrl = "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/apps.json"

# ═══ Инициализация и загрузка с GitHub ═══
function Initialize-PotatoPC {
    Write-Log "Инициализация рабочей среды..."

    # Создаём рабочую папку если нет
    if (-not (Test-Path $script:WorkFolder)) {
        New-Item -ItemType Directory -Path $script:WorkFolder -Force | Out-Null
    }

    # Скачиваем архив репозитория — внутри уже есть и scripts/ и apps.json
    $zipPath = Join-Path $script:WorkFolder "repo.zip"
    try {
        Write-Log "Загрузка репозитория с GitHub..."
        Invoke-WebRequest -Uri $script:RepoZipUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop

        # Распаковываем прямо в WorkFolder (перезаписываем)
        Expand-Archive -Path $zipPath -DestinationPath $script:WorkFolder -Force
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

        # Находим распакованную папку репозитория (PotatoPC-main)
        $repoFolder = Get-ChildItem -Path $script:WorkFolder -Filter "*-main" -Directory |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1

        if ($repoFolder) {
            # Используем scripts и apps.json прямо из папки репозитория — никаких лишних копирований
            $script:ScriptsFolder = Join-Path $repoFolder.FullName "scripts"
            $script:AppsJsonPath  = Join-Path $repoFolder.FullName "apps.json"

            $scriptCount = @(Get-ChildItem -Path $script:ScriptsFolder -Filter "*.ps1" -ErrorAction SilentlyContinue).Count
            Write-Log "✓ Репозиторий загружен. Скриптов: $scriptCount, apps.json: $(Test-Path $script:AppsJsonPath)"
        } else {
            Write-Log "✗ Не удалось найти папку репозитория после распаковки." -Color "Red"
        }
    } catch {
        Write-Log "✗ Ошибка загрузки репозитория: $_" -Color "Red"
        Write-Log "  Проверьте интернет-соединение или добавьте скрипты вручную в:" -Color "Yellow"
        Write-Log "  $($script:ScriptsFolder)" -Color "Yellow"
    }
}

# ═══ Загрузка метаданных скриптов ═══
function Load-Scripts {
    $result = @()
    $files = Get-ChildItem -Path $script:ScriptsFolder -Filter "*.ps1" -ErrorAction SilentlyContinue | Sort-Object Name
    foreach ($file in $files) {
        $meta = @{ Name = $file.BaseName; Desc = ""; Category = "Другое"; Icon = "📄"; Recommended = $false; Path = $file.FullName }
        $lines = Get-Content $file.FullName -TotalCount 15 -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            if ($line -match "^#\s*NAME:\s*(.+)")     { $meta.Name     = $Matches[1].Trim() }
            if ($line -match "^#\s*DESC:\s*(.+)")     { $meta.Desc     = $Matches[1].Trim() }
            if ($line -match "^#\s*CATEGORY:\s*(.+)") { $meta.Category = $Matches[1].Trim() }
            if ($line -match "^#\s*ICON:\s*(.+)")     { $meta.Icon     = $Matches[1].Trim() }
            if ($line -match "^#\s*RECOMMENDED:\s*true") { $meta.Recommended = $true }
        }
        $result += $meta
    }
    return $result
}

# ═══ Системная информация ═══
function Get-SystemInfo {
    try {
        $os   = Get-WmiObject Win32_OperatingSystem
        $cpu  = (Get-WmiObject Win32_Processor).Name
        $ramB = (Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory
        $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
        return @{
            OS    = "$($os.Caption) Build $($os.BuildNumber)"
            CPU   = $cpu.Trim()
            RAM   = "$([math]::Round($ramB/1GB,1)) ГБ"
            Disk  = "C: $([math]::Round($disk.FreeSpace/1GB,1)) ГБ своб. / $([math]::Round($disk.Size/1GB,1)) ГБ"
            Uptime= ((Get-Date) - $os.ConvertToDateTime($os.LastBootUpTime)) | ForEach-Object { "$($_.Days)д $($_.Hours)ч $($_.Minutes)м" }
        }
    } catch { 
        return @{ OS="Неизвестно"; CPU="Неизвестно"; RAM="Неизвестно"; Disk="Неизвестно"; Uptime="Неизвестно" } 
    }
}

# ═══ Точка восстановления ═══
function Create-RestorePoint {
    Write-Log "Создание точки восстановления системы..."
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "PotatoPC Optimizer Backup" -RestorePointType "MODIFY_SETTINGS"
        Write-Log "✓ Точка восстановления успешно создана!" -Color "Green"
        return $true
    } catch {
        Write-Log "✗ Ошибка создания точки восстановления: $_" -Color "Red"
        return $false
    }
}

# ═══ Логирование ═══
$script:LogBox = $null
function Write-Log($msg, $color = "Default") {
    $time = (Get-Date).ToString("HH:mm:ss")
    $line = "[$time] $msg"
    if ($script:LogBox) {
        $script:LogBox.Dispatcher.Invoke([action]{
            $script:LogBox.AppendText("$line`n")
            $script:LogBox.ScrollToEnd()
        })
    }
    # Цветной вывод в консоль PowerShell (если запущен не только через GUI)
    $consoleColor = switch ($color) { "Green" { "Green" } "Red" { "Red" } "Yellow" { "Yellow" } default { "White" } }
    Write-Host $line -ForegroundColor $consoleColor
}

# ═══ XAML Интерфейс ═══
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
            <Setter Property="Background" Value="#2a2a42"/>
            <Setter Property="Foreground" Value="#c0c0dd"/>
        </Style>
        <Style x:Key="BtnDanger" TargetType="Button" BasedOn="{StaticResource BtnPrimary}">
            <Setter Property="Background" Value="#8b1a1a"/>
        </Style>
        <Style x:Key="BtnGold" TargetType="Button" BasedOn="{StaticResource BtnPrimary}">
            <Setter Property="Background" Value="#d4a017"/>
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
        <Style TargetType="ScrollBar">
            <Setter Property="Width" Value="6"/>
            <Setter Property="Background" Value="Transparent"/>
        </Style>
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
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Text="🥔" FontSize="22" Foreground="#6c63ff" VerticalAlignment="Center" Margin="0,0,8,0"/>
                    <TextBlock Text="PotatoPC Optimizer" Foreground="#ffffff" FontSize="18" FontWeight="Bold" VerticalAlignment="Center"/>
                    <Border Background="#6c63ff" CornerRadius="4" Padding="5,2" Margin="8,0,0,0" VerticalAlignment="Center">
                        <TextBlock Text="v3.0" Foreground="#ffffff" FontSize="10" FontWeight="SemiBold"/>
                    </Border>
                </StackPanel>
                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                    <Button Content="🛡️ Создать точку восстановления" x:Name="RestorePointBtn" Style="{StaticResource BtnSecondary}" Height="32" FontSize="12" Margin="0,0,12,0"/>
                    <TextBlock x:Name="HeaderOsText" Foreground="#7070a0" FontSize="11" VerticalAlignment="Center"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- ВКЛАДКИ -->
        <TabControl Grid.Row="1" x:Name="MainTabControl" Background="#12121f" BorderThickness="0">
            <!-- ВКЛАДКА: СКРИПТЫ -->
            <TabItem>
                <TabItem.Header>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="🧩" FontSize="12" Margin="0,0,5,0" VerticalAlignment="Center"/>
                        <TextBlock Text="Модули" FontSize="12" VerticalAlignment="Center"/>
                    </StackPanel>
                </TabItem.Header>
                <Grid Background="#12121f">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <Border Grid.Row="0" Background="#1a1a2e" Padding="16,8">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <!-- Строка 1: Папка + кнопки -->
                            <Grid Grid.Row="0" Margin="0,0,0,8">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                    <TextBlock Foreground="#6060a0" FontSize="11" VerticalAlignment="Center" Margin="0,0,10,0">
                                        <Run Text="📂 Папка: "/>
                                    </TextBlock>
                                    <TextBlock x:Name="ScriptsFolderText" Foreground="#8080c0" FontSize="10" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" MaxWidth="500"/>
                                </StackPanel>
                                <StackPanel Grid.Column="1" Orientation="Horizontal">
                                    <Button Content="📂 Открыть" x:Name="OpenFolderBtn" Style="{StaticResource BtnSecondary}" Margin="0,0,6,0" Height="28" FontSize="11"/>
                                    <Button Content="🔄 Обновить" x:Name="RefreshBtn" Style="{StaticResource BtnSecondary}" Height="28" FontSize="11"/>
                                </StackPanel>
                            </Grid>
                            <!-- Строка 2: Поиск -->
                            <Border Grid.Row="1" Background="#12121f" CornerRadius="6" BorderBrush="#2a2a45" BorderThickness="1">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Text="🔍" FontSize="13" Foreground="#505070" VerticalAlignment="Center" Margin="10,0,0,0"/>
                                    <TextBox x:Name="ScriptSearchBox" Grid.Column="1"
                                             Background="Transparent" Foreground="#c0c0e0" FontSize="12"
                                             BorderThickness="0" Padding="8,6" VerticalAlignment="Center"
                                             CaretBrush="#6c63ff"/>
                                    <TextBlock x:Name="ScriptSearchHint" Grid.Column="1"
                                               Text="Поиск по названию или описанию..."
                                               Foreground="#404060" FontSize="12" VerticalAlignment="Center"
                                               Margin="8,0,0,0" IsHitTestVisible="False"/>
                                    <Button x:Name="ScriptSearchClear" Grid.Column="2" Content="✕"
                                            Background="Transparent" Foreground="#505070" BorderThickness="0"
                                            FontSize="12" Cursor="Hand" Padding="8,4" Visibility="Collapsed"/>
                                </Grid>
                            </Border>
                        </Grid>
                    </Border>
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="0,0,4,0">
                        <StackPanel x:Name="ScriptsPanel" Margin="16,12,16,12"/>
                    </ScrollViewer>
                    <Border Grid.Row="2" Background="#16162a" Padding="12,10">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock x:Name="SelectedCountText" Foreground="#8080c0" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,16,0"/>
                                <CheckBox x:Name="RebootAfterScriptsChk" VerticalAlignment="Center" Cursor="Hand">
                                    <CheckBox.Content>
                                        <TextBlock Text="🔄 Перезагрузить после выполнения" Foreground="#8080c0" FontSize="11" VerticalAlignment="Center"/>
                                    </CheckBox.Content>
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

            <!-- ВКЛАДКА: ПРИЛОЖЕНИЯ -->
            <TabItem>
                <TabItem.Header>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="📦" FontSize="12" Margin="0,0,5,0" VerticalAlignment="Center"/>
                        <TextBlock Text="Приложения" FontSize="12" VerticalAlignment="Center"/>
                    </StackPanel>
                </TabItem.Header>
                <Grid Background="#12121f">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    
                    <!-- Панель пресетов + поиск -->
                    <Border Grid.Row="0" Background="#1a1a2e" Padding="14,8">
                        <StackPanel>
                            <!-- Пресеты -->
                            <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                <TextBlock Foreground="#6060a0" FontSize="11" VerticalAlignment="Center" Margin="0,0,10,0">
                                    <Run Text="⚡ Пресеты:"/>
                                </TextBlock>
                                <Button Content="🏢 Офисный пакет" x:Name="PresetOfficeBtn" Style="{StaticResource BtnSecondary}" Margin="0,0,6,0" Height="28" FontSize="11"/>
                                <Button Content="🎮 Игровой пакет" x:Name="PresetGamesBtn" Style="{StaticResource BtnSecondary}" Height="28" FontSize="11"/>
                            </StackPanel>
                            <!-- Поиск -->
                            <Border Background="#12121f" CornerRadius="6" BorderBrush="#2a2a45" BorderThickness="1">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Text="🔍" FontSize="13" Foreground="#505070" VerticalAlignment="Center" Margin="10,0,0,0"/>
                                    <TextBox x:Name="AppSearchBox" Grid.Column="1"
                                             Background="Transparent" Foreground="#c0c0e0" FontSize="12"
                                             BorderThickness="0" Padding="8,6" VerticalAlignment="Center"
                                             CaretBrush="#6c63ff"/>
                                    <TextBlock x:Name="AppSearchHint" Grid.Column="1"
                                               Text="Поиск по названию или описанию..."
                                               Foreground="#404060" FontSize="12" VerticalAlignment="Center"
                                               Margin="8,0,0,0" IsHitTestVisible="False"/>
                                    <Button x:Name="AppSearchClear" Grid.Column="2" Content="✕"
                                            Background="Transparent" Foreground="#505070" BorderThickness="0"
                                            FontSize="12" Cursor="Hand" Padding="8,4" Visibility="Collapsed"/>
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

            <!-- ВКЛАДКА: ОБНОВЛЕНИЯ -->
            <TabItem>
                <TabItem.Header>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="🔄" FontSize="12" Margin="0,0,5,0" VerticalAlignment="Center"/>
                        <TextBlock Text="Обновления" FontSize="12" VerticalAlignment="Center"/>
                    </StackPanel>
                </TabItem.Header>
                <Grid Background="#12121f">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <!-- Toolbar -->
                    <Border Grid.Row="0" Background="#1a1a2e" Padding="14,8">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock x:Name="UpdateStatusText" Foreground="#6060a0" FontSize="11" VerticalAlignment="Center"
                                       Text="Нажмите «Проверить обновления» для получения списка доступных обновлений."/>
                            <StackPanel Grid.Column="1" Orientation="Horizontal">
                                <Button Content="🔍 Проверить обновления" x:Name="CheckUpdatesBtn" Style="{StaticResource BtnSecondary}" Margin="0,0,6,0" Height="28" FontSize="11"/>
                                <Button Content="✓ Все" x:Name="SelectAllUpdatesBtn" Style="{StaticResource BtnSecondary}" Margin="0,0,6,0" Height="28" Width="55" FontSize="11"/>
                                <Button Content="✗ Снять" x:Name="DeselectAllUpdatesBtn" Style="{StaticResource BtnSecondary}" Height="28" Width="60" FontSize="11"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- Список обновлений -->
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="0,0,4,0">
                        <StackPanel x:Name="UpdatesPanel" Margin="14,10,14,10">
                            <TextBlock Foreground="#50507a" FontSize="12" TextAlignment="Center" Margin="0,60,0,0"
                                       Text="📋 Список обновлений появится после нажатия «Проверить обновления»"/>
                        </StackPanel>
                    </ScrollViewer>

                    <!-- Нижняя панель -->
                    <Border Grid.Row="2" Background="#16162a" Padding="12,10">
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                            <TextBlock x:Name="UpdateCountText" Foreground="#8080c0" FontSize="11" VerticalAlignment="Center" Margin="0,0,12,0"/>
                            <Button Content="⬆ Обновить выбранные" x:Name="InstallUpdatesBtn" Style="{StaticResource BtnPrimary}" Height="30" FontSize="12"/>
                        </StackPanel>
                    </Border>
                </Grid>
            </TabItem>

            <!-- ВКЛАДКА: ТЕСТ СИСТЕМЫ -->
            <TabItem>
                <TabItem.Header>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="🔬" FontSize="12" Margin="0,0,5,0" VerticalAlignment="Center"/>
                        <TextBlock Text="Тест системы" FontSize="12" VerticalAlignment="Center"/>
                    </StackPanel>
                </TabItem.Header>
                <Grid Background="#12121f">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row="0" Background="#1a1a2e" Padding="14,8">
                        <TextBlock Foreground="#6060a0" FontSize="11" VerticalAlignment="Center"
                                   Text="⚠ Некоторые тесты требуют перезагрузки или длительного ожидания. Результаты отображаются в консоли."/>
                    </Border>

                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                        <StackPanel x:Name="DiagPanel" Margin="16,14,16,14"/>
                    </ScrollViewer>
                </Grid>
            </TabItem>

            <!-- ВКЛАДКА: О СИСТЕМЕ -->
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

        <!-- НИЖНЯЯ ПАНЕЛЬ: ЛОГ + КНОПКИ -->
        <Grid Grid.Row="2">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="220"/>
            </Grid.ColumnDefinitions>
            <Border Background="#0c0c18" BorderBrush="#1e1e38" BorderThickness="0,1,0,0">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <Border Background="#12122a" Padding="10,5">
                        <TextBlock Text="  КОНСОЛЬ" Foreground="#404060" FontSize="10" FontWeight="SemiBold" FontFamily="Consolas" VerticalAlignment="Center"/>
                    </Border>
                    <TextBox x:Name="LogOutput" Grid.Row="1" Background="#0c0c18" Foreground="#50e050" FontFamily="Consolas" FontSize="12"
                             BorderThickness="0" Padding="10,6" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" AcceptsReturn="True"/>
                </Grid>
            </Border>
            <Border Grid.Column="1" Background="#16162a" BorderBrush="#1e1e38" BorderThickness="1,1,0,0" Padding="14,14">
                <StackPanel VerticalAlignment="Top">
                    <TextBlock Text="КОНСОЛЬ" Foreground="#404060" FontSize="10" FontWeight="SemiBold" Margin="0,0,0,12"/>
                    <Button Content="🗑️ Очистить лог" x:Name="ClearLogBtn" Style="{StaticResource BtnSecondary}" Height="34" Margin="0,0,0,8" FontSize="12"/>
                    <Button Content="📋 Копировать лог" x:Name="CopyLogBtn" Style="{StaticResource BtnSecondary}" Height="34" Margin="0,0,0,16" FontSize="12"/>

                </StackPanel>
            </Border>
        </Grid>
    </Grid>
</Window>
'@

# ═══ Загрузка XAML и привязка контролов ═══
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$script:LogBox          = $window.FindName("LogOutput")
$scriptsPanel           = $window.FindName("ScriptsPanel")
$appsPanel              = $window.FindName("AppsPanel")
$sysPanel               = $window.FindName("SysPanel")
$updatesPanel           = $window.FindName("UpdatesPanel")
$diagPanel              = $window.FindName("DiagPanel")
$headerOsText           = $window.FindName("HeaderOsText")
$scriptsFolderText      = $window.FindName("ScriptsFolderText")
$selectedCountText      = $window.FindName("SelectedCountText")
$runScriptsBtn          = $window.FindName("RunScriptsBtn")
$rebootAfterChk         = $window.FindName("RebootAfterScriptsChk")
$selectAllBtn           = $window.FindName("SelectAllBtn")
$deselectAllBtn         = $window.FindName("DeselectAllBtn")
$refreshBtn             = $window.FindName("RefreshBtn")
$openFolderBtn          = $window.FindName("OpenFolderBtn")
$clearLogBtn            = $window.FindName("ClearLogBtn")
$copyLogBtn             = $window.FindName("CopyLogBtn")
$installAppsBtn         = $window.FindName("InstallAppsBtn")
$selectAllAppsBtn       = $window.FindName("SelectAllAppsBtn")
$deselectAllAppsBtn     = $window.FindName("DeselectAllAppsBtn")
$restorePointBtn        = $window.FindName("RestorePointBtn")
$presetOfficeBtn        = $window.FindName("PresetOfficeBtn")
$presetGamesBtn         = $window.FindName("PresetGamesBtn")
$selectRecommendedBtn   = $window.FindName("SelectRecommendedBtn")
$checkUpdatesBtn        = $window.FindName("CheckUpdatesBtn")
$selectAllUpdatesBtn    = $window.FindName("SelectAllUpdatesBtn")
$deselectAllUpdatesBtn  = $window.FindName("DeselectAllUpdatesBtn")
$installUpdatesBtn      = $window.FindName("InstallUpdatesBtn")
$updateStatusText       = $window.FindName("UpdateStatusText")
$updateCountText        = $window.FindName("UpdateCountText")

# ═══ Логика интерфейса ═══
$script:ScriptCheckboxes = @{}

function Update-SelectedCount {
    $count = ($script:ScriptCheckboxes.Values | Where-Object { $_.IsChecked }).Count
    $total = $script:ScriptCheckboxes.Count
    $selectedCountText.Text = "Выбрано: $count из $total скриптов"
}

function Build-ScriptsPanel {
    $scriptsPanel.Children.Clear()
    $script:ScriptCheckboxes.Clear()
    $scripts = Load-Scripts
    
    if ($scripts.Count -eq 0) {
        $empty = [System.Windows.Controls.TextBlock]::new()
        $empty.Text = "📂 Папка скриптов пуста.`n`nПроверьте подключение к интернету и корректность URL репозитория в скрипте.`nПапка: $($script:ScriptsFolder)"
        $empty.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#505070")
        $empty.FontSize = 13; $empty.TextAlignment = "Center"; $empty.Margin = "0,60,0,0"; $empty.FontFamily = [Windows.Media.FontFamily]::new("Consolas")
        $scriptsPanel.Children.Add($empty) | Out-Null
        Update-SelectedCount
        return
    }

    $grouped = $scripts | Group-Object { $_.Category } | Sort-Object Name

    foreach ($group in $grouped) {
        $catBorder = [System.Windows.Controls.Border]::new()
        $catBorder.Margin = [System.Windows.Thickness]::new(0, 16, 0, 6)
        $catBorder.Padding = [System.Windows.Thickness]::new(0, 0, 0, 6)
        $catBorder.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#1e1e38")
        $catBorder.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
        $catText = [System.Windows.Controls.TextBlock]::new()
        $catText.Text = $group.Name.ToUpper() 
        $catText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#6c63ff")
        $catText.FontSize = 11; $catText.FontWeight = "SemiBold"
        $catBorder.Child = $catText
        $scriptsPanel.Children.Add($catBorder) | Out-Null

        foreach ($script_item in $group.Group) {
            $card = [System.Windows.Controls.Border]::new()
            $card.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e")
            $card.CornerRadius = [System.Windows.CornerRadius]::new(8)
            $card.Margin = [System.Windows.Thickness]::new(0, 3, 0, 3)
            $card.Padding = [System.Windows.Thickness]::new(14, 10, 14, 10)
            
            # Золотая рамка для рекомендованных
            if ($script_item.Recommended) {
                $card.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#d4a017")
                $card.BorderThickness = [System.Windows.Thickness]::new(0,0,3,0)
            }

            $grid = [System.Windows.Controls.Grid]::new()
            $col1 = [System.Windows.Controls.ColumnDefinition]::new(); $col1.Width = [System.Windows.GridLength]::new(32)
            $col2 = [System.Windows.Controls.ColumnDefinition]::new(); $col2.Width = [System.Windows.GridLength]::Auto
            $col3 = [System.Windows.Controls.ColumnDefinition]::new(); $col3.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $col4 = [System.Windows.Controls.ColumnDefinition]::new(); $col4.Width = [System.Windows.GridLength]::Auto
            $grid.ColumnDefinitions.Add($col1); $grid.ColumnDefinitions.Add($col2)
            $grid.ColumnDefinitions.Add($col3); $grid.ColumnDefinitions.Add($col4)

            $cb = [System.Windows.Controls.CheckBox]::new()
            $cb.VerticalAlignment = "Center"
            $cb.Tag = $script_item.Path
            $cb.Add_Checked({ Update-SelectedCount })
            $cb.Add_Unchecked({ Update-SelectedCount })
            [System.Windows.Controls.Grid]::SetColumn($cb, 0)
            $script:ScriptCheckboxes[$script_item.Path] = $cb

            $icon = [System.Windows.Controls.TextBlock]::new()
            $icon.Text = $script_item.Icon
            $icon.FontSize = 18; $icon.VerticalAlignment = "Center"; $icon.Margin = [System.Windows.Thickness]::new(0, 0, 12, 0)
            [System.Windows.Controls.Grid]::SetColumn($icon, 1)

            $textStack = [System.Windows.Controls.StackPanel]::new()
            $textStack.VerticalAlignment = "Center"

            $nameText = [System.Windows.Controls.TextBlock]::new()
            $nameText.Text = $script_item.Name
            $nameText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#e0e0f4")
            $nameText.FontSize = 13; $nameText.FontWeight = "Medium"
            
            # Золотой цвет для рекомендованных
            if ($script_item.Recommended) {
                $nameText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#d4a017")
            }

            $descText = [System.Windows.Controls.TextBlock]::new()
            $descText.Text = if ($script_item.Desc) { $script_item.Desc } else { $script_item.Path | Split-Path -Leaf }
            $descText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#50507a")
            $descText.FontSize = 11; $descText.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
            $descText.TextTrimming = "CharacterEllipsis"

            $textStack.Children.Add($nameText) | Out-Null
            $textStack.Children.Add($descText) | Out-Null
            [System.Windows.Controls.Grid]::SetColumn($textStack, 2)

            $runOneBtn = [System.Windows.Controls.Button]::new()
            $runOneBtn.Content = "▶"
            $runOneBtn.ToolTip = "Запустить только этот скрипт"
            $runOneBtn.Cursor = [System.Windows.Input.Cursors]::Hand
            $runOneBtn.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#2a2a4a")
            $runOneBtn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#6c63ff")
            $runOneBtn.BorderThickness = [System.Windows.Thickness]::new(0)
            $runOneBtn.Width = 30; $runOneBtn.Height = 30; $runOneBtn.FontSize = 12
            $runOneBtn.VerticalAlignment = "Center"; $runOneBtn.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
            $runOneBtn.Tag = $script_item.Path
            $runOneBtn.Add_Click({
                $scriptPath = $this.Tag
                Write-Log "══ Запуск: $(Split-Path $scriptPath -Leaf) ══"
                try {
                    & $scriptPath 2>&1 | ForEach-Object { Write-Log "  $_" }
                    Write-Log "✓ Выполнено успешно" -Color "Green"
                } catch {
                    Write-Log "✗ Ошибка: $_" -Color "Red"
                }
            })
            [System.Windows.Controls.Grid]::SetColumn($runOneBtn, 3)

            $grid.Children.Add($cb) | Out-Null
            $grid.Children.Add($icon) | Out-Null 
            $grid.Children.Add($textStack) | Out-Null
            $grid.Children.Add($runOneBtn) | Out-Null
            $card.Child = $grid

            $card.Add_MouseEnter({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#20203a") })
            $card.Add_MouseLeave({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e") })

            $scriptsPanel.Children.Add($card) | Out-Null
        }
    }
    Update-SelectedCount
    Write-Log "Загружено скриптов: $($scripts.Count)"
}

# ═══ Загрузка приложений из JSON ═══
function Load-Apps {
    $fallbackApps = @{
        "Утилиты" = @(
            @{ Name="7-Zip"; Id="7zip.7zip"; Description="Бесплатный архиватор с высокой степенью сжатия." }
            @{ Name="Notepad++"; Id="Notepad++.Notepad++"; Description="Бесплатный текстовый редактор с открытым исходным кодом." }
        )
        "Медиа" = @(
            @{ Name="VLC"; Id="VideoLAN.VLC"; Description="Универсальный медиаплеер." }
        )
    }
    
    if (Test-Path $script:AppsJsonPath) {
        try {
            $jsonContent = Get-Content $script:AppsJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            Write-Log "✓ Загружено $($jsonContent.ManualCategories.PSObject.Properties.Name.Count) категорий из apps.json"
            return $jsonContent
        } catch {
            Write-Log "⚠ Ошибка парсинга apps.json, используется резервный список." -Color "Yellow"
        }
    }
    return [PSCustomObject]@{ ManualCategories = $fallbackApps; Presets = @{} }
}

function Build-AppsPanel {
    $appsPanel.Children.Clear()
    $script:AppCheckboxes = @{}
    $appsData = Load-Apps
    $categories = $appsData.ManualCategories
    
    foreach ($category in $categories.PSObject.Properties) {
        $catName = $category.Name
        $apps = $category.Value
        
        # Заголовок категории
        $h = [System.Windows.Controls.Border]::new()
        $h.Margin = [System.Windows.Thickness]::new(0,16,0,6)
        $h.Padding = [System.Windows.Thickness]::new(0,0,0,6)
        $h.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#1e1e38")
        $h.BorderThickness = [System.Windows.Thickness]::new(0,0,0,1)
        $t = [System.Windows.Controls.TextBlock]::new()
        $t.Text = $catName.ToUpper()
        $t.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#6c63ff")
        $t.FontSize = 11; $t.FontWeight = "SemiBold"
        $h.Child = $t
        $appsPanel.Children.Add($h) | Out-Null
        
        # Приложения в категории
        foreach ($app in $apps) {
            $card = [System.Windows.Controls.Border]::new()
            $card.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e")
            $card.CornerRadius = [System.Windows.CornerRadius]::new(6)
            $card.Margin = [System.Windows.Thickness]::new(0,2,0,2)
            $card.Padding = [System.Windows.Thickness]::new(12,8,12,8)
            
            $grid = [System.Windows.Controls.Grid]::new()
            $col1 = [System.Windows.Controls.ColumnDefinition]::new(); $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $col2 = [System.Windows.Controls.ColumnDefinition]::new(); $col2.Width = [System.Windows.GridLength]::Auto
            $grid.ColumnDefinitions.Add($col1)
            $grid.ColumnDefinitions.Add($col2)
            
            $textStack = [System.Windows.Controls.StackPanel]::new()
            $textStack.VerticalAlignment = "Center"
            
            $cb = [System.Windows.Controls.CheckBox]::new()
            $cb.Content = $app.Name
            $cb.Tag = $app.Id
            $cb.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#c8c8e0")
            $cb.FontSize = 13
            $cb.FontWeight = "Medium"
            $script:AppCheckboxes[$app.Id] = $cb
            
            $descText = [System.Windows.Controls.TextBlock]::new()
            $descText.Text = $app.Description
            $descText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#50507a")
            $descText.FontSize = 11
            $descText.Margin = [System.Windows.Thickness]::new(28, 2, 0, 0)
            $descText.TextWrapping = "Wrap"
            
            $textStack.Children.Add($cb) | Out-Null
            $textStack.Children.Add($descText) | Out-Null
            [System.Windows.Controls.Grid]::SetColumn($textStack, 0)
            
            $card.Child = $textStack
            $card.Add_MouseEnter({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#20203a") })
            $card.Add_MouseLeave({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e") })
            $appsPanel.Children.Add($card) | Out-Null
        }
    }
}

# ═══ О системе ═══
function Build-SysPanel {
    $sysInfo = Get-SystemInfo
    $headerOsText.Text = $sysInfo.OS

    # Получаем реальное название физического диска для C:
    try {
        $diskPartition = Get-WmiObject -Query "ASSOCIATORS OF {Win32_LogicalDisk.DeviceID='C:'} WHERE AssocClass=Win32_LogicalDiskToPartition" | Select-Object -First 1
        $diskDrive = Get-WmiObject -Query "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($diskPartition.DeviceID)'} WHERE AssocClass=Win32_DiskDriveToDiskPartition" | Select-Object -First 1
        $diskSizeGB = [math]::Round($diskDrive.Size / 1GB)
        $diskModelRaw = $diskDrive.Model -replace '\s+',' '
        $diskLabel = "$diskModelRaw ($diskSizeGB ГБ)"
    } catch {
        $diskLabel = $sysInfo.Disk
    }

    $sysItems = @(
        @{ L="💻 Операционная система"; V=$sysInfo.OS;     Btn=$null }
        @{ L="⚙️ Процессор";            V=$sysInfo.CPU;    Btn=$null }
        @{ L="🧠 Оперативная память";   V=$sysInfo.RAM;    Btn=$null }
        @{ L="💾 Диск";                 V=$diskLabel;      Btn=$null }
        @{ L="⏱️ Время работы";         V=$sysInfo.Uptime; Btn=$null }
        @{ L="📂 Рабочая папка";        V=$script:WorkFolder; Btn="Открыть" }
    )

    $sysPanel.Children.Clear()
    foreach ($item in $sysItems) {
        $row = [System.Windows.Controls.Border]::new()
        $row.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e")
        $row.CornerRadius = [System.Windows.CornerRadius]::new(8)
        $row.Margin = [System.Windows.Thickness]::new(0,4,0,4)
        $row.Padding = [System.Windows.Thickness]::new(16,12,16,12)

        $g = [System.Windows.Controls.Grid]::new()
        $c1 = [System.Windows.Controls.ColumnDefinition]::new(); $c1.Width = "210"
        $c2 = [System.Windows.Controls.ColumnDefinition]::new(); $c2.Width = "*"
        $c3 = [System.Windows.Controls.ColumnDefinition]::new(); $c3.Width = "Auto"
        $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2); $g.ColumnDefinitions.Add($c3)

        $lbl = [System.Windows.Controls.TextBlock]::new()
        $lbl.Text = $item.L
        $lbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#606080")
        $lbl.FontSize = 13; $lbl.VerticalAlignment = "Center"

        $val = [System.Windows.Controls.TextBlock]::new()
        $val.Text = $item.V
        $val.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#d0d0f0")
        $val.FontSize = 13; $val.FontWeight = "SemiBold"; $val.TextWrapping = "Wrap"
        $val.VerticalAlignment = "Center"
        [System.Windows.Controls.Grid]::SetColumn($val, 1)

        $g.Children.Add($lbl) | Out-Null
        $g.Children.Add($val) | Out-Null

        # Кнопка "Открыть" только для рабочей папки
        if ($item.Btn) {
            $folderPath = $item.V
            $openBtn = [System.Windows.Controls.Button]::new()
            $openBtn.Content = "📂 Открыть"
            $openBtn.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#2a2a42")
            $openBtn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#c0c0dd")
            $openBtn.BorderThickness = [System.Windows.Thickness]::new(0)
            $openBtn.Cursor = [System.Windows.Input.Cursors]::Hand
            $openBtn.FontSize = 11; $openBtn.Padding = [System.Windows.Thickness]::new(10,5,10,5)
            $openBtn.VerticalAlignment = "Center"
            $openBtn.Margin = [System.Windows.Thickness]::new(8,0,0,0)
            $openBtn.Tag = $folderPath
            $openBtn.Add_Click({
                $p = $this.Tag
                if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
                Start-Process explorer.exe $p
            })
            $openBtn.Add_MouseEnter({ $this.Opacity = 0.8 })
            $openBtn.Add_MouseLeave({ $this.Opacity = 1.0 })
            [System.Windows.Controls.Grid]::SetColumn($openBtn, 2)
            $g.Children.Add($openBtn) | Out-Null
        }

        $row.Child = $g
        $sysPanel.Children.Add($row) | Out-Null
    }
}

# ═══ Функция запуска скриптов ═══
function Run-SelectedScripts {
    $selected = $script:ScriptCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked }
    if (-not $selected) {
        Write-Log "⚠ Нет выбранных скриптов" -Color "Yellow"
        return
    }
    $count = @($selected).Count
    Write-Log "══════════════════════════════════════"
    Write-Log "▶ Запуск $count скриптов..."
    Write-Log "══════════════════════════════════════"
    $ok = 0; $fail = 0
    foreach ($entry in $selected) {
        $scriptPath = $entry.Key
        $scriptName = Split-Path $scriptPath -Leaf
        Write-Log "── $scriptName"
        try {
            $output = & $scriptPath 2>&1
            $output | ForEach-Object { Write-Log "   $_" }
            Write-Log "   ✓ Готово" -Color "Green"
            $ok++
        } catch {
            Write-Log "   ✗ Ошибка: $_" -Color "Red"
            $fail++
        }
    }
    Write-Log "══════════════════════════════════════"
    Write-Log "Завершено: ✓$ok успешно$(if($fail -gt 0){ "  ✗$fail ошибок" })"
    Write-Log "══════════════════════════════════════"

    # Перезагрузка если флаг установлен
    if ($rebootAfterChk.IsChecked) {
        $confirm = [System.Windows.MessageBox]::Show(
            "Все скрипты выполнены.`n`nПерезагрузить компьютер сейчас?",
            "Перезагрузка", "YesNo", "Question")
        if ($confirm -eq "Yes") {
            Write-Log "🔄 Перезагрузка..."
            Restart-Computer -Force
        } else {
            Write-Log "ℹ Перезагрузка отменена." -Color "Yellow"
            $rebootAfterChk.IsChecked = $false
        }
    }
}

# ═══ Функция выбора пресета ═══
function Select-Preset($presetName) {
    $appsData = Load-Apps
    $presets = $appsData.Presets
    
    if (-not $presets.$presetName) {
        Write-Log "⚠ Пресет '$presetName' не найден" -Color "Yellow"
        return
    }
    
    $presetApps = $presets.$presetName
    Write-Log "⚡ Применение пресета: $presetName ($($presetApps.Count) приложений)"
    
    # Снимаем все галочки
    foreach ($cb in $script:AppCheckboxes.Values) { $cb.IsChecked = $false }
    
    # Ставим галочки на приложения из пресета
    foreach ($appId in $presetApps) {
        if ($script:AppCheckboxes.ContainsKey($appId)) {
            $script:AppCheckboxes[$appId].IsChecked = $true
        }
    }
    
    Write-Log "✓ Пресет применен" -Color "Green"
}

# ═══ Функция выбора рекомендованных скриптов ═══
function Select-RecommendedScripts {
    $scripts = Load-Scripts
    $selectedCount = 0
    
    foreach ($script_item in $scripts) {
        if ($script_item.Recommended) {
            if ($script:ScriptCheckboxes.ContainsKey($script_item.Path)) {
                $script:ScriptCheckboxes[$script_item.Path].IsChecked = $true
                $selectedCount++
            }
        }
    }
    
    Write-Log "✓ Выбрано $selectedCount рекомендованных скриптов" -Color "Green"
    Update-SelectedCount
}

# ═══ Обновления через winget ═══
$script:UpdateCheckboxes = @{}

function Build-UpdatesPanel {
    $updatesPanel.Children.Clear()
    $script:UpdateCheckboxes.Clear()
    $updateStatusText.Text  = "Идёт проверка обновлений..."
    $updateCountText.Text   = ""

    Write-Log "🔍 Проверка доступных обновлений через winget..."

    $rawOutput = winget upgrade 2>&1 | Out-String
    $lines = $rawOutput -split "`n" | Where-Object { $_ -match '\S' }

    # Ищем строки с реальными пакетами: содержат winget-id (точка в середине слова без пробелов)
    $packages = @()
    $headerFound = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*-+\s*$') { $headerFound = $true; continue }
        if (-not $headerFound) { continue }
        if ($line -match '^\s*$') { continue }
        # Пробуем распарсить: Имя | Ид | Версия | Доступная версия | Источник
        $parts = $line -split '\s{2,}' | Where-Object { $_.Trim() -ne '' }
        if ($parts.Count -ge 4) {
            $packages += @{
                Name        = $parts[0].Trim()
                Id          = $parts[1].Trim()
                Version     = $parts[2].Trim()
                NewVersion  = $parts[3].Trim()
                Source      = if ($parts.Count -ge 5) { $parts[4].Trim() } else { "winget" }
            }
        }
    }

    if ($packages.Count -eq 0) {
        $lbl = [System.Windows.Controls.TextBlock]::new()
        $lbl.Text = "✅ Все установленные пакеты актуальны — обновлений нет."
        $lbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#50e050")
        $lbl.FontSize = 13; $lbl.TextAlignment = "Center"; $lbl.Margin = "0,60,0,0"
        $updatesPanel.Children.Add($lbl) | Out-Null
        $updateStatusText.Text = "✅ Обновления не найдены"
        Write-Log "✅ Обновлений нет"
        return
    }

    foreach ($pkg in $packages) {
        $card = [System.Windows.Controls.Border]::new()
        $card.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e")
        $card.CornerRadius = [System.Windows.CornerRadius]::new(7)
        $card.Margin = [System.Windows.Thickness]::new(0,3,0,3)
        $card.Padding = [System.Windows.Thickness]::new(12,8,12,8)

        $g = [System.Windows.Controls.Grid]::new()
        $c1 = [System.Windows.Controls.ColumnDefinition]::new(); $c1.Width = [System.Windows.GridLength]::new(28)
        $c2 = [System.Windows.Controls.ColumnDefinition]::new(); $c2.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
        $c3 = [System.Windows.Controls.ColumnDefinition]::new(); $c3.Width = [System.Windows.GridLength]::Auto
        $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2); $g.ColumnDefinitions.Add($c3)

        $cb = [System.Windows.Controls.CheckBox]::new()
        $cb.VerticalAlignment = "Center"
        $cb.Tag = $pkg.Id
        $cb.Add_Checked({
            $c = ($script:UpdateCheckboxes.Values | Where-Object { $_.IsChecked }).Count
            $updateCountText.Text = "Выбрано: $c"
        })
        $cb.Add_Unchecked({
            $c = ($script:UpdateCheckboxes.Values | Where-Object { $_.IsChecked }).Count
            $updateCountText.Text = "Выбрано: $c"
        })
        [System.Windows.Controls.Grid]::SetColumn($cb, 0)
        $script:UpdateCheckboxes[$pkg.Id] = $cb

        $info = [System.Windows.Controls.StackPanel]::new(); $info.VerticalAlignment = "Center"
        $nm = [System.Windows.Controls.TextBlock]::new()
        $nm.Text = $pkg.Name; $nm.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#e0e0f4")
        $nm.FontSize = 12; $nm.FontWeight = "Medium"
        $id = [System.Windows.Controls.TextBlock]::new()
        $id.Text = $pkg.Id; $id.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#50507a")
        $id.FontSize = 10; $id.Margin = [System.Windows.Thickness]::new(0,1,0,0)
        $info.Children.Add($nm) | Out-Null; $info.Children.Add($id) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($info, 1)

        $ver = [System.Windows.Controls.StackPanel]::new(); $ver.VerticalAlignment = "Center"; $ver.HorizontalAlignment = "Right"
        $v1 = [System.Windows.Controls.TextBlock]::new()
        $v1.Text = "$($pkg.Version)  →  $($pkg.NewVersion)"
        $v1.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#c0a030")
        $v1.FontSize = 11; $v1.HorizontalAlignment = "Right"
        $ver.Children.Add($v1) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($ver, 2)

        $g.Children.Add($cb) | Out-Null; $g.Children.Add($info) | Out-Null; $g.Children.Add($ver) | Out-Null
        $card.Child = $g
        $card.Add_MouseEnter({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#20203a") })
        $card.Add_MouseLeave({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e") })
        $updatesPanel.Children.Add($card) | Out-Null
    }

    $updateStatusText.Text = "Найдено обновлений: $($packages.Count)"
    $updateCountText.Text  = "Выбрано: 0"
    Write-Log "🔄 Найдено $($packages.Count) обновлений"
}

function Install-SelectedUpdates {
    $selected = $script:UpdateCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked }
    if (-not $selected) { Write-Log "⚠ Нет выбранных обновлений" -Color "Yellow"; return }
    $count = @($selected).Count
    Write-Log "══ Обновление $count пакетов ══"
    foreach ($entry in $selected) {
        Write-Log "⬆ Обновление: $($entry.Key)..."
        winget upgrade --id $entry.Key --silent --accept-source-agreements --accept-package-agreements 2>&1 |
            ForEach-Object { Write-Log "   $_" }
        Write-Log "   ✓ Готово" -Color "Green"
    }
    Write-Log "══ Обновление завершено ══"
    Build-UpdatesPanel
}

# ═══ Диагностика / Тест системы ═══
function Build-DiagPanel {
    $diagPanel.Children.Clear()

    $tests = @(
        @{
            Title  = "Проверка системных файлов (SFC)"
            Desc   = "Сканирует и восстанавливает повреждённые системные файлы Windows. Занимает 5–15 минут."
            Icon   = "🛡️"
            Color  = "#4a90d9"
            Action = {
                Write-Log "══ SFC: Запуск проверки системных файлов ══"
                Write-Log "⏳ Пожалуйста, подождите — это может занять несколько минут..."
                sfc /scannow 2>&1 | ForEach-Object { Write-Log "  $_" }
                Write-Log "✓ SFC завершён. Результаты выше." -Color "Green"
            }
        },
        @{
            Title  = "Восстановление компонентов Windows (DISM)"
            Desc   = "Восстанавливает образ Windows через Windows Update. Требует интернет. Занимает 10–30 минут."
            Icon   = "🔧"
            Color  = "#7c63ff"
            Action = {
                Write-Log "══ DISM: Восстановление образа Windows ══"
                Write-Log "⏳ Запуск DISM /RestoreHealth..."
                DISM /Online /Cleanup-Image /RestoreHealth 2>&1 | ForEach-Object { Write-Log "  $_" }
                Write-Log "✓ DISM завершён." -Color "Green"
            }
        },
        @{
            Title  = "Проверка диска C: (CHKDSK)"
            Desc   = "Проверяет диск C: на ошибки файловой системы. Полная проверка запустится при следующей перезагрузке."
            Icon   = "💾"
            Color  = "#2da86a"
            Action = {
                Write-Log "══ CHKDSK: Планирование проверки диска C: ══"
                $confirm = [System.Windows.MessageBox]::Show(
                    "CHKDSK запустится при следующей перезагрузке Windows.`n`nПланируете перезагрузку сейчас?",
                    "CHKDSK", "YesNo", "Question")
                chkdsk C: /f /r /x 2>&1 | ForEach-Object { Write-Log "  $_" }
                if ($confirm -eq "Yes") {
                    Write-Log "Перезагрузка через 30 секунд..."
                    shutdown /r /t 30 /c "PotatoPC: Запланирована проверка диска CHKDSK"
                } else {
                    Write-Log "ℹ CHKDSK выполнится при следующей перезагрузке." -Color "Yellow"
                }
            }
        },
        @{
            Title  = "Проверка оперативной памяти (RAM)"
            Desc   = "Запускает встроенный диагностический инструмент Windows Memory Diagnostic. Требует перезагрузку."
            Icon   = "🧠"
            Color  = "#d4601a"
            Action = {
                Write-Log "══ RAM: Диагностика оперативной памяти ══"
                $confirm = [System.Windows.MessageBox]::Show(
                    "Windows Memory Diagnostic запустится после перезагрузки компьютера.`n`nПерезагрузить сейчас?",
                    "Диагностика RAM", "YesNo", "Question")
                if ($confirm -eq "Yes") {
                    Write-Log "Запуск Windows Memory Diagnostic и перезагрузка..."
                    MdSched.exe
                } else {
                    Write-Log "ℹ Диагностика RAM отменена." -Color "Yellow"
                }
            }
        }
    )

    foreach ($test in $tests) {
        $card = [System.Windows.Controls.Border]::new()
        $card.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e")
        $card.CornerRadius = [System.Windows.CornerRadius]::new(10)
        $card.Margin = [System.Windows.Thickness]::new(0,5,0,5)
        $card.Padding = [System.Windows.Thickness]::new(16,14,16,14)
        $card.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom($test.Color + "55")
        $card.BorderThickness = [System.Windows.Thickness]::new(0,0,0,2)

        $g = [System.Windows.Controls.Grid]::new()
        $c1 = [System.Windows.Controls.ColumnDefinition]::new(); $c1.Width = [System.Windows.GridLength]::new(44)
        $c2 = [System.Windows.Controls.ColumnDefinition]::new(); $c2.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
        $c3 = [System.Windows.Controls.ColumnDefinition]::new(); $c3.Width = [System.Windows.GridLength]::Auto
        $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2); $g.ColumnDefinitions.Add($c3)

        $ico = [System.Windows.Controls.TextBlock]::new()
        $ico.Text = $test.Icon; $ico.FontSize = 26; $ico.VerticalAlignment = "Center"; $ico.HorizontalAlignment = "Center"
        [System.Windows.Controls.Grid]::SetColumn($ico, 0)

        $txt = [System.Windows.Controls.StackPanel]::new(); $txt.VerticalAlignment = "Center"; $txt.Margin = [System.Windows.Thickness]::new(12,0,12,0)
        $ttl = [System.Windows.Controls.TextBlock]::new()
        $ttl.Text = $test.Title; $ttl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#e0e0f4")
        $ttl.FontSize = 13; $ttl.FontWeight = "SemiBold"
        $dsc = [System.Windows.Controls.TextBlock]::new()
        $dsc.Text = $test.Desc; $dsc.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#60607a")
        $dsc.FontSize = 11; $dsc.Margin = [System.Windows.Thickness]::new(0,3,0,0); $dsc.TextWrapping = "Wrap"
        $txt.Children.Add($ttl) | Out-Null; $txt.Children.Add($dsc) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($txt, 1)

        $btn = [System.Windows.Controls.Button]::new()
        $btn.Content = "▶ Запустить"
        $btn.Background = [Windows.Media.BrushConverter]::new().ConvertFrom($test.Color)
        $btn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#ffffff")
        $btn.BorderThickness = [System.Windows.Thickness]::new(0)
        $btn.Cursor = [System.Windows.Input.Cursors]::Hand
        $btn.FontSize = 12; $btn.FontWeight = "SemiBold"
        $btn.Padding = [System.Windows.Thickness]::new(14,8,14,8)
        $btn.VerticalAlignment = "Center"
        $btn.Tag = $test.Action

        # Hover
        $col = $test.Color
        $btn.Add_MouseEnter({ $this.Opacity = 0.85 })
        $btn.Add_MouseLeave({ $this.Opacity = 1.0 })
        $btn.Add_Click({
            $actionBlock = $this.Tag
            & $actionBlock
        })

        [System.Windows.Controls.Grid]::SetColumn($btn, 2)
        $g.Children.Add($ico) | Out-Null; $g.Children.Add($txt) | Out-Null; $g.Children.Add($btn) | Out-Null
        $card.Child = $g

        $card.Add_MouseEnter({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1e1e35") })
        $card.Add_MouseLeave({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e") })
        $diagPanel.Children.Add($card) | Out-Null
    }
}

# ═══ Обработчики событий ═══
$checkUpdatesBtn.Add_Click({
    $updatesPanel.Children.Clear()
    $script:UpdateCheckboxes.Clear()
    Build-UpdatesPanel
})
$selectAllUpdatesBtn.Add_Click({
    foreach ($cb in $script:UpdateCheckboxes.Values) { $cb.IsChecked = $true }
    $updateCountText.Text = "Выбрано: $($script:UpdateCheckboxes.Count)"
})
$deselectAllUpdatesBtn.Add_Click({
    foreach ($cb in $script:UpdateCheckboxes.Values) { $cb.IsChecked = $false }
    $updateCountText.Text = "Выбрано: 0"
})
$installUpdatesBtn.Add_Click({ Install-SelectedUpdates })


$runScriptsBtn.Add_Click({ Run-SelectedScripts })
$selectAllBtn.Add_Click({ foreach ($cb in $script:ScriptCheckboxes.Values) { $cb.IsChecked = $true }; Update-SelectedCount })
$deselectAllBtn.Add_Click({ foreach ($cb in $script:ScriptCheckboxes.Values) { $cb.IsChecked = $false }; Update-SelectedCount })
$refreshBtn.Add_Click({ Write-Log "Обновление списка..."; Build-ScriptsPanel })
$selectRecommendedBtn.Add_Click({ Select-RecommendedScripts })

# ─── Поиск в Модулях ───────────────────────────────────────────────────────
$scriptSearchBox   = $window.FindName("ScriptSearchBox")
$scriptSearchHint  = $window.FindName("ScriptSearchHint")
$scriptSearchClear = $window.FindName("ScriptSearchClear")

$scriptSearchBox.Add_TextChanged({
    $query = $scriptSearchBox.Text.Trim().ToLower()
    # Показываем/скрываем hint и кнопку очистки
    $scriptSearchHint.Visibility  = if ($query -eq "") { "Visible" } else { "Collapsed" }
    $scriptSearchClear.Visibility = if ($query -eq "") { "Collapsed" } else { "Visible" }
    # Фильтрация: показываем/скрываем карточки, чекбоксы НЕ трогаем
    foreach ($child in $scriptsPanel.Children) {
        if ($child -is [System.Windows.Controls.Border]) {
            $child.Visibility = "Visible"  # заголовки категорий всегда видны
            # Находим имя и описание через дерево
            $grid = $child.Child
            if ($grid -is [System.Windows.Controls.Grid] -and $grid.ColumnDefinitions.Count -ge 3) {
                $nameVal = ""
                $descVal = ""
                foreach ($el in $grid.Children) {
                    if ($el -is [System.Windows.Controls.StackPanel]) {
                        foreach ($tb in $el.Children) {
                            if ($tb -is [System.Windows.Controls.TextBlock]) {
                                if ($nameVal -eq "") { $nameVal = $tb.Text.ToLower() }
                                else { $descVal = $tb.Text.ToLower() }
                            }
                        }
                    }
                }
                if ($query -ne "" -and ($nameVal -notlike "*$query*") -and ($descVal -notlike "*$query*")) {
                    $child.Visibility = "Collapsed"
                }
            }
        }
    }
})

$scriptSearchClear.Add_Click({ $scriptSearchBox.Text = "" })

# ─── Поиск в Приложениях ───────────────────────────────────────────────────
$appSearchBox   = $window.FindName("AppSearchBox")
$appSearchHint  = $window.FindName("AppSearchHint")
$appSearchClear = $window.FindName("AppSearchClear")

$appSearchBox.Add_TextChanged({
    $query = $appSearchBox.Text.Trim().ToLower()
    $appSearchHint.Visibility  = if ($query -eq "") { "Visible" } else { "Collapsed" }
    $appSearchClear.Visibility = if ($query -eq "") { "Collapsed" } else { "Visible" }
    foreach ($child in $appsPanel.Children) {
        if ($child -is [System.Windows.Controls.Border]) {
            $inner = $child.Child
            if ($inner -is [System.Windows.Controls.StackPanel]) {
                # Это карточка приложения — ищем чекбокс и описание
                $nameVal = ""
                $descVal = ""
                foreach ($el in $inner.Children) {
                    if ($el -is [System.Windows.Controls.CheckBox]) { $nameVal = $el.Content.ToString().ToLower() }
                    if ($el -is [System.Windows.Controls.TextBlock]) { $descVal = $el.Text.ToLower() }
                }
                if ($query -ne "" -and ($nameVal -notlike "*$query*") -and ($descVal -notlike "*$query*")) {
                    $child.Visibility = "Collapsed"
                } else {
                    $child.Visibility = "Visible"
                }
            } else {
                # Заголовок категории — всегда показываем
                $child.Visibility = "Visible"
            }
        }
    }
})

$appSearchClear.Add_Click({ $appSearchBox.Text = "" })

$openFolderAction = {
    if (-not (Test-Path $script:ScriptsFolder)) { New-Item -ItemType Directory -Path $script:ScriptsFolder -Force | Out-Null }
    Start-Process explorer.exe $script:ScriptsFolder
}
$openFolderBtn.Add_Click($openFolderAction)

$clearLogBtn.Add_Click({ $script:LogBox.Clear() })
$copyLogBtn.Add_Click({
    [System.Windows.Clipboard]::SetText($script:LogBox.Text)
    Write-Log "✓ Лог скопирован в буфер обмена" -Color "Green"
})


$restorePointBtn.Add_Click({ Create-RestorePoint })

$presetOfficeBtn.Add_Click({ Select-Preset "Office-pack" })
$presetGamesBtn.Add_Click({ Select-Preset "Games-pack" })

$installAppsBtn.Add_Click({
    $selected = $script:AppCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked }
    if (-not $selected) { Write-Log "⚠ Нет выбранных приложений" -Color "Yellow"; return }
    Write-Log "══ Установка приложений ══"
    foreach ($entry in $selected) {
        $appId = $entry.Key
        Write-Log "⏳ Установка $appId..."
        winget install --id $appId --silent --accept-source-agreements --accept-package-agreements 2>&1 | ForEach-Object { Write-Log "   $_" }
        Write-Log "✓ $appId установлена" -Color "Green"
    }
    Write-Log "══ Установка завершена ══"
})
$selectAllAppsBtn.Add_Click({ foreach ($cb in $script:AppCheckboxes.Values) { $cb.IsChecked = $true } })
$deselectAllAppsBtn.Add_Click({ foreach ($cb in $script:AppCheckboxes.Values) { $cb.IsChecked = $false } })

# ═══ ЗАПУСК И ИНИЦИАЛИЗАЦИЯ ═══
# 1. Предложение создать точку восстановления
$restoreResult = [System.Windows.MessageBox]::Show(
    "Рекомендуется создать точку восстановления системы перед внесением изменений.`n`nСоздать точку восстановления сейчас?",
    "PotatoPC Optimizer",
    [System.Windows.MessageBoxButton]::YesNo,
    [System.Windows.MessageBoxImage]::Question
)
if ($restoreResult -eq "Yes") {
    Create-RestorePoint
}

# Всё что зависит от LogBox и ScriptsFolder — только после открытия окна
$window.Add_Loaded({
    $scriptsFolderText.Text = $script:ScriptsFolder
    Write-Log "PotatoPC Optimizer v3.0 запущен"
    Write-Log "Система: $((Get-SystemInfo).OS)"
    Write-Log "Рабочая папка: $($script:WorkFolder)"

    # Загрузка данных (apps.json, скрипты если папка пустая)
    Initialize-PotatoPC

    # Построение всех панелей — строго после Initialize
    Build-ScriptsPanel
    Build-AppsPanel
    Build-SysPanel
    Build-DiagPanel

    Write-Log "✓ Готов к работе." -Color "Green"
})

$window.ShowDialog() | Out-Null
