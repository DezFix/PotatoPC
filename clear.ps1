# Проверка прав администратора в начале скрипта
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║                            ВНИМАНИЕ!                                  ║" -ForegroundColor Red
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    Write-Host "[-] Для работы с этим скриптом требуются права администратора!" -ForegroundColor Red
    Write-Host "[!] Пожалуйста, запустите PowerShell от имени администратора" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Нажмите любую клавишу для выхода..." -ForegroundColor White
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}
# Спрашиваем пользователя, создавать ли точку восстановления
$createRestore = Read-Host "Создать точку восстановления перед изменениями? (y/n)"
if ($createRestore -eq 'y' -or $createRestore -eq 'Y') {
    try {
        # Получаем системный диск (обычно C:)
        $systemDrive = $env:SystemDrive
        
        # Проверяем, включена ли функция System Restore для системного диска
        $restoreStatus = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
        $isRestoreEnabled = $false
        
        # Проверяем статус System Restore через WMI
        try {
            $restoreConfig = Get-WmiObject -Class "Win32_SystemRestore" -ErrorAction SilentlyContinue
            if ($restoreConfig) {
                $isRestoreEnabled = $true
            } else {
                # Дополнительная проверка через реестр
                $regKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
                $regValue = Get-ItemProperty -Path $regKey -Name "DisableSR" -ErrorAction SilentlyContinue
                if ($regValue -and $regValue.DisableSR -eq 0) {
                    $isRestoreEnabled = $true
                }
            }
        } catch {
            Write-Host "[!] Ошибка при проверке статуса System Restore" -ForegroundColor Yellow
        }
        
        # Если System Restore отключена, включаем её
        if (-not $isRestoreEnabled) {
            Write-Host "[!] System Restore отключена. Включаем..." -ForegroundColor Yellow
            try {
                # Включаем System Restore для системного диска
                Enable-ComputerRestore -Drive $systemDrive
                
                # Ждём немного, чтобы служба успела инициализироваться
                Start-Sleep -Seconds 3
                
                Write-Host "[+] System Restore успешно включена для диска $systemDrive" -ForegroundColor Green
            } catch {
                Write-Host "[-] Не удалось включить System Restore: $_" -ForegroundColor Red
                Write-Host "[!] Возможно, требуются права администратора или служба VSS недоступна" -ForegroundColor Yellow
                return
            }
        } else {
            Write-Host "[+] System Restore уже включена" -ForegroundColor Green
        }
        
        # Создаём точку восстановления
        Write-Host "[*] Создание точки восстановления..." -ForegroundColor Cyan
        Checkpoint-Computer -Description "До выполнения Wicked Raven System Clear" -RestorePointType "MODIFY_SETTINGS"
        Write-Host "[+] Точка восстановления успешно создана" -ForegroundColor Green
        
    } catch {
        Write-Host "[-] Не удалось создать точку восстановления: $_" -ForegroundColor Red
        
        # Дополнительная информация для диагностики
        if ($_.Exception.Message -match "0x80042308") {
            Write-Host "[!] Возможно, нужно подождать. Между точками восстановления должно пройти не менее 24 часов" -ForegroundColor Yellow
        } elseif ($_.Exception.Message -match "0x8004230F") {
            Write-Host "[!] System Restore отключена в групповых политиках" -ForegroundColor Yellow
        } else {
            Write-Host "[!] Убедитесь, что скрипт запущен с правами администратора" -ForegroundColor Yellow
        }
    }
}

# Функция отображения меню
function Show-Menu {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║                      WICKED RAVEN SYSTEM CLEAR                        ║" -ForegroundColor Yellow
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host " 1. " -ForegroundColor Green -NoNewline
    Write-Host "Отключение телеметрии Windows"
    
    Write-Host " 2. " -ForegroundColor Green -NoNewline
    Write-Host "Отключение ненужных служб"
    
    Write-Host " 3. " -ForegroundColor Green -NoNewline
    Write-Host "Повышение производительности"
    
    Write-Host " 4. " -ForegroundColor Green -NoNewline
    Write-Host "Удаление встроенного ПО"
    
    Write-Host " 5. " -ForegroundColor Green -NoNewline
    Write-Host "Очистка системы"
    
    Write-Host ""
    Write-Host " 6. " -ForegroundColor Magenta -NoNewline
    Write-Host "Применить ВСЕ оптимизации"
    
    Write-Host " 0. " -ForegroundColor Red -NoNewline
    Write-Host "Выход"

    Write-Host ""
    Write-Host "Выберите опцию: " -NoNewline -ForegroundColor White

}

# Расширенная очистка системы
function Clear-System {
    Write-Host "[+] Очистка временных файлов..." -ForegroundColor Yellow
    
    try {
        # Очистка стандартных временных папок
        Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction Stop
        Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction Stop
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Host "[+] Временные файлы успешно удалены" -ForegroundColor Green
    } catch {
        Write-Host "[-] Ошибка при очистке: $_" -ForegroundColor Red
    }

    # Очистка DNS кеша
    ipconfig /flushdns | Out-Null
    
    # Очистка Prefetch
    Remove-Item "C:\Windows\Prefetch\*" -Recurse -Force -ErrorAction SilentlyContinue

    # Очистка WinSxS
    Write-Host "[+] Очистка WinSxS..." -ForegroundColor Yellow
   try {
        # Проверяем наличие DISM
        if (Get-Command dism.exe -ErrorAction SilentlyContinue) {
            Write-Host "[+] Анализ компонентов WinSxS..." -ForegroundColor Cyan
            
            # Очистка устаревших компонентов
            Start-Process -FilePath "dism.exe" -ArgumentList "/online", "/cleanup-image", "/startcomponentcleanup" -Wait -NoNewWindow -PassThru | Out-Null
            Write-Host "[+] WinSxS очищен успешно" -ForegroundColor Green
        } else {
            Write-Host "[-] DISM не найден, пропускаем очистку WinSxS" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[-] Ошибка при очистке WinSxS: $_" -ForegroundColor Red
    }

    Start-Sleep -Seconds 2
    Write-Host "[+] Очистка системы завершена" -ForegroundColor Green
}


# Расширенное отключение телеметрии
function Disable-Telemetry {
    Write-Host "[+] Расширенное отключение телеметрии..." -ForegroundColor Yellow

    # --- Службы на отключение ---
    $services = @(
        "DiagTrack", "dmwappushservice", "DPS", "WdiServiceHost", 
        "WdiSystemHost", "Wecsvc", "WerSvc", "WMPNetworkSvc", 
        "WpnService", "XboxGameMonitoring", "XboxSpeechToTextService", 
        "XboxGipSvc", "XblGameSave", "XboxNetApiSvc"
    )
    foreach ($svc in $services) {
        if (Get-Service $svc -ErrorAction SilentlyContinue) {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Host "[−] Служба $svc отключена" -ForegroundColor Cyan
        }
    }

    # --- Задачи планировщика (телеметрия + диагностика) ---
    $tasks = @(
        "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
        "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
        "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
        "\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask",
        "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
        "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
        "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticResolver",
        "\Microsoft\Windows\Feedback\Siuf\DmClient",
        "\Microsoft\Windows\Feedback\Siuf\SiufTask",
        "\Microsoft\Windows\Windows Error Reporting\QueueReporting"
    )
    foreach ($task in $tasks) {
        schtasks /Change /TN $task /Disable 2>$null
        Write-Host "[−] Задача $task отключена" -ForegroundColor DarkCyan
    }

    # --- Реестр: AllowTelemetry, Cortana, реклама, WER ---
    $regPaths = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager",
        "HKCU:\Software\Microsoft\InputPersonalization",
        "HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore"
    )
    foreach ($path in $regPaths) {
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    }

    # AllowTelemetry в политиках (Group Policy)
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -Force

    # Отключение Cortana
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0 -Type DWord -Force

    # Отключение рекламы/контента
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338387Enabled" -Value 0 -Type DWord -Force

    # Отключение сбора рукописного ввода и текста
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\InputPersonalization" -Name "RestrictImplicitTextCollection" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\InputPersonalization" -Name "RestrictImplicitInkCollection" -Value 1 -Type DWord -Force

    # Отключение Windows Error Reporting
    if (-not (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting")) {
        New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Force | Out-Null
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Value 1 -Type DWord -Force

    Write-Host "[+] Телеметрия и диагностика отключены" -ForegroundColor Green
    Start-Sleep -Seconds 2
}



# Расширенное отключение служб
function Disable-Unused-Services {
    Write-Host "[+] Настройка служб..." -ForegroundColor Yellow
    
    $disableList = @(
        "XblGameSave", "XboxNetApiSvc", "Fax", "MapsBroker", 
        "RetailDemo", "SysMain", "WMPNetworkSvc", "XboxGipSvc",
        "OneSyncSvc", "UnistoreSvc", "MessagingService", 
        "PrintNotify", "TabletInputService", "BthAvctpSvc"
    )

    $manualList = @(
        "WSearch", "PcaSvc", "DiagSvcs", "TrkWks"      
    )

    # Отключаем ненужные
    foreach ($svc in $disableList) {
        if (Get-Service $svc -ErrorAction SilentlyContinue) {
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Host "[−] Служба $svc отключена" -ForegroundColor Cyan
        }
    }

    # Переводим в ручной запуск
    foreach ($svc in $manualList) {
        if (Get-Service $svc -ErrorAction SilentlyContinue) {
            Set-Service -Name $svc -StartupType Manual -ErrorAction SilentlyContinue
            Write-Host "[~] Служба $svc переведена в Manual" -ForegroundColor DarkCyan
        }
    }
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WSearch" -Name "Start" -Value 4 -Type DWord -Force
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\OneSyncSvc" -Name "Start" -Value 4 -Type DWord -Force

    Write-Host "[+] Все службы обработаны" -ForegroundColor Green
    Start-Sleep -Seconds 2
}




# Расширенная оптимизация производительности
function Optimize-Performance {
    Write-Host "[+] Применение оптимизаций производительности..." -ForegroundColor Yellow
    
    powercfg -setactive SCHEME_MIN
    powercfg /change standby-timeout-ac 0
    powercfg /change hibernate-timeout-ac 0
    
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "0" -Type String -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 3 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "DisablePagingExecutive" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "LargeSystemCache" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        
        # Создание ключей для Edge если не существуют
        if (-not (Test-Path "HKCU:\Software\Policies\Microsoft\Edge")) {
            New-Item -Path "HKCU:\Software\Policies\Microsoft\Edge" -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Edge" -Name "BackgroundModeEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Edge" -Name "StartupBoostEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "SeparateProcess" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        
        Write-Host "[+] Основные оптимизации производительности применены" -ForegroundColor Green
    } catch {
        Write-Host "[-] Некоторые оптимизации не удалось применить: $_" -ForegroundColor Yellow
    }
    
    # Отключение новостей и интересов на панели задач
    Write-Host "[+] Отключение новостей и интересов на панели задач..." -ForegroundColor Cyan
    try {
        # Создание ключа если не существует
        if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds")) {
            New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Force -ErrorAction SilentlyContinue | Out-Null
        }
        
        # Попытка через HKCU
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Name "ShellFeedsTaskbarViewMode" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
        
        # Альтернативный способ через HKLM (требует админ права)
        if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds")) {
            New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name "EnableFeeds" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        
        # Дополнительный способ отключения
        if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
            New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        
        Write-Host "[+] Новости и интересы отключены" -ForegroundColor Green
    } catch {
        Write-Host "[-] Частичная ошибка при отключении новостей: $_" -ForegroundColor Yellow
        Write-Host "[!] Попробуйте запустить скрипт от имени администратора для полного отключения" -ForegroundColor Yellow
    }
    
    # Отключение кнопки "Люди" на панели задач
    Write-Host "[+] Отключение кнопки 'Люди' на панели задач..." -ForegroundColor Cyan
    try {
        if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People")) {
            New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" -Name "PeopleBand" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        
        # Альтернативный путь для кнопки "Люди"
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "PeopleBand" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        
        Write-Host "[+] Кнопка 'Люди' отключена" -ForegroundColor Green
    } catch {
        Write-Host "[-] Ошибка при отключении кнопки 'Люди': $_" -ForegroundColor Yellow
    }
    
    Write-Host "[+] Оптимизации производительности применены" -ForegroundColor Green
    Start-Sleep -Seconds 2
}


# Расширенное удаление встроенного ПО
function Remove-Bloatware {
    Write-Host "[+] Расширенное удаление встроенного ПО..." -ForegroundColor Yellow
    
    # Удаление Copilot
    Write-Host "[+] Удаление Microsoft Copilot..." -ForegroundColor Cyan
    try {
        # Отключение Copilot через реестр
        if (-not (Test-Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot")) {
            New-Item -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force
        
        if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot")) {
            New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force
        
        # Удаление Copilot из панели задач
        if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
            New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 0 -Type DWord -Force
        
        # Попытка удалить приложение Copilot
        $copilotPackages = Get-AppxPackage -AllUsers -Name "*Microsoft.Copilot*" -ErrorAction SilentlyContinue
        foreach ($package in $copilotPackages) {
            Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction SilentlyContinue
            Write-Host "[+] Удален пакет Copilot: $($package.Name)" -ForegroundColor Cyan
        }
        
        Write-Host "[+] Microsoft Copilot успешно отключен и удален" -ForegroundColor Green
    } catch {
        Write-Host "[-] Ошибка при удалении Copilot: $_" -ForegroundColor Yellow
    }
    
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
        "Microsoft.windowscommunicationsapps",
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
        "Microsoft.WindowsCopilot",
        "Microsoft.AI.Copilot",
        "Microsoft.BingNews",
        "Microsoft.NewsAndInterests"
    )
    foreach ($app in $apps) {
        $package = Get-AppxPackage -Name $app -ErrorAction SilentlyContinue
        if ($package) {
            Remove-AppxPackage -Package $package.PackageFullName -ErrorAction SilentlyContinue
            Write-Host "[+] Удалено: $app" -ForegroundColor Cyan
        }
        $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $app }
        if ($provisioned) {
            Remove-AppxProvisionedPackage -Online -PackageName $provisioned.PackageName -ErrorAction SilentlyContinue
            Write-Host "[+] Системный пакет удален: $app" -ForegroundColor Cyan
        }
    }
    
    
    # Дополнительные настройки панели задач
    Write-Host "[+] Дополнительная настройка панели задач..." -ForegroundColor Cyan
    
    try {
        # Отключение поиска на панели задач
        if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search")) {
            New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        
        # Отключение представления задач
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        
        Write-Host "[+] Дополнительные настройки панели задач применены" -ForegroundColor Green
    } catch {
        Write-Host "[-] Ошибка при настройке панели задач: $_" -ForegroundColor Yellow
    }
    
    Write-Host "[+] Все нежелательное ПО удалено" -ForegroundColor Green
    Start-Sleep -Seconds 2
}


# Основной цикл
$backToMain = $false

while (-not $backToMain) {
    Show-Menu
    $choice = Read-Host
    switch ($choice) {
        '1' { Disable-Telemetry }
        '2' { Disable-Unused-Services }
        '3' { Optimize-Performance }
        '4' { Remove-Bloatware }
        '5' { Clear-System }
        '6' {
            try { Disable-Telemetry } catch {}
            try { Disable-Unused-Services } catch {}
            try { Optimize-Performance } catch {}
            try { Remove-Bloatware } catch {}
            try { Clear-System } catch {}
            Write-Host "[!] Перезагрузка ПК через 10 секунд...(Ctrl + C что бы отменить)" -ForegroundColor Red
            Start-Sleep -Seconds 10
            Restart-Computer
        }
        '0' {
            Write-Host "Возврат в главное меню..." -ForegroundColor Green
            Start-Sleep -Seconds 1
            iex (irm "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/menu.ps1")
            $backToMain = $true
        }
        default {
            Write-Host "Неверный ввод. Попробуйте снова." -ForegroundColor Red; Pause 
        }
    }
}
