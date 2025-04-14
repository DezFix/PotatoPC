function Show-Menu {
    Clear-Host
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host "     WICKED RAVEN SYSTEM CLEAR     " -ForegroundColor Magenta
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " 1. Очистка системы"
    Write-Host " 2. Отключение телеметрии Windows"
    Write-Host " 3. Настройка автозагрузки"
    Write-Host " 4. Отключение ненужных служб"
    Write-Host " 5. Повышение производительности"
    Write-Host " 6. Удаление встроенного ПО"
    Write-Host " 7. Выполнить всё"
    Write-Host " 0. Назад"
    Write-Host ""
}

function Clear-System {
    Write-Host "`n[+] Очистка временных файлов..." -ForegroundColor Yellow
    Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
}

function Disable-Telemetry {
    Write-Host "`n[+] Отключение телеметрии..." -ForegroundColor Yellow
    $services = @("DiagTrack", "dmwappushservice")
    foreach ($svc in $services) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled
    }
    reg add "HKLM\Software\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
    Start-Sleep -Seconds 5
}

function Manage-Startup {
    Write-Host "`n[+] Список автозагрузки:" -ForegroundColor Yellow
    Get-CimInstance -ClassName Win32_StartupCommand | 
        Select-Object Name, Command, Location | 
        Format-Table -AutoSize
    Pause
}

function Disable-Unused-Services {
    Write-Host "`n[+] Отключение ненужных служб..." -ForegroundColor Yellow
    $svcList = @("XblGameSave", "XboxNetApiSvc", "Fax", "MapsBroker", "RetailDemo")
    foreach ($svc in $svcList) {
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 5
}

function Optimize-Performance {
    Write-Host "`n[+] Включение режима высокой производительности..." -ForegroundColor Yellow
    powercfg -setactive SCHEME_MIN
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "0"
    Start-Sleep -Seconds 5
}

function Remove-Bloatware {
    Write-Host "`n[+] Удаление встроенного ПО..." -ForegroundColor Yellow
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
        "Microsoft.YourPhone"
    )
    foreach ($app in $apps) {
        Get-AppxPackage -Name $app | Remove-AppxPackage -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 5
}

$backToMain = $false

while (-not $backToMain) {
    Show-Menu
    $choice = Read-Host "Выберите опцию (0-7):"
    switch ($choice) {
        '1' { Clear-System }
        '2' { Disable-Telemetry }
        '3' { Manage-Startup }
        '4' { Disable-Unused-Services }
        '5' { Optimize-Performance }
        '6' { Remove-Bloatware }
        '7' {
            Clear-System
            Disable-Telemetry
            Disable-Unused-Services
            Optimize-Performance
            Remove-Bloatware
        }
        '0' {
            Write-Host "Возврат в главное меню..." -ForegroundColor Green
            Start-Sleep -Seconds 1
            iex (irm "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/menu.ps1")
            $backToMain = $true
        }
        default { Write-Host "Неверный ввод. Попробуйте снова." -ForegroundColor Red; Pause }
    }
}
