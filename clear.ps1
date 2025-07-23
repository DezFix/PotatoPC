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
    Write-Host " 1. Отключение телеметрии Windows"
    Write-Host " 2. Отключение ненужных служб"
    Write-Host " 3. Повышение производительности"
    Write-Host " 4. Удаление встроенного ПО"
    Write-Host " 5. Очистка системы"
    Write-Host ""
    Write-Host " 6. Выполнить всё"
    Write-Host " 0. Назад"
    Write-Host ""
}

# Расширенная очистка системы
function Clear-System {
    Write-Host "`n[+] Очистка временных файлов..." -ForegroundColor Yellow
    
    try {
        Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction Stop
        Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction Stop
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Host "[+] Временные файлы успешно удалены" -ForegroundColor Green
    } catch {
        Write-Host "[-] Ошибка при очистке: $_" -ForegroundColor Red
    }

    ipconfig /flushdns | Out-Null
    Remove-Item "C:\Windows\Prefetch\*" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# Расширенное отключение телеметрии
function Disable-Telemetry {
    Write-Host "`n[+] Расширенное отключение телеметрии..." -ForegroundColor Yellow
    
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
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WSearch" -Name "Start" -Value 4 -Type DWord -Force
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\OneSyncSvc" -Name "Start" -Value 4 -Type DWord -Force
    
    Write-Host "[+] Все ненужные службы отключены" -ForegroundColor Green
    Start-Sleep -Seconds 2
}

# Расширенная оптимизация производительности
function Optimize-Performance {
    Write-Host "`n[+] Применение оптимизаций производительности..." -ForegroundColor Yellow
    
    powercfg -setactive SCHEME_MIN
    powercfg /change standby-timeout-ac 0
    powercfg /change hibernate-timeout-ac 0
    
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "0" -Type String -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 3 -Type DWord -Force
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "DisablePagingExecutive" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "LargeSystemCache" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Edge" -Name "BackgroundModeEnabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Edge" -Name "PromoteFirefox" -Value 0 -Type DWord -Force
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
    Write-Host "[+] Все нежелательное ПО удалено" -ForegroundColor Green
    Start-Sleep -Seconds 2
}

# Основной цикл
$backToMain = $false

while (-not $backToMain) {
    Show-Menu
    $choice = Read-Host "Выберите опцию (0-7):"
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
