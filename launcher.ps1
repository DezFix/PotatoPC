# PotatoPS - GUI Лаунчер
# Запуск: & ([scriptblock]::Create((irm "https://raw.githubusercontent.com/DezFix/PotatoPC/main/launcher.ps1")))

# Проверка прав администратора
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process PowerShell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

# Загружаем WPF
try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName System.Windows.Forms
}
catch {
    Write-Host "WPF не доступен!" -ForegroundColor Red
    exit 1
}

# URL для модулей
$baseUrl = "https://raw.githubusercontent.com/DezFix/PotatoPC/main/"

# Временная папка для модулей
$tempModules = Join-Path $env:TEMP "PotatoPS-Modules"
if (-not (Test-Path $tempModules)) {
    New-Item -Path $tempModules -ItemType Directory -Force | Out-Null
}

# Функция загрузки и запуска модуля
function Load-Module {
    param($moduleName, $functionName)
    
    $window.Title = "PotatoPS - Загрузка $moduleName..."
    
    try {
        # Создаём папку для модуля
        $modulePath = Join-Path $tempModules $moduleName
        $moduleDir = Split-Path $modulePath -Parent
        if (-not (Test-Path $moduleDir)) {
            New-Item -Path $moduleDir -ItemType Directory -Force | Out-Null
        }
        
        # Скачиваем модуль
        $url = "$baseUrl$moduleName"
        Invoke-WebRequest -Uri $url -OutFile $modulePath -UseBasicParsing
        
        # Скачиваем Config файлы если нужно
        if (-not (Test-Path "$tempModules\Config")) {
            New-Item -Path "$tempModules\Config" -ItemType Directory -Force | Out-Null
            Invoke-WebRequest -Uri "$baseUrl/Config/apps.json" -OutFile "$tempModules\Config\apps.json" -UseBasicParsing
            Invoke-WebRequest -Uri "$baseUrl/Config/settings.json" -OutFile "$tempModules\Config\settings.json" -UseBasicParsing
        }
        
        # Загружаем модуль
        Import-Module $modulePath -Force
        
        # Вызываем функцию
        & $functionName
        
        # Выгружаем
        Remove-Module $moduleName -Force
    }
    catch {
        [System.Windows.MessageBox]::Show("Ошибка: $_", "PotatoPS", "OK", "Error")
    }
    finally {
        $window.Title = "PotatoPS"
    }
}

# XAML разметка
[xml]$xaml = @"
<Window 
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="PotatoPS" 
    Height="550" 
    Width="800"
    WindowStartupLocation="CenterScreen"
    Background="#1A1A1A"
    ResizeMode="CanResizeWithGrip"
    FontFamily="Segoe UI">
    
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#2D2D2D" CornerRadius="10" Padding="20" Margin="0,0,0,20">
            <StackPanel>
                <TextBlock Text="🥔 PotatoPS" FontSize="32" FontWeight="Bold" Foreground="#6366F1"/>
                <TextBlock Text="Системный менеджер Windows" FontSize="14" Foreground="#A1A1AA"/>
            </StackPanel>
        </Border>

        <!-- Buttons Grid -->
        <UniformGrid Grid.Row="1" Rows="3" Columns="2">
            <Button x:Name="btn1" Margin="5" Background="#6366F1" Foreground="White" FontSize="16" Padding="20" Cursor="Hand">
                <StackPanel>
                    <TextBlock Text="📦" FontSize="28" HorizontalAlignment="Center"/>
                    <TextBlock Text="Установка ПО" FontSize="16" FontWeight="Bold" Margin="0,5,0,0"/>
                    <TextBlock Text="88+ программ" FontSize="12" Foreground="#CCC"/>
                </StackPanel>
            </Button>
            
            <Button x:Name="btn2" Margin="5" Background="#6366F1" Foreground="White" FontSize="16" Padding="20" Cursor="Hand">
                <StackPanel>
                    <TextBlock Text="🧹" FontSize="28" HorizontalAlignment="Center"/>
                    <TextBlock Text="Очистка" FontSize="16" FontWeight="Bold" Margin="0,5,0,0"/>
                    <TextBlock Text="Телеметрия, temp" FontSize="12" Foreground="#CCC"/>
                </StackPanel>
            </Button>
            
            <Button x:Name="btn3" Margin="5" Background="#6366F1" Foreground="White" FontSize="16" Padding="20" Cursor="Hand">
                <StackPanel>
                    <TextBlock Text="🔍" FontSize="28" HorizontalAlignment="Center"/>
                    <TextBlock Text="Диагностика" FontSize="16" FontWeight="Bold" Margin="0,5,0,0"/>
                    <TextBlock Text="SFC, DISM, RAM" FontSize="12" Foreground="#CCC"/>
                </StackPanel>
            </Button>
            
            <Button x:Name="btn4" Margin="5" Background="#6366F1" Foreground="White" FontSize="16" Padding="20" Cursor="Hand">
                <StackPanel>
                    <TextBlock Text="🤖" FontSize="28" HorizontalAlignment="Center"/>
                    <TextBlock Text="Удаление AI" FontSize="16" FontWeight="Bold" Margin="0,5,0,0"/>
                    <TextBlock Text="Copilot, Recall" FontSize="12" Foreground="#CCC"/>
                </StackPanel>
            </Button>
            
            <Button x:Name="btn5" Margin="5" Background="#6366F1" Foreground="White" FontSize="16" Padding="20" Cursor="Hand">
                <StackPanel>
                    <TextBlock Text="🗑️" FontSize="28" HorizontalAlignment="Center"/>
                    <TextBlock Text="Деблотер" FontSize="16" FontWeight="Bold" Margin="0,5,0,0"/>
                    <TextBlock Text="20+ твиков" FontSize="12" Foreground="#CCC"/>
                </StackPanel>
            </Button>
            
            <Button x:Name="btn6" Margin="5" Background="#EF4444" Foreground="White" FontSize="16" Padding="20" Cursor="Hand">
                <StackPanel>
                    <TextBlock Text="🚪" FontSize="28" HorizontalAlignment="Center"/>
                    <TextBlock Text="Выход" FontSize="16" FontWeight="Bold" Margin="0,5,0,0"/>
                </StackPanel>
            </Button>
        </UniformGrid>
    </Grid>
</Window>
"@

try {
    $reader = New-Object System.Xml.XmlNodeReader $xaml.DocumentElement
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    
    if ($window) {
        # Находим кнопки
        $btn1 = $window.FindName("btn1")
        $btn2 = $window.FindName("btn2")
        $btn3 = $window.FindName("btn3")
        $btn4 = $window.FindName("btn4")
        $btn5 = $window.FindName("btn5")
        $btn6 = $window.FindName("btn6")
        
        # Обработчики
        $btn1.Add_Click({ Load-Module "SoftwareInstaller.psm1" "Invoke-SoftwareInstaller" })
        $btn2.Add_Click({ Load-Module "SystemClear.psm1" "Invoke-SystemClear" })
        $btn3.Add_Click({ Load-Module "Diagnostics.psm1" "Invoke-Diagnostics" })
        $btn4.Add_Click({ Load-Module "RemoveAI.psm1" "Invoke-RemoveAI" })
        $btn5.Add_Click({ Load-Module "Debloat.psm1" "Invoke-Debloat" })
        $btn6.Add_Click({ $window.Close() })
        
        # Показываем окно
        $window.ShowDialog()
    }
}
catch {
    Write-Host "Ошибка GUI: $_" -ForegroundColor Red
    Write-Host "Запуск консольной версии..." -ForegroundColor Yellow
    
    # Консольная версия
    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                    🥔 PotatoPS                                        ║" -ForegroundColor Cyan
        Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  1. 📦 Установка ПО" -ForegroundColor White
        Write-Host "  2. 🧹 Очистка" -ForegroundColor White
        Write-Host "  3. 🔍 Диагностика" -ForegroundColor White
        Write-Host "  4. 🤖 Удаление AI" -ForegroundColor White
        Write-Host "  5. 🗑️ Деблотер" -ForegroundColor White
        Write-Host ""
        Write-Host "  0. Выход" -ForegroundColor Red
        Write-Host ""
        
        $choice = Read-Host "Выберите"
        
        switch ($choice) {
            "1" { Load-Module "SoftwareInstaller.psm1" "Invoke-SoftwareInstaller" }
            "2" { Load-Module "SystemClear.psm1" "Invoke-SystemClear" }
            "3" { Load-Module "Diagnostics.psm1" "Invoke-Diagnostics" }
            "4" { Load-Module "RemoveAI.psm1" "Invoke-RemoveAI" }
            "5" { Load-Module "Debloat.psm1" "Invoke-Debloat" }
            "0" { exit }
        }
    }
}
