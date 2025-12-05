# ==========================================
# POTATO PC OPTIMIZER v6.0 (STABLE)
# ==========================================

# --- 1. AUTO-ELEVATE (ИСПРАВЛЕНО) ---
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (!($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    $scriptPath = $MyInvocation.MyCommand.Definition
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        Write-Host "Пожалуйста, сохраните скрипт в файл перед запуском!" -ForegroundColor Red
        Read-Host "Нажмите Enter для выхода"
        exit
    }
    Write-Host "Перезапуск от имени Администратора..." -ForegroundColor Yellow
    # Запускаем новый процесс и передаем ему путь к этому же файлу
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    exit
}

# --- НАСТРОЙКИ ---
$AppsJsonUrl = "https://raw.githubusercontent.com/DezFix/PotatoPC/main/apps.json"
$BackupDir = "C:\PotatoPC_Backups"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

# --- HELPER: Проверка и установка Winget ---
function Helper-CheckWinget {
    Write-Host " [CHECK] Проверка наличия WinGet (App Installer)..." -ForegroundColor DarkGray
    if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "WinGet не найден! Скачивание и установка..." -ForegroundColor Yellow
        try {
            # Ссылка на последний релиз с GitHub Microsoft
            $url = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
            $output = "$env:TEMP\winget.msixbundle"
            
            Invoke-WebRequest -Uri $url -OutFile $output -UseBasicParsing
            Write-Host "Установка пакета..." -ForegroundColor Cyan
            Add-AppxPackage -Path $output
            Remove-Item $output
            Write-Host "[OK] WinGet установлен." -ForegroundColor Green
        } catch {
            Write-Host "[ERROR] Не удалось установить WinGet автоматически." -ForegroundColor Red
            Write-Host "Пожалуйста, обновите Windows или установите 'App Installer' из Microsoft Store."
            Pause
            return $false
        }
    } else {
        Write-Host "[OK] WinGet найден." -ForegroundColor Green
    }
    return $true
}

# --- HELPER: Службы ---
function Helper-KillService {
    param($Name)
    $services = Get-Service $Name -ErrorAction SilentlyContinue
    foreach ($service in $services) {
        if ($service.Status -ne 'Stopped' -or $service.StartType -ne 'Disabled') {
            $state = [PSCustomObject]@{Name = $service.Name; StartType = $service.StartType; Status = $service.Status; Date = Get-Date}
            $state | Export-Csv -Path "$BackupDir\Services_Backup.csv" -Append -NoTypeInformation -Force

            Write-Host " [STOP] Служба: $($service.Name)" -ForegroundColor DarkCyan
            Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($service.Name)" -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- HELPER: Appx ---
function Helper-KillApp {
    param($NamePattern)
    $WhiteList = @("Microsoft.WindowsStore", "Microsoft.DesktopAppInstaller", "Microsoft.Windows.Photos", "Microsoft.WindowsCalculator", "Microsoft.VP9VideoExtensions") 
    
    $apps = Get-AppxPackage -AllUsers | Where-Object {$_.Name -like "*$NamePattern*" -and $_.Name -notin $WhiteList}
    if ($apps) {
        foreach ($app in $apps) {
            Write-Host "    -> [DEL] Пакет: $($app.Name)" -ForegroundColor Red
            Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction SilentlyContinue
        }
    }
    Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -like "*$NamePattern*" -and $_.DisplayName -notin $WhiteList} | ForEach-Object {
        Write-Host "    -> [IMG] Образ: $($_.DisplayName)" -ForegroundColor Magenta
        Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
    }
}

# --- HELPER: Реестр ---
function Helper-RegSet {
    param($Path, $Name, $Value, $Type="DWord")
    if (!(Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction SilentlyContinue
}

# --- MENU SYSTEM ---
function Show-MainMenu {
    $Host.UI.RawUI.BackgroundColor = "Black"
    while ($true) {
        Clear-Host
        Write-Host "==============================================================" -ForegroundColor Cyan
        Write-Host "               POTATO PC OPTIMIZER v6.0                       " -ForegroundColor Cyan
        Write-Host "==============================================================" -ForegroundColor Cyan
        Write-Host " Backups: $BackupDir" -ForegroundColor DarkGray
        Write-Host ""
        
        Write-Host " [1] " -NoNewline -ForegroundColor Green; Write-Host "Очистка Bloatware " -NoNewline; Write-Host "(Список из исследования)" -ForegroundColor Gray
        Write-Host " [2] " -NoNewline -ForegroundColor Green; Write-Host "Отключение Служб " -NoNewline; Write-Host "(Безопасный список + SysMain)" -ForegroundColor Gray
        Write-Host " [3] " -NoNewline -ForegroundColor Green; Write-Host "Очистка Мусора " -NoNewline; Write-Host "(Temp, Logs, Updates)" -ForegroundColor Gray
        Write-Host " [4] " -NoNewline -ForegroundColor Green; Write-Host "Магазин Приложений " -NoNewline; Write-Host "(WinGet GUI)" -ForegroundColor Gray
        Write-Host " [5] " -NoNewline -ForegroundColor Green; Write-Host "Твики Windows " -NoNewline; Write-Host "(Интерфейс)" -ForegroundColor Gray
        Write-Host ""
        Write-Host " [6] " -NoNewline -ForegroundColor Yellow; Write-Host ">> АВТО-РАЗГОН (PRESET)" -NoNewline; Write-Host " -> Максимальное ускорение" -ForegroundColor Gray
        Write-Host ""
        Write-Host " [9] " -NoNewline -ForegroundColor Magenta; Write-Host "Создать точку восстановления"
        Write-Host " [R] " -NoNewline -ForegroundColor DarkGray; Write-Host "Восстановить службы"
        Write-Host " [0] " -NoNewline -ForegroundColor Red; Write-Host "Выход"
        
        $choice = Read-Host " > Выбор"
        switch ($choice) {
            '1' { Module-RemoveBloatware }
            '2' { Module-DisableServices }
            '3' { Module-SystemCleanup }
            '4' { Module-InstallerGUI }
            '5' { Module-SystemTweaks }
            '6' { Module-AutoPreset }
            '9' { Module-CreateRestorePoint }
            'R' { Module-RestoreServices }
            '0' { exit }
        }
    }
}

# --- MODULE 6: PRESET ---
function Module-AutoPreset {
    Clear-Host
    Write-Host "=== АВТОМАТИЧЕСКАЯ ОПТИМИЗАЦИЯ ===" -ForegroundColor Yellow
    $c = Read-Host "Нажми Enter для старта (или 'n' для отмены)"
    if ($c -eq 'n') { return }

    Module-CreateRestorePoint -Auto $true
    Module-RemoveBloatware -Auto $true
    Module-DisableServices -Auto $true
    Module-SystemCleanup -Auto $true
    
    Write-Host "`n[TWEAK] Максимальная производительность..." -ForegroundColor Cyan
    powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null | Out-Null
    powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
    
    Write-Host "`n[TWEAK] Отключение анимаций..." -ForegroundColor Cyan
    Helper-RegSet "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2
    
    Write-Host "`n[DONE] Готово! Перезагрузи ПК." -ForegroundColor Green
    Pause
}

# --- MODULE 1: BLOATWARE ---
function Module-RemoveBloatware {
    param($Auto = $false)
    Write-Host "`n=== УДАЛЕНИЕ ВСТРОЕННОГО ПО ===" -ForegroundColor Yellow
    if (!$Auto) {
        Write-Host "Будут удалены: Почта, Xbox, Новости, Wallet, People, Cortana и др." -ForegroundColor Red
        if ((Read-Host "Продолжить? (y/n)") -ne 'y') { return }
        Module-CreateRestorePoint -Auto $true
    }

    $BloatList = @(
        "Microsoft.WindowsCommunicationsApps", "Microsoft.BingNews", "Microsoft.BingWeather",
        "Microsoft.XboxApp", "Microsoft.GamingApp", "Microsoft.XboxGamingOverlay",
        "Microsoft.Xbox.TCUI", "Microsoft.XboxSpeechToTextOverlay", "Microsoft.YourPhone",
        "Microsoft.GetHelp", "Microsoft.People", "Microsoft.SkypeApp", "Microsoft.Wallet",
        "Microsoft.549981C3F5F10", "Microsoft.MicrosoftOfficeHub", "Microsoft.Office.OneNote",
        "Microsoft.WindowsFeedbackHub", "Microsoft.ZuneMusic", "Microsoft.ZuneVideo",
        "Microsoft.Todos", "Microsoft.MicrosoftSolitaireCollection", "Microsoft.MixedReality.Portal",
        "Microsoft.WindowsSoundRecorder", "Microsoft.WindowsMaps"
    )

    foreach ($app in $BloatList) { Helper-KillApp $app }
    
    Write-Host " [REG] Скрытие виджетов новостей..." -ForegroundColor Cyan
    Helper-RegSet "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa" 0
    Write-Host " [REG] Отключение Copilot..." -ForegroundColor Cyan
    Helper-RegSet "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1

    Write-Host "`n[OK] Очистка завершена." -ForegroundColor Green
    if (!$Auto) { Pause }
}

# --- MODULE 2: SERVICES ---
function Module-DisableServices {
    param($Auto = $false)
    Write-Host "`n=== ОТКЛЮЧЕНИЕ СЛУЖБ ===" -ForegroundColor Yellow
    
    $ServicesToKill = @(
        "DiagTrack", "dmwappushservice", "WerSvc", "MapsBroker", "RetailDemo", "Fax",
        "TrkWks", "WbioSrvc", "TabletInputService"
    )
    $ServicesToKill += @("XblAuthManager", "XblGameSave", "XboxNetApiSvc", "XboxGipSvc", "BcastDVRUserService*")

    foreach ($svc in $ServicesToKill) { Helper-KillService $svc }

    # SysMain Check
    Write-Host " [CHECK] Проверка типа диска для SysMain..." -ForegroundColor DarkGray
    $isSSD = $false
    try {
        $disk = Get-PhysicalDisk | Where-Object { $_.MediaType -eq 'SSD' } | Select-Object -First 1
        if ($disk) { $isSSD = $true }
    } catch { Write-Host "Не удалось определить диск." -ForegroundColor Red }

    if ($isSSD) {
        Write-Host " -> SSD обнаружен. Отключаем SysMain..." -ForegroundColor Green
        Helper-KillService "SysMain"
    } else {
        Write-Host " -> HDD обнаружен. SysMain оставлен включенным." -ForegroundColor Yellow
    }

    Write-Host " [REG] Отключение GameDVR..." -ForegroundColor Cyan
    Helper-RegSet "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0
    Helper-RegSet "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" 0

    $Tasks = @(
        "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
        "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator"
    )
    foreach ($t in $Tasks) { schtasks /Change /TN "$t" /Disable 2>$null }

    Write-Host "`n[OK] Службы оптимизированы." -ForegroundColor Green
    if (!$Auto) { Pause }
}

# --- MODULE 3: CLEANUP ---
function Module-SystemCleanup {
    param($Auto = $false)
    Write-Host "`n=== ОЧИСТКА СИСТЕМЫ ===" -ForegroundColor Yellow
    
    $paths = @( "$env:TEMP\*", "C:\Windows\Temp\*", "$env:LOCALAPPDATA\Temp\*" )
    foreach ($p in $paths) {
        Write-Host " [CLEAN] $p" -ForegroundColor Gray
        Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
    }
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    
    Write-Host " [LOGS] Очистка журналов событий..." -ForegroundColor DarkGray
    Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | ForEach-Object { Wevtutil cl $_.LogName 2>$null }

    Write-Host "`n[OK] Мусор удален." -ForegroundColor Green
    if (!$Auto) { Pause }
}

# --- MODULE 4: GUI INSTALLER ---
function Module-InstallerGUI {
    # ПРОВЕРКА WINGET
    if (!(Helper-CheckWinget)) { return }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    Write-Host " [NET] Загрузка списка приложений..." -ForegroundColor Cyan
    try { $Json = Invoke-RestMethod -Uri $AppsJsonUrl -UseBasicParsing -TimeoutSec 10 } 
    catch { Write-Host "[ERROR] Нет интернета." -ForegroundColor Red; Pause; return }

    $Global:CachedApps = @()
    if ($Json.ManualCategories) {
        $Json.ManualCategories.PSObject.Properties | ForEach-Object {
            $cat = $_.Name
            foreach ($a in $_.Value) {
                $a | Add-Member -NotePropertyName "DisplayString" -NotePropertyValue "$($a.Name)  [$cat]" -Force
                $Global:CachedApps += $a
            }
        }
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "PotatoPC App Manager"
    $form.Size = New-Object System.Drawing.Size(600, 600)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"

    $txtSearch = New-Object System.Windows.Forms.TextBox
    $txtSearch.Location = New-Object System.Drawing.Point(10, 10)
    $txtSearch.Size = New-Object System.Drawing.Size(560, 20)
    $txtSearch.Text = "Поиск..."
    $form.Controls.Add($txtSearch)

    $list = New-Object System.Windows.Forms.CheckedListBox
    $list.Location = New-Object System.Drawing.Point(10, 40)
    $list.Size = New-Object System.Drawing.Size(560, 400)
    $list.CheckOnClick = $true
    $form.Controls.Add($list)

    $PopulateList = {
        param($filter)
        $list.BeginUpdate()
        $list.Items.Clear()
        foreach ($app in $Global:CachedApps) {
            if ([string]::IsNullOrWhiteSpace($filter) -or $filter -eq "Поиск..." -or $app.Name -match $filter) {
                $list.Items.Add($app.DisplayString)
            }
        }
        $list.EndUpdate()
    }
    & $PopulateList ""

    $txtSearch.Add_TextChanged({ & $PopulateList $txtSearch.Text })
    $txtSearch.Add_Click({ if($txtSearch.Text -eq "Поиск..."){$txtSearch.Text=""} })

    $btnInstall = New-Object System.Windows.Forms.Button
    $btnInstall.Text = "Установить (Install)"
    $btnInstall.Location = New-Object System.Drawing.Point(10, 450)
    $btnInstall.Size = New-Object System.Drawing.Size(275, 50)
    $btnInstall.BackColor = "Green"
    $btnInstall.ForeColor = "White"
    $btnInstall.Add_Click({
        $form.Hide()
        foreach ($item in $list.CheckedItems) {
            $name = $item.Split("[")[0].Trim()
            $id = ($Global:CachedApps | Where-Object {$_.Name -eq $name} | Select -First 1).Id
            Write-Host "Installing: $name..." -ForegroundColor Cyan
            winget install --id $id -e --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        }
        [System.Windows.Forms.MessageBox]::Show("Готово!")
        $form.Close()
    })
    $form.Controls.Add($btnInstall)

    $btnUpdate = New-Object System.Windows.Forms.Button
    $btnUpdate.Text = "Обновить ВСЁ (Update All)"
    $btnUpdate.Location = New-Object System.Drawing.Point(295, 450)
    $btnUpdate.Size = New-Object System.Drawing.Size(275, 50)
    $btnUpdate.BackColor = "DarkBlue"
    $btnUpdate.ForeColor = "White"
    $btnUpdate.Add_Click({
        $form.Hide()
        Write-Host "Обновление всех приложений..." -ForegroundColor Magenta
        winget upgrade --all --include-unknown --accept-source-agreements --accept-package-agreements
        [System.Windows.Forms.MessageBox]::Show("Обновление завершено!")
        $form.Close()
    })
    $form.Controls.Add($btnUpdate)

    [void]$form.ShowDialog()
}

# --- MODULE 5: SYSTEM TWEAKS (CLEANED) ---
function Module-SystemTweaks {
    function Get-Status($bool) { if($bool){return "[ON ]"}else{return "[OFF]"} }
    function Get-Color($bool) { if($bool){return "Green"}else{return "Gray"} }

    while ($true) {
        Clear-Host
        Write-Host "--- TWEAKS ---" -ForegroundColor Cyan
        
        $isClassic = Test-Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
        $isBingOff = (Get-ItemProperty "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" -EA SilentlyContinue).DisableSearchBoxSuggestions -eq 1
        $isTransp = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" -EA SilentlyContinue).EnableTransparency -eq 1
        
        Write-Host " [1] " -NoNewline; Write-Host $(Get-Status $isClassic) -F $(Get-Color $isClassic) -NoNewline; Write-Host " Классическое меню (Win 11)"
        Write-Host " [2] " -NoNewline; Write-Host $(Get-Status $isBingOff) -F $(Get-Color $isBingOff) -NoNewline; Write-Host " Отключить Bing поиск в меню Пуск"
        Write-Host " [3] " -NoNewline; Write-Host $(Get-Status $isTransp) -F $(Get-Color $isTransp) -NoNewline; Write-Host " Прозрачность Windows (Выкл = FPS)"
        Write-Host " [0] Назад"

        $c = Read-Host " >"
        switch ($c) {
            '1' { if($isClassic){reg delete "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" /f | Out-Null}else{reg add "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /f /ve | Out-Null} }
            '2' { $v=if($isBingOff){0}else{1}; Helper-RegSet "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" $v }
            '3' { $v=if($isTransp){0}else{1}; Helper-RegSet "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" $v }
            '0' { return }
        }
        if ($c -in '1','2','3') { Stop-Process -Name explorer -Force; Start-Sleep 1 }
    }
}

# --- RESTORE ---
function Module-CreateRestorePoint {
    param($Auto = $false)
    Write-Host "Создание точки восстановления..." -ForegroundColor Yellow
    Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
    try {
        Checkpoint-Computer -Description "PotatoPC_Point" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Host "[SUCCESS] Точка создана." -ForegroundColor Green
    } catch {
        Write-Host "[FAIL] Ошибка. (Возможно отключена защита системы)" -ForegroundColor Red
        if (!$Auto) { Pause }
    }
    if (!$Auto) { Pause }
}

function Module-RestoreServices {
    $csv = "$BackupDir\Services_Backup.csv"
    if (!(Test-Path $csv)) { Write-Host "Бэкап не найден!" -ForegroundColor Red; Pause; return }
    $backup = Import-Csv $csv
    foreach ($row in $backup) {
        Write-Host " [RESTORE] $($row.Name)" -ForegroundColor Cyan
        Set-Service -Name $row.Name -StartupType $row.StartType -ErrorAction SilentlyContinue
        if ($row.Status -eq "Running") { Start-Service -Name $row.Name -ErrorAction SilentlyContinue }
    }
    Write-Host "Готово." -ForegroundColor Green; Pause
}

# --- START ---
Show-MainMenu
