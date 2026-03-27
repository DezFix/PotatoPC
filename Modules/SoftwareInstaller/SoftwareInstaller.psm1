<#
.SYNOPSIS
    Модуль установки программного обеспечения
.DESCRIPTION
    Установка программ через winget с использованием каталога apps.json
#>

# Путь к Config файлам (сначала пробуем временную папку, потом локальную)
$tempConfig = Join-Path $env:TEMP "PotatoPS-Modules\Config\apps.json"
if (Test-Path $tempConfig) {
    $configPath = $tempConfig
}
elseif (Test-Path "$PSScriptRoot\..\Config\apps.json") {
    $configPath = "$PSScriptRoot\..\Config\apps.json"
}
else {
    $configPath = $null
}

$MODULE_CONFIG = @{
    Name = "Установка ПО"
    Version = "1.0.0"
    AppsConfigPath = $configPath
}

# Цвета
$COLOR_ACCENT = "Yellow"
$COLOR_SUCCESS = "Green"
$COLOR_ERROR = "Red"
$COLOR_INFO = "Cyan"

# ==============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ==============================================================================

function Write-InstallerStatus {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Error', 'Warning')]
        [string]$Type = 'Info'
    )
    
    $symbol = switch ($Type) {
        'Info' { '[ℹ]' }
        'Success' { '[✓]' }
        'Error' { '[✗]' }
        'Warning' { '[!]'}
    }
    
    $color = switch ($Type) {
        'Info' { $COLOR_INFO }
        'Success' { $COLOR_SUCCESS }
        'Error' { $COLOR_ERROR }
        'Warning' { $COLOR_WARNING }
    }
    
    Write-Host "  $symbol $Message" -ForegroundColor $color
}

function Test-WingetInstalled {
    try {
        $null = Get-Command winget -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Install-WingetIfMissing {
    if (-not (Test-WingetInstalled)) {
        Write-InstallerStatus -Message "winget не найден. Установка..." -Type Warning
        
        try {
            $wingetUrl = "https://aka.ms/getwinget"
            $tempPath = [System.IO.Path]::GetTempPath()
            $installerPath = Join-Path $tempPath "winget.install.ps1"
            
            Invoke-WebRequest -Uri $wingetUrl -OutFile $installerPath -UseBasicParsing
            & powershell -ExecutionPolicy Bypass -File $installerPath
            
            if (Test-WingetInstalled) {
                Write-InstallerStatus -Message "winget успешно установлен!" -Type Success
                return $true
            }
        }
        catch {
            Write-InstallerStatus -Message "Не удалось установить winget: $_" -Type Error
            return $false
        }
    }
    return $true
}

function Get-InstalledApps {
    try {
        $apps = winget list --source winget 2>$null | Select-Object -Skip 3 | Where-Object { $_ -match '\S' }
        return $apps | ForEach-Object {
            $parts = $_ -split '\s{2,}'
            if ($parts.Count -ge 2) {
                [PSCustomObject]@{
                    Id = $parts[1].Trim()
                    Name = $parts[0].Trim()
                    Version = if ($parts.Count -ge 3) { $parts[2].Trim() } else { "Unknown" }
                }
            }
        }
    }
    catch {
        return @()
    }
}

function Get-AppUpdates {
    try {
        $updates = winget upgrade 2>$null | Select-Object -Skip 3 | Where-Object { $_ -match '\S' -and $_ -notmatch '^Name' }
        return $updates | ForEach-Object {
            $parts = $_ -split '\s{2,}'
            if ($parts.Count -ge 2) {
                [PSCustomObject]@{
                    Id = $parts[1].Trim()
                    Name = $parts[0].Trim()
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

function Install-App {
    param(
        [string]$AppId,
        [string]$AppName,
        [switch]$Silent
    )
    
    Write-InstallerStatus -Message "Установка: $AppName ($AppId)" -Type Info
    
    try {
        $argumentList = @(
            "install",
            "--id", $AppId,
            "--silent",
            "--accept-package-agreements",
            "--accept-source-agreements"
        )
        
        $process = Start-Process -FilePath "winget" -ArgumentList $argumentList -PassThru -Wait -NoNewWindow
        
        if ($process.ExitCode -eq 0) {
            Write-InstallerStatus -Message "Успешно установлено: $AppName" -Type Success
            return $true
        }
        else {
            Write-InstallerStatus -Message "Ошибка установки (код: $($process.ExitCode)): $AppName" -Type Error
            return $false
        }
    }
    catch {
        Write-InstallerStatus -Message "Ошибка: $_" -Type Error
        return $false
    }
}

function Update-App {
    param(
        [string]$AppId,
        [string]$AppName
    )
    
    Write-InstallerStatus -Message "Обновление: $AppName ($AppId)" -Type Info
    
    try {
        $argumentList = @(
            "upgrade",
            "--id", $AppId,
            "--silent"
        )
        
        $process = Start-Process -FilePath "winget" -ArgumentList $argumentList -PassThru -Wait -NoNewWindow
        
        if ($process.ExitCode -eq 0) {
            Write-InstallerStatus -Message "Успешно обновлено: $AppName" -Type Success
            return $true
        }
        else {
            Write-InstallerStatus -Message "Ошибка обновления (код: $($process.ExitCode)): $AppName" -Type Error
            return $false
        }
    }
    catch {
        Write-InstallerStatus -Message "Ошибка: $_" -Type Error
        return $false
    }
}

function Load-AppsConfig {
    $configPath = $MODULE_CONFIG.AppsConfigPath
    
    if (Test-Path $configPath) {
        try {
            $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
            return $config
        }
        catch {
            Write-InstallerStatus -Message "Ошибка загрузки apps.json: $_" -Type Error
            return $null
        }
    }
    else {
        Write-InstallerStatus -Message "Файл apps.json не найден: $configPath" -Type Error
        return $null
    }
}

# ==============================================================================
# ФУНКЦИИ МЕНЮ
# ==============================================================================

function Show-CategoryMenu {
    param(
        [object]$AppsConfig,
        [ref]$SelectedApps
    )
    
    $categories = $AppsConfig.Categories.PSObject.Properties.Name
    
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $COLOR_ACCENT
    Write-Host "║  КАТЕГОРИИ ПРОГРАММ                                                   ║" -ForegroundColor $COLOR_ACCENT
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $COLOR_ACCENT
    Write-Host ""
    
    $index = 1
    foreach ($category in $categories) {
        $count = $AppsConfig.Categories.$category.Count
        Write-Host "  $index. $category ($count)" -ForegroundColor White
        $index++
    }
    
    Write-Host ""
    Write-Host "  P. Пресеты" -ForegroundColor DarkCyan
    Write-Host "  U. Проверить обновления" -ForegroundColor DarkMagenta
    Write-Host "  0. Назад" -ForegroundColor Red
    Write-Host ""
    
    $choice = Read-Host "  Выберите категорию"
    
    if ($choice -eq "0") {
        return
    }
    elseif ($choice -eq "P" -or $choice -eq "p") {
        Show-PresetsMenu -AppsConfig $AppsConfig -SelectedApps $SelectedApps
        return
    }
    elseif ($choice -eq "U" -or $choice -eq "u") {
        Show-UpdatesMenu
        return
    }
    
    $choiceNum = [int]::Parse($choice) - 1
    
    if ($choiceNum -ge 0 -and $choiceNum -lt $categories.Count) {
        $selectedCategory = $categories[$choiceNum]
        Show-AppsInCategory -AppsConfig $AppsConfig -Category $selectedCategory -SelectedApps $SelectedApps
    }
}

function Show-AppsInCategory {
    param(
        [object]$AppsConfig,
        [string]$Category,
        [ref]$SelectedApps
    )
    
    $apps = $AppsConfig.Categories.$Category
    
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $COLOR_ACCENT
    Write-Host "║  $Category" -ForegroundColor $COLOR_ACCENT -NoNewline
    $padding = 68 - $Category.Length
    Write-Host (" " * $padding) + "║" -ForegroundColor $COLOR_ACCENT
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $COLOR_ACCENT
    Write-Host ""
    
    $index = 1
    $appMap = @{}
    
    foreach ($app in $apps) {
        $isSelected = $SelectedApps.Value.Id -contains $app.Id
        $status = if ($isSelected) { " [✓]" } else { "     " }
        $color = if ($isSelected) { "Green" } else { "White" }
        
        Write-Host "  $index.$status " -ForegroundColor $color -NoNewline
        Write-Host "$($app.Name)" -ForegroundColor $color
        Write-Host "      $($app.Description)" -ForegroundColor DarkGray
        Write-Host ""
        
        $appMap[$index] = $app
        $index++
    }
    
    Write-Host "  0. Назад" -ForegroundColor Red
    Write-Host ""
    
    while ($true) {
        $choice = Read-Host "  Выберите программу"
        
        if ($choice -eq "0") {
            return
        }
        
        $choiceNum = [int]::Parse($choice)
        
        if ($choiceNum -gt 0 -and $choiceNum -lt $index) {
            $selectedApp = $appMap[$choiceNum]
            
            $existingIndex = $SelectedApps.Value.FindIndex({ param($a) $a.Id -eq $selectedApp.Id })
            
            if ($existingIndex -ge 0) {
                $SelectedApps.Value.RemoveAt($existingIndex)
                Write-InstallerStatus -Message "Удалено из списка: $($selectedApp.Name)" -Type Warning
            }
            else {
                $SelectedApps.Value.Add($selectedApp)
                Write-InstallerStatus -Message "Добавлено: $($selectedApp.Name)" -Type Success
            }
            
            # Перерисовываем список
            Clear-Host
            Show-AppsInCategory -AppsConfig $AppsConfig -Category $Category -SelectedApps $SelectedApps
        }
    }
}

function Show-PresetsMenu {
    param(
        [object]$AppsConfig,
        [ref]$SelectedApps
    )
    
    $presets = $AppsConfig.Presets.PSObject.Properties
    
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $COLOR_ACCENT
    Write-Host "║  ПРЕСЕТЫ                                                              ║" -ForegroundColor $COLOR_ACCENT
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $COLOR_ACCENT
    Write-Host ""
    
    $index = 1
    $presetMap = @{}
    
    foreach ($preset in $presets) {
        Write-Host "  $index. $($preset.Name)" -ForegroundColor White
        Write-Host "      Программ: $($preset.Value.Count)" -ForegroundColor DarkGray
        Write-Host ""
        
        $presetMap[$index] = $preset
        $index++
    }
    
    Write-Host "  0. Назад" -ForegroundColor Red
    Write-Host ""
    
    $choice = Read-Host "  Выберите пресет"
    
    if ($choice -eq "0") {
        return
    }
    
    $choiceNum = [int]::Parse($choice)
    
    if ($choiceNum -gt 0 -and $choiceNum -lt $index) {
        $selectedPreset = $presetMap[$choiceNum]
        
        foreach ($appId in $selectedPreset.Value) {
            # Находим информацию о приложении
            foreach ($category in $AppsConfig.Categories.PSObject.Properties.Value) {
                $app = $category | Where-Object { $_.Id -eq $appId }
                if ($app) {
                    if ($SelectedApps.Value.Id -notcontains $appId) {
                        $SelectedApps.Value.Add($app)
                    }
                    break
                }
            }
        }
        
        Write-InstallerStatus -Message "Пресет '$($selectedPreset.Name)' добавлен в список" -Type Success
        Wait-Key -Message "Нажмите Enter для продолжения..."
    }
}

function Show-UpdatesMenu {
    Write-Host ""
    Write-InstallerStatus -Message "Сканирование обновлений..." -Type Info
    
    $updates = Get-AppUpdates
    
    if ($updates.Count -eq 0) {
        Write-InstallerStatus -Message "Обновлений не найдено" -Type Success
        Wait-Key
        return
    }
    
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $COLOR_ACCENT
    Write-Host "║  ДОСТУПНЫ ОБНОВЛЕНИЯ: $($updates.Count)                               ║" -ForegroundColor $COLOR_ACCENT
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $COLOR_ACCENT
    Write-Host ""
    
    $index = 1
    $updateMap = @{}
    
    foreach ($update in $updates) {
        Write-Host "  $index. $($update.Name)" -ForegroundColor White
        Write-Host "      $($update.CurrentVersion) → $($update.AvailableVersion)" -ForegroundColor DarkGray
        Write-Host ""
        
        $updateMap[$index] = $update
        $index++
    }
    
    Write-Host "  A. Обновить всё" -ForegroundColor Green
    Write-Host "  0. Назад" -ForegroundColor Red
    Write-Host ""
    
    $choice = Read-Host "  Выберите для обновления"
    
    if ($choice -eq "0") {
        return
    }
    elseif ($choice -eq "A" -or $choice -eq "a") {
        foreach ($update in $updates) {
            Update-App -AppId $update.Id -AppName $update.Name
        }
    }
    else {
        $choiceNum = [int]::Parse($choice)
        if ($choiceNum -gt 0 -and $choiceNum -lt $index) {
            $selectedUpdate = $updateMap[$choiceNum]
            Update-App -AppId $selectedUpdate.Id -AppName $selectedUpdate.Name
        }
    }
    
    Wait-Key
}

function Show-SelectedApps {
    param(
        [ref]$SelectedApps
    )
    
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $COLOR_ACCENT
    Write-Host "║  ВЫБРАНО ПРОГРАММ: $($SelectedApps.Value.Count)                       ║" -ForegroundColor $COLOR_ACCENT
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $COLOR_ACCENT
    Write-Host ""
    
    if ($SelectedApps.Value.Count -eq 0) {
        Write-Host "  Список пуст" -ForegroundColor DarkGray
        Write-Host ""
    }
    else {
        $index = 1
        foreach ($app in $SelectedApps.Value) {
            Write-Host "  $index. $($app.Name)" -ForegroundColor White
            Write-Host "      ID: $($app.Id)" -ForegroundColor DarkGray
            $index++
        }
        Write-Host ""
    }
    
    Write-Host "  I. Установить выбранное" -ForegroundColor Green
    Write-Host "  C. Очистить список" -ForegroundColor Red
    Write-Host "  0. Назад" -ForegroundColor Red
    Write-Host ""
    
    $choice = Read-Host "  Выберите действие"
    
    if ($choice -eq "0") {
        return
    }
    elseif ($choice -eq "C" -or $choice -eq "c") {
        $SelectedApps.Value.Clear()
        Write-InstallerStatus -Message "Список очищен" -Type Warning
    }
    elseif ($choice -eq "I" -or $choice -eq "i") {
        if ($SelectedApps.Value.Count -gt 0) {
            $confirm = Read-Host "  Вы уверены? (y/n)"
            if ($confirm -eq "y" -or $confirm -eq "Y") {
                foreach ($app in $SelectedApps.Value) {
                    Install-App -AppId $app.Id -AppName $app.Name
                }
                Write-Host ""
                Write-InstallerStatus -Message "Установка завершена!" -Type Success
                $SelectedApps.Value.Clear()
            }
        }
        else {
            Write-InstallerStatus -Message "Список пуст. Выберите программы для установки" -Type Warning
        }
    }
    
    Wait-Key
}

function Wait-Key {
    param([string]$Message = "Нажмите любую клавишу для продолжения...")
    Write-Host ""
    Write-Host $Message -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ==============================================================================
# ТОЧКА ВХОДА МОДУЛЯ
# ==============================================================================

function Invoke-SoftwareInstaller {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $COLOR_ACCENT
    Write-Host "║  УСТАНОВКА ПРОГРАММНОГО ОБЕСПЕЧЕНИЯ                                   ║" -ForegroundColor $COLOR_ACCENT
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $COLOR_ACCENT
    Write-Host ""
    
    # Проверяем winget
    if (-not (Install-WingetIfMissing)) {
        Write-InstallerStatus -Message "winget не доступен. Модуль не может работать." -Type Error
        Wait-Key
        return
    }
    
    # Загружаем конфигурацию
    $appsConfig = Load-AppsConfig
    
    if (-not $appsConfig) {
        Write-InstallerStatus -Message "Не удалось загрузить конфигурацию" -Type Error
        Wait-Key
        return
    }
    
    # Инициализируем список выбранных приложений
    $selectedApps = [System.Collections.ArrayList]::new()
    
    # Основной цикл модуля
    $exit = $false
    
    while (-not $exit) {
        Clear-Host
        
        Write-Host ""
        Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $COLOR_ACCENT
        Write-Host "║  УСТАНОВКА ПРОГРАММ :: winget                                         ║" -ForegroundColor $COLOR_ACCENT
        Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $COLOR_ACCENT
        Write-Host ""
        
        Write-Host "  Выбрано программ: $($selectedApps.Count)" -ForegroundColor White
        Write-Host ""
        
        Show-CategoryMenu -AppsConfig $appsConfig -SelectedApps ([ref]$selectedApps)
        
        if ($selectedApps.Count -gt 0) {
            Show-SelectedApps -SelectedApps ([ref]$selectedApps)
        }
    }
}

# Экспортируем точку входа
Export-ModuleMember -Function Invoke-SoftwareInstaller
