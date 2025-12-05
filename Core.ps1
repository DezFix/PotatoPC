# ==========================================
# POTATO PC OPTIMIZER v5.0
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

# --- HELPER: Надежное отключение службы ---
function Helper-KillService {
    param($Name)
    $service = Get-Service $Name -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne 'Stopped') {
        # Бэкап
        $state = [PSCustomObject]@{Name = $service.Name; StartType = $service.StartType; Status = $service.Status; Date = Get-Date}
        $state | Export-Csv -Path "$BackupDir\Services_Backup.csv" -Append -NoTypeInformation -Force

        Write-Host " [STOP] Служба: $Name" -ForegroundColor DarkCyan
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue
    }
}

# --- HELPER: Надежное удаление Appx ---
function Helper-KillApp {
    param($NamePattern)
    # Белый список (НЕ УДАЛЯТЬ ЭТО)
    $WhiteList = @("Microsoft.WindowsStore", "Microsoft.DesktopAppInstaller", "Microsoft.Windows.Photos", "Microsoft.WindowsCalculator") 
    
    $apps = Get-AppxPackage -AllUsers | Where-Object {$_.Name -like "*$NamePattern*" -and $_.Name -notin $WhiteList}
    if ($apps) {
        foreach ($app in $apps) {
            Write-Host "    -> [DEL] Пакет: $($app.Name)" -ForegroundColor Red
            Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction SilentlyContinue
        }
    }
    # Удаление из образа (чтобы не вернулось)
    Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -like "*$NamePattern*" -and $_.DisplayName -notin $WhiteList} | ForEach-Object {
        Write-Host "    -> [IMG] Образ: $($_.DisplayName)" -ForegroundColor Magenta
        Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
    }
}

# --- HELPER: Реестр (Твики) ---
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
        Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║              POTATO PC OPTIMIZER v5.0                      ║" -ForegroundColor Cyan
        Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host " Backups: $BackupDir" -ForegroundColor DarkGray
        Write-Host ""
        
        Write-Host " [1] " -NoNewline -ForegroundColor Green; Write-Host "Очистка Bloatware " -NoNewline; Write-Host "(Почта, Новости, Xbox)" -ForegroundColor Gray
        Write-Host " [2] " -NoNewline -ForegroundColor Green; Write-Host "Отключение Служб " -NoNewline; Write-Host "(Телеметрия, SysMain)" -ForegroundColor Gray
        Write-Host " [3] " -NoNewline -ForegroundColor Green; Write-Host "Очистка Мусора " -NoNewline; Write-Host "(Temp, Update Cache)" -ForegroundColor Gray
        Write-Host " [4] " -NoNewline -ForegroundColor Green; Write-Host "Магазин Приложений " -NoNewline; Write-Host "(Установка/Обновление)" -ForegroundColor Gray
        Write-Host " [5] " -NoNewline -ForegroundColor Green; Write-Host "Твики Windows " -NoNewline; Write-Host "(Визуал, Проводник)" -ForegroundColor Gray
        Write-Host ""
        Write-Host " [6] " -NoNewline -ForegroundColor Yellow; Write-Host "🔥 АВТО-РАЗГОН (PRESET)" -NoNewline; Write-Host " -> Делает [1]+[2]+[3]+Твики" -ForegroundColor Gray
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

# --- MODULE 6: PRESET (АВТОМАТИЗАЦИЯ) ---
function Module-AutoPreset {
    Clear-Host
    Write-Host "=== ЗАПУСК АВТОМАТИЧЕСКОЙ ОПТИМИЗАЦИИ ===" -ForegroundColor Yellow
    Write-Host "Система будет оптимизирована для максимальной производительности." -ForegroundColor Gray
    $c = Read-Host "Нажми Enter для старта (или 'n' для отмены)"
    if ($c -eq 'n') { return }

    Module-CreateRestorePoint -Auto $true
    
    # Запуск модулей в тихом режиме
    Module-RemoveBloatware -Auto $true
    Module-DisableServices -Auto $true
    Module-SystemCleanup -Auto $true
    
    # Применение важных твиков автоматически
    Write-Host "`n[TWEAK] Отключение анимаций и эффектов..." -ForegroundColor Cyan
    # VisualFX: Adjust for best performance (Reg Tweak)
    Helper-RegSet "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2
    
    Write-Host "`n[DONE] Авто-разгон завершен! Перезагрузи ПК для эффекта." -ForegroundColor Green
    Pause
}

# --- MODULE 1: BLOATWARE REMOVAL (Обновленный список) ---
function Module-RemoveBloatware {
    param($Auto = $false)
    Write-Host "`n=== УДАЛЕНИЕ ВСТРОЕННОГО ПО ===" -ForegroundColor Yellow
    if (!$Auto) {
        Write-Host "ВНИМАНИЕ: Удалится Почта, Xbox, Новости, OneNote и прочее." -ForegroundColor Red
        $conf = Read-Host "Напишите 'y' для продолжения"
        if ($conf -ne 'y') { return }
        Module-CreateRestorePoint -Auto $true
    }

    # Расширенный список для слабых ПК
    $BloatList = @(
        "Microsoft.WindowsCommunicationsApps", # Почта и Календарь
        "Microsoft.BingNews",                 # Новости
        "Microsoft.BingWeather",              # Погода
        "Microsoft.XboxApp",                  # Xbox Hub
        "Microsoft.GamingApp",                # Xbox Gaming App
        "Microsoft.Xbox.TCUI",                # Xbox UI
        "Microsoft.XboxGameOverlay",          # Xbox Overlay
        "Microsoft.XboxGamingOverlay",        # Еще оверлей
        "Microsoft.XboxSpeechToTextOverlay",
        "Microsoft.YourPhone",                # Связь с телефоном
        "Microsoft.GetHelp",                  # Техподдержка
        "Microsoft.MicrosoftOfficeHub",       # Office (My Office)
        "Microsoft.Office.OneNote",           # OneNote
        "Microsoft.People",                   # Люди
        "Microsoft.SkypeApp",                 # Skype
        "Microsoft.WindowsFeedbackHub",       # Отзывы
        "Microsoft.ZuneMusic",                # Groove Music
        "Microsoft.ZuneVideo",                # Кино и ТВ
        "Microsoft.Windows.DevHome",          # DevHome (Win11)
        "Microsoft.PowerAutomateDesktop",     # Power Automate
        "Microsoft.Todos",                    # To Do
        "Microsoft.MicrosoftSolitaireCollection", # Косынка
        "Microsoft.MixedReality.Portal",
        "Microsoft.WindowsSoundRecorder",
        "Microsoft.WindowsMaps"
    )

    foreach ($app in $BloatList) {
        Helper-KillApp $app
    }
    
    # Убираем кнопку "Виджеты/Новости" с панели задач
    Write-Host " [REG] Скрытие новостей (Widgets)..." -ForegroundColor Cyan
    Helper-RegSet "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa" 0

    # Отключение Copilot
    Write-Host " [REG] Отключение Copilot..." -ForegroundColor Cyan
    Helper-RegSet "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1

    Write-Host "`n[OK] Очистка завершена." -ForegroundColor Green
    if (!$Auto) { Pause }
}

# --- MODULE 2: SERVICES (Для слабых ПК) ---
function Module-DisableServices {
    param($Auto = $false)
    Write-Host "`n=== ОТКЛЮЧЕНИЕ СЛУЖБ ===" -ForegroundColor Yellow
    
    # Список служб, которые безопасно (и нужно) отключить на слабом ПК
    $ServicesToKill = @(
        "DiagTrack",          # Телеметрия
        "dmwappushservice",   # Телеметрия
        "WerSvc",             # Отчеты об ошибках
        "SysMain",            # Superfetch (Грузит HDD/CPU на старых пк)
        "WMPNetworkSvc",      # Windows Media Player Network
        "XblGameSave",        # Xbox
        "XboxNetApiSvc",      # Xbox
        "XboxGipSvc",         # Xbox
        "Fax",                # Факс
        "MapsBroker",         # Карты
        "RetailDemo",         # Демо режим
        "WSearch",            # Windows Search (ОЧЕНЬ грузит диск, но отключает поиск файлов) - Решил пока не трогать по дефолту, слишком агрессивно.
        "DPS"                 # Diagnostic Policy Service
    )
    
    foreach ($svc in $ServicesToKill) {
        Helper-KillService $svc
    }

    # Отключение GameDVR (Запись игр) - жрет ресурсы
    Write-Host " [REG] Отключение GameDVR..." -ForegroundColor Cyan
    Helper-RegSet "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0
    Helper-RegSet "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" 0

    Write-Host " [TASK] Отключение заданий планировщика..." -ForegroundColor Cyan
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
    
    # Очистка логов событий (для параноиков и экономии места)
    Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | ForEach-Object { Wevtutil cl $_.LogName 2>$null }

    Write-Host "`n[OK] Мусор удален." -ForegroundColor Green
    if (!$Auto) { Pause }
}

# --- MODULE 4: GUI INSTALLER ---
function Module-InstallerGUI {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    Write-Host " [NET] Загрузка..." -ForegroundColor Cyan
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

# --- MODULE 5: SYSTEM TWEAKS ---
function Module-SystemTweaks {
    param($Auto = $false)
    
    # Если авто-режим, применяем только безопасные твики
    if ($Auto) {
        Write-Host " [TWEAK] Отключение Bing в пуске..."
        Helper-RegSet "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1
        return
    }

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

# --- RESTORE POINT & RESTORE ---
function Module-CreateRestorePoint {
    param($Auto = $false)
    Write-Host "Создание точки восстановления..." -ForegroundColor Yellow
    Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
    try {
        Checkpoint-Computer -Description "PotatoPC_Auto" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Host "[SUCCESS] Точка создана." -ForegroundColor Green
    } catch {
        Write-Host "[FAIL] Ошибка создания точки." -ForegroundColor Red
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
