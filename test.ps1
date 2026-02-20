# Potato PC - Modern Windows Package Manager GUI
# Run with: irm "https://raw.githubusercontent.com/USER/Potato-pc/main/install.ps1" | iex

param(
    [switch]$Debug
)

$ErrorActionPreference = 'Stop'

# Modern UI Configuration
$UI_CONFIG = @{
    PrimaryColor = "#6366F1"      # Indigo
    SecondaryColor = "#8B5CF6"    # Violet
    BackgroundDark = "#0F0F0F"
    BackgroundCard = "#1A1A1A"
    TextPrimary = "#FFFFFF"
    TextSecondary = "#A1A1AA"
    Success = "#10B981"
    Warning = "#F59E0B"
    Error = "#EF4444"
    FontFamily = "Segoe UI Variable"
}

# Check if running in PowerShell 5.1+
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "PowerShell 5.1 or higher is required." -ForegroundColor Red
    exit 1
}

# Load WPF Assembly
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Check for winget
function Test-Winget {
    try {
        $null = Get-Command winget -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

# Install winget if missing
function Install-Winget {
    Write-Host "Installing winget..." -ForegroundColor Cyan
    
    $wingetUrl = "https://aka.ms/getwinget"
    $tempPath = [System.IO.Path]::GetTempPath()
    $installerPath = Join-Path $tempPath "winget.install.ps1"
    
    try {
        Invoke-WebRequest -Uri $wingetUrl -OutFile $installerPath -UseBasicParsing
        & powershell -ExecutionPolicy Bypass -File $installerPath
        
        if (Test-Winget) {
            Write-Host "winget installed successfully!" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Host "Failed to install winget: $_" -ForegroundColor Red
    }
    
    return $false
}

# Get installed apps via winget
function Get-InstalledApps {
    try {
        $apps = winget list --source winget | Select-Object -Skip 3 | Where-Object { $_ -match '\S' }
        return $apps | ForEach-Object {
            $parts = $_ -split '\s{2,}'
            if ($parts.Count -ge 2) {
                [PSCustomObject]@{
                    Id = $parts[0].Trim()
                    Name = $parts[1].Trim()
                    Version = if ($parts.Count -ge 3) { $parts[2].Trim() } else { "Unknown" }
                }
            }
        }
    }
    catch {
        Write-Host "Error getting installed apps: $_" -ForegroundColor Red
        return @()
    }
}

# Get available updates
function Get-AppUpdates {
    try {
        $updates = winget upgrade | Select-Object -Skip 3 | Where-Object { $_ -match '\S' -and $_ -notmatch '^Name' }
        return $updates | ForEach-Object {
            $parts = $_ -split '\s{2,}'
            if ($parts.Count -ge 2) {
                [PSCustomObject]@{
                    Id = $parts[0].Trim()
                    Name = $parts[1].Trim()
                    CurrentVersion = if ($parts.Count -ge 3) { $parts[2].Trim() } else { "Unknown" }
                    AvailableVersion = if ($parts.Count -ge 4) { $parts[3].Trim() } else { "Unknown" }
                }
            }
        }
    }
    catch {
        return @()
    }
}

# Search apps in winget repository
function Search-WingetApps {
    param([string]$Query)
    
    try {
        if ([string]::IsNullOrWhiteSpace($Query)) {
            $results = winget search "" | Select-Object -Skip 3 | Select-Object -First 50
        }
        else {
            $results = winget search $Query | Select-Object -Skip 3 | Select-Object -First 50
        }
        
        return $results | Where-Object { $_ -match '\S' } | ForEach-Object {
            $parts = $_ -split '\s{2,}'
            if ($parts.Count -ge 2) {
                [PSCustomObject]@{
                    Id = $parts[0].Trim()
                    Name = $parts[1].Trim()
                    Publisher = if ($parts.Count -ge 3) { $parts[2].Trim() } else { "" }
                }
            }
        }
    }
    catch {
        return @()
    }
}

# Install app via winget
function Install-App {
    param([string]$AppId)
    
    try {
        $process = Start-Process -FilePath "winget" -ArgumentList "install", "--id", $AppId, "--silent", "--accept-package-agreements", "--accept-source-agreements" -PassThru -Wait
        return $process.ExitCode -eq 0
    }
    catch {
        Write-Host "Installation failed: $_" -ForegroundColor Red
        return $false
    }
}

# Update apps via winget
function Update-Apps {
    param([string[]]$AppIds)
    
    $results = @()
    foreach ($id in $AppIds) {
        try {
            $process = Start-Process -FilePath "winget" -ArgumentList "upgrade", "--id", $id, "--silent" -PassThru -Wait
            $results += [PSCustomObject]@{
                Id = $id
                Success = $process.ExitCode -eq 0
            }
        }
        catch {
            $results += [PSCustomObject]@{
                Id = $id
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }
    return $results
}

# Main GUI Application
function Show-PotatoPC {
    
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Potato PC - Package Manager" 
        Height="700" Width="1000"
        WindowStartupLocation="CenterScreen"
        Background="#0F0F0F"
        FontFamily="Segoe UI Variable"
        ResizeMode="CanResizeWithGrip"
        MinHeight="500" MinWidth="800">
    
    <Window.Resources>
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Background" Value="#6366F1"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="20,10"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" 
                                CornerRadius="8" 
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#4F46E5"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        
        <Style x:Key="ModernTextBox" TargetType="TextBox">
            <Setter Property="Background" Value="#1A1A1A"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="#333333"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="FontSize" Value="14"/>
        </Style>
        
        <Style x:Key="CardStyle" TargetType="Border">
            <Setter Property="Background" Value="#1A1A1A"/>
            <Setter Property="CornerRadius" Value="12"/>
            <Setter Property="Padding" Value="16"/>
            <Setter Property="Margin" Value="8"/>
        </Style>
    </Window.Resources>
    
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <!-- Header -->
        <Border Grid.Row="0" Background="#1A1A1A" Padding="20">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                
                <StackPanel Grid.Column="0">
                    <TextBlock Text="🥔 Potato PC" FontSize="28" FontWeight="Bold" Foreground="White"/>
                    <TextBlock Text="Modern Windows Package Manager" FontSize="14" Foreground="#A1A1AA" Margin="0,4,0,0"/>
                </StackPanel>
                
                <StackPanel Grid.Column="1" Orientation="Horizontal">
                    <Button x:Name="btnRefresh" Content="🔄 Refresh" Style="{StaticResource ModernButton}" Margin="0,0,10,0"/>
                    <Button x:Name="btnSettings" Content="⚙️ Settings" Style="{StaticResource ModernButton}"/>
                </StackPanel>
            </Grid>
        </Border>
        
        <!-- Main Content -->
        <Grid Grid.Row="1" Margin="20">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="300"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            
            <!-- Left Panel - Search & Categories -->
            <Border Grid.Column="0" Style="{StaticResource CardStyle}">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    
                    <StackPanel Grid.Row="0">
                        <TextBlock Text="Search Apps" FontSize="16" FontWeight="Bold" Foreground="White" Margin="0,0,0,12"/>
                        <TextBox x:Name="txtSearch" Style="{StaticResource ModernTextBox}" Margin="0,0,0,16"/>
                        <Button x:Name="btnSearch" Content="🔍 Search" Style="{StaticResource ModernButton}" Margin="0,0,0,20"/>
                        
                        <TextBlock Text="Categories" FontSize="16" FontWeight="Bold" Foreground="White" Margin="0,0,0,12"/>
                        <ListBox x:Name="lstCategories" Background="#1A1A1A" BorderBrush="#333333" 
                                 Foreground="White" Height="200">
                            <ListBoxItem Content="🌐 Browsers"/>
                            <ListBoxItem Content="💬 Communication"/>
                            <ListBoxItem Content="🎮 Gaming"/>
                            <ListBoxItem Content="🎵 Media"/>
                            <ListBoxItem Content="🛠️ Utilities"/>
                            <ListBoxItem Content="📦 Development"/>
                        </ListBox>
                    </StackPanel>
                </Grid>
            </Border>
            
            <!-- Right Panel - App List -->
            <Border Grid.Column="1" Style="{StaticResource CardStyle}">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    
                    <!-- Tabs -->
                    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,16">
                        <RadioButton x:Name="tabAvailable" Content="📦 Available Apps" IsChecked="True" 
                                     Foreground="White" Margin="0,0,20,0" FontSize="14"/>
                        <RadioButton x:Name="tabInstalled" Content="✅ Installed" Foreground="White" 
                                     Margin="0,0,20,0" FontSize="14"/>
                        <RadioButton x:Name="tabUpdates" Content="⬆️ Updates Available" Foreground="White" FontSize="14"/>
                    </StackPanel>
                    
                    <!-- App List -->
                    <DataGrid x:Name="dgApps" Grid.Row="1" 
                              Background="#1A1A1A" 
                              BorderBrush="#333333"
                              Foreground="White"
                              AutoGenerateColumns="False"
                              GridLinesVisibility="Horizontal"
                              HorizontalGridLinesBrush="#333333"
                              RowBackground="#1A1A1A"
                              AlternatingRowBackground="#252525"
                              HeadersVisibility="Column"
                              CanUserAddRows="False"
                              SelectionMode="Extended">
                        <DataGrid.ColumnHeaderStyle>
                            <Style TargetType="DataGridColumnHeader">
                                <Setter Property="Background" Value="#252525"/>
                                <Setter Property="Foreground" Value="White"/>
                                <Setter Property="Padding" Value="12,8"/>
                                <Setter Property="FontWeight" Value="Bold"/>
                            </Style>
                        </DataGrid.ColumnHeaderStyle>
                        <DataGrid.Columns>
                            <DataGridTemplateColumn Width="50">
                                <DataGridTemplateColumn.Header>
                                    <CheckBox x:Name="chkSelectAll"/>
                                </DataGridTemplateColumn.Header>
                                <DataGridTemplateColumn.CellTemplate>
                                    <DataTemplate>
                                        <CheckBox IsChecked="{Binding Selected, Mode=TwoWay}" 
                                                  HorizontalAlignment="Center"/>
                                    </DataTemplate>
                                </DataGridTemplateColumn.CellTemplate>
                            </DataGridTemplateColumn>
                            <DataGridTextColumn Header="Name" Binding="{Binding Name}" Width="*"/>
                            <DataGridTextColumn Header="ID" Binding="{Binding Id}" Width="200"/>
                            <DataGridTextColumn Header="Version" Binding="{Binding Version}" Width="120"/>
                        </DataGrid.Columns>
                    </DataGrid>
                    
                    <!-- Action Buttons -->
                    <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,16,0,0">
                        <Button x:Name="btnInstall" Content="📥 Install Selected" Style="{StaticResource ModernButton}" Margin="0,0,10,0"/>
                        <Button x:Name="btnUpdate" Content="⬆️ Update Selected" Style="{StaticResource ModernButton}" Margin="0,0,10,0"/>
                        <Button x:Name="btnUninstall" Content="🗑️ Uninstall Selected" Style="{StaticResource ModernButton}"/>
                    </StackPanel>
                </Grid>
            </Border>
        </Grid>
        
        <!-- Status Bar -->
        <Border Grid.Row="2" Background="#1A1A1A" Padding="16,8">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                
                <TextBlock x:Name="txtStatus" Grid.Column="0" Text="Ready" Foreground="#A1A1AA"/>
                <TextBlock x:Name="txtWingetStatus" Grid.Column="1" Text="winget: Checking..." Foreground="#A1A1AA"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@
    
    try {
        $reader = New-Object System.IO.StringReader $xaml
        $window = [System.Windows.Markup.XamlReader]::Load($reader)
        
        # Get controls
        $txtSearch = $window.FindName("txtSearch")
        $btnSearch = $window.FindName("btnSearch")
        $btnRefresh = $window.FindName("btnRefresh")
        $btnSettings = $window.FindName("btnSettings")
        $btnInstall = $window.FindName("btnInstall")
        $btnUpdate = $window.FindName("btnUpdate")
        $btnUninstall = $window.FindName("btnUninstall")
        $dgApps = $window.FindName("dgApps")
        $txtStatus = $window.FindName("txtStatus")
        $txtWingetStatus = $window.FindName("txtWingetStatus")
        $chkSelectAll = $window.FindName("chkSelectAll")
        $tabAvailable = $window.FindName("tabAvailable")
        $tabInstalled = $window.FindName("tabInstalled")
        $tabUpdates = $window.FindName("tabUpdates")
        $lstCategories = $window.FindName("lstCategories")
        
        # Check winget status
        $wingetAvailable = Test-Winget
        if ($wingetAvailable) {
            $txtWingetStatus.Text = "winget: ✓ Available"
            $txtWingetStatus.Foreground = "#10B981"
        }
        else {
            $txtWingetStatus.Text = "winget: ✗ Not Found"
            $txtWingetStatus.Foreground = "#EF4444"
            
            $result = [System.Windows.MessageBox]::Show(
                "winget is not installed. Would you like to install it now?",
                "Install winget",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Question
            )
            
            if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                if (Install-Winget) {
                    $wingetAvailable = $true
                    $txtWingetStatus.Text = "winget: ✓ Installed"
                    $txtWingetStatus.Foreground = "#10B981"
                }
            }
        }
        
        # Load available apps
        $global:AvailableApps = @()
        $global:InstalledApps = @()
        $global:UpdateApps = @()
        
        # Search button click
        $btnSearch.Add_Click({
            if (-not $wingetAvailable) {
                [System.Windows.MessageBox]::Show("winget is not available", "Error")
                return
            }
            
            $txtStatus.Text = "Searching..."
            $query = $txtSearch.Text
            $global:AvailableApps = Search-WingetApps -Query $query
            
            foreach ($app in $global:AvailableApps) {
                $app | Add-Member -NotePropertyName "Selected" -NotePropertyValue $false -Force
            }
            
            $dgApps.ItemsSource = $global:AvailableApps
            $txtStatus.Text = "Found $($global:AvailableApps.Count) apps"
        })
        
        # Refresh button
        $btnRefresh.Add_Click({
            $txtStatus.Text = "Refreshing..."
            
            if ($tabAvailable.IsChecked) {
                $global:AvailableApps = Search-WingetApps -Query ""
                foreach ($app in $global:AvailableApps) {
                    $app | Add-Member -NotePropertyName "Selected" -NotePropertyValue $false -Force
                }
                $dgApps.ItemsSource = $global:AvailableApps
            }
            elseif ($tabInstalled.IsChecked) {
                $global:InstalledApps = Get-InstalledApps
                foreach ($app in $global:InstalledApps) {
                    $app | Add-Member -NotePropertyName "Selected" -NotePropertyValue $false -Force
                }
                $dgApps.ItemsSource = $global:InstalledApps
            }
            elseif ($tabUpdates.IsChecked) {
                $global:UpdateApps = Get-AppUpdates
                foreach ($app in $global:UpdateApps) {
                    $app | Add-Member -NotePropertyName "Selected" -NotePropertyValue $false -Force
                }
                $dgApps.ItemsSource = $global:UpdateApps
            }
            
            $txtStatus.Text = "Refreshed"
        })
        
        # Tab changes
        $tabAvailable.Add_Checked({
            if ($wingetAvailable) {
                $global:AvailableApps = Search-WingetApps -Query ""
                foreach ($app in $global:AvailableApps) {
                    $app | Add-Member -NotePropertyName "Selected" -NotePropertyValue $false -Force
                }
                $dgApps.ItemsSource = $global:AvailableApps
            }
        })
        
        $tabInstalled.Add_Checked({
            if ($wingetAvailable) {
                $global:InstalledApps = Get-InstalledApps
                foreach ($app in $global:InstalledApps) {
                    $app | Add-Member -NotePropertyName "Selected" -NotePropertyValue $false -Force
                }
                $dgApps.ItemsSource = $global:InstalledApps
            }
        })
        
        $tabUpdates.Add_Checked({
            if ($wingetAvailable) {
                $global:UpdateApps = Get-AppUpdates
                foreach ($app in $global:UpdateApps) {
                    $app | Add-Member -NotePropertyName "Selected" -NotePropertyValue $false -Force
                }
                $dgApps.ItemsSource = $global:UpdateApps
            }
        })
        
        # Install button
        $btnInstall.Add_Click({
            $selected = $dgApps.SelectedItems | Where-Object { $_ }
            if ($selected.Count -eq 0) {
                [System.Windows.MessageBox]::Show("Please select apps to install")
                return
            }
            
            $confirm = [System.Windows.MessageBox]::Show(
                "Install $($selected.Count) app(s)?",
                "Confirm Installation",
                [System.Windows.MessageBoxButton]::YesNo
            )
            
            if ($confirm -eq [System.Windows.MessageBoxResult]::Yes) {
                foreach ($app in $selected) {
                    $txtStatus.Text = "Installing $($app.Name)..."
                    Install-App -AppId $app.Id
                }
                $txtStatus.Text = "Installation complete"
            }
        })
        
        # Update button
        $btnUpdate.Add_Click({
            $selected = $dgApps.SelectedItems | Where-Object { $_ }
            if ($selected.Count -eq 0) {
                [System.Windows.MessageBox]::Show("Please select apps to update")
                return
            }
            
            $appIds = $selected | ForEach-Object { $_.Id }
            $txtStatus.Text = "Updating $($selected.Count) app(s)..."
            
            $results = Update-Apps -AppIds $appIds
            $successCount = ($results | Where-Object { $_.Success }).Count
            
            $txtStatus.Text = "Updated $successCount of $($results.Count) app(s)"
        })
        
        # Select all checkbox
        $chkSelectAll.Add_Checked({
            foreach ($item in $dgApps.Items) {
                $item.Selected = $true
            }
            $dgApps.Items.Refresh()
        })
        
        $chkSelectAll.Add_Unchecked({
            foreach ($item in $dgApps.Items) {
                $item.Selected = $false
            }
            $dgApps.Items.Refresh()
        })
        
        # Show window
        $window.ShowDialog()
        
    }
    catch {
        Write-Host "Error creating GUI: $_" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
    }
}

# Start the application
Write-Host "Starting Potato PC..." -ForegroundColor Cyan
Show-PotatoPC
