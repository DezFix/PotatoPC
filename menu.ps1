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
$script:WorkFolder = Join-Path $env:TEMP "PotatoPC"
$script:ScriptsFolder = Join-Path $script:WorkFolder "scripts"
$script:BackupsFolder = Join-Path $script:WorkFolder "backups"
$script:AppsJsonPath = Join-Path $script:WorkFolder "apps.json"

# URL вашего репозитория GitHub
$script:RepoZipUrl = "https://github.com/DezFix/testerwrewindows/archive/refs/heads/main.zip"
$script:AppsJsonUrl = "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/apps.json"

# ═══ Инициализация и загрузка с GitHub ═══
function Initialize-PotatoPC {
    Write-Log "Инициализация рабочей среды..."
    
    # Создаем папки
    foreach ($folder in @($script:WorkFolder, $script:ScriptsFolder, $script:BackupsFolder)) {
        if (-not (Test-Path $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }
    }

    # Скачиваем apps.json
    try {
        Invoke-WebRequest -Uri $script:AppsJsonUrl -OutFile $script:AppsJsonPath -UseBasicParsing -ErrorAction Stop
        Write-Log "✓ Список приложений (apps.json) загружен."
    } catch {
        Write-Log "⚠ Не удалось загрузить apps.json. Будет использован резервный список." -Color "Yellow"
    }

    # Скачиваем и распаковываем скрипты
    $zipPath = Join-Path $script:WorkFolder "scripts_temp.zip"
    try {
        Write-Log "Загрузка пакета скриптов с GitHub..."
        Invoke-WebRequest -Uri $script:RepoZipUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop
        
        # Очищаем старую папку скриптов перед распаковкой
        Get-ChildItem -Path $script:ScriptsFolder -File | Remove-Item -Force
        
        Expand-Archive -Path $zipPath -DestinationPath $script:WorkFolder -Force
        
        # Перемещаем скрипты из распакованной папки репозитория в нашу папку scripts
        $extractedFolder = Get-ChildItem -Path $script:WorkFolder -Filter "*-main" -Directory | Select-Object -First 1
        if ($extractedFolder) {
            $sourceScripts = Join-Path $extractedFolder.FullName "scripts"
            if (Test-Path $sourceScripts) {
                Copy-Item -Path (Join-Path $sourceScripts "*") -Destination $script:ScriptsFolder -Force -Recurse
            } else {
                # Если папки scripts в архиве нет, копируем все .ps1 из корня распаковки
                Copy-Item -Path (Join-Path $extractedFolder.FullName "*.ps1") -Destination $script:ScriptsFolder -Force -ErrorAction SilentlyContinue
            }
        }
        
        Remove-Item $zipPath -Force
        Write-Log "✓ Скрипты успешно загружены и распакованы."
    } catch {
        Write-Log "✗ Ошибка загрузки скриптов с GitHub: $_" -Color "Red"
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
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="8" Padding="14,9">
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
                        <Border x:Name="bd" Background="{TemplateBinding Background}" BorderThickness="0,0,0,3" BorderBrush="Transparent" Padding="18,12">
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
                        <TextBlock Text="🧩" FontSize="14" Margin="0,0,6,0" VerticalAlignment="Center"/>
                        <TextBlock Text="Модули" FontSize="13" VerticalAlignment="Center"/>
                    </StackPanel>
                </TabItem.Header>
                <Grid Background="#12121f">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <Border Grid.Row="0" Background="#1a1a2e" Padding="16,10">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <Grid Grid.Row="0">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                    <TextBlock Foreground="#6060a0" FontSize="12" VerticalAlignment="Center" Margin="0,0,12,0">
                                        <Run Text="📂 Папка: "/>
                                    </TextBlock>
                                    <TextBlock x:Name="ScriptsFolderText" Foreground="#8080c0" FontSize="11" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" MaxWidth="500"/>
                                </StackPanel>
                                <StackPanel Grid.Column="1" Orientation="Horizontal">
                                    <Button Content="📂 Открыть" x:Name="OpenFolderBtn" Style="{StaticResource BtnSecondary}" Margin="0,0,8,0" Height="32" FontSize="12"/>
                                    <Button Content="🔄 Обновить" x:Name="RefreshBtn" Style="{StaticResource BtnSecondary}" Height="32" FontSize="12"/>
                                </StackPanel>
                            </Grid>
                        </Grid>
                    </Border>
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="0,0,4,0">
                        <StackPanel x:Name="ScriptsPanel" Margin="16,12,16,12"/>
                    </ScrollViewer>
                    <Border Grid.Row="2" Background="#16162a" Padding="16,12">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock x:Name="SelectedCountText" Foreground="#8080c0" FontSize="13" FontWeight="SemiBold" VerticalAlignment="Center"/>
                            </StackPanel>
                            <StackPanel Grid.Column="1" Orientation="Horizontal">
                                <Button Content="⭐ Рекомендованное" x:Name="SelectRecommendedBtn" Style="{StaticResource BtnGold}" Margin="0,0,6,0" Height="36" FontSize="13" Width="150"/>
                                <Button Content="✓ Выбрать все" x:Name="SelectAllBtn" Style="{StaticResource BtnSecondary}" Margin="0,0,6,0" Height="36" FontSize="13" Width="110"/>
                                <Button Content="✗ Снять все" x:Name="DeselectAllBtn" Style="{StaticResource BtnSecondary}" Margin="0,0,12,0" Height="36" FontSize="13" Width="110"/>
                                <Button Content="▶ Запустить выбранные" x:Name="RunScriptsBtn" Style="{StaticResource BtnPrimary}" Height="36" FontSize="14" Padding="16,8"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                </Grid>
            </TabItem>

            <!-- ВКЛАДКА: ПРИЛОЖЕНИЯ -->
            <TabItem>
                <TabItem.Header>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="📦" FontSize="14" Margin="0,0,6,0" VerticalAlignment="Center"/>
                        <TextBlock Text="Приложения" FontSize="13" VerticalAlignment="Center"/>
                    </StackPanel>
                </TabItem.Header>
                <Grid Background="#12121f">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    
                    <!-- Панель пресетов -->
                    <Border Grid.Row="0" Background="#1a1a2e" Padding="16,10">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Foreground="#6060a0" FontSize="12" VerticalAlignment="Center" Margin="0,0,12,0">
                                <Run Text="⚡ Пресеты:"/>
                            </TextBlock>
                            <Button Content="🏢 Офисный пакет" x:Name="PresetOfficeBtn" Style="{StaticResource BtnSecondary}" Margin="0,0,8,0" Height="32" FontSize="12"/>
                            <Button Content="🎮 Игровой пакет" x:Name="PresetGamesBtn" Style="{StaticResource BtnSecondary}" Height="32" FontSize="12"/>
                        </StackPanel>
                    </Border>
                    
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="0,0,4,0">
                        <StackPanel x:Name="AppsPanel" Margin="16,12,16,12"/>
                    </ScrollViewer>
                    <Border Grid.Row="2" Background="#16162a" Padding="16,12">
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                            <Button Content="✓ Все" x:Name="SelectAllAppsBtn" Style="{StaticResource BtnSecondary}" Margin="0,0,6,0" Height="34" Width="70" FontSize="12"/>
                            <Button Content="✗ Снять" x:Name="DeselectAllAppsBtn" Style="{StaticResource BtnSecondary}" Margin="0,0,12,0" Height="34" Width="70" FontSize="12"/>
                            <Button Content="📦 Установить выбранные" x:Name="InstallAppsBtn" Style="{StaticResource BtnPrimary}" Height="34" FontSize="13"/>
                        </StackPanel>
                    </Border>
                </Grid>
            </TabItem>

            <!-- ВКЛАДКА: О СИСТЕМЕ -->
            <TabItem>
                <TabItem.Header>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="💻" FontSize="14" Margin="0,0,6,0" VerticalAlignment="Center"/>
                        <TextBlock Text="О системе" FontSize="13" VerticalAlignment="Center"/>
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
                    <TextBlock Text="ДЕЙСТВИЯ" Foreground="#404060" FontSize="10" FontWeight="SemiBold" Margin="0,0,0,12"/>
                    <Button Content="▶ Запустить" x:Name="QuickRunBtn" Style="{StaticResource BtnPrimary}" Height="40" Margin="0,0,0,8" FontSize="12"/>
                    <Button Content="🗑️ Очистить лог" x:Name="ClearLogBtn" Style="{StaticResource BtnSecondary}" Height="34" Margin="0,0,0,8" FontSize="12"/>
                    <Button Content="📋 Копировать лог" x:Name="CopyLogBtn" Style="{StaticResource BtnSecondary}" Height="34" Margin="0,0,0,16" FontSize="12"/>
                    <Separator Background="#1e1e38" Margin="0,0,0,12"/>
                    <Button Content="📂 Папка скриптов" x:Name="OpenFolderBtn2" Style="{StaticResource BtnSecondary}" Height="34" FontSize="11" Margin="0,0,0,8"/>
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
$headerOsText           = $window.FindName("HeaderOsText")
$scriptsFolderText      = $window.FindName("ScriptsFolderText")
$selectedCountText      = $window.FindName("SelectedCountText")
$runScriptsBtn          = $window.FindName("RunScriptsBtn")
$quickRunBtn            = $window.FindName("QuickRunBtn")
$selectAllBtn           = $window.FindName("SelectAllBtn")
$deselectAllBtn         = $window.FindName("DeselectAllBtn")
$refreshBtn             = $window.FindName("RefreshBtn")
$openFolderBtn          = $window.FindName("OpenFolderBtn")
$openFolderBtn2         = $window.FindName("OpenFolderBtn2")
$clearLogBtn            = $window.FindName("ClearLogBtn")
$copyLogBtn             = $window.FindName("CopyLogBtn")
$installAppsBtn         = $window.FindName("InstallAppsBtn")
$selectAllAppsBtn       = $window.FindName("SelectAllAppsBtn")
$deselectAllAppsBtn     = $window.FindName("DeselectAllAppsBtn")
$restorePointBtn        = $window.FindName("RestorePointBtn")
$presetOfficeBtn        = $window.FindName("PresetOfficeBtn")
$presetGamesBtn         = $window.FindName("PresetGamesBtn")
$selectRecommendedBtn   = $window.FindName("SelectRecommendedBtn")

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
    $sysItems = @(
        @{ L="💻 Операционная система"; V=$sysInfo.OS }
        @{ L="⚙️ Процессор"; V=$sysInfo.CPU }
        @{ L="🧠 Оперативная память"; V=$sysInfo.RAM }
        @{ L="💾 Диск C:"; V=$sysInfo.Disk }
        @{ L="⏱️ Время работы"; V=$sysInfo.Uptime }
        @{ L="📂 Рабочая папка"; V=$script:WorkFolder }
    )
    $sysPanel.Children.Clear()
    foreach ($item in $sysItems) {
        $row = [System.Windows.Controls.Border]::new()
        $row.Background = [Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e")
        $row.CornerRadius = [System.Windows.CornerRadius]::new(8)
        $row.Margin = [System.Windows.Thickness]::new(0,4,0,4)
        $row.Padding = [System.Windows.Thickness]::new(16,12,16,12)
        $g = [System.Windows.Controls.Grid]::new()
        $c1 = [System.Windows.Controls.ColumnDefinition]::new(); $c1.Width = "200"
        $c2 = [System.Windows.Controls.ColumnDefinition]::new(); $c2.Width = "*"
        $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2)
        $lbl = [System.Windows.Controls.TextBlock]::new()
        $lbl.Text = $item.L; $lbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#606080"); $lbl.FontSize = 13
        $val = [System.Windows.Controls.TextBlock]::new()
        $val.Text = $item.V; $val.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#d0d0f0"); $val.FontSize = 13; $val.FontWeight = "SemiBold"
        $val.TextWrapping = "Wrap"
        [System.Windows.Controls.Grid]::SetColumn($val, 1)
        $g.Children.Add($lbl) | Out-Null; $g.Children.Add($val) | Out-Null
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
    Write-Log "Завершено: ✓$ok успешно  $(if($fail -gt 0){ "✗$fail ошибок" })"
    Write-Log "══════════════════════════════════════"
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

# ═══ Обработчики событий ═══
$runScriptsBtn.Add_Click({ Run-SelectedScripts })
$quickRunBtn.Add_Click({ Run-SelectedScripts })
$selectAllBtn.Add_Click({ foreach ($cb in $script:ScriptCheckboxes.Values) { $cb.IsChecked = $true }; Update-SelectedCount })
$deselectAllBtn.Add_Click({ foreach ($cb in $script:ScriptCheckboxes.Values) { $cb.IsChecked = $false }; Update-SelectedCount })
$refreshBtn.Add_Click({ Write-Log "Обновление списка..."; Build-ScriptsPanel })
$selectRecommendedBtn.Add_Click({ Select-RecommendedScripts })

$openFolderAction = {
    if (-not (Test-Path $script:ScriptsFolder)) { New-Item -ItemType Directory -Path $script:ScriptsFolder -Force | Out-Null }
    Start-Process explorer.exe $script:ScriptsFolder
}
$openFolderBtn.Add_Click($openFolderAction)
$openFolderBtn2.Add_Click($openFolderAction)

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

# 2. Загрузка данных с GitHub
Initialize-PotatoPC

# 3. Построение интерфейса
Build-ScriptsPanel
Build-AppsPanel
Build-SysPanel

$scriptsFolderText.Text = $script:ScriptsFolder

Write-Log "PotatoPC Optimizer v3.0 запущен"
Write-Log "Система: $(Get-SystemInfo).OS"
Write-Log "Рабочая папка: $($script:WorkFolder)"
Write-Log "Готов к работе." -Color "Green"

$window.ShowDialog() | Out-Null