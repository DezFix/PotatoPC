# ==========================================
# POTATO PC OPTIMIZER v8.5 (STABLE FIX)
# ==========================================

# 1. ПОДКЛЮЧЕНИЕ БИБЛИОТЕК (Сразу, чтобы показать баннер)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 2. ФУНКЦИЯ: БАННЕР АДМИНИСТРАТОРА
function Show-AdminWarning {
    $frmAdmin = New-Object System.Windows.Forms.Form
    $frmAdmin.Text = "ОШИБКА ДОСТУПА"
    $frmAdmin.Size = New-Object System.Drawing.Size(500, 250)
    $frmAdmin.StartPosition = "CenterScreen"
    $frmAdmin.FormBorderStyle = "FixedDialog"
    $frmAdmin.MaximizeBox = $false
    $frmAdmin.MinimizeBox = $false
    $frmAdmin.BackColor = [System.Drawing.Color]::DarkRed # Красный фон

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "⚠️ ТРЕБУЮТСЯ ПРАВА АДМИНИСТРАТОРА"
    $lblTitle.Font = New-Object System.Drawing.Font("Arial", 14, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = "White"
    $lblTitle.AutoSize = $true
    $lblTitle.Location = New-Object System.Drawing.Point(30, 40)

    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text = "Скрипт не может вносить изменения в систему без прав.`nПожалуйста, закройте это окно, нажмите правой кнопкой мыши на файл и выберите:`n👉 'Запуск от имени администратора'"
    $lblDesc.Font = New-Object System.Drawing.Font("Arial", 10)
    $lblDesc.ForeColor = "WhiteSmoke"
    $lblDesc.AutoSize = $true
    $lblDesc.Location = New-Object System.Drawing.Point(30, 80)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "ПОНЯТНО, ВЫХОЖУ"
    $btnClose.Size = New-Object System.Drawing.Size(200, 40)
    $btnClose.Location = New-Object System.Drawing.Point(140, 150)
    $btnClose.BackColor = "White"
    $btnClose.ForeColor = "DarkRed"
    $btnClose.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $btnClose.Add_Click({ $frmAdmin.Close() })

    $frmAdmin.Controls.AddRange(@($lblTitle, $lblDesc, $btnClose))
    $frmAdmin.ShowDialog() | Out-Null
}

# 3. ПРОВЕРКА ПРАВ
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (!($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    Show-AdminWarning
    exit # Останавливаем скрипт
}

# --- НАСТРОЙКИ ---
$WorkDir   = "C:\PotatoPC"
$BackupDir = "$WorkDir\Backups"
$TempDir   = "$WorkDir\Temp"
$AppsJsonUrl = "https://raw.githubusercontent.com/DezFix/PotatoPC/main/apps.json"

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
$Global:SelectedAppIDs = new-object System.Collections.Generic.HashSet[string]

# --- ФУНКЦИИ ЛОГИКИ ---

function Log($text, $color="Black") {
    $txtLog.SelectionColor = [System.Drawing.Color]::FromName($color)
    $txtLog.AppendText("[$([DateTime]::Now.ToString('HH:mm:ss'))] $text`r`n")
    $txtLog.ScrollToCaret()
}

# FIX: Исправленная функция WINGET
function Fix-Winget {
    Log "Восстановление WinGet..." "DarkMagenta"
    try {
        $vcUrl = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
        Invoke-WebRequest -Uri $vcUrl -OutFile "$TempDir\vclibs.appx" -UseBasicParsing
        Add-AppxPackage -Path "$TempDir\vclibs.appx" -ErrorAction SilentlyContinue
        
        $uiUrl = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"
        Invoke-WebRequest -Uri $uiUrl -OutFile "$TempDir\ui.xaml.appx" -UseBasicParsing
        Add-AppxPackage -Path "$TempDir\ui.xaml.appx" -ErrorAction SilentlyContinue

        $wgUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        Invoke-WebRequest -Uri $wgUrl -OutFile "$TempDir\winget.msixbundle" -UseBasicParsing
        Add-AppxPackage -Path "$TempDir\winget.msixbundle" -ForceApplicationShutdown
        
        Log "WinGet библиотеки установлены." "Green"
        return (Get-Command winget -ErrorAction SilentlyContinue)
    } catch {
        Log "Ошибка WinGet: $($_.Exception.Message)" "Red"
        return $false
    }
}

function Core-KillService($Name) {
    $services = Get-Service $Name -ErrorAction SilentlyContinue
    foreach ($s in $services) {
        if ($s.Status -ne 'Stopped' -or $s.StartType -ne 'Disabled') {
            Log "Stop Service: $($s.Name)" "DarkMagenta"
            [PSCustomObject]@{Name=$s.Name;Start=$s.StartType;Status=$s.Status} | Export-Csv "$BackupDir\Services_$(Get-Date -f yyyyMMdd).csv" -Append -NoType -Force
            Stop-Service $s.Name -Force -EA 0
            Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.Name)" "Start" 4 -Type DWord -Force -EA 0
        }
    }
}

function Core-RemoveApp($Pattern) {
    $White = @("Microsoft.WindowsStore", "Microsoft.DesktopAppInstaller", "Microsoft.Windows.Photos", "Microsoft.WindowsCalculator")
    $apps = Get-AppxPackage -AllUsers | Where {$_.Name -like "*$Pattern*" -and $_.Name -notin $White}
    foreach ($a in $apps) {
        Log "Remove App: $($a.Name)" "Red"
        Remove-AppxPackage -Package $a.PackageFullName -AllUsers -EA 0
    }
}

function Core-RegTweak($path, $name, $val) {
    if (!(Test-Path $path)) { New-Item $path -Force | Out-Null }
    Set-ItemProperty $path $name $val -Type DWord -Force -EA 0
}

# --- GUI HELPER (FIXED POINT ERROR) ---
$Global:ToolTip = New-Object System.Windows.Forms.ToolTip
$Global:ToolTip.AutoPopDelay = 15000
$Global:ToolTip.InitialDelay = 100

function Add-Item($panel, $text, $desc, $yRaw, $varName) {
    # FIX: Явное преобразование в целое число
    $y = [int]$yRaw
    
    # Checkbox
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = $text
    $chk.Location = New-Object System.Drawing.Point(15, $y)
    $chk.AutoSize = $true
    $panel.Controls.Add($chk)
    
    # Question Mark Label (FIX: Вычисление Y отдельно)
    $lblY = $y + 3
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "[?]"
    $lbl.ForeColor = "DodgerBlue"
    $lbl.Cursor = [System.Windows.Forms.Cursors]::Hand
    $lbl.Location = New-Object System.Drawing.Point(235, $lblY) 
    $lbl.AutoSize = $true
    
    $Global:ToolTip.SetToolTip($lbl, $desc)
    $panel.Controls.Add($lbl)

    Set-Variable -Name $varName -Value $chk -Scope Script
}

# --- GUI CONSTRUCTION ---

$form = New-Object System.Windows.Forms.Form
$form.Text = "PotatoPC Optimizer v8.5"
$form.Size = New-Object System.Drawing.Size(950, 700)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::WhiteSmoke

# TABS
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(10, 10)
$tabControl.Size = New-Object System.Drawing.Size(915, 500)

# === TAB 1: PRESETS ===
$tabPresets = New-Object System.Windows.Forms.TabPage; $tabPresets.Text = " [1] ПРЕСЕТЫ "
$lblP1 = New-Object System.Windows.Forms.Label; $lblP1.Text = "Выберите режим:"; $lblP1.Location = New-Object System.Drawing.Point(20, 20); $lblP1.AutoSize=$true; $lblP1.Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)

$btnP_Safe = New-Object System.Windows.Forms.Button; $btnP_Safe.Text = "[ SAFE ]`nБезопасный"; $btnP_Safe.Location = New-Object System.Drawing.Point(50, 60); $btnP_Safe.Size = New-Object System.Drawing.Size(200, 60); $btnP_Safe.BackColor = "SeaGreen"; $btnP_Safe.ForeColor = "White"
$lblP_Safe = New-Object System.Windows.Forms.Label; $lblP_Safe.Text = "Только очистка мусора. Ничего не ломает."; $lblP_Safe.Location = New-Object System.Drawing.Point(270, 70); $lblP_Safe.AutoSize=$true

$btnP_Office = New-Object System.Windows.Forms.Button; $btnP_Office.Text = "[ OFFICE ]`nОфисный"; $btnP_Office.Location = New-Object System.Drawing.Point(50, 140); $btnP_Office.Size = New-Object System.Drawing.Size(200, 60); $btnP_Office.BackColor = "SteelBlue"; $btnP_Office.ForeColor = "White"
$lblP_Office = New-Object System.Windows.Forms.Label; $lblP_Office.Text = "Удаляет игры/Xbox. Оставляет Почту и Принтеры."; $lblP_Office.Location = New-Object System.Drawing.Point(270, 150); $lblP_Office.AutoSize=$true

$btnP_Gamer = New-Object System.Windows.Forms.Button; $btnP_Gamer.Text = "[ GAMER ]`nИгровой"; $btnP_Gamer.Location = New-Object System.Drawing.Point(50, 220); $btnP_Gamer.Size = New-Object System.Drawing.Size(200, 60); $btnP_Gamer.BackColor = "DarkOrange"; $btnP_Gamer.ForeColor = "White"
$lblP_Gamer = New-Object System.Windows.Forms.Label; $lblP_Gamer.Text = "Сохраняет Xbox/Store. Оптимизирует FPS и мышь."; $lblP_Gamer.Location = New-Object System.Drawing.Point(270, 230); $lblP_Gamer.AutoSize=$true

$btnP_Potato = New-Object System.Windows.Forms.Button; $btnP_Potato.Text = "[ POTATO ]`nМаксимум"; $btnP_Potato.Location = New-Object System.Drawing.Point(50, 300); $btnP_Potato.Size = New-Object System.Drawing.Size(200, 60); $btnP_Potato.BackColor = "Maroon"; $btnP_Potato.ForeColor = "White"
$lblP_Potato = New-Object System.Windows.Forms.Label; $lblP_Potato.Text = "Отключает ВСЁ лишнее. Для очень слабых ПК."; $lblP_Potato.Location = New-Object System.Drawing.Point(270, 310); $lblP_Potato.AutoSize=$true

$tabPresets.Controls.AddRange(@($lblP1, $btnP_Safe, $lblP_Safe, $btnP_Office, $lblP_Office, $btnP_Gamer, $lblP_Gamer, $btnP_Potato, $lblP_Potato))

# === TAB 2: TWEAKS ===
$tabTweaks = New-Object System.Windows.Forms.TabPage; $tabTweaks.Text = " [2] ТВИКИ "

# Group 1
$grpPriv = New-Object System.Windows.Forms.GroupBox; $grpPriv.Text = "Приватность"; $grpPriv.Location = New-Object System.Drawing.Point(10, 10); $grpPriv.Size = New-Object System.Drawing.Size(280, 400)
Add-Item $grpPriv "Откл. Телеметрию" "Отключает службы DiagTrack (сбор данных) и кейлоггеры Microsoft." 25 "chkTel"
Add-Item $grpPriv "Убрать Copilot" "Полностью выключает ИИ-ассистента в Windows 11/10." 55 "chkCop"
Add-Item $grpPriv "Убрать Bing (Поиск)" "Убирает результаты из интернета в меню Пуск." 85 "chkBing"

# Group 2
$grpBloat = New-Object System.Windows.Forms.GroupBox; $grpBloat.Text = "Удаление"; $grpBloat.Location = New-Object System.Drawing.Point(300, 10); $grpBloat.Size = New-Object System.Drawing.Size(280, 400)
Add-Item $grpBloat "Удалить Xbox" "Удаляет все сервисы Xbox. ВНИМАНИЕ: Игры из Store не будут работать!" 25 "chkXbox"
Add-Item $grpBloat "Удалить Почту" "Удаляет Почту и Календарь." 55 "chkMail"
Add-Item $grpBloat "Удалить Новости" "Удаляет виджет Погоды/Новостей." 85 "chkNews"
Add-Item $grpBloat "Удалить Cortana" "Удаляет голосового помощника." 115 "chkCort"
Add-Item $grpBloat "Удалить Office Hub" "Удаляет приложение 'My Office'." 145 "chkOff"

# Group 3
$grpPerf = New-Object System.Windows.Forms.GroupBox; $grpPerf.Text = "Производительность"; $grpPerf.Location = New-Object System.Drawing.Point(590, 10); $grpPerf.Size = New-Object System.Drawing.Size(280, 400)
Add-Item $grpPerf "SysMain (Авто)" "Отключает Superfetch, если SSD. Не трогает HDD." 25 "chkSysMain"
Add-Item $grpPerf "Откл. Анимации" "Убирает визуальные эффекты окон." 55 "chkAnim"
Add-Item $grpPerf "Откл. GameDVR" "Выключает фоновую запись геймплея." 85 "chkDVR"
Add-Item $grpPerf "Откл. Залипание" "Отключает окно при нажатии Shift 5 раз." 115 "chkSticky"
Add-Item $grpPerf "Откл. Гибернацию" "Освобождает место на диске C:." 145 "chkHib"
Add-Item $grpPerf "Показ расширений" "Показывает .exe, .txt и другие." 175 "chkExt"
Add-Item $grpPerf "Fix Мыши" "Отключает акселерацию для точности." 205 "chkMouse"

$btnResetSelection = New-Object System.Windows.Forms.Button; $btnResetSelection.Text = "Сбросить галочки"; $btnResetSelection.Location = New-Object System.Drawing.Point(10, 420); $btnResetSelection.Size = New-Object System.Drawing.Size(200, 30)
$tabTweaks.Controls.AddRange(@($grpPriv, $grpBloat, $grpPerf, $btnResetSelection))

# === TAB 3: APPS ===
$tabApps = New-Object System.Windows.Forms.TabPage; $tabApps.Text = " [3] МАГАЗИН "
$lblCat = New-Object System.Windows.Forms.Label; $lblCat.Text = "Категория:"; $lblCat.Location = New-Object System.Drawing.Point(10, 13); $lblCat.AutoSize=$true
$comboCat = New-Object System.Windows.Forms.ComboBox; $comboCat.Location = New-Object System.Drawing.Point(80, 10); $comboCat.Size = New-Object System.Drawing.Size(200, 25); $comboCat.DropDownStyle = "DropDownList"
$comboCat.Items.Add("ВСЕ (All)")
$txtSearch = New-Object System.Windows.Forms.TextBox; $txtSearch.Location = New-Object System.Drawing.Point(300, 10); $txtSearch.Size = New-Object System.Drawing.Size(300, 25); $txtSearch.Text = "Поиск..."
$listApps = New-Object System.Windows.Forms.CheckedListBox; $listApps.Location = New-Object System.Drawing.Point(10, 45); $listApps.Size = New-Object System.Drawing.Size(590, 400); $listApps.CheckOnClick = $true
$btnAppInstall = New-Object System.Windows.Forms.Button; $btnAppInstall.Text = "Установить"; $btnAppInstall.Location = New-Object System.Drawing.Point(620, 45); $btnAppInstall.Size = New-Object System.Drawing.Size(250, 50); $btnAppInstall.BackColor = "Green"; $btnAppInstall.ForeColor = "White"
$btnAppUpdate = New-Object System.Windows.Forms.Button; $btnAppUpdate.Text = "Обновить ВСЁ"; $btnAppUpdate.Location = New-Object System.Drawing.Point(620, 110); $btnAppUpdate.Size = New-Object System.Drawing.Size(250, 50); $btnAppUpdate.BackColor = "DarkBlue"; $btnAppUpdate.ForeColor = "White"
$lblInfo = New-Object System.Windows.Forms.Label; $lblInfo.Text = "Если установка не работает - проверьте WinGet (он установится автоматически)."; $lblInfo.Location = New-Object System.Drawing.Point(620, 180); $lblInfo.Size = New-Object System.Drawing.Size(250, 100); $lblInfo.ForeColor = "Gray"
$tabApps.Controls.AddRange(@($lblCat, $comboCat, $txtSearch, $listApps, $btnAppInstall, $btnAppUpdate, $lblInfo))

# === TAB 4: CLEANUP ===
$tabClean = New-Object System.Windows.Forms.TabPage; $tabClean.Text = " [4] ОЧИСТКА "
Add-Item $tabClean "Очистка Temp" "Удаляет временные файлы." 30 "chkTmp"; $chkTmp.Checked=$true
Add-Item $tabClean "Очистка Логов" "Очищает журнал событий Windows." 60 "chkLog"
Add-Item $tabClean "Очистка Update Cache" "Удаляет кэш обновлений." 90 "chkUpdCache"
Add-Item $tabClean "Сброс DNS" "Чистит кэш DNS." 120 "chkDns"
Add-Item $tabClean "Очистить Корзину" "Чистит корзину." 150 "chkBin"
Add-Item $tabClean "DISM Очистка" "Очистка образа Windows (долго)." 180 "chkDism"

$tabControl.Controls.AddRange(@($tabPresets, $tabTweaks, $tabApps, $tabClean))

# BOTTOM
$txtLog = New-Object System.Windows.Forms.RichTextBox; $txtLog.Location = New-Object System.Drawing.Point(10, 560); $txtLog.Size = New-Object System.Drawing.Size(915, 90); $txtLog.ReadOnly = $true; $txtLog.BackColor="White"
$btnRun = New-Object System.Windows.Forms.Button; $btnRun.Text = "ЗАПУСТИТЬ ВЫБРАННОЕ"; $btnRun.Location = New-Object System.Drawing.Point(400, 515); $btnRun.Size = New-Object System.Drawing.Size(325, 40); $btnRun.BackColor="DarkSlateGray"; $btnRun.ForeColor="White"; $btnRun.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
$chkRestore = New-Object System.Windows.Forms.CheckBox; $chkRestore.Text = "Точка восстановления"; $chkRestore.Location = New-Object System.Drawing.Point(20, 525); $chkRestore.AutoSize=$true; $chkRestore.Checked=$true; $chkRestore.ForeColor="DarkBlue"

# КНОПКА ПЕРЕЗАГРУЗКИ
$btnRestart = New-Object System.Windows.Forms.Button; $btnRestart.Text = "Перезагрузить ПК"; $btnRestart.Location = New-Object System.Drawing.Point(740, 515); $btnRestart.Size = New-Object System.Drawing.Size(180, 40); $btnRestart.BackColor="Maroon"; $btnRestart.ForeColor="White"

$form.Controls.AddRange(@($tabControl, $txtLog, $btnRun, $chkRestore, $btnRestart))

# --- 6. EVENTS & LOGIC ---

# Reset Logic
function Reset-Checkboxes {
    $tabTweaks.Controls | % { if($_ -is [System.Windows.Forms.GroupBox]){ $_.Controls | % { if($_ -is [System.Windows.Forms.CheckBox]){$_.Checked=$false} } } }
    $tabClean.Controls | % { if($_ -is [System.Windows.Forms.CheckBox]){$_.Checked=$false} }
}
$btnResetSelection.Add_Click({ Reset-Checkboxes; Log "Выбор сброшен." })

# Presets
$btnP_Safe.Add_Click({ Reset-Checkboxes; $chkTel.Checked=$true; $chkBing.Checked=$true; $chkSysMain.Checked=$true; $chkTmp.Checked=$true; $chkLog.Checked=$true; Log "Пресет: SAFE"; [System.Windows.Forms.MessageBox]::Show("SAFE режим. Нажмите ЗАПУСТИТЬ.") })
$btnP_Office.Add_Click({ Reset-Checkboxes; $chkTel.Checked=$true; $chkCop.Checked=$true; $chkBing.Checked=$true; $chkXbox.Checked=$true; $chkNews.Checked=$true; $chkSysMain.Checked=$true; $chkTmp.Checked=$true; Log "Пресет: OFFICE"; [System.Windows.Forms.MessageBox]::Show("OFFICE режим.") })
$btnP_Gamer.Add_Click({ Reset-Checkboxes; $chkTel.Checked=$true; $chkCop.Checked=$true; $chkBing.Checked=$true; $chkMail.Checked=$true; $chkNews.Checked=$true; $chkCort.Checked=$true; $chkOff.Checked=$true; $chkSysMain.Checked=$true; $chkAnim.Checked=$true; $chkDVR.Checked=$true; $chkMouse.Checked=$true; $chkSticky.Checked=$true; $chkTmp.Checked=$true; Log "Пресет: GAMER"; [System.Windows.Forms.MessageBox]::Show("GAMER режим.") })
$btnP_Potato.Add_Click({ Reset-Checkboxes; $tabTweaks.Controls | % { if($_ -is [System.Windows.Forms.GroupBox]){ $_.Controls | % { if($_ -is [System.Windows.Forms.CheckBox]){$_.Checked=$true} } } }; $tabClean.Controls | % { if($_ -is [System.Windows.Forms.CheckBox]){$_.Checked=$true} }; $chkDism.Checked=$false; Log "Пресет: POTATO"; [System.Windows.Forms.MessageBox]::Show("POTATO режим.") })

# Apps
$Global:Apps = @()
try { $json = Invoke-RestMethod $AppsJsonUrl -UseBasicParsing -TimeoutSec 5; if ($json.ManualCategories) { $json.ManualCategories.PSObject.Properties | % { $cat=$_.Name; $comboCat.Items.Add($cat); $_.Value | % { $_.PSObject.Properties.Add((New-Object PSNoteProperty("Category", $cat))); $_.PSObject.Properties.Add((New-Object PSNoteProperty("Display", "$($_.Name)"))); $Global:Apps += $_ } } } } catch { Log "Ошибка Apps JSON." "Red" }
$comboCat.SelectedIndex = 0
$listApps.Add_ItemCheck({ $id = ($Global:Apps | Where {$_.Display -eq $listApps.Items[$_.Index]}).Id; if ($_.NewValue -eq 'Checked') { $Global:SelectedAppIDs.Add($id)|Out-Null } else { $Global:SelectedAppIDs.Remove($id)|Out-Null } })
function Refresh-Apps { $cat=$comboCat.SelectedItem; $f=$txtSearch.Text; if($f-eq"Поиск..."){$f=""}; $listApps.Items.Clear(); $sub=$Global:Apps|Where{($cat-eq"ВСЕ (All)"-or$_.Category-eq$cat)-and($_.Name-match$f)}; foreach($a in $sub){ $idx=$listApps.Items.Add($a.Display); if($Global:SelectedAppIDs.Contains($a.Id)){$listApps.SetItemChecked($idx,$true)} } }
$comboCat.Add_SelectedIndexChanged({Refresh-Apps}); $txtSearch.Add_KeyUp({Refresh-Apps}); $txtSearch.Add_Click({if($txtSearch.Text-eq"Поиск..."){$txtSearch.Text=""}})

# Install/Update
$btnAppInstall.Add_Click({ 
    if(!(Get-Command winget -EA 0)){ if(!(Fix-Winget)){ return } }
    if ($Global:SelectedAppIDs.Count -gt 0) { $Global:SelectedAppIDs | % { Log "Установка: $_" "Blue"; Start-Process winget -ArgumentList "install --id $_ -e --silent --accept-package-agreements --accept-source-agreements" -Wait } } 
})
$btnAppUpdate.Add_Click({ 
    if(!(Get-Command winget -EA 0)){ if(!(Fix-Winget)){ return } }
    Log "Обновление..." "Blue"; Start-Process winget -ArgumentList "upgrade --all --include-unknown --accept-source-agreements" -Wait; Log "Готово." "Green" 
})

# Run Main
$btnRun.Add_Click({
    $form.Cursor=[System.Windows.Forms.Cursors]::WaitCursor; $form.Enabled=$false
    if ($chkRestore.Checked) { Log "Точка восстановления..." "Blue"; Enable-ComputerRestore -Drive "C:\" -EA 0; Checkpoint-Computer -Description "PotatoPC" -RestorePointType "MODIFY_SETTINGS" -EA 0 }
    
    if($chkTel.Checked){Core-KillService "DiagTrack";Core-KillService "dmwappushservice";Core-RegTweak "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0}
    if($chkCop.Checked){Core-RegTweak "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1}
    if($chkBing.Checked){Core-RegTweak "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1}
    
    if($chkXbox.Checked){("XboxApp","GamingApp","XboxGamingOverlay","Xbox.TCUI")|%{Core-RemoveApp $_};("XblAuthManager","XblGameSave","XboxNetApiSvc")|%{Core-KillService $_}}
    if($chkMail.Checked){Core-RemoveApp "windowscommunicationsapps"}
    if($chkNews.Checked){Core-RemoveApp "BingNews";Core-RemoveApp "BingWeather";Core-RegTweak "HKCU:\Software\Microsoft\Windows\CurrentVersio
