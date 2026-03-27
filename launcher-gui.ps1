#Requires -RunAsAdministrator
<#
.SYNOPSIS
    PotatoPS - Универсальный менеджер настройки Windows (GUI)
.DESCRIPTION
    Модульное приложение с графическим интерфейсом
.NOTES
    Версия: 2.0.0
    Автор: DezFix
    GitHub: https://github.com/DezFix/PotatoPC
#>

param(
    [switch]$Debug
)

$ErrorActionPreference = 'Stop'

# Проверка PowerShell
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "Требуется PowerShell 5.1+",
        "Ошибка",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

# Загрузка WPF
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# ==============================================================================
# GUI ПРИЛОЖЕНИЕ
# ==============================================================================

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PotatoPS - Системный менеджер Windows"
        Height="650" Width="900"
        WindowStartupLocation="CenterScreen"
        Background="#1A1A1A"
        FontFamily="Segoe UI"
        ResizeMode="CanResizeWithGrip">

    <Window.Resources>
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Background" Value="#6366F1"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="15,10"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Margin" Value="5"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
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
    </Window.Resources>

    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#2D2D2D" CornerRadius="10" Padding="20" Margin="0,0,0,20">
            <StackPanel>
                <TextBlock Text="🥔 PotatoPS" FontSize="32" FontWeight="Bold" Foreground="#6366F1"/>
                <TextBlock Text="Системный менеджер Windows" FontSize="14" Foreground="#A1A1AA" Margin="0,5,0,0"/>
                <TextBlock x:Name="txtVersion" Text="Версия: 2.0.0" FontSize="12" Foreground="#666" Margin="0,5,0,0"/>
            </StackPanel>
        </Border>

        <!-- Main Content -->
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- Left Column -->
            <StackPanel Grid.Column="0" Margin="0,0,10,0">
                <Button x:Name="btnInstaller" Style="{StaticResource ModernButton}" Height="80">
                    <StackPanel>
                        <TextBlock Text="📦" FontSize="24" HorizontalAlignment="Center"/>
                        <TextBlock Text="Установка ПО" FontSize="16" FontWeight="Bold" Margin="0,5,0,0"/>
                        <TextBlock Text="88+ программ через winget" FontSize="12" Foreground="#CCC" Margin="0,3,0,0"/>
                    </StackPanel>
                </Button>

                <Button x:Name="btnClear" Style="{StaticResource ModernButton}" Height="80" Margin="5">
                    <StackPanel>
                        <TextBlock Text="🧹" FontSize="24" HorizontalAlignment="Center"/>
                        <TextBlock Text="Очистка системы" FontSize="16" FontWeight="Bold" Margin="0,5,0,0"/>
                        <TextBlock Text="Телеметрия, службы, temp" FontSize="12" Foreground="#CCC" Margin="0,3,0,0"/>
                    </StackPanel>
                </Button>

                <Button x:Name="btnDiagnostics" Style="{StaticResource ModernButton}" Height="80">
                    <StackPanel>
                        <TextBlock Text="🔍" FontSize="24" HorizontalAlignment="Center"/>
                        <TextBlock Text="Диагностика" FontSize="16" FontWeight="Bold" Margin="0,5,0,0"/>
                        <TextBlock Text="SFC, DISM, CHKDSK, RAM" FontSize="12" Foreground="#CCC" Margin="0,3,0,0"/>
                    </StackPanel>
                </Button>
            </StackPanel>

            <!-- Right Column -->
            <StackPanel Grid.Column="1" Margin="10,0,0,0">
                <Button x:Name="btnRemoveAI" Style="{StaticResource ModernButton}" Height="80">
                    <StackPanel>
                        <TextBlock Text="🤖" FontSize="24" HorizontalAlignment="Center"/>
                        <TextBlock Text="Удаление AI" FontSize="16" FontWeight="Bold" Margin="0,5,0,0"/>
                        <TextBlock Text="Copilot, Recall, AI пакеты" FontSize="12" Foreground="#CCC" Margin="0,3,0,0"/>
                    </StackPanel>
                </Button>

                <Button x:Name="btnDebloat" Style="{StaticResource ModernButton}" Height="80" Margin="5">
                    <StackPanel>
                        <TextBlock Text="🗑️" FontSize="24" HorizontalAlignment="Center"/>
                        <TextBlock Text="Деблотер" FontSize="16" FontWeight="Bold" Margin="0,5,0,0"/>
                        <TextBlock Text="20+ твиков реестра" FontSize="12" Foreground="#CCC" Margin="0,3,0,0"/>
                    </StackPanel>
                </Button>

                <Button x:Name="btnExit" Style="{StaticResource ModernButton}" Height="80" Background="#EF4444">
                    <StackPanel>
                        <TextBlock Text="🚪" FontSize="24" HorizontalAlignment="Center"/>
                        <TextBlock Text="Выход" FontSize="16" FontWeight="Bold" Margin="0,5,0,0"/>
                        <TextBlock Text="Закрыть приложение" FontSize="12" Foreground="#CCC" Margin="0,3,0,0"/>
                    </StackPanel>
                </Button>
            </StackPanel>
        </Grid>

        <!-- Status Bar -->
        <Border Grid.Row="2" Background="#2D2D2D" CornerRadius="10" Padding="15" Margin="0,20,0,0">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="txtStatus" Text="Готов к работе" Foreground="#A1A1AA" Grid.Column="0"/>
                <TextBlock x:Name="txtWinget" Text="winget: проверка..." Foreground="#666" Grid.Column="1"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

# ==============================================================================
# ФУНКЦИИ
# ==============================================================================

function Test-Winget {
    try {
        $null = Get-Command winget -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Write-Log {
    param([string]$Message)
    if ($Debug) {
        Write-Host "[DEBUG] $Message" -ForegroundColor Cyan
    }
}

# ==============================================================================
# ЗАГРУЗКА GUI
# ==============================================================================

try {
    Write-Log "Загрузка XAML..."
    $reader = New-Object System.IO.StringReader $xaml
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    if (-not $window) {
        throw "Не удалось загрузить GUI"
    }

    # Получаем элементы
    $txtVersion = $window.FindName("txtVersion")
    $txtStatus = $window.FindName("txtStatus")
    $txtWinget = $window.FindName("txtWinget")
    $btnInstaller = $window.FindName("btnInstaller")
    $btnClear = $window.FindName("btnClear")
    $btnDiagnostics = $window.FindName("btnDiagnostics")
    $btnRemoveAI = $window.FindName("btnRemoveAI")
    $btnDebloat = $window.FindName("btnDebloat")
    $btnExit = $window.FindName("btnExit")

    # Проверка winget
    if (Test-Winget) {
        $txtWinget.Text = "winget: ✓ доступен"
        $txtWinget.Foreground = "#10B981"
    }
    else {
        $txtWinget.Text = "winget: ✗ не найден"
        $txtWinget.Foreground = "#EF4444"
    }

    # Обработчики кнопок
    $btnInstaller.Add_Click({
        $txtStatus.Text = "Запуск модуля установки ПО..."
        Write-Log "Запуск SoftwareInstaller"
        
        try {
            $modulePath = "$PSScriptRoot\Modules\SoftwareInstaller\SoftwareInstaller.psm1"
            if (Test-Path $modulePath) {
                Import-Module $modulePath -Force
                Invoke-SoftwareInstaller
                Remove-Module SoftwareInstaller -Force
            }
            else {
                [System.Windows.MessageBox]::Show("Модуль не найден: $modulePath", "Ошибка")
            }
        }
        catch {
            [System.Windows.MessageBox]::Show("Ошибка: $_", "Ошибка")
        }
        
        $txtStatus.Text = "Готов к работе"
    })

    $btnClear.Add_Click({
        $txtStatus.Text = "Запуск модуля очистки..."
        Write-Log "Запуск SystemClear"
        
        try {
            $modulePath = "$PSScriptRoot\Modules\SystemClear\SystemClear.psm1"
            if (Test-Path $modulePath) {
                Import-Module $modulePath -Force
                Invoke-SystemClear
                Remove-Module SystemClear -Force
            }
            else {
                [System.Windows.MessageBox]::Show("Модуль не найден: $modulePath", "Ошибка")
            }
        }
        catch {
            [System.Windows.MessageBox]::Show("Ошибка: $_", "Ошибка")
        }
        
        $txtStatus.Text = "Готов к работе"
    })

    $btnDiagnostics.Add_Click({
        $txtStatus.Text = "Запуск модуля диагностики..."
        Write-Log "Запуск Diagnostics"
        
        try {
            $modulePath = "$PSScriptRoot\Modules\Diagnostics\Diagnostics.psm1"
            if (Test-Path $modulePath) {
                Import-Module $modulePath -Force
                Invoke-Diagnostics
                Remove-Module Diagnostics -Force
            }
            else {
                [System.Windows.MessageBox]::Show("Модуль не найден: $modulePath", "Ошибка")
            }
        }
        catch {
            [System.Windows.MessageBox]::Show("Ошибка: $_", "Ошибка")
        }
        
        $txtStatus.Text = "Готов к работе"
    })

    $btnRemoveAI.Add_Click({
        $txtStatus.Text = "Запуск модуля удаления AI..."
        Write-Log "Запуск RemoveAI"
        
        try {
            $modulePath = "$PSScriptRoot\Modules\RemoveAI\RemoveAI.psm1"
            if (Test-Path $modulePath) {
                Import-Module $modulePath -Force
                Invoke-RemoveAI
                Remove-Module RemoveAI -Force
            }
            else {
                [System.Windows.MessageBox]::Show("Модуль не найден: $modulePath", "Ошибка")
            }
        }
        catch {
            [System.Windows.MessageBox]::Show("Ошибка: $_", "Ошибка")
        }
        
        $txtStatus.Text = "Готов к работе"
    })

    $btnDebloat.Add_Click({
        $txtStatus.Text = "Запуск модуля деблотинга..."
        Write-Log "Запуск Debloat"
        
        try {
            $modulePath = "$PSScriptRoot\Modules\Debloat\Debloat.psm1"
            if (Test-Path $modulePath) {
                Import-Module $modulePath -Force
                Invoke-Debloat
                Remove-Module Debloat -Force
            }
            else {
                [System.Windows.MessageBox]::Show("Модуль не найден: $modulePath", "Ошибка")
            }
        }
        catch {
            [System.Windows.MessageBox]::Show("Ошибка: $_", "Ошибка")
        }
        
        $txtStatus.Text = "Готов к работе"
    })

    $btnExit.Add_Click({
        $window.Close()
    })

    # Показываем окно
    Write-Log "Показ GUI..."
    $window.ShowDialog() | Out-Null

}
catch {
    Write-Host "Ошибка GUI: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    
    # Fallback к консольному режиму
    Write-Host ""
    Write-Host "Запуск в консольном режиме..." -ForegroundColor Yellow
    & "$PSScriptRoot\launcher.ps1"
}
