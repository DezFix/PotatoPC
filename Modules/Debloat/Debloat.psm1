<#
.SYNOPSIS
    Модуль деблотинга Windows
.DESCRIPTION
    Удаление встроенного мусора, отключение телеметрии, твики реестра
    На основе проекта Win11Debloat
#>

$MODULE_CONFIG = @{
    Name = "Деблотер"
    Version = "1.0.0"
}

# Цвета
$COLOR_ACCENT = "DarkYellow"
$COLOR_SUCCESS = "Green"
$COLOR_ERROR = "Red"
$COLOR_INFO = "Cyan"
$COLOR_WARNING = "DarkYellow"

# ==============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ==============================================================================

function Write-Status {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Error', 'Warning')]
        [string]$Type = 'Info'
    )
    
    $symbol = switch ($Type) {
        'Info' { '[+]}' }
        'Success' { '[✓]' }
        'Error' { '[✗]' }
        'Warning' { '[!]' }
    }
    
    $color = switch ($Type) {
        'Info' { $COLOR_INFO }
        'Success' { $COLOR_SUCCESS }
        'Error' { $COLOR_ERROR }
        'Warning' { $COLOR_WARNING }
    }
    
    Write-Host "  $symbol $Message" -ForegroundColor $color
}

function Wait-Key {
    param([string]$Message = "Нажмите любую клавишу для продолжения...")
    Write-Host ""
    Write-Host $Message -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Create-RestorePoint {
    Write-Status -Message "Создание точки восстановления..." -Type Info
    
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "PotatoPS Debloat - $(Get-Date -Format 'yyyy-MM-dd')" -RestorePointType "MODIFY_SETTINGS"
        Write-Status -Message "Точка восстановления создана" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Не удалось создать точку восстановления: $_" -Type Warning
        return $false
    }
}

# ==============================================================================
# ФУНКЦИИ ДЕБЛОТИНГА
# ==============================================================================

function Disable-Telemetry {
    Write-Status -Message "Отключение телеметрии..." -Type Info
    
    try {
        # DiagTrack
        if (Get-Service "DiagTrack" -ErrorAction SilentlyContinue) {
            Stop-Service -Name "DiagTrack" -Force -ErrorAction SilentlyContinue
            Set-Service -Name "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue
        }
        
        # dmwappushservice
        if (Get-Service "dmwappushservice" -ErrorAction SilentlyContinue) {
            Stop-Service -Name "dmwappushservice" -Force -ErrorAction SilentlyContinue
            Set-Service -Name "dmwappushservice" -StartupType Disabled -ErrorAction SilentlyContinue
        }
        
        # Реестр - телеметрия
        $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name "AllowTelemetry" -Value 0 -Type DWord -Force
        
        Write-Status -Message "Телеметрия отключена" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка отключения телеметрии: $_" -Type Error
        return $false
    }
}

function Disable-SearchHistory {
    Write-Status -Message "Отключение истории поиска..." -Type Info
    
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "HistoryViewMode" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 0 -Type DWord -Force
        
        Write-Status -Message "История поиска отключена" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка: $_" -Type Error
        return $false
    }
}

function Disable-FastStartup {
    Write-Status -Message "Отключение быстрого запуска..." -Type Info
    
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 0 -Type DWord -Force
        
        Write-Status -Message "Быстрый запуск отключен" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка: $_" -Type Error
        return $false
    }
}

function Disable-BitlockerAutoEncryption {
    Write-Status -Message "Отключение авто-шифрования BitLocker..." -Type Info
    
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker"
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name "PreventDeviceEncryption" -Value 1 -Type DWord -Force
        
        Write-Status -Message "Авто-шифрование BitLocker отключено" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка: $_" -Type Error
        return $false
    }
}

function Disable-StorageSense {
    Write-Status -Message "Отключение Storage Sense..." -Type Info
    
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" -Name "01" -Value 0 -Type DWord -Force
        
        Write-Status -Message "Storage Sense отключен" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка: $_" -Type Error
        return $false
    }
}

function Disable-WindowsUpdate {
    Write-Status -Message "Настройка Windows Update..." -Type Info
    
    try {
        # Отключение автоматических обновлений
        $regPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"
        Set-ItemProperty -Path $regPath -Name "AUOptions" -Value 2 -Type DWord -Force
        
        # Отключение Delivery Optimization
        Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -Value 0 -Type DWord -Force
        
        Write-Status -Message "Windows Update настроен" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка настройки Windows Update: $_" -Type Error
        return $false
    }
}

function Disable-BingSearch {
    Write-Status -Message "Отключение Bing в поиске..." -Type Info
    
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 0 -Type DWord -Force
        
        Write-Status -Message "Bing в поиске отключен" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка: $_" -Type Error
        return $false
    }
}

function Disable-EdgeAds {
    Write-Status -Message "Отключение рекламы в Edge..." -Type Info
    
    try {
        $edgePaths = @(
            "HKCU:\Software\Policies\Microsoft\Edge",
            "HKLM:\Software\Policies\Microsoft\Edge"
        )
        
        foreach ($path in $edgePaths) {
            if (-not (Test-Path $path)) {
                New-Item -Path $path -Force | Out-Null
            }
            Set-ItemProperty -Path $path -Name "PersonalizationReportingEnabled" -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $path -Name "ShowRecommendationsEnabled" -Value 0 -Type DWord -Force
        }
        
        Write-Status -Message "Реклама в Edge отключена" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка: $_" -Type Error
        return $false
    }
}

function Enable-DarkMode {
    Write-Status -Message "Включение темной темы..." -Type Info
    
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0 -Type DWord -Force
        
        Write-Status -Message "Темная тема включена" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка: $_" -Type Error
        return $false
    }
}

function Disable-Transparency {
    Write-Status -Message "Отключение прозрачности..." -Type Info
    
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 0 -Type DWord -Force
        
        Write-Status -Message "Прозрачность отключена" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка: $_" -Type Error
        return $false
    }
}

function TaskbarAlignLeft {
    Write-Status -Message "Выравнивание панели задач влево..." -Type Info
    
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 0 -Type DWord -Force
        
        Write-Status -Message "Панель задач выровнена влево" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка: $_" -Type Error
        return $false
    }
}

function Disable-Widgets {
    Write-Status -Message "Отключение виджетов..." -Type Info
    
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 -Type DWord -Force
        
        Write-Status -Message "Виджеты отключены" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка: $_" -Type Error
        return $false
    }
}

function Disable-Chat {
    Write-Status -Message "Отключение чата на панели задач..." -Type Info
    
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarMn" -Value 0 -Type DWord -Force
        
        Write-Status -Message "Чат отключен" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка: $_" -Type Error
        return $false
    }
}

function Enable-EndTask {
    Write-Status -Message "Включение 'Завершить задачу' в панели задач..." -Type Info
    
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" -Name "TaskbarEndTask" -Value 1 -Type DWord -Force
        
        Write-Status -Message "'Завершить задачу' включено" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка: $_" -Type Error
        return $false
    }
}

function Hide-TaskView {
    Write-Status -Message "Скрытие кнопки Task View..." -Type Info
    
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0 -Type DWord -Force
        
        Write-Status -Message "Task View скрыт" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка: $_" -Type Error
        return $false
    }
}

function Disable-StartRecommended {
    Write-Status -Message "Отключение рекомендованного в меню Пуск..." -Type Info
    
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_Layout" -Value 1 -Type DWord -Force
        
        Write-Status -Message "Рекомендованное в Пуске отключено" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка: $_" -Type Error
        return $false
    }
}

function ShowFileExtensions {
    Write-Status -Message "Показ расширений файлов..." -Type Info
    
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0 -Type DWord -Force
        
        Write-Status -Message "Расширения файлов показаны" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка: $_" -Type Error
        return $false
    }
}

function ShowHiddenFiles {
    Write-Status -Message "Показ скрытых файлов..." -Type Info
    
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1 -Type DWord -Force
        
        Write-Status -Message "Скрытые файлы показаны" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка: $_" -Type Error
        return $false
    }
}

function Disable-OneDrive {
    Write-Status -Message "Отключение OneDrive..." -Type Info
    
    try {
        # Отключение автозапуска
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDriveSetup" -Value "" -Type String -Force
        
        # Отключение OneDrive
        $regPath = "HKLM:\Software\Policies\Microsoft\Windows\OneDrive"
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force
        
        Write-Status -Message "OneDrive отключен" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка: $_" -Type Error
        return $false
    }
}

function Remove-BloatApps {
    Write-Status -Message "Удаление встроенных приложений..." -Type Info
    
    try {
        $apps = @(
            "Microsoft.3DBuilder",
            "Microsoft.BingNews",
            "Microsoft.BingWeather",
            "Microsoft.GetHelp",
            "Microsoft.Getstarted",
            "Microsoft.Microsoft3DViewer",
            "Microsoft.MicrosoftOfficeHub",
            "Microsoft.MicrosoftSolitaireCollection",
            "Microsoft.MicrosoftStickyNotes",
            "Microsoft.MixedReality.Portal",
            "Microsoft.NetworkSpeedTest",
            "Microsoft.News",
            "Microsoft.Office.OneNote",
            "Microsoft.Office.Sway",
            "Microsoft.OneConnect",
            "Microsoft.People",
            "Microsoft.Print3D",
            "Microsoft.SkypeApp",
            "Microsoft.Todos",
            "Microsoft.WindowsAlarms",
            "Microsoft.WindowsFeedbackHub",
            "Microsoft.WindowsMaps",
            "Microsoft.WindowsSoundRecorder",
            "Microsoft.XboxApp",
            "Microsoft.XboxGameOverlay",
            "Microsoft.XboxGamingOverlay",
            "Microsoft.XboxIdentityProvider",
            "Microsoft.XboxSpeechToTextOverlay",
            "Microsoft.Xbox.TCUI",
            "Microsoft.YourPhone",
            "Microsoft.ZuneMusic",
            "Microsoft.ZuneVideo",
            "Microsoft.GamingApp",
            "Microsoft.Copilot",
            "Microsoft.Windows.AIHub"
        )
        
        $removed = 0
        
        foreach ($app in $apps) {
            $package = Get-AppxPackage -Name $app -ErrorAction SilentlyContinue
            if ($package) {
                Remove-AppxPackage -Package $package.PackageFullName -ErrorAction SilentlyContinue
                Write-Status -Message "Удалено: $app" -Type Success
                $removed++
            }
        }
        
        Write-Status -Message "Всего удалено: $removed" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка удаления приложений: $_" -Type Error
        return $false
    }
}

function Disable-XboxGameBar {
    Write-Status -Message "Отключение Xbox Game Bar..." -Type Info
    
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\GameBar" -Name "GamePanelStartupTipEnabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\GameBar" -Name "ShowStartupPanel" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force
        
        Write-Status -Message "Xbox Game Bar отключен" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка: $_" -Type Error
        return $false
    }
}

function Restore-ClassicContextMenu {
    Write-Status -Message "Восстановление классического контекстного меню..." -Type Info
    
    try {
        $regPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a7}\InprocServer32"
        New-Item -Path $regPath -Force | Out-Null
        Set-ItemProperty -Path $regPath -Name "" -Value "" -Type String -Force
        
        Write-Status -Message "Классическое меню включено" -Type Success
        Write-Status -Message "Требуется перезапуск проводника или перезагрузка" -Type Warning
        return $true
    }
    catch {
        Write-Status -Message "Ошибка: $_" -Type Error
        return $false
    }
}

# ==============================================================================
# МЕНЮ МОДУЛЯ
# ==============================================================================

function Show-DebloatMenu {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $COLOR_ACCENT
    Write-Host "║  ДЕБЛОТЕР WINDOWS                                                     ║" -ForegroundColor $COLOR_ACCENT
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $COLOR_ACCENT
    Write-Host ""
    
    Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host "  ТЕЛЕМЕТРИЯ И КОНФИДЕНЦИАЛЬНОСТЬ" -ForegroundColor $COLOR_ACCENT
    Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  1. " -ForegroundColor Green -NoNewline; Write-Host "Отключить телеметрию" -ForegroundColor White
    Write-Host "  2. " -ForegroundColor Green -NoNewline; Write-Host "Отключить историю поиска" -ForegroundColor White
    Write-Host "  3. " -ForegroundColor Green -NoNewline; Write-Host "Отключить Bing в поиске" -ForegroundColor White
    Write-Host ""
    
    Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host "  СИСТЕМА" -ForegroundColor $COLOR_ACCENT
    Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  4. " -ForegroundColor Green -NoNewline; Write-Host "Отключить быстрый запуск" -ForegroundColor White
    Write-Host "  5. " -ForegroundColor Green -NoNewline; Write-Host "Отключить авто-шифрование BitLocker" -ForegroundColor White
    Write-Host "  6. " -ForegroundColor Green -NoNewline; Write-Host "Отключить Storage Sense" -ForegroundColor White
    Write-Host "  7. " -ForegroundColor Green -NoNewline; Write-Host "Настройка Windows Update" -ForegroundColor White
    Write-Host "  8. " -ForegroundColor Green -NoNewline; Write-Host "Отключить OneDrive" -ForegroundColor White
    Write-Host "  9. " -ForegroundColor Green -NoNewline; Write-Host "Удалить встроенные приложения" -ForegroundColor White
    Write-Host "  A. " -ForegroundColor Green -NoNewline; Write-Host "Отключить Xbox Game Bar" -ForegroundColor White
    Write-Host ""
    
    Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host "  ИНТЕРФЕЙС" -ForegroundColor $COLOR_ACCENT
    Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  B. " -ForegroundColor Green -NoNewline; Write-Host "Включить темную тему" -ForegroundColor White
    Write-Host "  C. " -ForegroundColor Green -NoNewline; Write-Host "Отключить прозрачность" -ForegroundColor White
    Write-Host "  D. " -ForegroundColor Green -NoNewline; Write-Host "Выровнять панель задач влево" -ForegroundColor White
    Write-Host "  E. " -ForegroundColor Green -NoNewline; Write-Host "Отключить виджеты" -ForegroundColor White
    Write-Host "  F. " -ForegroundColor Green -NoNewline; Write-Host "Отключить чат" -ForegroundColor White
    Write-Host "  G. " -ForegroundColor Green -NoNewline; Write-Host "Включить 'Завершить задачу'" -ForegroundColor White
    Write-Host "  H. " -ForegroundColor Green -NoNewline; Write-Host "Скрыть Task View" -ForegroundColor White
    Write-Host "  I. " -ForegroundColor Green -NoNewline; Write-Host "Отключить рекомендованное в Пуске" -ForegroundColor White
    Write-Host ""
    
    Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host "  ПРОВОДНИК" -ForegroundColor $COLOR_ACCENT
    Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  J. " -ForegroundColor Green -NoNewline; Write-Host "Показывать расширения файлов" -ForegroundColor White
    Write-Host "  K. " -ForegroundColor Green -NoNewline; Write-Host "Показывать скрытые файлы" -ForegroundColor White
    Write-Host "  L. " -ForegroundColor Green -NoNewline; Write-Host "Восстановить классическое контекстное меню" -ForegroundColor White
    Write-Host ""
    
    Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host "  БЫСТРЫЕ НАСТРОЙКИ" -ForegroundColor $COLOR_ACCENT
    Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  M. " -ForegroundColor DarkMagenta -NoNewline; Write-Host "Применить ВСЕ оптимизации" -ForegroundColor White
    Write-Host ""
    Write-Host "  0. " -ForegroundColor Red -NoNewline; Write-Host "Назад" -ForegroundColor White
    Write-Host ""
}

function Invoke-Debloat {
    Write-Host ""
    Write-Status -Message "Модуль деблотинга Windows" -Type Info
    Write-Host ""
    
    $createRestore = Read-Host "  Создать точку восстановления? (y/n)"
    
    if ($createRestore -eq "y" -or $createRestore -eq "Y") {
        Create-RestorePoint
    }
    
    $exit = $false
    
    while (-not $exit) {
        Show-DebloatMenu
        
        $choice = Read-Host "  Выберите опцию"
        
        switch ($choice) {
            "1" {
                Clear-Host
                Write-Host ""
                Disable-Telemetry
                Wait-Key
            }
            "2" {
                Clear-Host
                Write-Host ""
                Disable-SearchHistory
                Wait-Key
            }
            "3" {
                Clear-Host
                Write-Host ""
                Disable-BingSearch
                Wait-Key
            }
            "4" {
                Clear-Host
                Write-Host ""
                Disable-FastStartup
                Wait-Key
            }
            "5" {
                Clear-Host
                Write-Host ""
                Disable-BitlockerAutoEncryption
                Wait-Key
            }
            "6" {
                Clear-Host
                Write-Host ""
                Disable-StorageSense
                Wait-Key
            }
            "7" {
                Clear-Host
                Write-Host ""
                Disable-WindowsUpdate
                Wait-Key
            }
            "8" {
                Clear-Host
                Write-Host ""
                Disable-OneDrive
                Wait-Key
            }
            "9" {
                Clear-Host
                Write-Host ""
                Remove-BloatApps
                Wait-Key
            }
            "A" {
                Clear-Host
                Write-Host ""
                Disable-XboxGameBar
                Wait-Key
            }
            "B" {
                Clear-Host
                Write-Host ""
                Enable-DarkMode
                Wait-Key
            }
            "C" {
                Clear-Host
                Write-Host ""
                Disable-Transparency
                Wait-Key
            }
            "D" {
                Clear-Host
                Write-Host ""
                TaskbarAlignLeft
                Wait-Key
            }
            "E" {
                Clear-Host
                Write-Host ""
                Disable-Widgets
                Wait-Key
            }
            "F" {
                Clear-Host
                Write-Host ""
                Disable-Chat
                Wait-Key
            }
            "G" {
                Clear-Host
                Write-Host ""
                Enable-EndTask
                Wait-Key
            }
            "H" {
                Clear-Host
                Write-Host ""
                Hide-TaskView
                Wait-Key
            }
            "I" {
                Clear-Host
                Write-Host ""
                Disable-StartRecommended
                Wait-Key
            }
            "J" {
                Clear-Host
                Write-Host ""
                ShowFileExtensions
                Wait-Key
            }
            "K" {
                Clear-Host
                Write-Host ""
                ShowHiddenFiles
                Wait-Key
            }
            "L" {
                Clear-Host
                Write-Host ""
                Restore-ClassicContextMenu
                Wait-Key
            }
            "M" {
                Clear-Host
                Write-Host ""
                Write-Status -Message "Применение всех оптимизаций..." -Type Warning
                Write-Host ""
                
                $confirm = Read-Host "  Вы уверены? (y/n)"
                
                if ($confirm -eq "y" -or $confirm -eq "Y") {
                    Disable-Telemetry
                    Disable-SearchHistory
                    Disable-BingSearch
                    Disable-FastStartup
                    Disable-BitlockerAutoEncryption
                    Disable-StorageSense
                    Disable-WindowsUpdate
                    Disable-OneDrive
                    Remove-BloatApps
                    Disable-XboxGameBar
                    Enable-DarkMode
                    Disable-Transparency
                    TaskbarAlignLeft
                    Disable-Widgets
                    Disable-Chat
                    Enable-EndTask
                    Hide-TaskView
                    Disable-StartRecommended
                    ShowFileExtensions
                    ShowHiddenFiles
                    Restore-ClassicContextMenu
                    
                    Write-Host ""
                    Write-Status -Message "Все оптимизации применены!" -Type Success
                    Write-Status -Message "Требуется перезагрузка" -Type Warning
                    Write-Host ""
                    
                    $restart = Read-Host "  Перезагрузить сейчас? (y/n)"
                    if ($restart -eq "y" -or $restart -eq "Y") {
                        Restart-Computer
                    }
                }
                
                Wait-Key
            }
            "0" {
                $exit = $true
            }
            default {
                Write-Status -Message "Неверный ввод" -Type Warning
                Start-Sleep -Seconds 1
            }
        }
        
        if (-not $exit) {
            Clear-Host
        }
    }
}

# Экспортируем точку входа
Export-ModuleMember -Function Invoke-Debloat
