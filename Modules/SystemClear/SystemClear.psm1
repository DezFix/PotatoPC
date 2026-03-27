<#
.SYNOPSIS
    Модуль очистки и оптимизации системы
.DESCRIPTION
    Очистка временных файлов, отключение телеметрии, оптимизация служб и производительности
#>

$MODULE_CONFIG = @{
    Name = "Очистка системы"
    Version = "1.0.0"
}

# Цвета
$COLOR_ACCENT = "Yellow"
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
        'Info' { '[+]' }
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
        # Проверяем VSS
        $vssService = Get-Service -Name 'VSS' -ErrorAction SilentlyContinue
        if ($vssService -and $vssService.StartType -eq 'Disabled') {
            Set-Service -Name 'VSS' -StartupType Manual -ErrorAction SilentlyContinue
            Start-Service -Name 'VSS' -ErrorAction SilentlyContinue
        }
        
        # Включаем восстановление системы
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        
        # Создаем точку
        Checkpoint-Computer -Description "PotatoPS Clear - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType "MODIFY_SETTINGS"
        
        Write-Status -Message "Точка восстановления создана" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Не удалось создать точку восстановления: $_" -Type Warning
        return $false
    }
}

# ==============================================================================
# ФУНКЦИИ ОЧИСТКИ
# ==============================================================================

function Clear-TempFiles {
    Write-Status -Message "Очистка временных файлов..." -Type Info
    
    try {
        # Пользовательские временные файлы
        $tempPath = $env:TEMP
        if (Test-Path $tempPath) {
            $count = (Get-ChildItem $tempPath -Recurse -File -ErrorAction SilentlyContinue).Count
            Remove-Item "$tempPath\*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Status -Message "Удалено файлов из TEMP: $count" -Type Success
        }
        
        # Системные временные файлы
        $systemTemp = "C:\Windows\Temp"
        if (Test-Path $systemTemp) {
            $count = (Get-ChildItem $systemTemp -Recurse -File -ErrorAction SilentlyContinue).Count
            Remove-Item "$systemTemp\*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Status -Message "Удалено файлов из Windows\Temp: $count" -Type Success
        }
        
        # Корзина
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-Status -Message "Корзина очищена" -Type Success
        
        # Prefetch
        $prefetch = "C:\Windows\Prefetch"
        if (Test-Path $prefetch) {
            $count = (Get-ChildItem $prefetch -File -ErrorAction SilentlyContinue).Count
            Remove-Item "$prefetch\*" -Force -ErrorAction SilentlyContinue
            Write-Status -Message "Удалено файлов из Prefetch: $count" -Type Success
        }
        
        # DNS кэш
        ipconfig /flushdns | Out-Null
        Write-Status -Message "DNS кэш очищен" -Type Success
        
        return $true
    }
    catch {
        Write-Status -Message "Ошибка очистки: $_" -Type Error
        return $false
    }
}

function Disable-Telemetry {
    Write-Status -Message "Отключение телеметрии..." -Type Info
    
    try {
        # Службы телеметрии
        $services = @(
            "DiagTrack", "dmwappushservice", "DPS", "WdiServiceHost",
            "WdiSystemHost", "Wecsvc", "WerSvc", "WMPNetworkSvc",
            "XboxGameMonitoring", "XboxSpeechToTextService",
            "XboxGipSvc", "XblGameSave", "XboxNetApiSvc"
        )
        
        foreach ($svc in $services) {
            if (Get-Service $svc -ErrorAction SilentlyContinue) {
                Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
                Write-Status -Message "Служба $svc отключена" -Type Success
            }
        }
        
        # Задачи планировщика
        $tasks = @(
            "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
            "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
            "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
            "\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask",
            "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
            "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
            "\Microsoft\Windows\Feedback\Siuf\DmClient",
            "\Microsoft\Windows\Feedback\Siuf\SiufTask",
            "\Microsoft\Windows\Windows Error Reporting\QueueReporting"
        )
        
        foreach ($task in $tasks) {
            schtasks /Change /TN $task /Disable 2>$null
        }
        Write-Status -Message "Задачи планировщика отключены" -Type Success
        
        # Реестр
        $regPaths = @(
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
        )
        
        foreach ($path in $regPaths) {
            if (-not (Test-Path $path)) {
                New-Item -Path $path -Force | Out-Null
            }
            Set-ItemProperty -Path $path -Name "AllowTelemetry" -Value 0 -Type DWord -Force
        }
        Write-Status -Message "Телеметрия отключена в реестре" -Type Success
        
        # Cortana
        if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search")) {
            New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0 -Type DWord -Force
        Write-Status -Message "Cortana отключена" -Type Success
        
        # Windows Error Reporting
        if (-not (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting")) {
            New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Value 1 -Type DWord -Force
        Write-Status -Message "Windows Error Reporting отключен" -Type Success
        
        return $true
    }
    catch {
        Write-Status -Message "Ошибка отключения телеметрии: $_" -Type Error
        return $false
    }
}

function Disable-UnusedServices {
    Write-Status -Message "Настройка служб..." -Type Info
    
    try {
        $disableList = @(
            "XblGameSave", "XboxNetApiSvc", "Fax", "MapsBroker",
            "RetailDemo", "SysMain", "WMPNetworkSvc", "XboxGipSvc",
            "OneSyncSvc", "UnistoreSvc", "MessagingService",
            "PrintNotify", "TabletInputService", "BthAvctpSvc"
        )
        
        foreach ($svc in $disableList) {
            if (Get-Service $svc -ErrorAction SilentlyContinue) {
                Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
                Write-Status -Message "Служба $svc отключена" -Type Success
            }
        }
        
        # В ручной запуск
        $manualList = @("WSearch", "PcaSvc", "DiagSvcs", "TrkWks")
        
        foreach ($svc in $manualList) {
            if (Get-Service $svc -ErrorAction SilentlyContinue) {
                Set-Service -Name $svc -StartupType Manual -ErrorAction SilentlyContinue
                Write-Status -Message "Служба $svc переведена в Manual" -Type Info
            }
        }
        
        return $true
    }
    catch {
        Write-Status -Message "Ошибка настройки служб: $_" -Type Error
        return $false
    }
}

function Optimize-Performance {
    Write-Status -Message "Оптимизация производительности..." -Type Info
    
    try {
        # Схема электропитания
        powercfg -setactive SCHEME_MIN 2>$null
        powercfg /change standby-timeout-ac 0 2>$null
        powercfg /change hibernate-timeout-ac 0 2>$null
        Write-Status -Message "Схема электропитания настроена" -Type Success
        
        # Реестр
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "0" -Type String -Force -ErrorAction SilentlyContinue
        Write-Status -Message "Задержка меню уменьшена" -Type Success
        
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 3 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Status -Message "Визуальные эффекты настроены" -Type Success
        
        # Edge фон
        if (-not (Test-Path "HKCU:\Software\Policies\Microsoft\Edge")) {
            New-Item -Path "HKCU:\Software\Policies\Microsoft\Edge" -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Edge" -Name "BackgroundModeEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Edge" -Name "StartupBoostEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Status -Message "Microsoft Edge оптимизирован" -Type Success
        
        # Новости и интересы
        if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds")) {
            New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Name "ShellFeedsTaskbarViewMode" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Status -Message "Новости и интересы отключены" -Type Success
        
        # Люди на панели задач
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" -Name "PeopleBand" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Status -Message "Кнопка 'Люди' отключена" -Type Success
        
        return $true
    }
    catch {
        Write-Status -Message "Ошибка оптимизации: $_" -Type Error
        return $false
    }
}

function Remove-Bloatware {
    Write-Status -Message "Удаление встроенного ПО..." -Type Info
    
    try {
        $apps = @(
            "Microsoft.3DBuilder",
            "Microsoft.XboxApp",
            "Microsoft.GetHelp",
            "Microsoft.ZuneMusic",
            "Microsoft.ZuneVideo",
            "Microsoft.windowscommunicationsapps",
            "Microsoft.WindowsCamera",
            "Microsoft.549981C3F5F10",
            "Microsoft.BingWeather",
            "Microsoft.Getstarted",
            "Microsoft.Microsoft3DViewer",
            "Microsoft.MicrosoftOfficeHub",
            "Microsoft.MicrosoftSolitaireCollection",
            "Microsoft.MicrosoftStickyNotes",
            "Microsoft.MixedReality.Portal",
            "Microsoft.MSPaint",
            "Microsoft.Office.OneNote",
            "Microsoft.OutlookForWindows",
            "Microsoft.People",
            "Microsoft.ScreenSketch",
            "Microsoft.SkypeApp",
            "Microsoft.Wallet",
            "Microsoft.WindowsAlarms",
            "Microsoft.WindowsFeedbackHub",
            "Microsoft.WindowsMaps",
            "Microsoft.WindowsSoundRecorder",
            "Microsoft.XboxGameOverlay",
            "Microsoft.XboxGamingOverlay",
            "Microsoft.XboxIdentityProvider",
            "Microsoft.YourPhone",
            "Microsoft.GamingApp",
            "Microsoft.Copilot",
            "Microsoft.BingNews"
        )
        
        foreach ($app in $apps) {
            $package = Get-AppxPackage -Name $app -ErrorAction SilentlyContinue
            if ($package) {
                Remove-AppxPackage -Package $package.PackageFullName -ErrorAction SilentlyContinue
                Write-Status -Message "Удалено: $app" -Type Success
            }
            
            $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $app }
            if ($provisioned) {
                Remove-AppxProvisionedPackage -Online -PackageName $provisioned.PackageName -ErrorAction SilentlyContinue
            }
        }
        
        # Отключение Copilot
        if (-not (Test-Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot")) {
            New-Item -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force
        
        if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot")) {
            New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force
        
        Write-Status -Message "Copilot отключен" -Type Success
        
        # Настройки панели задач
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Status -Message "Панель задач настроена" -Type Success
        
        return $true
    }
    catch {
        Write-Status -Message "Ошибка удаления bloatware: $_" -Type Error
        return $false
    }
}

# ==============================================================================
# МЕНЮ МОДУЛЯ
# ==============================================================================

function Show-ClearMenu {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $COLOR_ACCENT
    Write-Host "║  ОЧИСТКА СИСТЕМЫ                                                      ║" -ForegroundColor $COLOR_ACCENT
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $COLOR_ACCENT
    Write-Host ""
    
    Write-Host "  1. " -ForegroundColor Green -NoNewline
    Write-Host "Очистка временных файлов" -ForegroundColor White
    
    Write-Host "  2. " -ForegroundColor Green -NoNewline
    Write-Host "Отключение телеметрии" -ForegroundColor White
    
    Write-Host "  3. " -ForegroundColor Green -NoNewline
    Write-Host "Настройка служб" -ForegroundColor White
    
    Write-Host "  4. " -ForegroundColor Green -NoNewline
    Write-Host "Оптимизация производительности" -ForegroundColor White
    
    Write-Host "  5. " -ForegroundColor Green -NoNewline
    Write-Host "Удаление встроенного ПО" -ForegroundColor White
    
    Write-Host ""
    Write-Host "  6. " -ForegroundColor DarkMagenta -NoNewline
    Write-Host "Применить ВСЕ оптимизации" -ForegroundColor White
    
    Write-Host ""
    Write-Host "  0. " -ForegroundColor Red -NoNewline
    Write-Host "Назад" -ForegroundColor White
    
    Write-Host ""
}

function Invoke-SystemClear {
    $createRestore = Read-Host "  Создать точку восстановления? (y/n)"
    
    if ($createRestore -eq "y" -or $createRestore -eq "Y") {
        Create-RestorePoint
    }
    
    $exit = $false
    
    while (-not $exit) {
        Show-ClearMenu
        
        $choice = Read-Host "  Выберите опцию"
        
        switch ($choice) {
            "1" {
                Clear-Host
                Write-Host ""
                Write-Status -Message "Запуск очистки временных файлов..." -Type Info
                Clear-TempFiles
                Write-Status -Message "Очистка завершена" -Type Success
                Wait-Key
            }
            "2" {
                Clear-Host
                Write-Host ""
                Write-Status -Message "Отключение телеметрии..." -Type Info
                Disable-Telemetry
                Write-Status -Message "Телеметрия отключена" -Type Success
                Wait-Key
            }
            "3" {
                Clear-Host
                Write-Host ""
                Write-Status -Message "Настройка служб..." -Type Info
                Disable-UnusedServices
                Write-Status -Message "Службы настроены" -Type Success
                Wait-Key
            }
            "4" {
                Clear-Host
                Write-Host ""
                Write-Status -Message "Оптимизация производительности..." -Type Info
                Optimize-Performance
                Write-Status -Message "Оптимизация завершена" -Type Success
                Wait-Key
            }
            "5" {
                Clear-Host
                Write-Host ""
                Write-Status -Message "Удаление встроенного ПО..." -Type Info
                Remove-Bloatware
                Write-Status -Message "Bloatware удален" -Type Success
                Wait-Key
            }
            "6" {
                Clear-Host
                Write-Host ""
                Write-Status -Message "Применение всех оптимизаций..." -Type Info
                Write-Host ""
                
                Disable-Telemetry
                Disable-UnusedServices
                Optimize-Performance
                Remove-Bloatware
                Clear-TempFiles
                
                Write-Host ""
                Write-Status -Message "Все оптимизации применены!" -Type Success
                Write-Status -Message "Рекомендуется перезагрузка" -Type Warning
                Write-Host ""
                
                $restart = Read-Host "  Перезагрузить сейчас? (y/n)"
                if ($restart -eq "y" -or $restart -eq "Y") {
                    Restart-Computer
                }
                
                Wait-Key
            }
            "0" {
                $exit = $true
            }
            default {
                Write-Status -Message "Неверный ввод!" -Type Warning
                Start-Sleep -Seconds 1
            }
        }
        
        if (-not $exit) {
            Clear-Host
        }
    }
}

# Экспортируем точку входа
Export-ModuleMember -Function Invoke-SystemClear
