# Спрашиваем пользователя, создавать ли точку восстановления
$createRestore = Read-Host "Создать точку восстановления перед изменениями? (y/n)"
if ($createRestore -eq 'y' -or $createRestore -eq 'Y') {
    try {
        Checkpoint-Computer -Description "До выполнения Wicked Raven System Clear" -RestorePointType "MODIFY_SETTINGS"
        Write-Host "[+] Точка восстановления создана" -ForegroundColor Green
    } catch {
        Write-Host "[-] Не удалось создать точку восстановления: $_" -ForegroundColor Yellow
    }
}

# Функция отображения меню
function Show-Menu {
    Clear-Host
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host "     WICKED RAVEN SYSTEM CLEAR     " -ForegroundColor Magenta
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " 1. Настройка автозагрузки"
    Write-Host ""
    Write-Host " 2. Отключение телеметрии Windows"
    Write-Host " 3. Отключение ненужных служб"
    Write-Host " 4. Повышение производительности"
    Write-Host " 5. Удаление встроенного ПО"
    Write-Host " 6. Очистка системы"
    Write-Host ""
    Write-Host " 7. Выполнить всё"
    Write-Host " 0. Назад"
    Write-Host ""
}

# Расширенная очистка системы
function Clear-System {
    Write-Host "`n[+] Очистка временных файлов..." -ForegroundColor Yellow
    
    # Очистка временных файлов
    try {
        Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction Stop
        Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction Stop
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Host "[+] Временные файлы успешно удалены" -ForegroundColor Green
    } catch {
        Write-Host "[-] Ошибка при очистке: $_" -ForegroundColor Red
    }

    # Очистка DNS кэша
    ipconfig /flushdns | Out-Null
    
    # Очистка prefetch
    Remove-Item "C:\Windows\Prefetch\*" -Recurse -Force -ErrorAction SilentlyContinue
    
    Start-Sleep -Seconds 2
}

# Расширенное отключение телеметрии
function Disable-Telemetry {
    Write-Host "`n[+] Расширенное отключение телеметрии..." -ForegroundColor Yellow
    
    # Службы телеметрии
    $services = @(
        "DiagTrack", "dmwappushservice", "DPS", "WdiServiceHost", 
        "WdiSystemHost", "Wecsvc", "WerSvc", "WMPNetworkSvc", 
        "WpnService", "XboxGameMonitoring", 
        "XboxSpeechToTextService", "XboxGipSvc"
    )
    
    foreach ($svc in $services) {
        if (Get-Service $svc -ErrorAction SilentlyContinue) {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Host "[+] Служба $svc отключена" -ForegroundColor Cyan
        }
    }

    # Запланированные задачи
    $tasks = @(
        "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
        "\Microsoft\Windows\Autochk\Proxy",
        "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
        "\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask",
        "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
        "\Microsoft\Windows\Windows Error Reporting\Windows Problem Reporting Scheduled Task",
        "\Microsoft\Windows\Feedback\Siuf\DmClient",
        "\Microsoft\Windows\Feedback\Siuf\SiufTask"
    )
    
    foreach ($task in $tasks) {
        schtasks /Change /TN $task /Disable 2>$null
    }

    # Реестр
    $regPaths = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager",
        "HKCU:\Software\Microsoft\InputPersonalization",
        "HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore"
    )
    
    foreach ($path in $regPaths) {
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    }

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338387Enabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\InputPersonalization" -Name "RestrictImplicitTextCollection" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\InputPersonalization" -Name "RestrictImplicitInkCollection" -Value 1 -Type DWord -Force
    
    Write-Host "[+] Телеметрия полностью отключена" -ForegroundColor Green
    Start-Sleep -Seconds 2
}
# Расширенное управление автозагрузкой
function Get-StartupItems {
    Write-Host "`n[+] Сканирование автозагрузки всех пользователей..." -ForegroundColor Yellow

    $allStartupItems = @()
    $userProfiles = Get-WmiObject -Class Win32_UserProfile | Where-Object { $_.Loaded -eq $true -and $_.LocalPath -like "C:\Users\*" }

    # Собираем автозагрузку для каждого пользователя
    foreach ($userProf in $userProfiles) {
        $userName = Split-Path $userProf.LocalPath -Leaf
        $startupItems = @()

        # HKCU для каждого пользователя
        $ntUserDat = "$($userProf.LocalPath)\NTUSER.DAT"
        if (Test-Path $ntUserDat) {
            try {
                $regHive = "HKU\$userName"
                reg load $regHive $ntUserDat | Out-Null
                $runPath = "$regHive\Software\Microsoft\Windows\CurrentVersion\Run"
                if (Test-Path $runPath) {
                    $valueNames = (Get-ItemProperty -Path $runPath | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)
                    foreach ($val in $valueNames) {
                        $startupItems += [PSCustomObject]@{
                            Name = $val
                            Location = (Get-ItemProperty -Path $runPath -Name $val).$val
                            Type = "Registry (HKCU)"
                            User = $userName
                        }
                    }
                }
                reg unload $regHive | Out-Null
            } catch {}
        }

        # Startup folder для каждого пользователя
        $startupFolder = "$($profile.LocalPath)\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
        $startupFolder = "$($userProf.LocalPath)\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
        if (Test-Path $startupFolder) {
            $startupItems += Get-ChildItem -Path $startupFolder -File | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.BaseName
                    Location = $_.FullName
                    Type = "Startup Folder"
                    User = $userName
                }
            }
        }

        if ($startupItems.Count -gt 0) {
            $allStartupItems += [PSCustomObject]@{
                User = $userName
                Items = $startupItems
            }
        }
    }
    # HKLM для всех
    $startupItemsHKLM = @()
    $runPathHKLM = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
    if (Test-Path $runPathHKLM) {
        $valueNames = (Get-ItemProperty -Path $runPathHKLM | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)
        foreach ($val in $valueNames) {
            $startupItemsHKLM += [PSCustomObject]@{
                Name = $val
                Location = (Get-ItemProperty -Path $runPathHKLM -Name $val).$val
                Type = "Registry (HKLM)"
                User = "All Users"
            }
        }
    }
    if ($startupItemsHKLM.Count -gt 0) {
        $allStartupItems += [PSCustomObject]@{
            User = "All Users (HKLM)"
            Items = $startupItemsHKLM
        }
    }

    # Startup folder для всех пользователей (Public)
    $publicStartupFolder = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path $publicStartupFolder) {
        $publicItems = Get-ChildItem -Path $publicStartupFolder -File | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.BaseName
                Location = $_.FullName
                Type = "Startup Folder (Public)"
                User = "All Users"
            }
        }
        if ($publicItems.Count -gt 0) {
            $allStartupItems += [PSCustomObject]@{
                User = "All Users (Startup Folder)"
                Items = $publicItems
            }
        }
    }

    if ($allStartupItems.Count -eq 0) {
        Write-Host "[!] Элементы автозагрузки не найдены" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    # Выводим список в нужном формате
    $flatList = @()
    $displayIndex = 1
    foreach ($userBlock in $allStartupItems) {
        Write-Host "`nПользователь: $($userBlock.User)" -ForegroundColor Magenta
        $itemIndex = 1
        foreach ($item in $userBlock.Items) {
            Write-Host " $itemIndex. $($item.Name) [$($item.Type)]" -ForegroundColor Cyan
            $flatList += [PSCustomObject]@{
                DisplayIndex = "$displayIndex.$itemIndex"
                ItemIndex = $itemIndex
                Item = $item
                User = $userBlock.User
            }
            $itemIndex++
        }
        $displayIndex++
    }

    do {
        $selection = Read-Host "`nВведите номера элементов для отключения (например: 1,2,3; 0 - выход)"
        if ($selection -eq '0') { return }

        $indices = $selection -split ',' | ForEach-Object { $_.Trim() }
        $valid = $true

        foreach ($index in $indices) {
            $selected = $flatList | Where-Object { $_.ItemIndex -eq [int]$index }
            if ($selected) {
                $selectedItem = $selected.Item
                switch ($selectedItem.Type) {
                    "Registry (HKCU)" {
                        $userProfSel = $userProfiles | Where-Object { (Split-Path $_.LocalPath -Leaf) -eq $selectedItem.User }
                        if ($userProfSel) {
                            $ntUserDat = "$($userProfSel.LocalPath)\NTUSER.DAT"
                            $regHive = "HKU\$($selectedItem.User)"
                            try {
                                reg load $regHive $ntUserDat | Out-Null
                                $runPath = "$regHive\Software\Microsoft\Windows\CurrentVersion\Run"
                                Remove-ItemProperty -Path $runPath -Name $selectedItem.Name -ErrorAction SilentlyContinue
                                reg unload $regHive | Out-Null
                                Write-Host "[+] Элемент $($selectedItem.Name) отключен для $($selectedItem.User)" -ForegroundColor Green
                            } catch {
                                Write-Host "[!] Не удалось отключить $($selectedItem.Name) для $($selectedItem.User)" -ForegroundColor Red
                            }
                        }
                    }
                    "Registry (HKLM)" {
                        Remove-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name $selectedItem.Name -ErrorAction SilentlyContinue
                        Write-Host "[+] Элемент $($selectedItem.Name) отключен (HKLM)" -ForegroundColor Green
                    }
                    "Startup Folder" {
                        Remove-Item -Path $selectedItem.Location -Force -ErrorAction SilentlyContinue
                        Write-Host "[+] Элемент $($selectedItem.Name) удален из автозагрузки пользователя $($selectedItem.User)" -ForegroundColor Green
                    }
                    "Startup Folder (Public)" {
                        Remove-Item -Path $selectedItem.Location -Force -ErrorAction SilentlyContinue
                        Write-Host "[+] Элемент $($selectedItem.Name) удален из автозагрузки всех пользователей" -ForegroundColor Green
                    }
                }
            } else {
                Write-Host "[!] Неверный выбор: $index" -ForegroundColor Red
                $valid = $false
            }
        }
    } while (-not $valid)
    Pause
}
# Расширенное отключение служб
function Disable-Unused-Services {
    Write-Host "`n[+] Отключение ненужных служб..." -ForegroundColor Yellow
    
    $svcList = @(
        "XblGameSave", "XboxNetApiSvc", "Fax", "MapsBroker", 
        "RetailDemo", "WSearch", "PcaSvc", "DiagSvcs", 
        "TrkWks", "SysMain", "WMPNetworkSvc", "XboxGipSvc",
        "OneSyncSvc", "UnistoreSvc", "MessagingService", 
        "PrintNotify", "TabletInputService", "BthAvctpSvc"
    )
    
    foreach ($svc in $svcList) {
        if (Get-Service $svc -ErrorAction SilentlyContinue) {
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Host "[+] Служба $svc отключена" -ForegroundColor Cyan
        }
    }
    
    # Дополнительные параметры реестра для служб
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WSearch" -Name "Start" -Value 4 -Type DWord -Force
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\OneSyncSvc" -Name "Start" -Value 4 -Type DWord -Force
    
    Write-Host "[+] Все ненужные службы отключены" -ForegroundColor Green
    Start-Sleep -Seconds 2
}

# Расширенная оптимизация производительности
function Optimize-Performance {
    Write-Host "`n[+] Применение оптимизаций производительности..." -ForegroundColor Yellow
    
    # Энергия
    powercfg -setactive SCHEME_MIN
    powercfg /change standby-timeout-ac 0
    powercfg /change hibernate-timeout-ac 0
    
    # Регистр
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "0" -Type String -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 3 -Type DWord -Force
    
    # Системные параметры
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "DisablePagingExecutive" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "LargeSystemCache" -Value 1 -Type DWord -Force
    
    # Edge
    Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Edge" -Name "BackgroundModeEnabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Edge" -Name "PromoteFirefox" -Value 0 -Type DWord -Force
    
    # Диспетчер задач
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "SeparateProcess" -Value 1 -Type DWord -Force
    
    Write-Host "[+] Оптимизации производительности применены" -ForegroundColor Green
    Start-Sleep -Seconds 2
}

# Расширенное удаление встроенного ПО
function Remove-Bloatware {
    Write-Host "`n[+] Расширенное удаление встроенного ПО..." -ForegroundColor Yellow
    
    $apps = @(
        "Microsoft.3DBuilder",
        "Microsoft.XboxApp",
        "Microsoft.GetHelp",
        "Microsoft.ZuneMusic",
        "Microsoft.ZuneVideo",
        "Microsoft.windowscommunicationsapps",
        "Microsoft.WindowsCalculator",
        "Microsoft.WindowsCamera",
        "Microsoft.549981C3F5F10",
        "Microsoft.BingWeather",
        "Microsoft.DesktopAppInstaller",
        "Microsoft.Getstarted",
        "Microsoft.Microsoft3DViewer",
        "Microsoft.MicrosoftOfficeHub",
        "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.MicrosoftStickyNotes",
        "Microsoft.MixedReality.Portal",
        "Microsoft.MSPaint",
        "Microsoft.Office.OneNote",
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
        "Microsoft.MixedReality.Portal",
        "Microsoft.MixedReality.OpenXR",
        "Microsoft.MixedReality.Portal",
        "Microsoft.MixedReality.SpectatorView",
        "Microsoft.MixedReality.WebView2",
        "Microsoft.MixedReality.SceneUnderstanding",
        "Microsoft.MixedReality.SceneUnderstanding.Samples",
        "Microsoft.MixedReality.SpatialPerception",
        "Microsoft.MixedReality.Toolkit.Unity",
        "Microsoft.MixedReality.Toolkit.Editor",
        "Microsoft.MixedReality.Toolkit.Extensions",
        "Microsoft.MixedReality.Toolkit.GLTFSerialization",
        "Microsoft.MixedReality.Toolkit.Physics",
        "Microsoft.MixedReality.Toolkit.Providers",
        "Microsoft.MixedReality.Toolkit.SDK",
        "Microsoft.MixedReality.Toolkit.Services",
        "Microsoft.MixedReality.Toolkit.Tools",
        "Microsoft.MixedReality.Toolkit.UX",
        "Microsoft.MixedReality.Toolkit.Utilities",
        "Microsoft.MixedReality.Toolkit.WSA",
        "Microsoft.MixedReality.Toolkit.XRSDK",
        "Microsoft.MixedReality.Toolkit.XRSDK.OpenXR",
        "Microsoft.MixedReality.Toolkit.XRSDK.WindowsMixedReality",
        "Microsoft.MixedReality.Toolkit.XRSDK.Unity",
        "Microsoft.MixedReality.Toolkit.XRSDK.Editor",
        "Microsoft.MixedReality.Toolkit.XRSDK.Extensions",
        "Microsoft.MixedReality.Toolkit.XRSDK.GLTFSerialization",
        "Microsoft.MixedReality.Toolkit.XRSDK.Physics",
        "Microsoft.MixedReality.Toolkit.XRSDK.Providers",
        "Microsoft.MixedReality.Toolkit.XRSDK.Services",
        "Microsoft.MixedReality.Toolkit.XRSDK.Tools",
        "Microsoft.MixedReality.Toolkit.XRSDK.UX",
        "Microsoft.MixedReality.Toolkit.XRSDK.Utilities",
        "Microsoft.MixedReality.Toolkit.XRSDK.WSA"
    )
    
    foreach ($app in $apps) {
        # Удаление для текущего пользователя
        $package = Get-AppxPackage -Name $app -ErrorAction SilentlyContinue
        if ($package) {
            Remove-AppxPackage -Package $package.PackageFullName -ErrorAction SilentlyContinue
            Write-Host "[+] Удалено: $app" -ForegroundColor Cyan
        }
        
        # Удаление для всех пользователей
        $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $app }
        if ($provisioned) {
            Remove-AppxProvisionedPackage -Online -PackageName $provisioned.PackageName -ErrorAction SilentlyContinue
            Write-Host "[+] Системный пакет удален: $app" -ForegroundColor Cyan
        }
    }
    
    Write-Host "[+] Все нежелательное ПО удалено" -ForegroundColor Green
    Start-Sleep -Seconds 2
}
# Основной цикл
$backToMain = $false

while (-not $backToMain) {
    Show-Menu
    $choice = Read-Host "Выберите опцию (0-7):"
    switch ($choice) {
        '1' { Manage-Startup }
        '2' { Disable-Telemetry }
        '3' { Disable-Unused-Services }
        '4' { Optimize-Performance }
        '5' { Remove-Bloatware }
        '6' { Clear-System }
        '7' {
            Write-Host "[+] Выполнение всех действий..." -ForegroundColor Magenta
            Disable-Telemetry
            Disable-Unused-Services
            Optimize-Performance
            Remove-Bloatware
            Clear-System
            Write-Host "[+] Все действия выполнены!" -ForegroundColor Green
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
