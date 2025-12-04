# ==========================================
# POTATO PC CORE ENGINE v5.0 (ULTIMATE)
# ==========================================

# --- 1. AUTO-ELEVATE (Запуск от Админа) ---
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Перезапуск от имени Администратора..." -ForegroundColor Yellow
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# --- НАСТРОЙКИ ---
$AppsJsonUrl = "https://raw.githubusercontent.com/DezFix/PotatoPC/main/apps.json"
$BackupDir = "C:\PotatoPC_Backups"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

# --- HELPER: Надежное отключение службы с БЭКАПОМ ---
function Helper-KillService {
    param($Name)
    $service = Get-Service $Name -ErrorAction SilentlyContinue
    if ($service) {
        # Сохраняем состояние
        $state = [PSCustomObject]@{
            Name = $service.Name
            StartType = $service.StartType
            Status = $service.Status
            Date = Get-Date
        }
        $state | Export-Csv -Path "$BackupDir\Services_Backup.csv" -Append -NoTypeInformation -Force

        Write-Host " [STOP] Служба: $Name" -ForegroundColor DarkCyan
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue
    }
}

# --- HELPER: Надежное удаление Appx ---
function Helper-KillApp {
    param($NamePattern)
    # Белый список (Защита от удаления критических компонентов)
    $WhiteList = @("Microsoft.WindowsStore", "Microsoft.DesktopAppInstaller", "Microsoft.Windows.Photos") 
    
    Write-Host " [SCAN] Поиск: *$NamePattern*" -ForegroundColor DarkGray
    
    $apps = Get-AppxPackage -AllUsers | Where-Object {$_.Name -like "*$NamePattern*" -and $_.Name -notin $WhiteList}
    
    if ($apps) {
        foreach ($app in $apps) {
            Write-Host "    -> [DEL] Пакет: $($app.Name)" -ForegroundColor Red
            Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction SilentlyContinue
        }
        Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -like "*$NamePattern*" -and $_.DisplayName -notin $WhiteList} | ForEach-Object {
            Write-Host "    -> [IMG] Образ: $($_.DisplayName)" -ForegroundColor Magenta
            Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

# --- MENU SYSTEM ---
function Show-MainMenu {
    $Host.UI.RawUI.BackgroundColor = "Black"
    while ($true) {
        Clear-Host
        Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║              POTATO PC OPTIMIZER v5.0 (ULTIMATE)           ║" -ForegroundColor Cyan
        Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host " Backups saved to: $BackupDir" -ForegroundColor DarkGray
        Write-Host ""
        
        Write-Host " [1] " -NoNewline -ForegroundColor Green; Write-Host "Очистка Bloatware " -NoNewline; Write-Host "(Удаление мусора)" -ForegroundColor Gray
        Write-Host " [2] " -NoNewline -ForegroundColor Green; Write-Host "Отключение Служб " -NoNewline; Write-Host "(Телеметрия + Лишнее)" -ForegroundColor Gray
        Write-Host " [3] " -NoNewline -ForegroundColor Green; Write-Host "Очистка Мусора " -NoNewline; Write-Host "(Temp, Update Cache)" -ForegroundColor Gray
        Write-Host " [4] " -NoNewline -ForegroundColor Green; Write-Host "Магазин Приложений " -NoNewline; Write-Host "(Поиск + Обновление)" -ForegroundColor Gray
        Write-Host " [5] " -NoNewline -ForegroundColor Green; Write-Host "Твики Интерфейса " -NoNewline; Write-Host "(Меню, Проводник)" -ForegroundColor Gray
        Write-Host ""
        Write-Host " [9] " -NoNewline -ForegroundColor Yellow; Write-Host "Создать точку восстановления (RECOMMENDED)"
        Write-Host " [R] " -NoNewline -ForegroundColor Magenta; Write-Host "Восстановить службы (Из бэкапа)"
        Write-Host " [0] " -NoNewline -ForegroundColor Red; Write-Host "Выход"
        
        $choice = Read-Host " > Выбор"
        switch ($choice) {
            '1' { Module-RemoveBloatware }
            '2' { Module-DisableServices }
            '3' { Module-SystemCleanup }
            '4' { Module-InstallerGUI }
            '5' { Module-SystemTweaks }
            '9' { Module-CreateRestorePoint }
            'R' { Module-RestoreServices }
            '0' { exit }
        }
    }
}

# --- MODULE 1: BLOATWARE REMOVAL ---
function Module-RemoveBloatware {
    Write-Host "`n=== УДАЛЕНИЕ ВСТРОЕННОГО ПО ===" -ForegroundColor Yellow
    Write-Host "ВНИМАНИЕ: Это удалит Copilot, Xbox, Погоду и т.д." -ForegroundColor Red
    $conf = Read-Host "Напишите 'y' для продолжения"
    if ($conf -ne 'y') { return }

    Module-CreateRestorePoint -Auto $true

    $BloatList = @(
        "3DBuilder", "BingWeather", "GetHelp", "ZuneMusic", "ZuneVideo",
        "WindowsCamera", "Solitaire", "StickyNotes", "MixedReality",
        "MSPaint", "OneNote", "People", "SkypeApp", "Wallet",
        "WindowsAlarms", "WindowsFeedback", "WindowsMaps", "SoundRecorder",
        "Xbox", "YourPhone", "Copilot", "Cortana", "NewsAndInterests", "BingNews"
    )

    foreach ($app in $BloatList) {
        Helper-KillApp $app
    }
    
    Write-Host " [REG] Отключение Copilot..." -ForegroundColor Cyan
    New-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    
    Write-Host "`n[OK] Очистка завершена." -ForegroundColor Green
    Pause
}

# --- MODULE 2: SERVICES ---
function Module-DisableServices {
    Write-Host "`n=== ОТКЛЮЧЕНИЕ СЛУЖБ ===" -ForegroundColor Yellow
    if (Test-Path "$BackupDir\Services_Backup.csv") { Remove-Item "$BackupDir\Services_Backup.csv" }
    
    $ServicesToKill = @(
        "DiagTrack", "dmwappushservice", "WerSvc", "WMPNetworkSvc", 
        "XblGameSave", "XboxNetApiSvc", "Fax", "MapsBroker", 
        "RetailDemo", "SysMain" 
    )
    
    foreach ($svc in $ServicesToKill) {
        Helper-KillService $svc
    }

    Write-Host " [TASK] Отключение заданий планировщика..." -ForegroundColor Cyan
    $Tasks = @(
        "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
        "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator"
    )
    foreach ($t in $Tasks) { schtasks /Change /TN "$t" /Disable 2>$null }

    Write-Host " [REG] Блокировка телеметрии..." -ForegroundColor Cyan
    if (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection")) {
        New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Force | Out-Null
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

    Write-Host "`n[OK] Службы оптимизированы. Бэкап создан." -ForegroundColor Green
    Pause
}

# --- MODULE: RESTORE SERVICES ---
function Module-RestoreServices {
    $csv = "$BackupDir\Services_Backup.csv"
    if (!(Test-Path $csv)) { Write-Host "Бэкап не найден!" -ForegroundColor Red; Pause; return }
    
    Write-Host "Восстановление служб..." -ForegroundColor Yellow
    $backup = Import-Csv $csv
    foreach ($row in $backup) {
        Write-Host " [RESTORE] $($row.Name) -> $($row.StartType)" -ForegroundColor Cyan
        $startType = $row.StartType
        if ($startType -eq "Automatic") { Set-Service -Name $row.Name -StartupType Automatic }
        if ($startType -eq "Manual") { Set-Service -Name $row.Name -StartupType Manual }
        if ($startType -eq "Disabled") { Set-Service -Name $row.Name -StartupType Disabled }
        if ($row.Status -eq "Running") { Start-Service -Name $row.Name -ErrorAction SilentlyContinue }
    }
    Write-Host "Готово." -ForegroundColor Green
    Pause
}

# --- MODULE 3: CLEANUP ---
function Module-SystemCleanup {
    Write-Host "`n=== ОЧИСТКА СИСТЕМЫ ===" -ForegroundColor Yellow
    
    $paths = @( "$env:TEMP\*", "C:\Windows\Temp\*", "$env:LOCALAPPDATA\Temp\*" )
    foreach ($p in $paths) {
        Write-Host " [CLEAN] $p" -ForegroundColor Gray
        Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
    }
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    
    Write-Host " [UPD] Очистка кэша обновлений..." -ForegroundColor Cyan
    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service wuauserv -ErrorAction SilentlyContinue
    
    Write-Host "`n[OK] Мусор удален." -ForegroundColor Green
    Pause
}

# --- MODULE 4: ADVANCED GUI INSTALLER (v5.0) ---
function Module-InstallerGUI {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    Write-Host " [NET] Загрузка списка приложений..." -ForegroundColor Cyan
    try { 
        $Json = Invoke-RestMethod -Uri $AppsJsonUrl -UseBasicParsing -TimeoutSec 10
    } catch { 
        Write-Host "[ERROR] Не удалось загрузить apps.json." -ForegroundColor Red; Pause; return 
    }

    # Подготовка данных (Кэширование для поиска)
    $Global:CachedApps = @()
    if ($Json.ManualCategories) {
        $Json.ManualCategories.PSObject.Properties | ForEach-Object {
            $cat = $_.Name
            foreach ($a in $_.Value) {
                # Добавляем свойство DisplayString для удобства поиска
                $a | Add-Member -NotePropertyName "DisplayString" -NotePropertyValue "$($a.Name)  [$cat]" -Force
                $Global:CachedApps += $a
            }
        }
    } else { Write-Host "JSON error."; Pause; return }

    # --- ФОРМА ---
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "PotatoPC App Manager"
    $form.Size = New-Object System.Drawing.Size(600, 600)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"

    # Label Поиска
    $lblSearch = New-Object System.Windows.Forms.Label
    $lblSearch.Text = "Поиск / Фильтр:"
    $lblSearch.Location = New-Object System.Drawing.Point(10, 10)
    $lblSearch.Size = New-Object System.Drawing.Size(100, 20)
    $form.Controls.Add($lblSearch)

    # Поле Поиска
    $txtSearch = New-Object System.Windows.Forms.TextBox
    $txtSearch.Location = New-Object System.Drawing.Point(110, 8)
    $txtSearch.Size = New-Object System.Drawing.Size(460, 20)
    $form.Controls.Add($txtSearch)

    # Список
    $list = New-Object System.Windows.Forms.CheckedListBox
    $list.Location = New-Object System.Drawing.Point(10, 40)
    $list.Size = New-Object System.Drawing.Size(560, 400)
    $list.CheckOnClick = $true
    $form.Controls.Add($list)

    # Функция заполнения списка
    $PopulateList = {
        param($filter)
        $list.BeginUpdate()
        $list.Items.Clear()
        foreach ($app in $Global:CachedApps) {
            if ([string]::IsNullOrWhiteSpace($filter) -or $app.Name -match $filter -or $app.DisplayString -match $filter) {
                $list.Items.Add($app.DisplayString)
            }
        }
        $list.EndUpdate()
    }

    # Инициализация списка
    & $PopulateList ""

    # Событие поиска
    $txtSearch.Add_TextChanged({
        & $PopulateList $txtSearch.Text
    })

    # Кнопка Установить
    $btnInstall = New-Object System.Windows.Forms.Button
    $btnInstall.Text = "Установить выбранные (Install)"
    $btnInstall.Location = New-Object System.Drawing.Point(10, 450)
    $btnInstall.Size = New-Object System.Drawing.Size(275, 50)
    $btnInstall.BackColor = "Green"
    $btnInstall.ForeColor = "White"
    $btnInstall.FlatStyle = "Flat"
    $btnInstall.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    
    $btnInstall.Add_Click({
        $form.Hide()
        $count = $list.CheckedItems.Count
        if ($count -eq 0) { [System.Windows.Forms.MessageBox]::Show("Ничего не выбрано!"); $form.Show(); return }
        
        Write-Host "`nНачинаем установку ($count)..." -ForegroundColor Yellow
        foreach ($item in $list.CheckedItems) {
            $name = $item.Split("[")[0].Trim()
            $id = ($Global:CachedApps | Where-Object {$_.Name -eq $name} | Select -First 1).Id
            Write-Host " -> Installing: $name ($id)..." -ForegroundColor Cyan
            winget install --id $id -e --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        }
        [System.Windows.Forms.MessageBox]::Show("Установка завершена!")
        $form.Close()
    })
    $form.Controls.Add($btnInstall)

    # Кнопка Обновить ВСЁ
    $btnUpdate = New-Object System.Windows.Forms.Button
    $btnUpdate.Text = "Обновить всё установленное (Update All)"
    $btnUpdate.Location = New-Object System.Drawing.Point(295, 450)
    $btnUpdate.Size = New-Object System.Drawing.Size(275, 50)
    $btnUpdate.BackColor = "DarkBlue"
    $btnUpdate.ForeColor = "White"
    $btnUpdate.FlatStyle = "Flat"
    $btnUpdate.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)

    $btnUpdate.Add_Click({
        $form.Hide()
        Write-Host "`nЗапуск полного обновления системы..." -ForegroundColor Magenta
        # Запускаем winget upgrade --all --include-unknown
        # Делаем это в текущем окне, чтобы пользователь видел прогресс
        winget upgrade --all --include-unknown --accept-source-agreements --accept-package-agreements
        
        [System.Windows.Forms.MessageBox]::Show("Процесс обновления завершен! Проверьте консоль на наличие ошибок.")
        $form.Close()
    })
    $form.Controls.Add($btnUpdate)

    [void]$form.ShowDialog()
}

# --- MODULE 5: SYSTEM TWEAKS ---
function Module-SystemTweaks {
    function Get-Status($bool) { if($bool){return "[ON ]"}else{return "[OFF]"} }
    function Get-Color($bool) { if($bool){return "Green"}else{return "Gray"} }

    while ($true) {
        Clear-Host
        Write-Host "--- TWEAKS ---" -ForegroundColor Cyan
        
        $isClassic = Test-Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
        $isBingOff = (Get-ItemProperty "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" -EA SilentlyContinue).DisableSearchBoxSuggestions -eq 1
        $isSec = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSecondsInSystemClock" -EA SilentlyContinue).ShowSecondsInSystemClock -eq 1
        $isPerf = (Get-CimInstance Win32_PowerPlan -Namespace root\cimv2\power -Filter "IsActive='True'").ElementName -like "*High Performance*"

        Write-Host " [1] " -NoNewline; Write-Host $(Get-Status $isClassic) -F $(Get-Color $isClassic) -NoNewline; Write-Host " Классическое контекстное меню (Win 11)"
        Write-Host " [2] " -NoNewline; Write-Host $(Get-Status $isBingOff) -F $(Get-Color $isBingOff) -NoNewline; Write-Host " Отключить Bing поиск в меню Пуск"
        Write-Host " [3] " -NoNewline; Write-Host $(Get-Status $isSec) -F $(Get-Color $isSec) -NoNewline; Write-Host " Секунды в часах"
        Write-Host " [4] " -NoNewline; Write-Host $(Get-Status $isPerf) -F $(Get-Color $isPerf) -NoNewline; Write-Host " Режим высокой производительности"
        Write-Host " [0] Назад"

        $c = Read-Host " >"
        switch ($c) {
            '1' { if($isClassic){reg delete "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" /f | Out-Null}else{reg add "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /f /ve | Out-Null} }
            '2' { $v=if($isBingOff){0}else{1}; New-Item "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Force -EA 0|Out-Null; Set-ItemProperty "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" $v -Type DWord }
            '3' { $v=if($isSec){0}else{1}; Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSecondsInSystemClock" $v -Type DWord }
            '4' { powercfg -duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c; powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c }
            '0' { return }
        }
        if ($c -in '1','2','3') { Stop-Process -Name explorer -Force; Start-Sleep 1 }
    }
}

# --- RESTORE POINT ---
function Module-CreateRestorePoint {
    param($Auto = $false)
    Write-Host "Создание точки восстановления..." -ForegroundColor Yellow
    Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
    try {
        Checkpoint-Computer -Description "PotatoPC_Point" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Host "[SUCCESS] Точка создана." -ForegroundColor Green
    } catch {
        Write-Host "[FAIL] Не удалось создать точку." -ForegroundColor Red
        if (!$Auto) { Pause }
    }
    if (!$Auto) { Pause }
}

# --- START ---
Show-MainMenu
