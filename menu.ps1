#Requires -RunAsAdministrator
<#
.SYNOPSIS
PotatoPC Optimizer - Modular Edition
.DESCRIPTION
Запуск: irm https://raw.githubusercontent.com/DezFix/PotatoPC/main/potatopc.ps1 | iex
#>

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

$script:WorkFolder    = Join-Path $env:TEMP "PotatoPC"
$script:ScriptsFolder = Join-Path $script:WorkFolder "scripts"
$script:AppsJsonPath  = Join-Path $script:WorkFolder "apps.json"
$script:RepoZipUrl    = "https://github.com/DezFix/PotatoPC/archive/refs/heads/main.zip"
$script:AppsJsonUrl   = "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/apps.json"

# ═══ Определение версии Windows ═══
function Get-WindowsMajorVersion {
    try {
        $build = [int](Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuildNumber
        if ($build -ge 22000) { return 11 }
        return 10
    } catch { return 10 }
}
$script:WindowsMajorVersion = Get-WindowsMajorVersion

# ═══ Загрузка репозитория ═══
function Download-Repo {
    param([switch]$Force)
    $zipPath = Join-Path $script:WorkFolder "repo.zip"
    try {
        Write-Log "$(if($Force){'🔄 Обновление'}else{'📦 Загрузка'}) репозитория с GitHub..."

        # При обновлении — сначала удаляем все старые папки репозитория
        if ($Force) {
            $oldFolders = Get-ChildItem -Path $script:WorkFolder -Filter "*-main" -Directory -ErrorAction SilentlyContinue
            foreach ($old in $oldFolders) {
                Write-Log "🗑️ Удаление старой папки: $($old.Name)"
                Remove-Item -Path $old.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        Invoke-WebRequest -Uri $script:RepoZipUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop
        Expand-Archive -Path $zipPath -DestinationPath $script:WorkFolder -Force
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

        $repoFolder = Get-ChildItem -Path $script:WorkFolder -Filter "*-main" -Directory |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($repoFolder) {
            $script:ScriptsFolder = Join-Path $repoFolder.FullName "scripts"
            $script:AppsJsonPath  = Join-Path $repoFolder.FullName "apps.json"
            $n = @(Get-ChildItem -Path $script:ScriptsFolder -Recurse -Filter "*.ps1" -ErrorAction SilentlyContinue).Count
            Write-Log "✓ Готово. Скриптов: $n"
            return $true
        } else {
            Write-Log "✗ Папка репозитория не найдена." -Color "Red"
            return $false
        }
    } catch {
        Write-Log "✗ Ошибка загрузки: $_" -Color "Red"
        return $false
    }
}

function Initialize-PotatoPC {
    Write-Log "Инициализация..."
    if (-not (Test-Path $script:WorkFolder)) {
        New-Item -ItemType Directory -Path $script:WorkFolder -Force | Out-Null
    }
    $repoFolder = Get-ChildItem -Path $script:WorkFolder -Filter "*-main" -Directory |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($repoFolder -and (Test-Path (Join-Path $repoFolder.FullName "scripts"))) {
        $script:ScriptsFolder = Join-Path $repoFolder.FullName "scripts"
        $script:AppsJsonPath  = Join-Path $repoFolder.FullName "apps.json"
        $n = @(Get-ChildItem -Path $script:ScriptsFolder -Recurse -Filter "*.ps1" -ErrorAction SilentlyContinue).Count
        Write-Log "✓ Репозиторий найден локально. Скриптов: $n"
    } else {
        Download-Repo
    }
}

# ═══ Загрузка метаданных скриптов ═══
function Load-Scripts {
    $result = @()
    $files = Get-ChildItem -Path $script:ScriptsFolder -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue | Sort-Object Name
    foreach ($file in $files) {
        $parentName = $file.Directory.Name
        $category = if ($parentName -ne (Split-Path $script:ScriptsFolder -Leaf)) { $parentName } else { "Другое" }
        $meta = @{
            Name        = $file.BaseName
            Desc        = ""
            Category    = $category
            Icon        = "📄"
            Recommended = $false
            Tag         = 0       # 0=нет, 1=безопасно, 2=осторожно, 3=опасно
            Win11Only   = $false  # true = только для Windows 11
            Path        = $file.FullName
        }
        $lines = Get-Content $file.FullName -TotalCount 15 -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            if ($line -match '^#\s*NAME:\s*(.+)')        { $meta.Name        = $Matches[1].Trim() }
            if ($line -match '^#\s*DESC:\s*(.+)')        { $meta.Desc        = $Matches[1].Trim() }
            if ($line -match '^#\s*ICON:\s*(.+)')        { $meta.Icon        = $Matches[1].Trim() }
            if ($line -match '^#\s*RECOMMENDED:\s*true') { $meta.Recommended = $true }
            if ($line -match '^#\s*TAGS:\s*(\d)')        { $meta.Tag         = [int]$Matches[1].Trim() }
            # Тег win11: # WIN11: true  или  # TAGS: win11
            if ($line -match '^#\s*WIN11:\s*true')       { $meta.Win11Only   = $true }
            if ($line -match '^#\s*TAGS:.*win11')        { $meta.Win11Only   = $true }
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
            OS     = "$($os.Caption) Build $($os.BuildNumber)"
            CPU    = $cpu.Trim()
            RAM    = "$([math]::Round($ramB/1GB,1)) ГБ"
            Disk   = "C: $([math]::Round($disk.FreeSpace/1GB,1)) ГБ своб. / $([math]::Round($disk.Size/1GB,1)) ГБ"
            Uptime = ((Get-Date) - $os.ConvertToDateTime($os.LastBootUpTime)) | ForEach-Object { "$($_.Days)д $($_.Hours)ч $($_.Minutes)м" }
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
    $consoleColor = switch ($color) { "Green" {"Green"} "Red" {"Red"} "Yellow" {"Yellow"} default {"White"} }
    Write-Host $line -ForegroundColor $consoleColor
}

# ═══ XAML ═══
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
                        <TextBlock Text="v3.0" Foreground="#ffffff" FontSize="10" FontWeight="SemiBold"/>
                    </Border>
                </StackPanel>
                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                    <Button Content="🛡️ Создать точку восстановления" x:Name="RestorePointBtn" Style="{StaticResource BtnSecondary}" Height="32" FontSize="12" Margin="0,0,12,0"/>
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
                            <!-- Кнопки-фильтры -->
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <Button x:Name="StartupFilterAllBtn"  Content="📋 Все"              Height="28" FontSize="11" Margin="0,0,5,0" Style="{StaticResource BtnPrimary}"/>
                                <Button x:Name="StartupFilterAppBtn"  Content="📦 Приложения"       Height="28" FontSize="11" Margin="0,0,5,0" Style="{StaticResource BtnSecondary}"/>
                                <Button x:Name="StartupFilterTaskBtn" Content="🗓️ Задачи"           Height="28" FontSize="11" Style="{StaticResource BtnSecondary}"/>
                            </StackPanel>
                            <!-- Счётчик -->
                            <TextBlock x:Name="StartupCountText" Grid.Column="1"
                                       Foreground="#c0c0ee" FontSize="11" VerticalAlignment="Center"
                                       HorizontalAlignment="Center"/>
                            <!-- Поиск -->
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

# ═══ Загрузка XAML ═══
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$script:LogBox         = $window.FindName("LogOutput")
$scriptsPanel          = $window.FindName("ScriptsPanel")
$appsPanel             = $window.FindName("AppsPanel")
$sysPanel              = $window.FindName("SysPanel")
$updatesPanel          = $window.FindName("UpdatesPanel")
$diagPanel             = $window.FindName("DiagPanel")
$headerOsText          = $window.FindName("HeaderOsText")
$scriptsFolderText     = $window.FindName("ScriptsFolderText")
$selectedCountText     = $window.FindName("SelectedCountText")
$runScriptsBtn         = $window.FindName("RunScriptsBtn")
$rebootAfterChk        = $window.FindName("RebootAfterScriptsChk")
$selectAllBtn          = $window.FindName("SelectAllBtn")
$deselectAllBtn        = $window.FindName("DeselectAllBtn")
$refreshBtn            = $window.FindName("RefreshBtn")
$openFolderBtn         = $window.FindName("OpenFolderBtn")
$clearLogBtn           = $window.FindName("ClearLogBtn")
$copyLogBtn            = $window.FindName("CopyLogBtn")
$installAppsBtn        = $window.FindName("InstallAppsBtn")
$selectAllAppsBtn      = $window.FindName("SelectAllAppsBtn")
$deselectAllAppsBtn    = $window.FindName("DeselectAllAppsBtn")
$restorePointBtn       = $window.FindName("RestorePointBtn")
$presetOfficeBtn       = $window.FindName("PresetOfficeBtn")
$presetGamesBtn        = $window.FindName("PresetGamesBtn")
$selectRecommendedBtn  = $window.FindName("SelectRecommendedBtn")
$checkUpdatesBtn       = $window.FindName("CheckUpdatesBtn")
$selectAllUpdatesBtn   = $window.FindName("SelectAllUpdatesBtn")
$deselectAllUpdatesBtn = $window.FindName("DeselectAllUpdatesBtn")
$installUpdatesBtn     = $window.FindName("InstallUpdatesBtn")
$updateStatusText      = $window.FindName("UpdateStatusText")
$updateCountText       = $window.FindName("UpdateCountText")
$startupAppsPanel      = $window.FindName("StartupAppsPanel")
$scheduledTasksPanel   = $null   # больше не используется (единый список)
$refreshStartupBtn     = $window.FindName("RefreshStartupBtn")
$disableStartupBtn     = $window.FindName("DisableStartupBtn")
$enableStartupBtn      = $window.FindName("EnableStartupBtn")
$selectAllStartupBtn   = $window.FindName("SelectAllStartupBtn")
$deselectAllStartupBtn = $window.FindName("DeselectAllStartupBtn")
$startupFilterAllBtn   = $window.FindName("StartupFilterAllBtn")
$startupFilterAppBtn   = $window.FindName("StartupFilterAppBtn")
$startupFilterTaskBtn  = $window.FindName("StartupFilterTaskBtn")
$startupCountText      = $window.FindName("StartupCountText")
$startupSelectedText   = $window.FindName("StartupSelectedText")
$startupSearchBox      = $window.FindName("StartupSearchBox")
$startupSearchHint     = $window.FindName("StartupSearchHint")
$startupSearchClear    = $window.FindName("StartupSearchClear")
$script:StartupFilter  = "All"   # All | Apps | Tasks
$scriptSearchBox       = $window.FindName("ScriptSearchBox")
$scriptSearchHint      = $window.FindName("ScriptSearchHint")
$scriptSearchClear     = $window.FindName("ScriptSearchClear")
$appSearchBox          = $window.FindName("AppSearchBox")
$appSearchHint         = $window.FindName("AppSearchHint")
$appSearchClear        = $window.FindName("AppSearchClear")

# ═══ Логика скриптов ═══
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
        $empty.Text = "📂 Папка скриптов пуста.`nПапка: $($script:ScriptsFolder)"
        $empty.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#a8a8d0")
        $empty.FontSize = 13; $empty.TextAlignment = "Center"; $empty.Margin = "0,60,0,0"
        $scriptsPanel.Children.Add($empty) | Out-Null
        Update-SelectedCount; return
    }

    $grouped = $scripts | Group-Object { $_.Category } | Sort-Object Name

    foreach ($group in $grouped) {
        $catBorder = [System.Windows.Controls.Border]::new()
        $catBorder.Margin = [System.Windows.Thickness]::new(0,16,0,6)
        $catBorder.Padding = [System.Windows.Thickness]::new(0,0,0,6)
        $catBorder.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#1e1e38")
        $catBorder.BorderThickness = [System.Windows.Thickness]::new(0,0,0,1)
        $catText = [System.Windows.Controls.TextBlock]::new()
        $catText.Text = $group.Name.ToUpper()
        $catText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#6c63ff")
        $catText.FontSize = 11; $catText.FontWeight = "SemiBold"
        $catBorder.Child = $catText
        $scriptsPanel.Children.Add($catBorder) | Out-Null

        foreach ($script_item in $group.Group) {
            # Совместимость с ОС
            $isWin11Incompatible = $script_item.Win11Only -and ($script:WindowsMajorVersion -lt 11)

            $card = [System.Windows.Controls.Border]::new()
            $card.CornerRadius = [System.Windows.CornerRadius]::new(8)
            $card.Margin = [System.Windows.Thickness]::new(0,3,0,3)
            $card.Padding = [System.Windows.Thickness]::new(14,10,14,10)

            if ($isWin11Incompatible) {
                $card.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#141420")
                $card.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#2a1a2a")
                $card.BorderThickness = [System.Windows.Thickness]::new(0,0,3,0)
                $card.Opacity = 0.55
            } elseif ($script_item.Recommended) {
                $card.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e")
                $card.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#d4a017")
                $card.BorderThickness = [System.Windows.Thickness]::new(0,0,3,0)
            } else {
                $card.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e")
            }

            $grid = [System.Windows.Controls.Grid]::new()
            $col1 = [System.Windows.Controls.ColumnDefinition]::new(); $col1.Width = [System.Windows.GridLength]::new(32)
            $col2 = [System.Windows.Controls.ColumnDefinition]::new(); $col2.Width = [System.Windows.GridLength]::Auto
            $col3 = [System.Windows.Controls.ColumnDefinition]::new(); $col3.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
            $col4 = [System.Windows.Controls.ColumnDefinition]::new(); $col4.Width = [System.Windows.GridLength]::Auto
            $grid.ColumnDefinitions.Add($col1); $grid.ColumnDefinitions.Add($col2)
            $grid.ColumnDefinitions.Add($col3); $grid.ColumnDefinitions.Add($col4)

            $cb = [System.Windows.Controls.CheckBox]::new()
            $cb.VerticalAlignment = "Center"
            $cb.Tag = $script_item.Path
            if ($isWin11Incompatible) {
                $cb.IsEnabled = $false
            } else {
                $cb.Add_Checked({ Update-SelectedCount })
                $cb.Add_Unchecked({ Update-SelectedCount })
            }
            [System.Windows.Controls.Grid]::SetColumn($cb, 0)
            $script:ScriptCheckboxes[$script_item.Path] = $cb

            $icon = [System.Windows.Controls.TextBlock]::new()
            $icon.Text = $script_item.Icon
            $icon.FontSize = 18; $icon.VerticalAlignment = "Center"; $icon.Margin = [System.Windows.Thickness]::new(0,0,12,0)
            [System.Windows.Controls.Grid]::SetColumn($icon, 1)

            $textStack = [System.Windows.Controls.StackPanel]::new()
            $textStack.VerticalAlignment = "Center"

            $nameRow = [System.Windows.Controls.StackPanel]::new()
            $nameRow.Orientation = "Horizontal"; $nameRow.VerticalAlignment = "Center"

            $nameText = [System.Windows.Controls.TextBlock]::new()
            $nameText.Text = $script_item.Name; $nameText.FontSize = 13; $nameText.FontWeight = "Medium"
            $nameText.VerticalAlignment = "Center"
            $nameColor = if ($isWin11Incompatible) { "#505060" } elseif ($script_item.Recommended) { "#d4a017" } else { "#e0e0f4" }
            $nameText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom($nameColor)
            $nameRow.Children.Add($nameText) | Out-Null

            # Бейдж Win11
            if ($script_item.Win11Only) {
                $w11b = [System.Windows.Controls.Border]::new()
                $w11b.CornerRadius = [System.Windows.CornerRadius]::new(4)
                $w11b.Padding = [System.Windows.Thickness]::new(5,1,5,1)
                $w11b.Margin  = [System.Windows.Thickness]::new(7,0,0,0)
                $w11b.VerticalAlignment = "Center"
                $w11b.BorderThickness = [System.Windows.Thickness]::new(1)
                if ($isWin11Incompatible) {
                    $w11b.Background  = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a0a0a")
                    $w11b.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#4a2222")
                } else {
                    $w11b.Background  = [Windows.Media.BrushConverter]::new().ConvertFrom("#0a1a2e")
                    $w11b.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a5aaa")
                }
                $w11t = [System.Windows.Controls.TextBlock]::new()
                $w11t.FontSize = 10; $w11t.FontWeight = "SemiBold"
                $w11t.Text = if ($isWin11Incompatible) { "⊘ Только Win 11" } else { "⊞ Win 11" }
                $w11t.Foreground = if ($isWin11Incompatible) {
                    [Windows.Media.BrushConverter]::new().ConvertFrom("#7a3030")
                } else {
                    [Windows.Media.BrushConverter]::new().ConvertFrom("#4a9eff")
                }
                $w11b.Child = $w11t
                $nameRow.Children.Add($w11b) | Out-Null
            }

            # Бейдж безопасности (только для совместимых)
            if (-not $isWin11Incompatible -and $script_item.Tag -in 1,2,3) {
                $tagBorder = [System.Windows.Controls.Border]::new()
                $tagBorder.CornerRadius = [System.Windows.CornerRadius]::new(4)
                $tagBorder.Padding = [System.Windows.Thickness]::new(5,1,5,1)
                $tagBorder.Margin  = [System.Windows.Thickness]::new(7,0,0,0)
                $tagBorder.VerticalAlignment = "Center"
                $tagBorder.BorderThickness = [System.Windows.Thickness]::new(1)
                $tagTxt = [System.Windows.Controls.TextBlock]::new()
                $tagTxt.FontSize = 10; $tagTxt.FontWeight = "SemiBold"
                switch ($script_item.Tag) {
                    1 { $tagBorder.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#0d2d1a"); $tagBorder.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFrom("#1a6b35"); $tagTxt.Text="● безопасно"; $tagTxt.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#2ecc71") }
                    2 { $tagBorder.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#2d2200"); $tagBorder.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFrom("#a07800"); $tagTxt.Text="● осторожно"; $tagTxt.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#f0c040") }
                    3 { $tagBorder.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#2d0d0d"); $tagBorder.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFrom("#8b1a1a"); $tagTxt.Text="● опасно"; $tagTxt.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#e74c3c") }
                }
                $tagBorder.Child = $tagTxt
                $nameRow.Children.Add($tagBorder) | Out-Null
            }
            $textStack.Children.Add($nameRow) | Out-Null

            $descText = [System.Windows.Controls.TextBlock]::new()
            if ($isWin11Incompatible) {
                $descText.Text = "Требуется Windows 11 — недоступно на вашей системе"
                $descText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#7a5a5a")
            } else {
                $descText.Text = if ($script_item.Desc) { $script_item.Desc } else { $script_item.Path | Split-Path -Leaf }
                $descText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#c4c4ee")
            }
            $descText.FontSize = 11; $descText.Margin = [System.Windows.Thickness]::new(0,2,0,0)
            $descText.TextTrimming = "CharacterEllipsis"
            $textStack.Children.Add($descText) | Out-Null
            [System.Windows.Controls.Grid]::SetColumn($textStack, 2)

            # Кнопка ▶ одного скрипта
            $runOneBtn = [System.Windows.Controls.Button]::new()
            $runOneBtn.Content = "▶"
            $runOneBtn.ToolTip = "Запустить только этот скрипт"
            $runOneBtn.Cursor = [System.Windows.Input.Cursors]::Hand
            $runOneBtn.BorderThickness = [System.Windows.Thickness]::new(0)
            $runOneBtn.Width = 30; $runOneBtn.Height = 30; $runOneBtn.FontSize = 12
            $runOneBtn.VerticalAlignment = "Center"
            $runOneBtn.Margin = [System.Windows.Thickness]::new(8,0,0,0)
            $runOneBtn.Tag = $script_item.Path

            if ($isWin11Incompatible) {
                $runOneBtn.IsEnabled = $false
                $runOneBtn.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a28")
                $runOneBtn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#505068")
            } else {
                $runOneBtn.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#2a2a4a")
                $runOneBtn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#6c63ff")
                $runOneBtn.Add_Click({
                    $scriptPath = $this.Tag
                    Write-Log "══ Запуск: $(Split-Path $scriptPath -Leaf) ══"
                    [System.Threading.Tasks.Task]::Run([Action]{
                        try {
                            & $scriptPath 2>&1 | ForEach-Object { Write-Log "  $_" }
                            Write-Log "✓ Выполнено успешно" -Color "Green"
                        } catch {
                            Write-Log "✗ Ошибка: $_" -Color "Red"
                        }
                    }) | Out-Null
                })
            }
            [System.Windows.Controls.Grid]::SetColumn($runOneBtn, 3)

            $grid.Children.Add($cb) | Out-Null
            $grid.Children.Add($icon) | Out-Null
            $grid.Children.Add($textStack) | Out-Null
            $grid.Children.Add($runOneBtn) | Out-Null
            $card.Child = $grid

            if (-not $isWin11Incompatible) {
                $card.Add_MouseEnter({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#20203a") })
                $card.Add_MouseLeave({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e") })
            }
            $scriptsPanel.Children.Add($card) | Out-Null
        }
    }
    Update-SelectedCount
    $win11Count = @($scripts | Where-Object { $_.Win11Only }).Count
    Write-Log "Загружено скриптов: $($scripts.Count)$(if($win11Count -gt 0){" (только Win11: $win11Count, ОС: Windows $($script:WindowsMajorVersion))"})"
}

# ═══ Приложения ═══
function Load-Apps {
    $fallback = @{
        "Утилиты" = @(
            @{ Name="7-Zip"; Id="7zip.7zip"; Description="Бесплатный архиватор." }
            @{ Name="Notepad++"; Id="Notepad++.Notepad++"; Description="Текстовый редактор." }
        )
        "Медиа" = @(@{ Name="VLC"; Id="VideoLAN.VLC"; Description="Универсальный медиаплеер." })
    }
    if (Test-Path $script:AppsJsonPath) {
        try {
            $j = Get-Content $script:AppsJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            Write-Log "✓ apps.json: $($j.ManualCategories.PSObject.Properties.Name.Count) категорий"
            return $j
        } catch { Write-Log "⚠ Ошибка apps.json, резервный список." -Color "Yellow" }
    }
    return [PSCustomObject]@{ ManualCategories = $fallback; Presets = @{} }
}

function Build-AppsPanel {
    $appsPanel.Children.Clear()
    $script:AppCheckboxes = @{}
    $appsData = Load-Apps
    foreach ($category in $appsData.ManualCategories.PSObject.Properties) {
        $h = [System.Windows.Controls.Border]::new()
        $h.Margin=[System.Windows.Thickness]::new(0,16,0,6); $h.Padding=[System.Windows.Thickness]::new(0,0,0,6)
        $h.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFrom("#1e1e38"); $h.BorderThickness=[System.Windows.Thickness]::new(0,0,0,1)
        $t=[System.Windows.Controls.TextBlock]::new(); $t.Text=$category.Name.ToUpper()
        $t.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#6c63ff"); $t.FontSize=11; $t.FontWeight="SemiBold"
        $h.Child=$t; $appsPanel.Children.Add($h) | Out-Null
        foreach ($app in $category.Value) {
            $card=[System.Windows.Controls.Border]::new()
            $card.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e")
            $card.CornerRadius=[System.Windows.CornerRadius]::new(6); $card.Margin=[System.Windows.Thickness]::new(0,2,0,2); $card.Padding=[System.Windows.Thickness]::new(12,8,12,8)
            $stk=[System.Windows.Controls.StackPanel]::new(); $stk.VerticalAlignment="Center"
            $cb=[System.Windows.Controls.CheckBox]::new(); $cb.Content=$app.Name; $cb.Tag=$app.Id
            $cb.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#c8c8e0"); $cb.FontSize=13; $cb.FontWeight="Medium"
            $script:AppCheckboxes[$app.Id]=$cb
            $desc=[System.Windows.Controls.TextBlock]::new(); $desc.Text=$app.Description
            $desc.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#c4c4ee"); $desc.FontSize=11; $desc.Margin=[System.Windows.Thickness]::new(28,2,0,0); $desc.TextWrapping="Wrap"
            $stk.Children.Add($cb) | Out-Null; $stk.Children.Add($desc) | Out-Null
            $card.Child=$stk
            $card.Add_MouseEnter({ $this.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#20203a") })
            $card.Add_MouseLeave({ $this.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e") })
            $appsPanel.Children.Add($card) | Out-Null
        }
    }
}

# ═══ О системе ═══
function Build-SysPanel {
    $sysInfo = Get-SystemInfo
    $headerOsText.Text = $sysInfo.OS
    $allDisks = @()
    try {
        foreach ($ld in (Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 })) {
            try {
                $part = Get-WmiObject -Query "ASSOCIATORS OF {Win32_LogicalDisk.DeviceID='$($ld.DeviceID)'} WHERE AssocClass=Win32_LogicalDiskToPartition" | Select-Object -First 1
                $phys = Get-WmiObject -Query "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($part.DeviceID)'} WHERE AssocClass=Win32_DiskDriveToDiskPartition" | Select-Object -First 1
                $model = ($phys.Model -replace '\s+',' ').Trim()
            } catch { $model="Неизвестно"; $phys=$null }
            $allDisks += @{ Letter=$ld.DeviceID; Model=$model; FreeGB=[math]::Round($ld.FreeSpace/1GB,1); TotalGB=[math]::Round($ld.Size/1GB,1); IsSystem=($ld.DeviceID -eq "C:"); PhysDisk=$phys }
        }
    } catch {}

    $sysPanel.Children.Clear()
    foreach ($item in @(
        @{ L="💻 ОС"; V=$sysInfo.OS; Btn=$null }
        @{ L="⚙️ Процессор"; V=$sysInfo.CPU; Btn=$null }
        @{ L="🧠 RAM"; V=$sysInfo.RAM; Btn=$null }
        @{ L="🪟 Windows"; V="Windows $($script:WindowsMajorVersion)"; Btn=$null }
        @{ L="⏱️ Время работы"; V=$sysInfo.Uptime; Btn=$null }
        @{ L="📂 Рабочая папка"; V=$script:WorkFolder; Btn="Открыть" }
    )) {
        $row=[System.Windows.Controls.Border]::new()
        $row.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e"); $row.CornerRadius=[System.Windows.CornerRadius]::new(8)
        $row.Margin=[System.Windows.Thickness]::new(0,4,0,4); $row.Padding=[System.Windows.Thickness]::new(16,12,16,12)
        $g=[System.Windows.Controls.Grid]::new()
        $c1=[System.Windows.Controls.ColumnDefinition]::new(); $c1.Width="210"
        $c2=[System.Windows.Controls.ColumnDefinition]::new(); $c2.Width="*"
        $c3=[System.Windows.Controls.ColumnDefinition]::new(); $c3.Width="Auto"
        $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2); $g.ColumnDefinitions.Add($c3)
        $lbl=[System.Windows.Controls.TextBlock]::new(); $lbl.Text=$item.L; $lbl.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#9898b0"); $lbl.FontSize=13; $lbl.VerticalAlignment="Center"
        $val=[System.Windows.Controls.TextBlock]::new(); $val.Text=$item.V; $val.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#d0d0f0"); $val.FontSize=13; $val.FontWeight="SemiBold"; $val.TextWrapping="Wrap"; $val.VerticalAlignment="Center"
        [System.Windows.Controls.Grid]::SetColumn($val,1)
        $g.Children.Add($lbl) | Out-Null; $g.Children.Add($val) | Out-Null
        if ($item.Btn -eq "Открыть") {
            $fp=$item.V
            $ob=[System.Windows.Controls.Button]::new(); $ob.Content="📂 Открыть"; $ob.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#2a2a42")
            $ob.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#c0c0dd"); $ob.BorderThickness=[System.Windows.Thickness]::new(0); $ob.Cursor=[System.Windows.Input.Cursors]::Hand
            $ob.FontSize=11; $ob.Padding=[System.Windows.Thickness]::new(10,5,10,5); $ob.VerticalAlignment="Center"; $ob.Margin=[System.Windows.Thickness]::new(8,0,0,0); $ob.Tag=$fp
            $ob.Add_Click({ $p=$this.Tag; if (-not (Test-Path $p)){New-Item -ItemType Directory -Path $p -Force|Out-Null}; Start-Process explorer.exe $p })
            [System.Windows.Controls.Grid]::SetColumn($ob,2); $g.Children.Add($ob) | Out-Null
        }
        $row.Child=$g; $sysPanel.Children.Add($row) | Out-Null
    }

    if ($allDisks.Count -gt 0) {
        $dh=[System.Windows.Controls.Border]::new(); $dh.Margin=[System.Windows.Thickness]::new(0,8,0,4); $dh.Padding=[System.Windows.Thickness]::new(0,0,0,6)
        $dh.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFrom("#1e1e38"); $dh.BorderThickness=[System.Windows.Thickness]::new(0,0,0,1)
        $dht=[System.Windows.Controls.TextBlock]::new(); $dht.Text="ДИСКИ"; $dht.FontSize=11; $dht.FontWeight="SemiBold"; $dht.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#6c63ff")
        $dh.Child=$dht; $sysPanel.Children.Add($dh) | Out-Null
        foreach ($disk in $allDisks) {
            $drow=[System.Windows.Controls.Border]::new(); $drow.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e"); $drow.CornerRadius=[System.Windows.CornerRadius]::new(8)
            $drow.Margin=[System.Windows.Thickness]::new(0,3,0,3); $drow.Padding=[System.Windows.Thickness]::new(16,10,16,10)
            $dg=[System.Windows.Controls.Grid]::new()
            foreach ($w in @("40","*","Auto","Auto")) { $dc=[System.Windows.Controls.ColumnDefinition]::new(); $dc.Width=$w; $dg.ColumnDefinitions.Add($dc) }
            $dl=[System.Windows.Controls.TextBlock]::new(); $dl.Text=$disk.Letter; $dl.FontSize=14; $dl.FontWeight="Bold"; $dl.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#8080d0"); $dl.VerticalAlignment="Center"
            $di=[System.Windows.Controls.StackPanel]::new(); $di.VerticalAlignment="Center"
            $dm=[System.Windows.Controls.TextBlock]::new(); $dm.Text=$disk.Model; $dm.FontSize=12; $dm.FontWeight="Medium"; $dm.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#d0d0f0"); $dm.TextTrimming="CharacterEllipsis"
            $ds=[System.Windows.Controls.TextBlock]::new(); $ds.Text="$($disk.FreeGB) ГБ своб. из $($disk.TotalGB) ГБ"; $ds.FontSize=10; $ds.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#c4c4ee")
            $di.Children.Add($dm)|Out-Null; $di.Children.Add($ds)|Out-Null; [System.Windows.Controls.Grid]::SetColumn($di,1)
            if ($disk.IsSystem) {
                $sb=[System.Windows.Controls.Border]::new(); $sb.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a4a"); $sb.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFrom("#3a3aaa"); $sb.BorderThickness=[System.Windows.Thickness]::new(1); $sb.CornerRadius=[System.Windows.CornerRadius]::new(4); $sb.Padding=[System.Windows.Thickness]::new(6,2,6,2); $sb.VerticalAlignment="Center"; $sb.Margin=[System.Windows.Thickness]::new(8,0,0,0)
                $st=[System.Windows.Controls.TextBlock]::new(); $st.Text="СИСТЕМА"; $st.FontSize=10; $st.FontWeight="SemiBold"; $st.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#8080ff")
                $sb.Child=$st; [System.Windows.Controls.Grid]::SetColumn($sb,2); $dg.Children.Add($sb)|Out-Null
            }
            $smBtn=[System.Windows.Controls.Button]::new(); $smBtn.Content="🔍 SMART"; $smBtn.FontSize=11
            $smBtn.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#1a2a42"); $smBtn.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#7ab0e0"); $smBtn.BorderThickness=[System.Windows.Thickness]::new(0); $smBtn.Cursor=[System.Windows.Input.Cursors]::Hand; $smBtn.Padding=[System.Windows.Thickness]::new(10,4,10,4); $smBtn.VerticalAlignment="Center"; $smBtn.Margin=[System.Windows.Thickness]::new(8,0,0,0); $smBtn.Tag=$disk.PhysDisk
            $smBtn.Add_Click({
                $driveObj=$this.Tag
                try {
                    $physDisk=Get-PhysicalDisk|Where-Object{$driveObj-and($_.FriendlyName-like "*$($driveObj.Model.Trim().Split(' ')[0])*")}|Select-Object -First 1
                    if(-not $physDisk){$physDisk=Get-PhysicalDisk|Select-Object -First 1}
                    $rel=$physDisk|Get-StorageReliabilityCounter
                    $healthRu=switch($physDisk.HealthStatus){"Healthy"{"✅ Здоров"}"Warning"{"⚠️ Предупреждение"}"Unhealthy"{"❌ Неисправен"}default{"❓ Неизвестно"}}
                    $healthColor=switch($physDisk.HealthStatus){"Healthy"{"#2ecc71"}"Warning"{"#f39c12"}"Unhealthy"{"#e74c3c"}default{"#a0a0c0"}}
                    [xml]$sx=@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="SMART" Width="460" Height="420" WindowStartupLocation="CenterScreen" Background="#12121f" ResizeMode="NoResize">
  <StackPanel Margin="20">
    <TextBlock Text="$($physDisk.FriendlyName)" Foreground="White" FontSize="14" FontWeight="Bold" Margin="0,0,0,4"/>
    <TextBlock Text="$($physDisk.MediaType)  •  $([math]::Round($physDisk.Size/1GB)) ГБ" Foreground="#606080" FontSize="11" Margin="0,0,0,14"/>
    <Border Background="#1a1a2e" CornerRadius="8" Padding="14,9" Margin="0,0,0,5"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Состояние" Foreground="#808090" FontSize="12" VerticalAlignment="Center"/><TextBlock Grid.Column="1" Text="$healthRu" Foreground="$healthColor" FontSize="12" FontWeight="Bold"/></Grid></Border>
    <Border Background="#1a1a2e" CornerRadius="8" Padding="14,9" Margin="0,0,0,5"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Температура" Foreground="#808090" FontSize="12" VerticalAlignment="Center"/><TextBlock Grid.Column="1" Text="$(if($rel.Temperature){"$($rel.Temperature) °C"}else{"Нет данных"})" Foreground="$(if($rel.Temperature -gt 50){"#e74c3c"}elseif($rel.Temperature -gt 40){"#f39c12"}else{"#2ecc71"})" FontSize="12" FontWeight="Bold"/></Grid></Border>
    <Border Background="#1a1a2e" CornerRadius="8" Padding="14,9" Margin="0,0,0,5"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Часов наработки" Foreground="#808090" FontSize="12" VerticalAlignment="Center"/><TextBlock Grid.Column="1" Text="$(if($rel.PowerOnHours){"$($rel.PowerOnHours) ч"}else{"Нет данных"})" Foreground="#d0d0f0" FontSize="12" FontWeight="Bold"/></Grid></Border>
    <Border Background="#1a1a2e" CornerRadius="8" Padding="14,9" Margin="0,0,0,5"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Ошибки чтения" Foreground="#808090" FontSize="12" VerticalAlignment="Center"/><TextBlock Grid.Column="1" Text="$(if($rel.ReadErrorsTotal){"$($rel.ReadErrorsTotal)"}else{"0"})" Foreground="$(if($rel.ReadErrorsTotal -gt 0){"#f39c12"}else{"#2ecc71"})" FontSize="12" FontWeight="Bold"/></Grid></Border>
    <Border Background="#1a1a2e" CornerRadius="8" Padding="14,9" Margin="0,0,0,5"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Ошибки записи" Foreground="#808090" FontSize="12" VerticalAlignment="Center"/><TextBlock Grid.Column="1" Text="$(if($rel.WriteErrorsTotal){"$($rel.WriteErrorsTotal)"}else{"0"})" Foreground="$(if($rel.WriteErrorsTotal -gt 0){"#f39c12"}else{"#2ecc71"})" FontSize="12" FontWeight="Bold"/></Grid></Border>
    <Border Background="#1a1a2e" CornerRadius="8" Padding="14,9" Margin="0,0,0,14"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Износ" Foreground="#808090" FontSize="12" VerticalAlignment="Center"/><TextBlock Grid.Column="1" Text="$(if($rel.Wear){"$($rel.Wear)%"}else{"Нет данных"})" Foreground="#d0d0f0" FontSize="12" FontWeight="Bold"/></Grid></Border>
    <TextBlock Text="⚠ Данные через Windows Storage API. Для детального анализа используйте CrystalDiskInfo." Foreground="#9898c8" FontSize="10" TextWrapping="Wrap"/>
  </StackPanel>
</Window>
"@
                    $sr=[System.Xml.XmlNodeReader]::new($sx); $sw=[Windows.Markup.XamlReader]::Load($sr); $sw.ShowDialog()|Out-Null
                } catch { [System.Windows.MessageBox]::Show("Не удалось получить SMART данные:`n$_","SMART","OK","Warning") }
            })
            $smBtn.Add_MouseEnter({ $this.Opacity=0.8 }); $smBtn.Add_MouseLeave({ $this.Opacity=1.0 })
            [System.Windows.Controls.Grid]::SetColumn($smBtn,3)
            $dg.Children.Add($dl)|Out-Null; $dg.Children.Add($di)|Out-Null; $dg.Children.Add($smBtn)|Out-Null
            $drow.Child=$dg; $sysPanel.Children.Add($drow)|Out-Null
        }
    }
}

# ═══ Запуск скриптов (фон) ═══
function Run-SelectedScripts {
    $selected = $script:ScriptCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked }
    if (-not $selected) { Write-Log "⚠ Нет выбранных скриптов" -Color "Yellow"; return }
    $pathsList = @($selected | ForEach-Object { $_.Key })
    $reboot = $rebootAfterChk.IsChecked
    $count = $pathsList.Count
    Write-Log "══════════════════════════════════════"
    Write-Log "▶ Запуск $count скриптов..."
    Write-Log "══════════════════════════════════════"
    [System.Threading.Tasks.Task]::Run([Action]{
        $ok=0; $fail=0
        foreach ($scriptPath in $pathsList) {
            Write-Log "── $(Split-Path $scriptPath -Leaf)"
            try {
                & $scriptPath 2>&1 | ForEach-Object { Write-Log "   $_" }
                Write-Log "   ✓ Готово" -Color "Green"; $ok++
            } catch {
                Write-Log "   ✗ Ошибка: $_" -Color "Red"; $fail++
            }
        }
        Write-Log "══════════════════════════════════════"
        Write-Log "Завершено: ✓$ok$(if($fail-gt 0){" ✗$fail ошибок"})"
        Write-Log "══════════════════════════════════════"
        if ($reboot) { Write-Log "🔄 Перезагрузка через 10 секунд..."; Start-Sleep 10; Restart-Computer -Force }
    }) | Out-Null
}

function Select-Preset($presetName) {
    $appsData = Load-Apps
    if (-not $appsData.Presets.$presetName) { Write-Log "⚠ Пресет '$presetName' не найден" -Color "Yellow"; return }
    foreach ($cb in $script:AppCheckboxes.Values) { $cb.IsChecked = $false }
    foreach ($id in $appsData.Presets.$presetName) {
        if ($script:AppCheckboxes.ContainsKey($id)) { $script:AppCheckboxes[$id].IsChecked = $true }
    }
    Write-Log "✓ Пресет $presetName применён" -Color "Green"
}

function Select-RecommendedScripts {
    $scripts = Load-Scripts; $n = 0
    foreach ($s in $scripts) {
        if ($s.Win11Only -and $script:WindowsMajorVersion -lt 11) { continue }
        if ($s.Recommended -and $script:ScriptCheckboxes.ContainsKey($s.Path)) {
            $script:ScriptCheckboxes[$s.Path].IsChecked = $true; $n++
        }
    }
    Write-Log "✓ Выбрано $n рекомендованных скриптов" -Color "Green"
    Update-SelectedCount
}

# ═══ Обновления ═══
$script:UpdateCheckboxes = @{}

function Build-UpdatesPanel {
    $updatesPanel.Children.Clear(); $script:UpdateCheckboxes.Clear()
    $updateStatusText.Text = "Идёт проверка обновлений..."; $updateCountText.Text = ""
    Write-Log "🔍 Проверка обновлений через winget..."
    $rawOutput = winget upgrade 2>&1 | Out-String
    $lines = $rawOutput -split "`n" | Where-Object { $_ -match '\S' }
    $packages = @(); $headerFound = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*-+\s*$') { $headerFound=$true; continue }
        if (-not $headerFound -or $line -match '^\s*$') { continue }
        $parts = $line -split '\s{2,}' | Where-Object { $_.Trim() -ne '' }
        if ($parts.Count -ge 4) {
            $packages += @{ Name=$parts[0].Trim(); Id=$parts[1].Trim(); Version=$parts[2].Trim(); NewVersion=$parts[3].Trim() }
        }
    }
    if ($packages.Count -eq 0) {
        $lbl=[System.Windows.Controls.TextBlock]::new(); $lbl.Text="✅ Все пакеты актуальны — обновлений нет."
        $lbl.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#50e050"); $lbl.FontSize=13; $lbl.TextAlignment="Center"; $lbl.Margin="0,60,0,0"
        $updatesPanel.Children.Add($lbl)|Out-Null; $updateStatusText.Text="✅ Обновлений нет"; Write-Log "✅ Обновлений нет"; return
    }
    foreach ($pkg in $packages) {
        $card=[System.Windows.Controls.Border]::new(); $card.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e"); $card.CornerRadius=[System.Windows.CornerRadius]::new(7); $card.Margin=[System.Windows.Thickness]::new(0,3,0,3); $card.Padding=[System.Windows.Thickness]::new(12,8,12,8)
        $g=[System.Windows.Controls.Grid]::new()
        foreach ($w in @(28,0,0)) { $dc=[System.Windows.Controls.ColumnDefinition]::new(); if($w-gt 0){$dc.Width=[System.Windows.GridLength]::new($w)}else{if($g.ColumnDefinitions.Count-eq 1){$dc.Width=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)}else{$dc.Width=[System.Windows.GridLength]::Auto}}; $g.ColumnDefinitions.Add($dc) }
        $cb=[System.Windows.Controls.CheckBox]::new(); $cb.VerticalAlignment="Center"; $cb.Tag=$pkg.Id
        $cb.Add_Checked({ $updateCountText.Text="Выбрано: $(($script:UpdateCheckboxes.Values|Where-Object{$_.IsChecked}).Count)" })
        $cb.Add_Unchecked({ $updateCountText.Text="Выбрано: $(($script:UpdateCheckboxes.Values|Where-Object{$_.IsChecked}).Count)" })
        [System.Windows.Controls.Grid]::SetColumn($cb,0); $script:UpdateCheckboxes[$pkg.Id]=$cb
        $info=[System.Windows.Controls.StackPanel]::new(); $info.VerticalAlignment="Center"
        $nm=[System.Windows.Controls.TextBlock]::new(); $nm.Text=$pkg.Name; $nm.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#e0e0f4"); $nm.FontSize=12; $nm.FontWeight="Medium"
        $id=[System.Windows.Controls.TextBlock]::new(); $id.Text=$pkg.Id; $id.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#c4c4ee"); $id.FontSize=10; $id.Margin=[System.Windows.Thickness]::new(0,1,0,0)
        $info.Children.Add($nm)|Out-Null; $info.Children.Add($id)|Out-Null; [System.Windows.Controls.Grid]::SetColumn($info,1)
        $ver=[System.Windows.Controls.TextBlock]::new(); $ver.Text="$($pkg.Version) → $($pkg.NewVersion)"; $ver.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#c0a030"); $ver.FontSize=11; $ver.VerticalAlignment="Center"; [System.Windows.Controls.Grid]::SetColumn($ver,2)
        $g.Children.Add($cb)|Out-Null; $g.Children.Add($info)|Out-Null; $g.Children.Add($ver)|Out-Null; $card.Child=$g
        $card.Add_MouseEnter({ $this.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#20203a") })
        $card.Add_MouseLeave({ $this.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e") })
        $updatesPanel.Children.Add($card)|Out-Null
    }
    $updateStatusText.Text="Найдено обновлений: $($packages.Count)"; $updateCountText.Text="Выбрано: 0"
    Write-Log "🔄 Найдено $($packages.Count) обновлений"
}

function Install-SelectedUpdates {
    $sel=$script:UpdateCheckboxes.GetEnumerator()|Where-Object{$_.Value.IsChecked}
    if (-not $sel){Write-Log "⚠ Нет выбранных" -Color "Yellow"; return}
    $idList=@($sel|ForEach-Object{$_.Key})
    Write-Log "══ Обновление $($idList.Count) пакетов ══"
    [System.Threading.Tasks.Task]::Run([Action]{
        foreach ($id in $idList) {
            Write-Log "⬆ $id..."; winget upgrade --id $id --silent --accept-source-agreements --accept-package-agreements 2>&1|ForEach-Object{Write-Log "   $_"}; Write-Log "   ✓" -Color "Green"
        }
        Write-Log "══ Обновление завершено ══"
        $script:LogBox.Dispatcher.Invoke([action]{ Build-UpdatesPanel })
    }) | Out-Null
}

# ═══ Тест системы (с фоновым запуском + статус) ═══
function Build-DiagPanel {
    $diagPanel.Children.Clear()
    $tests = @(
        @{ Title="Проверка системных файлов (SFC)"; Desc="Сканирует и восстанавливает повреждённые файлы Windows. Занимает 5–15 минут."; Icon="🛡️"; Color="#4a90d9"
           Action={ [System.Threading.Tasks.Task]::Run([Action]{ sfc /scannow 2>&1|ForEach-Object{Write-Log "  $_"}; Write-Log "✓ SFC завершён" -Color "Green" }) | Out-Null } }
        @{ Title="Восстановление Windows (DISM)"; Desc="Восстанавливает образ через Windows Update. Требует интернет. Занимает 10–30 минут."; Icon="🔧"; Color="#7c63ff"
           Action={ [System.Threading.Tasks.Task]::Run([Action]{ DISM /Online /Cleanup-Image /RestoreHealth 2>&1|ForEach-Object{Write-Log "  $_"}; Write-Log "✓ DISM завершён" -Color "Green" }) | Out-Null } }
        @{ Title="Проверка диска C: (CHKDSK)"; Desc="Проверяет ФС на ошибки. Полная проверка — при перезагрузке."; Icon="💾"; Color="#2da86a"
           Action={
               $confirm=[System.Windows.MessageBox]::Show("CHKDSK запустится при следующей перезагрузке.`nПерезагрузить сейчас?","CHKDSK","YesNo","Question")
               [System.Threading.Tasks.Task]::Run([Action]{
                   chkdsk C: /f /r /x 2>&1|ForEach-Object{Write-Log "  $_"}
                   if($confirm-eq"Yes"){Write-Log "Перезагрузка через 30 сек..."; shutdown /r /t 30 /c "PotatoPC CHKDSK"}
                   else{Write-Log "ℹ CHKDSK выполнится при следующей перезагрузке." -Color "Yellow"}
               }) | Out-Null
           } }
        @{ Title="Диагностика RAM"; Desc="Windows Memory Diagnostic. Требует перезагрузку."; Icon="🧠"; Color="#d4601a"
           Action={
               $confirm=[System.Windows.MessageBox]::Show("Диагностика запустится после перезагрузки.`nПерезагрузить сейчас?","RAM","YesNo","Question")
               if($confirm-eq"Yes"){Write-Log "Запуск MdSched..."; MdSched.exe}
               else{Write-Log "ℹ Диагностика RAM отменена." -Color "Yellow"}
           } }
    )

    foreach ($test in $tests) {
        $card=[System.Windows.Controls.Border]::new(); $card.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e"); $card.CornerRadius=[System.Windows.CornerRadius]::new(10); $card.Margin=[System.Windows.Thickness]::new(0,5,0,5); $card.Padding=[System.Windows.Thickness]::new(16,14,16,14)
        $card.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFrom($test.Color+"55"); $card.BorderThickness=[System.Windows.Thickness]::new(0,0,0,2)
        $g=[System.Windows.Controls.Grid]::new()
        $c1=[System.Windows.Controls.ColumnDefinition]::new(); $c1.Width=[System.Windows.GridLength]::new(44)
        $c2=[System.Windows.Controls.ColumnDefinition]::new(); $c2.Width=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
        $c3=[System.Windows.Controls.ColumnDefinition]::new(); $c3.Width=[System.Windows.GridLength]::Auto
        $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2); $g.ColumnDefinitions.Add($c3)

        $ico=[System.Windows.Controls.TextBlock]::new(); $ico.Text=$test.Icon; $ico.FontSize=26; $ico.VerticalAlignment="Center"; $ico.HorizontalAlignment="Center"
        [System.Windows.Controls.Grid]::SetColumn($ico,0)

        $txt=[System.Windows.Controls.StackPanel]::new(); $txt.VerticalAlignment="Center"; $txt.Margin=[System.Windows.Thickness]::new(12,0,12,0)
        $titleRow=[System.Windows.Controls.StackPanel]::new(); $titleRow.Orientation="Horizontal"
        $ttl=[System.Windows.Controls.TextBlock]::new(); $ttl.Text=$test.Title; $ttl.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#e0e0f4"); $ttl.FontSize=13; $ttl.FontWeight="SemiBold"
        # Метка статуса рядом с заголовком
        $statusLbl=[System.Windows.Controls.TextBlock]::new(); $statusLbl.FontSize=11; $statusLbl.VerticalAlignment="Center"; $statusLbl.Margin=[System.Windows.Thickness]::new(10,0,0,0); $statusLbl.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#a8a8d0"); $statusLbl.Text=""
        $titleRow.Children.Add($ttl)|Out-Null; $titleRow.Children.Add($statusLbl)|Out-Null
        $dsc=[System.Windows.Controls.TextBlock]::new(); $dsc.Text=$test.Desc; $dsc.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#b8b8cc"); $dsc.FontSize=11; $dsc.Margin=[System.Windows.Thickness]::new(0,3,0,0); $dsc.TextWrapping="Wrap"
        $txt.Children.Add($titleRow)|Out-Null; $txt.Children.Add($dsc)|Out-Null
        [System.Windows.Controls.Grid]::SetColumn($txt,1)

        $btn=[System.Windows.Controls.Button]::new(); $btn.Content="▶ Запустить"
        $btn.Background=[Windows.Media.BrushConverter]::new().ConvertFrom($test.Color); $btn.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#ffffff")
        $btn.BorderThickness=[System.Windows.Thickness]::new(0); $btn.Cursor=[System.Windows.Input.Cursors]::Hand; $btn.FontSize=12; $btn.FontWeight="SemiBold"; $btn.Padding=[System.Windows.Thickness]::new(14,8,14,8); $btn.VerticalAlignment="Center"
        $btn.Add_MouseEnter({ $this.Opacity=0.85 }); $btn.Add_MouseLeave({ $this.Opacity=1.0 })

        # Захватываем переменные для замыкания
        $capturedAction  = $test.Action
        $capturedBtn     = $btn
        $capturedLbl     = $statusLbl

        $btn.Add_Click({
            # Немедленно блокируем кнопку и показываем статус
            $capturedBtn.IsEnabled = $false
            $capturedBtn.Content = "⏳ Выполняется..."
            $capturedLbl.Text = "● запущено"
            $capturedLbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#f0c040")

            $localAction = $capturedAction
            $localBtn    = $capturedBtn
            $localLbl    = $capturedLbl

            # Запускаем action (он сам управляет потоком если нужно)
            try { & $localAction } catch { Write-Log "✗ $_" -Color "Red" }

            # Восстанавливаем кнопку через диспетчер после небольшой задержки
            [System.Threading.Tasks.Task]::Run([Action]{
                Start-Sleep -Milliseconds 500
                $localBtn.Dispatcher.Invoke([action]{
                    $localBtn.IsEnabled = $true
                    $localBtn.Content = "▶ Запустить"
                    $localLbl.Text = "✓ запущено в фоне"
                    $localLbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#2ecc71")
                })
            }) | Out-Null
        })

        [System.Windows.Controls.Grid]::SetColumn($btn,2)
        $g.Children.Add($ico)|Out-Null; $g.Children.Add($txt)|Out-Null; $g.Children.Add($btn)|Out-Null; $card.Child=$g
        $card.Add_MouseEnter({ $this.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#1e1e35") })
        $card.Add_MouseLeave({ $this.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e") })
        $diagPanel.Children.Add($card)|Out-Null
    }
}

# ═══ Автозагрузка (улучшенная версия) ═══
$script:StartupCheckboxes = @{}
$script:TaskCheckboxes    = @{}

# Проверяет StartupApproved в реестре (байт[0]: 02/06=вкл, 03/07=выкл)
function Get-StartupApprovedStatus {
    param($ApprovedKey, [string]$ValueName)
    if ($null -eq $ApprovedKey) { return $true }
    try {
        $data = $ApprovedKey.GetValue($ValueName)
        if ($data -is [byte[]] -and $data.Length -ge 4) {
            return ($data[0] -ne 0x03 -and $data[0] -ne 0x07)
        }
    } catch {}
    return $true
}

# Получает издателя/описание из FileVersionInfo
function Get-AppPublisher {
    param([string]$Command)
    try {
        $path = $Command.Trim('"')
        $exeIdx = $path.IndexOf('.exe', [System.StringComparison]::OrdinalIgnoreCase)
        if ($exeIdx -gt 0) { $path = $path.Substring(0, $exeIdx + 4).Trim('"', ' ') }
        $path = [System.Environment]::ExpandEnvironmentVariables($path)
        if (-not [System.IO.File]::Exists($path)) {
            # Пробуем найти в PATH
            if (-not $path.Contains('\') -and -not $path.Contains('/')) {
                $envPath = $env:PATH -split [System.IO.Path]::PathSeparator
                foreach ($dir in $envPath) {
                    $full = [System.IO.Path]::Combine($dir, $path)
                    if ([System.IO.File]::Exists($full)) { $path = $full; break }
                }
            }
        }
        if ([System.IO.File]::Exists($path)) {
            $fvi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path)
            $pub = if (-not [string]::IsNullOrWhiteSpace($fvi.CompanyName)) { $fvi.CompanyName }
                   elseif (-not [string]::IsNullOrWhiteSpace($fvi.FileDescription)) { $fvi.FileDescription }
                   else { $null }
            return @{ Publisher=$pub; FilePath=$path }
        }
    } catch {}
    return @{ Publisher=$null; FilePath=$null }
}

# Извлекает иконку приложения (возвращает ImageSource для WPF)
function Get-AppIcon {
    param([string]$Command)
    try {
        $path = $Command.Trim('"')
        $path = [System.Environment]::ExpandEnvironmentVariables($path)
        $exeIdx = $path.IndexOf('.exe', [System.StringComparison]::OrdinalIgnoreCase)
        if ($exeIdx -gt 0) { $path = $path.Substring(0, $exeIdx + 4).Trim('"', ' ') }
        if (-not [System.IO.File]::Exists($path)) {
            if (-not $path.Contains('\') -and -not $path.Contains('/')) {
                $envPath = $env:PATH -split [System.IO.Path]::PathSeparator
                foreach ($dir in $envPath) {
                    $full = [System.IO.Path]::Combine($dir, $path)
                    if ([System.IO.File]::Exists($full)) { $path = $full; break }
                }
            }
        }
        if ([System.IO.File]::Exists($path)) {
            Add-Type -AssemblyName System.Drawing
            $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
            if ($icon) {
                $bmp = $icon.ToBitmap()
                $ms  = [System.IO.MemoryStream]::new()
                $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
                $ms.Position = 0
                $img = [System.Windows.Media.Imaging.BitmapImage]::new()
                $img.BeginInit()
                $img.StreamSource = $ms
                $img.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $img.EndInit()
                $img.Freeze()
                $icon.Dispose(); $bmp.Dispose()
                return $img
            }
        }
    } catch {}
    return $null
}

# Сканирует один ключ реестра и возвращает список элементов
function Scan-RegistryStartup {
    param($RootKey, [string]$SubKeyPath, [string]$ApprovedSubKeyPath, [string]$LocationLabel)
    $result = @()
    try {
        $key = $RootKey.OpenSubKey($SubKeyPath)
        if ($null -eq $key) { return $result }
        $approvedKey = $RootKey.OpenSubKey($ApprovedSubKeyPath)
        foreach ($name in $key.GetValueNames()) {
            $rawVal  = $key.GetValue($name)
            $cmd     = if ($null -ne $rawVal) { $rawVal.ToString() } else { '' }
            $enabled = Get-StartupApprovedStatus -ApprovedKey $approvedKey -ValueName $name
            $result += @{
                Name        = $name
                Command     = $cmd
                Location    = $LocationLabel
                PathOrKey   = "$($RootKey.Name)\$SubKeyPath"
                IsEnabled   = $enabled
                Publisher   = $null
                Icon        = $null
            }
        }
        $key.Dispose()
        if ($approvedKey) { $approvedKey.Dispose() }
    } catch {}
    return $result
}

# Сканирует папку автозагрузки
function Scan-FolderStartup {
    param([string]$DirPath, [string]$LocationLabel, $RootKeyForApproved)
    $result = @()
    if ([string]::IsNullOrWhiteSpace($DirPath) -or -not (Test-Path $DirPath)) { return $result }
    try {
        $approvedPath = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApprovedStartupFolder'
        $approvedKey  = $RootKeyForApproved.OpenSubKey($approvedPath)
        foreach ($file in [System.IO.Directory]::GetFiles($DirPath)) {
            $fileName = [System.IO.Path]::GetFileName($file)
            if ($fileName -eq 'desktop.ini') { continue }
            $enabled = Get-StartupApprovedStatus -ApprovedKey $approvedKey -ValueName $fileName
            $name    = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
            $result += @{
                Name      = if ([string]::IsNullOrWhiteSpace($name)) { $fileName } else { $name }
                Command   = $file
                Location  = $LocationLabel
                PathOrKey = $DirPath
                IsEnabled = $enabled
                Publisher = 'Folder Shortcut'
                Icon      = $null
            }
        }
        if ($approvedKey) { $approvedKey.Dispose() }
    } catch {}
    return $result
}


# Вспомогательная функция обновления счётчика выбранных
function Update-StartupSelectedCount {
    $apps  = ($script:StartupCheckboxes.Values | Where-Object { $_.IsChecked }).Count
    $tasks = ($script:TaskCheckboxes.Values    | Where-Object { $_.IsChecked }).Count
    $total = $apps + $tasks
    if ($total -eq 0) { $startupSelectedText.Text = "" }
    else { $startupSelectedText.Text = "Выбрано: $total" }
}

# Применяет текущий фильтр и поиск к карточкам списка
function Apply-StartupFilter {
    $q = $startupSearchBox.Text.Trim().ToLower()
    foreach ($child in $startupAppsPanel.Children) {
        if ($child -isnot [System.Windows.Controls.Border]) { continue }
        $tag = $child.Tag
        if ($null -eq $tag) { $child.Visibility = "Visible"; continue }

        # Фильтр по типу
        $typeOk = switch ($script:StartupFilter) {
            "Apps"  { $tag.Type -eq "App" }
            "Tasks" { $tag.Type -eq "Task" }
            default { $true }
        }

        # Поиск по имени/издателю
        $searchOk = $q -eq "" -or
                    $tag.Name.ToLower()      -like "*$q*" -or
                    $tag.Publisher.ToLower() -like "*$q*"

        $child.Visibility = if ($typeOk -and $searchOk) { "Visible" } else { "Collapsed" }
    }
}

function Build-StartupPanel {
    $startupAppsPanel.Children.Clear()
    $script:StartupCheckboxes.Clear()
    $script:TaskCheckboxes.Clear()

    # ── Сбор автозагрузки реестра + папок ─────────────────────────────────
    $startupItems = @()
    $approvedRun     = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApprovedRun'
    $approvedRunOnce = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApprovedRunOnce'

    $startupItems += Scan-RegistryStartup `
        -RootKey ([Microsoft.Win32.Registry]::CurrentUser) `
        -SubKeyPath 'Software\Microsoft\Windows\CurrentVersion\Run' `
        -ApprovedSubKeyPath $approvedRun -LocationLabel 'HKCU\Run'

    $startupItems += Scan-RegistryStartup `
        -RootKey ([Microsoft.Win32.Registry]::LocalMachine) `
        -SubKeyPath 'Software\Microsoft\Windows\CurrentVersion\Run' `
        -ApprovedSubKeyPath $approvedRun -LocationLabel 'HKLM\Run'

    $startupItems += Scan-RegistryStartup `
        -RootKey ([Microsoft.Win32.Registry]::LocalMachine) `
        -SubKeyPath 'Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' `
        -ApprovedSubKeyPath $approvedRun -LocationLabel 'HKLM\Run (x86)'

    $startupItems += Scan-RegistryStartup `
        -RootKey ([Microsoft.Win32.Registry]::CurrentUser) `
        -SubKeyPath 'Software\Microsoft\Windows\CurrentVersion\RunOnce' `
        -ApprovedSubKeyPath $approvedRunOnce -LocationLabel 'HKCU\RunOnce'

    $startupItems += Scan-RegistryStartup `
        -RootKey ([Microsoft.Win32.Registry]::LocalMachine) `
        -SubKeyPath 'Software\Microsoft\Windows\CurrentVersion\RunOnce' `
        -ApprovedSubKeyPath $approvedRunOnce -LocationLabel 'HKLM\RunOnce'

    $userStartup   = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Startup)
    $commonStartup = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonStartup)

    $startupItems += Scan-FolderStartup `
        -DirPath $userStartup -LocationLabel 'Папка (пользователь)' `
        -RootKeyForApproved ([Microsoft.Win32.Registry]::CurrentUser)

    $startupItems += Scan-FolderStartup `
        -DirPath $commonStartup -LocationLabel 'Папка (все польз.)' `
        -RootKeyForApproved ([Microsoft.Win32.Registry]::LocalMachine)

    # ── Параллельно: иконки + издатель ────────────────────────────────────
    if ($startupItems.Count -gt 0) {
        $jobs = $startupItems | ForEach-Object {
            $item = $_
            [System.Threading.Tasks.Task]::Run([Action]{
                if ($null -eq $item.Publisher) {
                    $info = Get-AppPublisher -Command $item.Command
                    $item.Publisher = if (-not [string]::IsNullOrWhiteSpace($info.Publisher)) { $info.Publisher } else { $item.Location }
                }
                $item.Icon = Get-AppIcon -Command $item.Command
            })
        }
        [System.Threading.Tasks.Task]::WhenAll($jobs) | Out-Null
    }

    # ── Сбор задач планировщика ────────────────────────────────────────────
    $scheduledTasks = @()
    try {
        $scheduledTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskPath -notmatch "\\Microsoft\\" } |
            Sort-Object TaskName | Select-Object -First 60)
    } catch {}

    # ── Обновляем счётчик в шапке ─────────────────────────────────────────
    $enabledCount = ($startupItems | Where-Object { $_.IsEnabled }).Count
    $totalCount   = $startupItems.Count + $scheduledTasks.Count
    $startupCountText.Text = "Приложений: $totalCount  •  Активных: $enabledCount  •  Задач: $($scheduledTasks.Count)"

    # ═══════════════════════════════════════════════════════════════════════
    # СЕКЦИЯ 1: Автозагрузка приложений
    # ═══════════════════════════════════════════════════════════════════════
    if ($startupItems.Count -eq 0) {
        $lbl = [System.Windows.Controls.TextBlock]::new()
        $lbl.Text = "Элементы автозагрузки не найдены"
        $lbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#c4c4ee")
        $lbl.FontSize = 12; $lbl.Margin = [System.Windows.Thickness]::new(4,8,0,0)
        $lbl.Tag = [PSCustomObject]@{ Type="App"; Name=""; Publisher="" }
        $startupAppsPanel.Children.Add($lbl) | Out-Null
    }

    # Заголовок секции приложений
    $secApp = [System.Windows.Controls.Border]::new()
    $secApp.Margin = [System.Windows.Thickness]::new(0,8,0,4)
    $secApp.Padding = [System.Windows.Thickness]::new(0,0,0,6)
    $secApp.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#1e1e38")
    $secApp.BorderThickness = [System.Windows.Thickness]::new(0,0,0,1)
    $secApp.Tag = [PSCustomObject]@{ Type="App"; Name="__header__"; Publisher="" }
    $secTxt = [System.Windows.Controls.TextBlock]::new()
    $secTxt.Text = "📦 АВТОЗАГРУЗКА ПРИЛОЖЕНИЙ ($($startupItems.Count))"
    $secTxt.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#6c63ff")
    $secTxt.FontSize = 10; $secTxt.FontWeight = "SemiBold"
    $secApp.Child = $secTxt
    $startupAppsPanel.Children.Add($secApp) | Out-Null

    # Сортируем: включённые сверху, потом по имени
    $sorted = $startupItems | Sort-Object { -([int]$_.IsEnabled) }, Name

    foreach ($item in $sorted) {
        $card = [System.Windows.Controls.Border]::new()
        $card.CornerRadius = [System.Windows.CornerRadius]::new(7)
        $card.Margin = [System.Windows.Thickness]::new(0,2,0,2)
        $card.Padding = [System.Windows.Thickness]::new(10,7,10,7)
        $card.BorderThickness = [System.Windows.Thickness]::new(0,0,0,1)

        if ($item.IsEnabled) {
            $card.Background   = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e")
            $card.BorderBrush  = [Windows.Media.BrushConverter]::new().ConvertFrom("#1e1e38")
        } else {
            $card.Background   = [Windows.Media.BrushConverter]::new().ConvertFrom("#111118")
            $card.BorderBrush  = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a25")
            $card.Opacity      = 0.6
        }

        # Tag для фильтрации
        $card.Tag = [PSCustomObject]@{
            Type      = "App"
            Name      = $item.Name
            Publisher = if ($item.Publisher) { $item.Publisher } else { "" }
        }

        # Grid: [cb][ico][имя+путь][источник][статус]
        $g = [System.Windows.Controls.Grid]::new()
        $widths = @(24, 28, 0, 110, 80)
        foreach ($w in $widths) {
            $dc = [System.Windows.Controls.ColumnDefinition]::new()
            if ($w -eq 0) { $dc.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star) }
            else          { $dc.Width = [System.Windows.GridLength]::new($w) }
            $g.ColumnDefinitions.Add($dc)
        }

        # Чекбокс
        $cb = [System.Windows.Controls.CheckBox]::new()
        $cb.VerticalAlignment = "Center"
        $cb.Tag = @{
            Type        = "App"
            Name        = $item.Name
            RegKey      = $item.PathOrKey
            Location    = $item.Location
            IsEnabled   = $item.IsEnabled
            Command     = $item.Command
        }
        $cb.Add_Checked({   Update-StartupSelectedCount })
        $cb.Add_Unchecked({ Update-StartupSelectedCount })
        [System.Windows.Controls.Grid]::SetColumn($cb, 0)
        $script:StartupCheckboxes["$($item.PathOrKey)|$($item.Name)"] = $cb

        # Иконка
        $ico = [System.Windows.Controls.Image]::new()
        $ico.Width = 18; $ico.Height = 18; $ico.VerticalAlignment = "Center"
        $ico.Margin = [System.Windows.Thickness]::new(0,0,6,0)
        if ($item.Icon) { $ico.Source = $item.Icon }
        [System.Windows.Controls.Grid]::SetColumn($ico, 1)

        # Имя + путь к exe
        $nameStack = [System.Windows.Controls.StackPanel]::new()
        $nameStack.VerticalAlignment = "Center"
        $nameStack.Margin = [System.Windows.Thickness]::new(0,0,8,0)

        $nmColor = if ($item.IsEnabled) { "#e8e8ff" } else { "#808090" }
        $nm = [System.Windows.Controls.TextBlock]::new()
        $nm.Text = $item.Name; $nm.FontSize = 12; $nm.FontWeight = "SemiBold"
        $nm.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom($nmColor)
        $nm.TextTrimming = "CharacterEllipsis"

        $cmdShort = try { [System.IO.Path]::GetFileName($item.Command.Trim('"').Split(' ')[0]) } catch { $item.Command }
        $pathLbl = [System.Windows.Controls.TextBlock]::new()
        $pathLbl.Text = $cmdShort; $pathLbl.FontSize = 10; $pathLbl.TextTrimming = "CharacterEllipsis"
        $pathLbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#9898b8")
        $nameStack.Children.Add($nm) | Out-Null
        $nameStack.Children.Add($pathLbl) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($nameStack, 2)

        # Бейдж источника
        $locB = [System.Windows.Controls.Border]::new()
        $locB.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $locB.Padding = [System.Windows.Thickness]::new(5,2,5,2)
        $locB.VerticalAlignment = "Center"
        $locB.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a3a")
        $locB.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#3a3a6a")
        $locB.BorderThickness = [System.Windows.Thickness]::new(1)
        $locT = [System.Windows.Controls.TextBlock]::new()
        $locT.Text = $item.Location; $locT.FontSize = 10
        $locT.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#a8a8d0")
        $locB.Child = $locT
        [System.Windows.Controls.Grid]::SetColumn($locB, 3)

        # Бейдж статуса
        $stB = [System.Windows.Controls.Border]::new()
        $stB.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $stB.Padding = [System.Windows.Thickness]::new(6,2,6,2)
        $stB.VerticalAlignment = "Center"; $stB.HorizontalAlignment = "Center"
        $stB.BorderThickness = [System.Windows.Thickness]::new(1)
        $stT = [System.Windows.Controls.TextBlock]::new()
        $stT.FontSize = 10; $stT.FontWeight = "SemiBold"
        if ($item.IsEnabled) {
            $stB.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#0d2d1a")
            $stB.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a6b35")
            $stT.Text = "● вкл"
            $stT.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#2ecc71")
        } else {
            $stB.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#2d0d0d")
            $stB.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#6b1a1a")
            $stT.Text = "● выкл"
            $stT.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#e74c3c")
        }
        $stB.Child = $stT
        [System.Windows.Controls.Grid]::SetColumn($stB, 4)

        $g.Children.Add($cb) | Out-Null; $g.Children.Add($ico) | Out-Null
        $g.Children.Add($nameStack) | Out-Null
        $g.Children.Add($locB) | Out-Null; $g.Children.Add($stB) | Out-Null
        $card.Child = $g

        if ($item.IsEnabled) {
            $card.Add_MouseEnter({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#20203a") })
            $card.Add_MouseLeave({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e") })
        }
        $startupAppsPanel.Children.Add($card) | Out-Null
    }

    # ═══════════════════════════════════════════════════════════════════════
    # СЕКЦИЯ 2: Запланированные задачи
    # ═══════════════════════════════════════════════════════════════════════
    $secTask = [System.Windows.Controls.Border]::new()
    $secTask.Margin = [System.Windows.Thickness]::new(0,16,0,4)
    $secTask.Padding = [System.Windows.Thickness]::new(0,0,0,6)
    $secTask.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#1e1e38")
    $secTask.BorderThickness = [System.Windows.Thickness]::new(0,0,0,1)
    $secTask.Tag = [PSCustomObject]@{ Type="Task"; Name="__header__"; Publisher="" }
    $secTaskTxt = [System.Windows.Controls.TextBlock]::new()
    $secTaskTxt.Text = "🗓️ ЗАПЛАНИРОВАННЫЕ ЗАДАЧИ ($($scheduledTasks.Count))"
    $secTaskTxt.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#6c63ff")
    $secTaskTxt.FontSize = 10; $secTaskTxt.FontWeight = "SemiBold"
    $secTask.Child = $secTaskTxt
    $startupAppsPanel.Children.Add($secTask) | Out-Null

    if ($scheduledTasks.Count -eq 0) {
        $lbl = [System.Windows.Controls.TextBlock]::new()
        $lbl.Text = "Сторонних задач не найдено"
        $lbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#c4c4ee")
        $lbl.FontSize = 12; $lbl.Margin = [System.Windows.Thickness]::new(4,6,0,0)
        $lbl.Tag = [PSCustomObject]@{ Type="Task"; Name=""; Publisher="" }
        $startupAppsPanel.Children.Add($lbl) | Out-Null
    }

    foreach ($task in $scheduledTasks) {
        $card = [System.Windows.Controls.Border]::new()
        $card.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e")
        $card.CornerRadius = [System.Windows.CornerRadius]::new(7)
        $card.Margin = [System.Windows.Thickness]::new(0,2,0,2)
        $card.Padding = [System.Windows.Thickness]::new(10,7,10,7)
        $card.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#1e1e38")
        $card.BorderThickness = [System.Windows.Thickness]::new(0,0,0,1)
        $card.Tag = [PSCustomObject]@{
            Type      = "Task"
            Name      = $task.TaskName
            Publisher = ""
        }

        $g = [System.Windows.Controls.Grid]::new()
        $widths = @(24, 0, 90, 70)
        foreach ($w in $widths) {
            $dc = [System.Windows.Controls.ColumnDefinition]::new()
            if ($w -eq 0) { $dc.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star) }
            else          { $dc.Width = [System.Windows.GridLength]::new($w) }
            $g.ColumnDefinitions.Add($dc)
        }

        $cb = [System.Windows.Controls.CheckBox]::new(); $cb.VerticalAlignment = "Center"
        $cb.Tag = @{ Type="Task"; Name=$task.TaskName; Path=$task.TaskPath }
        $cb.Add_Checked({   Update-StartupSelectedCount })
        $cb.Add_Unchecked({ Update-StartupSelectedCount })
        [System.Windows.Controls.Grid]::SetColumn($cb, 0)
        $script:TaskCheckboxes["$($task.TaskPath)$($task.TaskName)"] = $cb

        $stk = [System.Windows.Controls.StackPanel]::new(); $stk.VerticalAlignment = "Center"
        $stk.Margin = [System.Windows.Thickness]::new(0,0,8,0)
        $nm = [System.Windows.Controls.TextBlock]::new()
        $nm.Text = $task.TaskName; $nm.FontSize = 12; $nm.FontWeight = "Medium"
        $nm.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#d0d0f0")
        $nm.TextTrimming = "CharacterEllipsis"
        $trigClass = if ($task.Triggers.Count -gt 0) { $task.Triggers[0].CimClass.CimClassName } else { "" }
        $trigRu = switch -Wildcard ($trigClass) {
            "*Logon*" {"При входе"} "*Boot*" {"При запуске"}
            "*Daily*" {"Ежедневно"} "*Weekly*" {"Еженедельно"}
            "*Time*"  {"По расписанию"} default {"Триггер"}
        }
        $sub = [System.Windows.Controls.TextBlock]::new()
        $sub.Text = "$trigRu  •  $($task.TaskPath)"
        $sub.FontSize = 10; $sub.TextTrimming = "CharacterEllipsis"
        $sub.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#c0c0e8")
        $stk.Children.Add($nm) | Out-Null; $stk.Children.Add($sub) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($stk, 1)

        # Бейдж триггера
        $trigB = [System.Windows.Controls.Border]::new()
        $trigB.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $trigB.Padding = [System.Windows.Thickness]::new(5,2,5,2)
        $trigB.VerticalAlignment = "Center"
        $trigB.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#14142a")
        $trigB.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#2a2a50")
        $trigB.BorderThickness = [System.Windows.Thickness]::new(1)
        $trigT = [System.Windows.Controls.TextBlock]::new()
        $trigT.Text = $trigRu; $trigT.FontSize = 9
        $trigT.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#a8a8d0")
        $trigB.Child = $trigT
        [System.Windows.Controls.Grid]::SetColumn($trigB, 2)

        # Бейдж статуса задачи
        $tStB = [System.Windows.Controls.Border]::new()
        $tStB.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $tStB.Padding = [System.Windows.Thickness]::new(6,2,6,2)
        $tStB.VerticalAlignment = "Center"; $tStB.HorizontalAlignment = "Center"
        $tStB.BorderThickness = [System.Windows.Thickness]::new(1)
        $tStT = [System.Windows.Controls.TextBlock]::new(); $tStT.FontSize = 10; $tStT.FontWeight = "SemiBold"
        $isTaskEnabled = ($task.State -ne "Disabled")
        if ($isTaskEnabled) {
            $tStB.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#0d2d1a")
            $tStB.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a6b35")
            $tStT.Text = "● вкл"; $tStT.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#2ecc71")
        } else {
            $tStB.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#2d0d0d")
            $tStB.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom("#6b1a1a")
            $tStT.Text = "● выкл"; $tStT.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#e74c3c")
        }
        $tStB.Child = $tStT
        [System.Windows.Controls.Grid]::SetColumn($tStB, 3)

        $g.Children.Add($cb) | Out-Null; $g.Children.Add($stk) | Out-Null
        $g.Children.Add($trigB) | Out-Null; $g.Children.Add($tStB) | Out-Null
        $card.Child = $g
        $card.Add_MouseEnter({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#20203a") })
        $card.Add_MouseLeave({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e") })
        $startupAppsPanel.Children.Add($card) | Out-Null
    }

    Write-Log "Автозагрузка: $($startupItems.Count) приложений (вкл: $enabledCount), $($scheduledTasks.Count) задач"
    Apply-StartupFilter
}


# ═══ Обработчики событий ═══
$checkUpdatesBtn.Add_Click({ $updatesPanel.Children.Clear(); $script:UpdateCheckboxes.Clear(); Build-UpdatesPanel })
$selectAllUpdatesBtn.Add_Click({ foreach($cb in $script:UpdateCheckboxes.Values){$cb.IsChecked=$true}; $updateCountText.Text="Выбрано: $($script:UpdateCheckboxes.Count)" })
$deselectAllUpdatesBtn.Add_Click({ foreach($cb in $script:UpdateCheckboxes.Values){$cb.IsChecked=$false}; $updateCountText.Text="Выбрано: 0" })
$installUpdatesBtn.Add_Click({ Install-SelectedUpdates })

$runScriptsBtn.Add_Click({ Run-SelectedScripts })
$selectAllBtn.Add_Click({
    foreach ($cb in $script:ScriptCheckboxes.Values) { if ($cb.IsEnabled) { $cb.IsChecked=$true } }
    Update-SelectedCount
})
$deselectAllBtn.Add_Click({ foreach($cb in $script:ScriptCheckboxes.Values){$cb.IsChecked=$false}; Update-SelectedCount })
$selectRecommendedBtn.Add_Click({ Select-RecommendedScripts })

$refreshBtn.Add_Click({
    Download-Repo -Force
    $scriptsFolderText.Text = $script:ScriptsFolder
    Build-ScriptsPanel
    Write-Log "✓ Список скриптов обновлён"
})

$openFolderBtn.Add_Click({
    if (-not (Test-Path $script:ScriptsFolder)) { New-Item -ItemType Directory -Path $script:ScriptsFolder -Force | Out-Null }
    Start-Process explorer.exe $script:ScriptsFolder
})

$clearLogBtn.Add_Click({ $script:LogBox.Clear() })
$copyLogBtn.Add_Click({ [System.Windows.Clipboard]::SetText($script:LogBox.Text); Write-Log "✓ Лог скопирован" -Color "Green" })
$restorePointBtn.Add_Click({ Create-RestorePoint })
$refreshStartupBtn.Add_Click({ Build-StartupPanel })

# Записывает байты в StartupApproved для включения/отключения
function Set-StartupApprovedState {
    param([string]$RegKey, [string]$ValueName, [bool]$Enable)
    try {
        # Определяем ветку approved по источнику
        $isHKCU      = $RegKey -like "HKEY_CURRENT_USER*"
        $isRunOnce   = $RegKey -like "*RunOnce*"
        $approvedSub = if ($isRunOnce) {
            'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApprovedRunOnce'
        } else {
            'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApprovedRun'
        }
        $rootKey = if ($isHKCU) { [Microsoft.Win32.Registry]::CurrentUser }
                   else         { [Microsoft.Win32.Registry]::LocalMachine }

        $approvedKey = $rootKey.OpenSubKey($approvedSub, $true)
        if ($null -eq $approvedKey) {
            $approvedKey = $rootKey.CreateSubKey($approvedSub)
        }

        # Читаем существующие байты или создаём шаблон (12 байт нулей)
        $existing = $approvedKey.GetValue($ValueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

        # Явно приводим к [byte[]] — иначе PowerShell может вернуть [Object[]]
        if ($existing -is [byte[]] -and $existing.Length -ge 4) {
            $data = [byte[]]$existing
        } else {
            # Стандартный шаблон Windows: 12 байт, первый байт — статус
            $data = [byte[]]@(0x02,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)
        }

        # байт[0]: 02=включено, 03=отключено
        $statusByte = if ($Enable) { [byte]0x02 } else { [byte]0x03 }
        $data[0] = $statusByte

        # Явно передаём [byte[]] — не Object[], не Array
        $byteArray = [byte[]]$data
        $approvedKey.SetValue($ValueName, $byteArray, [Microsoft.Win32.RegistryValueKind]::Binary)
        $approvedKey.Dispose()
        return $true
    } catch {
        Write-Log "✗ StartupApproved для '$ValueName': $_" -Color "Red"
        return $false
    }
}

# Отключить выбранные
$disableStartupBtn.Add_Click({
    $total = 0
    $sel = @($script:StartupCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked })
    foreach ($kv in $sel) {
        $tag = $kv.Value.Tag
        # Папки автозагрузки — переименовываем файл
        if ($tag.Location -like "Папка*") {
            try {
                $src = $tag.Command
                $dst = $src + ".disabled"
                Rename-Item -Path $src -NewName $dst -Force -ErrorAction Stop
                Write-Log "⏸ Отключено (папка): $($tag.Name)" -Color "Green"; $total++
            } catch { Write-Log "✗ $($tag.Name): $_" -Color "Red" }
        } else {
            # Реестр — через StartupApproved (не удаляем запись!)
            $ok = Set-StartupApprovedState -RegKey $tag.RegKey -ValueName $tag.Name -Enable $false
            if ($ok) { Write-Log "⏸ Отключено: $($tag.Name)" -Color "Green"; $total++ }
        }
    }
    foreach ($kv in @($script:TaskCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked })) {
        $tag = $kv.Value.Tag
        try {
            Disable-ScheduledTask -TaskName $tag.Name -TaskPath $tag.Path -ErrorAction Stop | Out-Null
            Write-Log "⏸ Задача отключена: $($tag.Name)" -Color "Green"; $total++
        } catch { Write-Log "✗ $($tag.Name): $_" -Color "Red" }
    }
    if ($total -gt 0) { Write-Log "Отключено: $total элементов"; Build-StartupPanel }
    else { Write-Log "⚠ Нет выбранных элементов" -Color "Yellow" }
})

# Включить выбранные
$enableStartupBtn.Add_Click({
    $total = 0
    $sel = @($script:StartupCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked })
    foreach ($kv in $sel) {
        $tag = $kv.Value.Tag
        if ($tag.Location -like "Папка*") {
            try {
                $src = $tag.Command
                # Убираем .disabled если есть
                $dst = $src -replace '\.disabled$', ''
                if ($src -ne $dst) { Rename-Item -Path $src -NewName $dst -Force -ErrorAction Stop }
                Write-Log "▶ Включено (папка): $($tag.Name)" -Color "Green"; $total++
            } catch { Write-Log "✗ $($tag.Name): $_" -Color "Red" }
        } else {
            $ok = Set-StartupApprovedState -RegKey $tag.RegKey -ValueName $tag.Name -Enable $true
            if ($ok) { Write-Log "▶ Включено: $($tag.Name)" -Color "Green"; $total++ }
        }
    }
    foreach ($kv in @($script:TaskCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked })) {
        $tag = $kv.Value.Tag
        try {
            Enable-ScheduledTask -TaskName $tag.Name -TaskPath $tag.Path -ErrorAction Stop | Out-Null
            Write-Log "▶ Задача включена: $($tag.Name)" -Color "Green"; $total++
        } catch { Write-Log "✗ $($tag.Name): $_" -Color "Red" }
    }
    if ($total -gt 0) { Write-Log "Включено: $total элементов"; Build-StartupPanel }
    else { Write-Log "⚠ Нет выбранных элементов" -Color "Yellow" }
})

# Выбрать/снять всё
$selectAllStartupBtn.Add_Click({
    foreach ($cb in $script:StartupCheckboxes.Values) { $cb.IsChecked = $true }
    foreach ($cb in $script:TaskCheckboxes.Values)    { $cb.IsChecked = $true }
    Update-StartupSelectedCount
})
$deselectAllStartupBtn.Add_Click({
    foreach ($cb in $script:StartupCheckboxes.Values) { $cb.IsChecked = $false }
    foreach ($cb in $script:TaskCheckboxes.Values)    { $cb.IsChecked = $false }
    Update-StartupSelectedCount
})

# Фильтры
$startupFilterAllBtn.Add_Click({
    $script:StartupFilter = "All"
    $startupFilterAllBtn.Style  = $window.FindResource("BtnPrimary")
    $startupFilterAppBtn.Style  = $window.FindResource("BtnSecondary")
    $startupFilterTaskBtn.Style = $window.FindResource("BtnSecondary")
    Apply-StartupFilter
})
$startupFilterAppBtn.Add_Click({
    $script:StartupFilter = "Apps"
    $startupFilterAllBtn.Style  = $window.FindResource("BtnSecondary")
    $startupFilterAppBtn.Style  = $window.FindResource("BtnPrimary")
    $startupFilterTaskBtn.Style = $window.FindResource("BtnSecondary")
    Apply-StartupFilter
})
$startupFilterTaskBtn.Add_Click({
    $script:StartupFilter = "Tasks"
    $startupFilterAllBtn.Style  = $window.FindResource("BtnSecondary")
    $startupFilterAppBtn.Style  = $window.FindResource("BtnSecondary")
    $startupFilterTaskBtn.Style = $window.FindResource("BtnPrimary")
    Apply-StartupFilter
})

# Поиск
$startupSearchBox.Add_TextChanged({
    $q = $startupSearchBox.Text.Trim()
    $startupSearchHint.Visibility  = if ($q -eq "") { "Visible" } else { "Collapsed" }
    $startupSearchClear.Visibility = if ($q -eq "") { "Collapsed" } else { "Visible" }
    Apply-StartupFilter
})
$startupSearchClear.Add_Click({ $startupSearchBox.Text = "" })

$presetOfficeBtn.Add_Click({ Select-Preset "Office-pack" })
$presetGamesBtn.Add_Click({ Select-Preset "Games-pack" })

$installAppsBtn.Add_Click({
    $sel=$script:AppCheckboxes.GetEnumerator()|Where-Object{$_.Value.IsChecked}
    if (-not $sel){Write-Log "⚠ Нет выбранных приложений" -Color "Yellow"; return}
    $idList=@($sel|ForEach-Object{$_.Key}); Write-Log "══ Установка приложений ══"
    [System.Threading.Tasks.Task]::Run([Action]{
        foreach ($id in $idList) {
            Write-Log "⏳ $id..."
            winget install --id $id --silent --accept-source-agreements --accept-package-agreements 2>&1|ForEach-Object{Write-Log "   $_"}
            Write-Log "✓ $id установлена" -Color "Green"
        }
        Write-Log "══ Установка завершена ══"
    }) | Out-Null
})
$selectAllAppsBtn.Add_Click({ foreach($cb in $script:AppCheckboxes.Values){$cb.IsChecked=$true} })
$deselectAllAppsBtn.Add_Click({ foreach($cb in $script:AppCheckboxes.Values){$cb.IsChecked=$false} })

# ─── Поиск в модулях ───────────────────────────────────────────────────────
$scriptSearchBox.Add_TextChanged({
    $q=$scriptSearchBox.Text.Trim().ToLower()
    $scriptSearchHint.Visibility  = if($q -eq ""){"Visible"}else{"Collapsed"}
    $scriptSearchClear.Visibility = if($q -eq ""){"Collapsed"}else{"Visible"}
    foreach ($child in $scriptsPanel.Children) {
        if ($child -is [System.Windows.Controls.Border]) {
            $child.Visibility="Visible"
            $grid=$child.Child
            if ($grid -is [System.Windows.Controls.Grid] -and $grid.ColumnDefinitions.Count -ge 3) {
                $nameVal=""; $descVal=""
                foreach ($el in $grid.Children) {
                    if ($el -is [System.Windows.Controls.StackPanel]) {
                        foreach ($tb in $el.Children) {
                            if ($tb -is [System.Windows.Controls.TextBlock]) {
                                if ($nameVal -eq ""){$nameVal=$tb.Text.ToLower()} else {$descVal=$tb.Text.ToLower()}
                            }
                        }
                    }
                }
                if ($q -ne "" -and ($nameVal -notlike "*$q*") -and ($descVal -notlike "*$q*")) { $child.Visibility="Collapsed" }
            }
        }
    }
})
$scriptSearchClear.Add_Click({ $scriptSearchBox.Text="" })

# ─── Поиск в приложениях ───────────────────────────────────────────────────
$appSearchBox.Add_TextChanged({
    $q=$appSearchBox.Text.Trim().ToLower()
    $appSearchHint.Visibility  = if($q -eq ""){"Visible"}else{"Collapsed"}
    $appSearchClear.Visibility = if($q -eq ""){"Collapsed"}else{"Visible"}
    foreach ($child in $appsPanel.Children) {
        if ($child -is [System.Windows.Controls.Border]) {
            $inner=$child.Child
            if ($inner -is [System.Windows.Controls.StackPanel]) {
                $nameVal=""; $descVal=""
                foreach ($el in $inner.Children) {
                    if ($el -is [System.Windows.Controls.CheckBox]) { $nameVal=$el.Content.ToString().ToLower() }
                    if ($el -is [System.Windows.Controls.TextBlock]) { $descVal=$el.Text.ToLower() }
                }
                $child.Visibility = if ($q -ne "" -and ($nameVal -notlike "*$q*") -and ($descVal -notlike "*$q*")){"Collapsed"}else{"Visible"}
            } else { $child.Visibility="Visible" }
        }
    }
})
$appSearchClear.Add_Click({ $appSearchBox.Text="" })

# ═══ Запуск ═══
$restoreResult=[System.Windows.MessageBox]::Show(
    "Рекомендуется создать точку восстановления системы перед внесением изменений.`n`nСоздать точку восстановления сейчас?",
    "PotatoPC Optimizer",
    [System.Windows.MessageBoxButton]::YesNo,
    [System.Windows.MessageBoxImage]::Question)
if ($restoreResult -eq "Yes") { Create-RestorePoint }

$window.Add_Loaded({
    $scriptsFolderText.Text = $script:ScriptsFolder
    Write-Log "PotatoPC Optimizer v3.0 запущен"
    Write-Log "Система: $((Get-SystemInfo).OS)"
    Write-Log "Windows $($script:WindowsMajorVersion) обнаружена"
    Write-Log "Рабочая папка: $($script:WorkFolder)"
    Initialize-PotatoPC
    Build-ScriptsPanel
    Build-AppsPanel
    Build-SysPanel
    Build-DiagPanel
    Build-StartupPanel
    Write-Log "✓ Готов к работе." -Color "Green"
})

$window.ShowDialog() | Out-Null
