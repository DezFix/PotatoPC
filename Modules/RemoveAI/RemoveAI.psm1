<#
.SYNOPSIS
    Модуль удаления AI-компонентов Windows
.DESCRIPTION
    Удаление и отключение Copilot, Recall, AI-пакетов и связанных компонентов
    На основе проекта RemoveWindowsAI
#>

$MODULE_CONFIG = @{
    Name = "Удаление AI"
    Version = "1.0.0"
}

# Цвета
$COLOR_ACCENT = "DarkMagenta"
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

function Test-TrustedInstallerAccess {
    # Проверяем доступ к TrustedInstaller
    try {
        $testKey = "HKLM:\SOFTWARE\RemoveWindowsAI_Test"
        New-Item -Path $testKey -Force -ErrorAction Stop | Out-Null
        Remove-Item -Path $testKey -Force -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

# ==============================================================================
# ФУНКЦИИ УДАЛЕНИЯ AI
# ==============================================================================

function Disable-CopilotRegistry {
    Write-Status -Message "Отключение Copilot через реестр..." -Type Info
    
    try {
        # HKCU - текущий пользователь
        $paths = @(
            "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot",
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
        )
        
        foreach ($path in $paths) {
            if (-not (Test-Path $path)) {
                New-Item -Path $path -Force | Out-Null
            }
            Set-ItemProperty -Path $path -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force
        }
        
        # Отключение кнопки Copilot на панели задач
        if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
            New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 0 -Type DWord -Force
        
        # Отключение Copilot в Edge
        if (-not (Test-Path "HKCU:\Software\Policies\Microsoft\Edge\HubsEnabled")) {
            New-Item -Path "HKCU:\Software\Policies\Microsoft\Edge" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Edge" -Name "HubsEnabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Edge" -Name "CopilotEnabled" -Value 0 -Type DWord -Force
        
        Write-Status -Message "Copilot отключен в реестре" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка отключения Copilot: $_" -Type Error
        return $false
    }
}

function Disable-Recall {
    Write-Status -Message "Отключение Windows Recall..." -Type Info
    
    try {
        # Отключение Recall через реестр
        $recallPaths = @(
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Recall",
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
        )
        
        foreach ($path in $recallPaths) {
            if (-not (Test-Path $path)) {
                New-Item -Path $path -Force | Out-Null
            }
        }
        
        # Отключение скриншотов Recall
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Recall" -Name "RecallEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        
        # Отключение задач планировщика Recall
        $recallTasks = @(
            "\Microsoft\Windows\WindowsAI\Recall",
            "\Microsoft\Windows\WindowsAI\SnapshotAgent"
        )
        
        foreach ($task in $recallTasks) {
            schtasks /Change /TN $task /Disable 2>$null
        }
        
        Write-Status -Message "Recall отключен" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка отключения Recall: $_" -Type Error
        return $false
    }
}

function Remove-AIAppxPackages {
    Write-Status -Message "Удаление AI AppX пакетов..." -Type Info
    
    try {
        $aiPackages = @(
            "Microsoft.Copilot",
            "Microsoft.Windows.AIHub",
            "Microsoft.Windows.Ai.Copilot.Provider",
            "MicrosoftWindows.Client.AIX",
            "MicrosoftWindows.Client.CoPilot",
            "MicrosoftWindows.Client.CoreAI",
            "Microsoft.Edge.GameAssist",
            "Microsoft.Office.ActionsServer",
            "Microsoft.WritingAssistant",
            "Microsoft.MicrosoftOfficeHub"
        )
        
        $removed = 0
        $notFound = 0
        
        foreach ($package in $aiPackages) {
            # Поиск установленных пакетов
            $installed = Get-AppxPackage -AllUsers -Name "*$package*" -ErrorAction SilentlyContinue
            
            foreach ($pkg in $installed) {
                try {
                    Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue
                    Write-Status -Message "Удалено: $($pkg.Name)" -Type Success
                    $removed++
                }
                catch {
                    Write-Status -Message "Не удалось удалить $($pkg.Name)" -Type Warning
                }
            }
            
            # Поиск provisioned пакетов
            $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$package*" }
            
            foreach ($pkg in $provisioned) {
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -ErrorAction SilentlyContinue
                    Write-Status -Message "Удален provisioned: $($pkg.DisplayName)" -Type Success
                    $removed++
                }
                catch {
                    Write-Status -Message "Не удалось удалить provisioned $($pkg.DisplayName)" -Type Warning
                }
            }
            
            if (-not $installed -and -not $provisioned) {
                $notFound++
            }
        }
        
        Write-Status -Message "Удалено пакетов: $removed" -Type Success
        Write-Status -Message "Не найдено пакетов: $notFound" -Type Info
        
        return $true
    }
    catch {
        Write-Status -Message "Ошибка удаления пакетов: $_" -Type Error
        return $false
    }
}

function Disable-AIServices {
    Write-Status -Message "Отключение AI-служб..." -Type Info
    
    try {
        $aiServices = @(
            "WSAIFabricSvc",
            "WisSvc",
            "AppVSvc"
        )
        
        foreach ($service in $aiServices) {
            $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
            
            if ($svc) {
                Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
                Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
                Write-Status -Message "Служба $service отключена" -Type Success
            }
        }
        
        Write-Status -Message "AI-службы обработаны" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка отключения служб: $_" -Type Error
        return $false
    }
}

function Disable-PaintAI {
    Write-Status -Message "Отключение AI в Paint..." -Type Info
    
    try {
        # Отключение AI функций в Paint через реестр
        if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Paint")) {
            New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Paint" -Force | Out-Null
        }
        
        # Отключение генеративного заполнения
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Paint" -Name "GenerativeFillEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        
        Write-Status -Message "AI в Paint отключен" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка отключения AI в Paint: $_" -Type Error
        return $false
    }
}

function Disable-NotepadAI {
    Write-Status -Message "Отключение AI в Notepad..." -Type Info
    
    try {
        # Отключение AI функций в Notepad
        if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notepad")) {
            New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notepad" -Force | Out-Null
        }
        
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notepad" -Name "AIFeaturesEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        
        Write-Status -Message "AI в Notepad отключен" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка отключения AI в Notepad: $_" -Type Error
        return $false
    }
}

function Disable-ClickToDo {
    Write-Status -Message "Отключение Click to Do..." -Type Info
    
    try {
        # Отключение Click to Do через реестр
        if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
            New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
        }
        
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableClickToDo" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        
        Write-Status -Message "Click to Do отключен" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка отключения Click to Do: $_" -Type Error
        return $false
    }
}

function Remove-AIFiles {
    Write-Status -Message "Очистка AI-файлов..." -Type Info
    
    try {
        $aiPaths = @(
            "$env:ProgramFiles\WindowsApps\Microsoft.Copilot*",
            "$env:ProgramFiles\WindowsApps\Microsoft.Windows.AIHub*",
            "$env:LocalAppData\Packages\Microsoft.Copilot*",
            "$env:LocalAppData\Packages\Microsoft.Windows.AIHub*"
        )
        
        foreach ($path in $aiPaths) {
            if (Test-Path $path) {
                try {
                    # Попытка удаления (может потребовать TrustedInstaller)
                    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Status -Message "Удалено: $path" -Type Success
                }
                catch {
                    Write-Status -Message "Не удалось удалить (требуется TrustedInstaller): $path" -Type Warning
                }
            }
        }
        
        Write-Status -Message "Очистка файлов завершена" -Type Success
        return $true
    }
    catch {
        Write-Status -Message "Ошибка очистки файлов: $_" -Type Error
        return $false
    }
}

function Install-ClassicApps {
    Write-Status -Message "Установка классических приложений..." -Type Info
    
    try {
        Write-Host ""
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
        Write-Host "  КЛАССИЧЕСКИЕ ПРИЛОЖЕНИЯ" -ForegroundColor $COLOR_ACCENT
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
        Write-Host ""
        
        $apps = @(
            @{Name = "Классический Notepad"; Id = "Microsoft.WindowsNotepad"},
            @{Name = "Классический Paint"; Id = "Microsoft.Paint"},
            @{Name = "Классический Snipping Tool"; Id = "Microsoft.ScreenSketch"},
            @{Name = "Windows Photo Viewer"; Id = "Microsoft.Windows.Photos"}
        )
        
        $index = 1
        foreach ($app in $apps) {
            Write-Host "  $index. $($app.Name)" -ForegroundColor White
            $index++
        }
        
        Write-Host ""
        Write-Host "  0. Назад" -ForegroundColor Red
        Write-Host ""
        
        $choice = Read-Host "  Выберите приложение для установки"
        
        if ($choice -ne "0") {
            $choiceNum = [int]::Parse($choice)
            if ($choiceNum -gt 0 -and $choiceNum -lt $index) {
                $selectedApp = $apps[$choiceNum - 1]
                
                Write-Status -Message "Установка $($selectedApp.Name)..." -Type Info
                
                try {
                    winget install --id $selectedApp.Id --silent --accept-package-agreements 2>$null
                    Write-Status -Message "$($selectedApp.Name) установлено" -Type Success
                }
                catch {
                    Write-Status -Message "Ошибка установки: $_" -Type Error
                }
            }
        }
        
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

function Show-RemoveAIMenu {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $COLOR_ACCENT
    Write-Host "║  УДАЛЕНИЕ AI-КОМПОНЕНТОВ                                              ║" -ForegroundColor $COLOR_ACCENT
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $COLOR_ACCENT
    Write-Host ""
    
    Write-Host "  1. " -ForegroundColor Green -NoNewline
    Write-Host "Отключить Copilot (реестр)" -ForegroundColor White
    
    Write-Host "  2. " -ForegroundColor Green -NoNewline
    Write-Host "Отключить Windows Recall" -ForegroundColor White
    
    Write-Host "  3. " -ForegroundColor Green -NoNewline
    Write-Host "Удалить AI AppX пакеты" -ForegroundColor White
    
    Write-Host "  4. " -ForegroundColor Green -NoNewline
    Write-Host "Отключить AI-службы" -ForegroundColor White
    
    Write-Host "  5. " -ForegroundColor Green -NoNewline
    Write-Host "Отключить AI в Paint" -ForegroundColor White
    
    Write-Host "  6. " -ForegroundColor Green -NoNewline
    Write-Host "Отключить AI в Notepad" -ForegroundColor White
    
    Write-Host "  7. " -ForegroundColor Green -NoNewline
    Write-Host "Отключить Click to Do" -ForegroundColor White
    
    Write-Host "  8. " -ForegroundColor Green -NoNewline
    Write-Host "Очистить AI-файлы" -ForegroundColor White
    
    Write-Host "  9. " -ForegroundColor Green -NoNewline
    Write-Host "Установить классические приложения" -ForegroundColor White
    
    Write-Host ""
    Write-Host "  A. " -ForegroundColor DarkMagenta -NoNewline
    Write-Host "Удалить ВСЁ AI (полная очистка)" -ForegroundColor White
    
    Write-Host ""
    Write-Host "  0. " -ForegroundColor Red -NoNewline
    Write-Host "Назад" -ForegroundColor White
    
    Write-Host ""
}

function Invoke-RemoveAI {
    Write-Host ""
    Write-Status -Message "Модуль удаления AI-компонентов Windows" -Type Info
    Write-Status -Message "Требуется PowerShell 5.1 и права администратора" -Type Warning
    Write-Host ""
    
    # Проверка версии PowerShell
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-Status -Message "ВНИМАНИЕ: Рекомендуется PowerShell 5.1!" -Type Warning
        $continue = Read-Host "  Продолжить? (y/n)"
        if ($continue -ne "y") {
            return
        }
    }
    
    $createRestore = Read-Host "  Создать точку восстановления? (y/n)"
    
    if ($createRestore -eq "y" -or $createRestore -eq "Y") {
        try {
            Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
            Checkpoint-Computer -Description "PotatoPS RemoveAI - $(Get-Date -Format 'yyyy-MM-dd')" -RestorePointType "MODIFY_SETTINGS"
            Write-Status -Message "Точка восстановления создана" -Type Success
        }
        catch {
            Write-Status -Message "Не удалось создать точку восстановления" -Type Warning
        }
    }
    
    $exit = $false
    
    while (-not $exit) {
        Show-RemoveAIMenu
        
        $choice = Read-Host "  Выберите опцию"
        
        switch ($choice) {
            "1" {
                Clear-Host
                Write-Host ""
                Disable-CopilotRegistry
                Wait-Key
            }
            "2" {
                Clear-Host
                Write-Host ""
                Disable-Recall
                Wait-Key
            }
            "3" {
                Clear-Host
                Write-Host ""
                Remove-AIAppxPackages
                Wait-Key
            }
            "4" {
                Clear-Host
                Write-Host ""
                Disable-AIServices
                Wait-Key
            }
            "5" {
                Clear-Host
                Write-Host ""
                Disable-PaintAI
                Wait-Key
            }
            "6" {
                Clear-Host
                Write-Host ""
                Disable-NotepadAI
                Wait-Key
            }
            "7" {
                Clear-Host
                Write-Host ""
                Disable-ClickToDo
                Wait-Key
            }
            "8" {
                Clear-Host
                Write-Host ""
                Remove-AIFiles
                Wait-Key
            }
            "9" {
                Clear-Host
                Write-Host ""
                Install-ClassicApps
                Wait-Key
            }
            "A" {
                Clear-Host
                Write-Host ""
                Write-Status -Message "Запуск полной очистки AI..." -Type Warning
                Write-Host ""
                
                $confirm = Read-Host "  Вы уверены? Это действие необратимо! (y/n)"
                
                if ($confirm -eq "y" -or $confirm -eq "Y") {
                    Disable-CopilotRegistry
                    Disable-Recall
                    Remove-AIAppxPackages
                    Disable-AIServices
                    Disable-PaintAI
                    Disable-NotepadAI
                    Disable-ClickToDo
                    Remove-AIFiles
                    
                    Write-Host ""
                    Write-Status -Message "Полная очистка AI завершена!" -Type Success
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
Export-ModuleMember -Function Invoke-RemoveAI
