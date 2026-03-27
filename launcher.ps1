# PotatoPS - Прямой запуск без загрузки
# Этот скрипт запускает модули напрямую из GitHub без скачивания

$ErrorActionPreference = "Stop"

# Проверка прав администратора
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║  ТРЕБУЮТСЯ ПРАВА АДМИНИСТРАТОРА                                       ║" -ForegroundColor Red
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    Write-Host "Перезапуск с правами администратора..." -ForegroundColor Yellow
    
    $arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/DezFix/PotatoPC/main/install.ps1')))`""
    Start-Process PowerShell -Verb RunAs -ArgumentList $arguments
    exit
}

# Проверка PowerShell
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "[ОШИБКА] Требуется PowerShell 5.1 или выше!" -ForegroundColor Red
    Start-Sleep -Seconds 3
    exit 1
}

# Временное отключение Execution Policy для текущей сессии
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Загрузка WPF для GUI
try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    $WPF_AVAILABLE = $true
}
catch {
    $WPF_AVAILABLE = $false
    Write-Host "[ВНИМАНИЕ] WPF недоступен, запуск в консольном режиме" -ForegroundColor Yellow
}

# URL для загрузки модулей
$baseUrl = "https://raw.githubusercontent.com/DezFix/PotatoPC/main/"

# Функция загрузки и выполнения модуля
function Invoke-ModuleFromWeb {
    param([string]$ModulePath, [string]$FunctionName)
    
    try {
        $url = $baseUrl + $ModulePath
        Write-Host "[ЗАГРУЗКА] $ModulePath..." -ForegroundColor Cyan
        
        $scriptContent = Invoke-RestMethod -Uri $url -UseBasicParsing
        
        # Выполняем скрипт
        Invoke-Expression $scriptContent
        
        # Вызываем функцию модуля
        if (Get-Command $FunctionName -ErrorAction SilentlyContinue) {
            & $FunctionName
        }
        else {
            Write-Host "[ОШИБКА] Функция $FunctionName не найдена" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "[ОШИБКА] Не удалось загрузить модуль: $_" -ForegroundColor Red
        Write-Host "Нажмите любую клавишу для продолжения..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}

# ==============================================================================
# GUI ПРИЛОЖЕНИЕ (если WPF доступен)
# ==============================================================================

if ($WPF_AVAILABLE) {
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PotatoPS - Системный менеджер Windows"
        Height="600" Width="850"
        WindowStartupLocation="CenterScreen"
        Background="#1A1A1A"
        FontFamily="Segoe UI">

    <Window.Resources>
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Background" Value="#6366F1"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="15,10"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Margin" Value="5"/>
            <Setter Property="Cursor" Value="Hand"/>
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
                <TextBlock Text="🥔 PotatoPS" FontSize="28" FontWeight="Bold" Foreground="#6366F1"/>
                <TextBlock Text="Системный менеджер Windows" FontSize="13" Foreground="#A1A1AA" Margin="0,5,0,0"/>
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
                <Button x:Name="btnInstaller" Style="{StaticResource ModernButton}" Height="75">
                    <StackPanel>
                        <TextBlock Text="📦" FontSize="22" HorizontalAlignment="Center"/>
                        <TextBlock Text="Установка ПО" FontSize="15" FontWeight="Bold" Margin="0,5,0,0"/>
                        <TextBlock Text="88+ программ через winget" FontSize="11" Foreground="#CCC"/>
                    </StackPanel>
                </Button>

                <Button x:Name="btnClear" Style="{StaticResource ModernButton}" Height="75">
                    <StackPanel>
                        <TextBlock Text="🧹" FontSize="22" HorizontalAlignment="Center"/>
                        <TextBlock Text="Очистка системы" FontSize="15" FontWeight="Bold" Margin="0,5,0,0"/>
                        <TextBlock Text="Телеметрия, службы, temp" FontSize="11" Foreground="#CCC"/>
                    </StackPanel>
                </Button>

                <Button x:Name="btnDiagnostics" Style="{StaticResource ModernButton}" Height="75">
                    <StackPanel>
                        <TextBlock Text="🔍" FontSize="22" HorizontalAlignment="Center"/>
                        <TextBlock Text="Диагностика" FontSize="15" FontWeight="Bold" Margin="0,5,0,0"/>
                        <TextBlock Text="SFC, DISM, CHKDSK, RAM" FontSize="11" Foreground="#CCC"/>
                    </StackPanel>
                </Button>
            </StackPanel>

            <!-- Right Column -->
            <StackPanel Grid.Column="1" Margin="10,0,0,0">
                <Button x:Name="btnRemoveAI" Style="{StaticResource ModernButton}" Height="75">
                    <StackPanel>
                        <TextBlock Text="🤖" FontSize="22" HorizontalAlignment="Center"/>
                        <TextBlock Text="Удаление AI" FontSize="15" FontWeight="Bold" Margin="0,5,0,0"/>
                        <TextBlock Text="Copilot, Recall, AI пакеты" FontSize="11" Foreground="#CCC"/>
                    </StackPanel>
                </Button>

                <Button x:Name="btnDebloat" Style="{StaticResource ModernButton}" Height="75">
                    <StackPanel>
                        <TextBlock Text="🗑️" FontSize="22" HorizontalAlignment="Center"/>
                        <TextBlock Text="Деблотер" FontSize="15" FontWeight="Bold" Margin="0,5,0,0"/>
                        <TextBlock Text="20+ твиков реестра" FontSize="11" Foreground="#CCC"/>
                    </StackPanel>
                </Button>

                <Button x:Name="btnExit" Style="{StaticResource ModernButton}" Height="75" Background="#EF4444">
                    <StackPanel>
                        <TextBlock Text="🚪" FontSize="22" HorizontalAlignment="Center"/>
                        <TextBlock Text="Выход" FontSize="15" FontWeight="Bold" Margin="0,5,0,0"/>
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
                <TextBlock x:Name="txtStatus" Text="Готов к работе" Foreground="#A1A1AA"/>
                <TextBlock x:Name="txtWinget" Text="winget: проверка..." Foreground="#666" Grid.Column="1"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

    try {
        $reader = New-Object System.IO.StringReader $xaml
        $window = [System.Windows.Markup.XamlReader]::Load($reader)

        if ($window) {
            $txtStatus = $window.FindName("txtStatus")
            $txtWinget = $window.FindName("txtWinget")

            # Проверка winget
            try {
                $null = Get-Command winget -ErrorAction Stop
                $txtWinget.Text = "winget: ✓"
                $txtWinget.Foreground = "#10B981"
            }
            catch {
                $txtWinget.Text = "winget: ✗"
                $txtWinget.Foreground = "#EF4444"
            }

            # Обработчики
            $btnInstaller.Add_Click({
                $txtStatus.Text = "Загрузка модуля..."
                Invoke-ModuleFromWeb "Modules/SoftwareInstaller/SoftwareInstaller.psm1" "Invoke-SoftwareInstaller"
                $txtStatus.Text = "Готов к работе"
            })

            $btnClear.Add_Click({
                $txtStatus.Text = "Загрузка модуля..."
                Invoke-ModuleFromWeb "Modules/SystemClear/SystemClear.psm1" "Invoke-SystemClear"
                $txtStatus.Text = "Готов к работе"
            })

            $btnDiagnostics.Add_Click({
                $txtStatus.Text = "Загрузка модуля..."
                Invoke-ModuleFromWeb "Modules/Diagnostics/Diagnostics.psm1" "Invoke-Diagnostics"
                $txtStatus.Text = "Готов к работе"
            })

            $btnRemoveAI.Add_Click({
                $txtStatus.Text = "Загрузка модуля..."
                Invoke-ModuleFromWeb "Modules/RemoveAI/RemoveAI.psm1" "Invoke-RemoveAI"
                $txtStatus.Text = "Готов к работе"
            })

            $btnDebloat.Add_Click({
                $txtStatus.Text = "Загрузка модуля..."
                Invoke-ModuleFromWeb "Modules/Debloat/Debloat.psm1" "Invoke-Debloat"
                $txtStatus.Text = "Готов к работе"
            })

            $btnExit.Add_Click({ $window.Close() })

            $window.ShowDialog() | Out-Null
            exit
        }
    }
    catch {
        Write-Host "[ОШИБКА GUI] $_" -ForegroundColor Yellow
        Write-Host "Переключение на консольный режим..." -ForegroundColor Yellow
    }
}

# ==============================================================================
# КОНСОЛЬНОЕ МЕНЮ (fallback)
# ==============================================================================

function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                    🥔 PotatoPS v2.0                                   ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. 📦 Установка ПО" -ForegroundColor White
    Write-Host "  2. 🧹 Очистка системы" -ForegroundColor White
    Write-Host "  3. 🔍 Диагностика" -ForegroundColor White
    Write-Host "  4. 🤖 Удаление AI" -ForegroundColor White
    Write-Host "  5. 🗑️ Деблотер" -ForegroundColor White
    Write-Host ""
    Write-Host "  0. Выход" -ForegroundColor Red
    Write-Host ""
}

while ($true) {
    Show-Menu
    $choice = Read-Host "Выберите опцию"

    switch ($choice) {
        "1" { Invoke-ModuleFromWeb "Modules/SoftwareInstaller/SoftwareInstaller.psm1" "Invoke-SoftwareInstaller" }
        "2" { Invoke-ModuleFromWeb "Modules/SystemClear/SystemClear.psm1" "Invoke-SystemClear" }
        "3" { Invoke-ModuleFromWeb "Modules/Diagnostics/Diagnostics.psm1" "Invoke-Diagnostics" }
        "4" { Invoke-ModuleFromWeb "Modules/RemoveAI/RemoveAI.psm1" "Invoke-RemoveAI" }
        "5" { Invoke-ModuleFromWeb "Modules/Debloat/Debloat.psm1" "Invoke-Debloat" }
        "0" { 
            Write-Host "До свидания!" -ForegroundColor Green
            exit 
        }
        default { 
            Write-Host "Неверный ввод!" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
