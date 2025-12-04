# ==========================================
# POTATO PC CORE ENGINE v4.0 (FIXED)
# ==========================================

$AppsJsonUrl = "https://raw.githubusercontent.com/DezFix/PotatoPC/main/apps.json"

# --- HELPER: Надежное отключение службы через Реестр ---
function Helper-KillService {
    param($Name)
    if (Get-Service $Name -ErrorAction SilentlyContinue) {
        Write-Host " [STOP] Служба: $Name" -ForegroundColor DarkCyan
        # 1. Пытаемся остановить штатно
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        # 2. Вырубаем через реестр (Start = 4 - Disabled)
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue
    }
}

# --- HELPER: Надежное удаление Appx ---
function Helper-KillApp {
    param($NamePattern)
    Write-Host " [DEL] Поиск приложений по маске: *$NamePattern*" -ForegroundColor DarkYellow
    
    # 1. Удаляем у текущего пользователя и всех остальных
    Get-AppxPackage -AllUsers | Where-Object {$_.Name -like "*$NamePattern*"} | ForEach-Object {
        Write-Host "    -> Удаление пакета: $($_.Name)" -ForegroundColor Red
        Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
    }
    
    # 2. Удаляем из образа (чтобы не вернулось при создании нового юзера)
    Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -like "*$NamePattern*"} | ForEach-Object {
        Write-Host "    -> Удаление из образа: $($_.DisplayName)" -ForegroundColor Magenta
        Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
    }
}

# --- MENU SYSTEM ---
function Show-MainMenu {
    $Host.UI.RawUI.BackgroundColor = "Black"
    while ($true) {
        Clear-Host
        Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║              POTATO PC OPTIMIZER v4.0 (FIXED)              ║" -ForegroundColor Cyan
        Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        
        Write-Host " [1] " -NoNewline -ForegroundColor Green; Write-Host "Очистка Bloatware " -NoNewline; Write-Host "(Удаление мусора)" -ForegroundColor Gray
        Write-Host " [2] " -NoNewline -ForegroundColor Green; Write-Host "Отключение Служб " -NoNewline; Write-Host "(Телеметрия + Лишнее)" -ForegroundColor Gray
        Write-Host " [3] " -NoNewline -ForegroundColor Green; Write-Host "Очистка Мусора " -NoNewline; Write-Host "(Temp, Update Cache)" -ForegroundColor Gray
        Write-Host " [4] " -NoNewline -ForegroundColor Green; Write-Host "Магазин Приложений " -NoNewline; Write-Host "(GUI)" -ForegroundColor Gray
        Write-Host " [5] " -NoNewline -ForegroundColor Green; Write-Host "Твики Windows " -NoNewline; Write-Host "(Меню, Проводник)" -ForegroundColor Gray
        Write-Host ""
        Write-Host " [9] " -NoNewline -ForegroundColor Yellow; Write-Host "Создать точку восстановления"
        Write-Host " [0] " -NoNewline -ForegroundColor Red; Write-Host "Выход"
        
        $choice = Read-Host " > Выбор"
        switch ($choice) {
            '1' { Module-RemoveBloatware }
            '2' { Module-DisableServices }
            '3' { Module-SystemCleanup }
            '4' { Module-InstallerGUI }
            '5' { Module-SystemTweaks }
            '9' { Module-CreateRestorePoint }
            '0' { exit }
        }
    }
}

# --- MODULE 1: BLOATWARE REMOVAL (Исправлено) ---
function Module-RemoveBloatware {
    Write-Host "`n=== УДАЛЕНИЕ ВСТРОЕННОГО ПО ===" -ForegroundColor Yellow
    Write-Host "ВНИМАНИЕ: Это удалит Copilot, Xbox, Погоду и т.д." -ForegroundColor Red
    $conf = Read-Host "Продолжить? (y/n)"
    if ($conf -ne 'y') { return }

    # Список мусора (Wildcards)
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
    
    # Дополнительно: Copilot через реестр
    Write-Host " [REG] Отключение Copilot в реестре..." -ForegroundColor Cyan
    New-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    
    Write-Host "`n[OK] Очистка завершена." -ForegroundColor Green
    Pause
}

# --- MODULE 2: SERVICES & TELEMETRY (Исправлено) ---
function Module-DisableServices {
    Write-Host "`n=== ОТКЛЮЧЕНИЕ СЛУЖБ И ТЕЛЕМЕТРИИ ===" -ForegroundColor Yellow
    
    # 1. Службы (Hard Kill)
    $ServicesToKill = @(
        "DiagTrack", "dmwappushservice", "WerSvc", "WMPNetworkSvc", 
        "XblGameSave", "XboxNetApiSvc", "Fax", "MapsBroker", 
        "RetailDemo", "SysMain"  # SysMain только для HDD, но тут рубим все
    )
    
    foreach ($svc in $ServicesToKill) {
        Helper-KillService $svc
    }

    # 2. Планировщик заданий (Телеметрия)
    Write-Host " [TASK] Отключение заданий планировщика..." -ForegroundColor Cyan
    $Tasks = @(
        "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
        "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator"
    )
    foreach ($t in $Tasks) {
        schtasks /Change /TN "$t" /Disable 2>$null
    }

    # 3. Реестр (Телеметрия)
    Write-Host " [REG] Блокировка телеметрии в реестре..." -ForegroundColor Cyan
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

    Write-Host "`n[OK] Службы оптимизированы." -ForegroundColor Green
    Pause
}

# --- MODULE 3: CLEANUP ---
function Module-SystemCleanup {
    Write-Host "`n=== ОЧИСТКА СИСТЕМЫ ===" -ForegroundColor Yellow
    
    # Temp
    Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    
    # SoftwareDistribution (Исправляет баги обновлений)
    Write-Host " [UPD] Очистка кэша обновлений..." -ForegroundColor Cyan
    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service wuauserv -ErrorAction SilentlyContinue
    
    Write-Host "`n[OK] Мусор удален." -ForegroundColor Green
    Pause
}

# --- MODULE 4: GUI INSTALLER ---
function Module-InstallerGUI {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    # Загрузка JSON
    try { $Json = Invoke-RestMethod -Uri $AppsJsonUrl -UseBasicParsing } catch { Write-Host "Error loading JSON"; return }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "PotatoPC Installer"
    $form.Size = New-Object System.Drawing.Size(600, 500)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"

    $list = New-Object System.Windows.Forms.CheckedListBox
    $list.Location = New-Object System.Drawing.Point(10, 10)
    $list.Size = New-Object System.Drawing.Size(560, 380)
    $list.CheckOnClick = $true

    $AllApps = @()
    $Json.ManualCategories.PSObject.Properties | ForEach-Object {
        $cat = $_.Name
        foreach ($a in $_.Value) {
            $list.Items.Add("$($a.Name)  [$cat]")
            $AllApps += $a
        }
    }
    $form.Controls.Add($list)

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = "Установить выбранное"
    $btn.Location = New-Object System.Drawing.Point(10, 400)
    $btn.Size = New-Object System.Drawing.Size(560, 40)
    $btn.BackColor = "Green"
    $btn.ForeColor = "White"
    
    $btn.Add_Click({
        $form.Hide()
        foreach ($item in $list.CheckedItems) {
            $name = $item.Split("[")[0].Trim()
            $id = ($AllApps | Where-Object {$_.Name -eq $name} | Select -First 1).Id
            Write-Host "Installing $name..." -ForegroundColor Yellow
            winget install --id $id -e --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        }
        [System.Windows.Forms.MessageBox]::Show("Готово!")
        $form.Close()
    })
    $form.Controls.Add($btn)
    [void]$form.ShowDialog()
}

# --- MODULE 5: SYSTEM TWEAKS (TOGGLE) ---
function Module-SystemTweaks {
    function Get-Status($bool) { if($bool){return "[ON ]"}else{return "[OFF]"} }
    function Get-Color($bool) { if($bool){return "Green"}else{return "Red"} }

    while ($true) {
        Clear-Host
        Write-Host "--- TWEAKS (Нажми цифру для переключения) ---" -ForegroundColor Cyan
        
        # Check Statuses
        $isClassic = Test-Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
        $isBingOff = (Get-ItemProperty "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" -EA SilentlyContinue).DisableSearchBoxSuggestions -eq 1
        $isSec = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSecondsInSystemClock" -EA SilentlyContinue).ShowSecondsInSystemClock -eq 1

        Write-Host " [1] " -NoNewline; Write-Host $(Get-Status $isClassic) -F $(Get-Color $isClassic) -NoNewline; Write-Host " Классическое контекстное меню (Win 11)"
        Write-Host " [2] " -NoNewline; Write-Host $(Get-Status $isBingOff) -F $(Get-Color $isBingOff) -NoNewline; Write-Host " Отключить Bing поиск в меню Пуск"
        Write-Host " [3] " -NoNewline; Write-Host $(Get-Status $isSec) -F $(Get-Color $isSec) -NoNewline; Write-Host " Секунды в часах"
        Write-Host " [0] Назад"

        $c = Read-Host " >"
        switch ($c) {
            '1' { if($isClassic){reg delete "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" /f}else{reg add "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /f /ve} }
            '2' { $v=if($isBingOff){0}else{1}; New-Item "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Force -EA 0|Out-Null; Set-ItemProperty "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" $v -Type DWord }
            '3' { $v=if($isSec){0}else{1}; Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSecondsInSystemClock" $v -Type DWord }
            '0' { return }
        }
        # Перезапуск explorer только если были изменения
        if ($c -in '1','2','3') { Stop-Process -Name explorer -Force }
    }
}

# --- RESTORE POINT ---
function Module-CreateRestorePoint {
    Write-Host "Создание точки восстановления..." -ForegroundColor Yellow
    try {
        Checkpoint-Computer -Description "PotatoPC_Point" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Host "[SUCCESS]" -ForegroundColor Green
    } catch {
        Write-Host "[FAIL] Включите защиту системы (System Protection) на диске C:" -ForegroundColor Red
    }
    Pause
}

# --- START ---
Show-MainMenu