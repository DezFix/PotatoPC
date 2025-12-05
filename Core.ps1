# ==========================================
# POTATO PC OPTIMIZER v0.2 (PRESETS UPDATE)
# ==========================================

# --- 1. AUTO-ELEVATE ---
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (!($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    $scriptPath = $MyInvocation.MyCommand.Definition
    if ([string]::IsNullOrWhiteSpace($scriptPath)) { Write-Host "Ошибка путей. Сохраните файл."; Read-Host; exit }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    exit
}

# --- 2. НАСТРОЙКИ ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$WorkDir   = "C:\PotatoPC"
$BackupDir = "$WorkDir\Backups"
$TempDir   = "$WorkDir\Temp"
$AppsJsonUrl = "https://raw.githubusercontent.com/DezFix/PotatoPC/main/apps.json"

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
$Global:SelectedAppIDs = new-object System.Collections.Generic.HashSet[string]

# --- 3. ФУНКЦИИ ---

function Log($text, $color="Black") {
    $txtLog.SelectionColor = [System.Drawing.Color]::FromName($color)
    $txtLog.AppendText("[$([DateTime]::Now.ToString('HH:mm:ss'))] $text`r`n")
    $txtLog.ScrollToCaret()
}

function Add-Tooltip($ctrl, $text) {
    $tt = New-Object System.Windows.Forms.ToolTip
    $tt.AutoPopDelay = 10000
    $tt.InitialDelay = 500
    $tt.SetToolTip($ctrl, $text)
}

function Core-KillService($Name) {
    $services = Get-Service $Name -ErrorAction SilentlyContinue
    foreach ($s in $services) {
        if ($s.Status -ne 'Stopped' -or $s.StartType -ne 'Disabled') {
            Log "Отключение службы: $($s.Name)" "DarkMagenta"
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
        Log "Удаление пакета: $($a.Name)" "Red"
        Remove-AppxPackage -Package $a.PackageFullName -AllUsers -EA 0
    }
}

function Core-RegTweak($path, $name, $val) {
    if (!(Test-Path $path)) { New-Item $path -Force | Out-Null }
    Set-ItemProperty $path $name $val -Type DWord -Force -EA 0
}

# --- 4. GUI ---

$form = New-Object System.Windows.Forms.Form
$form.Text = "PotatoPC Optimizer v0.2"
$form.Size = New-Object System.Drawing.Size(950, 700)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::WhiteSmoke

# TABS
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(10, 10)
$tabControl.Size = New-Object System.Drawing.Size(915, 500)

# === TAB 1: PRESETS (ТЕПЕРЬ ПЕРВАЯ) ===
$tabPresets = New-Object System.Windows.Forms.TabPage; $tabPresets.Text = " [1] ПРЕСЕТЫ (Авто) "
$lblP1 = New-Object System.Windows.Forms.Label; $lblP1.Text = "Выберите режим оптимизации:"; $lblP1.Location = New-Object System.Drawing.Point(20, 20); $lblP1.AutoSize=$true; $lblP1.Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)

# SAFE
$btnP_Safe = New-Object System.Windows.Forms.Button; $btnP_Safe.Text = "[ SAFE ]`nБезопасный"; $btnP_Safe.Location = New-Object System.Drawing.Point(50, 60); $btnP_Safe.Size = New-Object System.Drawing.Size(200, 60); $btnP_Safe.BackColor = "SeaGreen"; $btnP_Safe.ForeColor = "White"
$lblP_Safe = New-Object System.Windows.Forms.Label; $lblP_Safe.Text = "Только очистка мусора. Ничего не удаляет, ничего не ломает.`nПодходит для любых ПК."; $lblP_Safe.Location = New-Object System.Drawing.Point(270, 70); $lblP_Safe.AutoSize=$true

# OFFICE
$btnP_Office = New-Object System.Windows.Forms.Button; $btnP_Office.Text = "[ OFFICE ]`nОфисный ПК"; $btnP_Office.Location = New-Object System.Drawing.Point(50, 140); $btnP_Office.Size = New-Object System.Drawing.Size(200, 60); $btnP_Office.BackColor = "SteelBlue"; $btnP_Office.ForeColor = "White"
$lblP_Office = New-Object System.Windows.Forms.Label; $lblP_Office.Text = "Удаляет игры и Xbox. Оставляет Почту, Office, Принтеры.`nОтключает телеметрию, но сохраняет красивый вид Windows."; $lblP_Office.Location = New-Object System.Drawing.Point(270, 150); $lblP_Office.AutoSize=$true

# GAMER
$btnP_Gamer = New-Object System.Windows.Forms.Button; $btnP_Gamer.Text = "[ GAMER ]`nИгровой"; $btnP_Gamer.Location = New-Object System.Drawing.Point(50, 220); $btnP_Gamer.Size = New-Object System.Drawing.Size(200, 60); $btnP_Gamer.BackColor = "DarkOrange"; $btnP_Gamer.ForeColor = "White"
$lblP_Gamer = New-Object System.Windows.Forms.Label; $lblP_Gamer.Text = "Ускоряет систему (MouseFix, PowerPlan).`nНЕ УДАЛЯЕТ Xbox (можно играть в GamePass). Удаляет остальной мусор."; $lblP_Gamer.Location = New-Object System.Drawing.Point(270, 230); $lblP_Gamer.AutoSize=$true

# POTATO
$btnP_Potato = New-Object System.Windows.Forms.Button; $btnP_Potato.Text = "[ POTATO ]`nМаксимум"; $btnP_Potato.Location = New-Object System.Drawing.Point(50, 300); $btnP_Potato.Size = New-Object System.Drawing.Size(200, 60); $btnP_Potato.BackColor = "Maroon"; $btnP_Potato.ForeColor = "White"
$lblP_Potato = New-Object System.Windows.Forms.Label; $lblP_Potato.Text = "Отключает ВСЁ лишнее. Xbox, Почту, Анимации, ИИ, Службы.`nТолько для максимального FPS на слабых ПК."; $lblP_Potato.Location = New-Object System.Drawing.Point(270, 310); $lblP_Potato.AutoSize=$true

$tabPresets.Controls.AddRange(@($lblP1, $btnP_Safe, $lblP_Safe, $btnP_Office, $lblP_Office, $btnP_Gamer, $lblP_Gamer, $btnP_Potato, $lblP_Potato))


# === TAB 2: TWEAKS ===
$tabTweaks = New-Object System.Windows.Forms.TabPage; $tabTweaks.Text = " [2] ТВИКИ (Вручную) "

# Privacy
$grpPriv = New-Object System.Windows.Forms.GroupBox; $grpPriv.Text = "Приватность"; $grpPriv.Location = New-Object System.Drawing.Point(10, 10); $grpPriv.Size = New-Object System.Drawing.Size(280, 400)
$chkTel = New-Object System.Windows.Forms.CheckBox; $chkTel.Text = "Отключить Телеметрию"; $chkTel.Location = New-Object System.Drawing.Point(15, 25); $chkTel.AutoSize=$true
$chkCop = New-Object System.Windows.Forms.CheckBox; $chkCop.Text = "Убрать Copilot (AI)"; $chkCop.Location = New-Object System.Drawing.Point(15, 55); $chkCop.AutoSize=$true
$chkBing = New-Object System.Windows.Forms.CheckBox; $chkBing.Text = "Убрать Bing из Поиска"; $chkBing.Location = New-Object System.Drawing.Point(15, 85); $chkBing.AutoSize=$true
$grpPriv.Controls.AddRange(@($chkTel, $chkCop, $chkBing))

# Bloatware
$grpBloat = New-Object System.Windows.Forms.GroupBox; $grpBloat.Text = "Встроенный мусор"; $grpBloat.Location = New-Object System.Drawing.Point(300, 10); $grpBloat.Size = New-Object System.Drawing.Size(280, 400)
$chkXbox = New-Object System.Windows.Forms.CheckBox; $chkXbox.Text = "Удалить Xbox (+Services)"; $chkXbox.Location = New-Object System.Drawing.Point(15, 25); $chkXbox.AutoSize=$true
Add-Tooltip $chkXbox "ВНИМАНИЕ: Удалив это, вы не сможете играть в игры Microsoft Store."
$chkMail = New-Object System.Windows.Forms.CheckBox; $chkMail.Text = "Удалить Почту и Календарь"; $chkMail.Location = New-Object System.Drawing.Point(15, 55); $chkMail.AutoSize=$true
$chkNews = New-Object System.Windows.Forms.CheckBox; $chkNews.Text = "Удалить Новости/Погоду"; $chkNews.Location = New-Object System.Drawing.Point(15, 85); $chkNews.AutoSize=$true
$chkCort = New-Object System.Windows.Forms.CheckBox; $chkCort.Text = "Удалить Cortana/People"; $chkCort.Location = New-Object System.Drawing.Point(15, 115); $chkCort.AutoSize=$true
$chkOff = New-Object System.Windows.Forms.CheckBox; $chkOff.Text = "Удалить Office Hub"; $chkOff.Location = New-Object System.Drawing.Point(15, 145); $chkOff.AutoSize=$true
$grpBloat.Controls.AddRange(@($chkXbox, $chkMail, $chkNews, $chkCort, $chkOff))

# Performance
$grpPerf = New-Object System.Windows.Forms.GroupBox; $grpPerf.Text = "Производительность"; $grpPerf.Location = New-Object System.Drawing.Point(590, 10); $grpPerf.Size = New-Object System.Drawing.Size(280, 400)
$chkSysMain = New-Object System.Windows.Forms.CheckBox; $chkSysMain.Text = "SysMain (Авто-SSD)"; $chkSysMain.Location = New-Object System.Drawing.Point(15, 25); $chkSysMain.AutoSize=$true
$chkAnim = New-Object System.Windows.Forms.CheckBox; $chkAnim.Text = "Отключить Анимации"; $chkAnim.Location = New-Object System.Drawing.Point(15, 55); $chkAnim.AutoSize=$true
$chkDVR = New-Object System.Windows.Forms.CheckBox; $chkDVR.Text = "Отключить GameDVR"; $chkDVR.Location = New-Object System.Drawing.Point(15, 85); $chkDVR.AutoSize=$true
$chkSticky = New-Object System.Windows.Forms.CheckBox; $chkSticky.Text = "Отключить залипание (Shift)"; $chkSticky.Location = New-Object System.Drawing.Point(15, 115); $chkSticky.AutoSize=$true
$chkHib = New-Object System.Windows.Forms.CheckBox; $chkHib.Text = "Отключить Гибернацию"; $chkHib.Location = New-Object System.Drawing.Point(15, 145); $chkHib.AutoSize=$true
$chkExt = New-Object System.Windows.Forms.CheckBox; $chkExt.Text = "Показывать расширения файлов"; $chkExt.Location = New-Object System.Drawing.Point(15, 175); $chkExt.AutoSize=$true
$chkMouse = New-Object System.Windows.Forms.CheckBox; $chkMouse.Text = "Откл. акселерацию мыши"; $chkMouse.Location = New-Object System.Drawing.Point(15, 205); $chkMouse.AutoSize=$true

$grpPerf.Controls.AddRange(@($chkSysMain, $chkAnim, $chkDVR, $chkSticky, $chkHib, $chkExt, $chkMouse))

# КНОПКА СБРОСА (Перенесена сюда)
$btnResetSelection = New-Object System.Windows.Forms.Button; $btnResetSelection.Text = "Сбросить все галочки"; $btnResetSelection.Location = New-Object System.Drawing.Point(10, 420); $btnResetSelection.Size = New-Object System.Drawing.Size(200, 30)
$tabTweaks.Controls.AddRange(@($grpPriv, $grpBloat, $grpPerf, $btnResetSelection))


# === TAB 3: APPS ===
$tabApps = New-Object System.Windows.Forms.TabPage; $tabApps.Text = " [3] МАГАЗИН "
$lblCat = New-Object System.Windows.Forms.Label; $lblCat.Text = "Категория:"; $lblCat.Location = New-Object System.Drawing.Point(10, 13); $lblCat.AutoSize=$true
$comboCat = New-Object System.Windows.Forms.ComboBox; $comboCat.Location = New-Object System.Drawing.Point(80, 10); $comboCat.Size = New-Object System.Drawing.Size(200, 25); $comboCat.DropDownStyle = "DropDownList"
$comboCat.Items.Add("ВСЕ (All)")
$txtSearch = New-Object System.Windows.Forms.TextBox; $txtSearch.Location = New-Object System.Drawing.Point(300, 10); $txtSearch.Size = New-Object System.Drawing.Size(300, 25); $txtSearch.Text = "Поиск..."
$listApps = New-Object System.Windows.Forms.CheckedListBox; $listApps.Location = New-Object System.Drawing.Point(10, 45); $listApps.Size = New-Object System.Drawing.Size(590, 400); $listApps.CheckOnClick = $true
$btnAppInstall = New-Object System.Windows.Forms.Button; $btnAppInstall.Text = "Установить выбранное"; $btnAppInstall.Location = New-Object System.Drawing.Point(620, 45); $btnAppInstall.Size = New-Object System.Drawing.Size(250, 50); $btnAppInstall.BackColor = "Green"; $btnAppInstall.ForeColor = "White"
$btnAppUpdate = New-Object System.Windows.Forms.Button; $btnAppUpdate.Text = "Обновить ВСЁ на ПК"; $btnAppUpdate.Location = New-Object System.Drawing.Point(620, 110); $btnAppUpdate.Size = New-Object System.Drawing.Size(250, 50); $btnAppUpdate.BackColor = "DarkBlue"; $btnAppUpdate.ForeColor = "White"
$lblInfo = New-Object System.Windows.Forms.Label; $lblInfo.Text = "Выбор сохраняется при смене категории."; $lblInfo.Location = New-Object System.Drawing.Point(620, 180); $lblInfo.Size = New-Object System.Drawing.Size(250, 100); $lblInfo.ForeColor = "Gray"
$tabApps.Controls.AddRange(@($lblCat, $comboCat, $txtSearch, $listApps, $btnAppInstall, $btnAppUpdate, $lblInfo))

# === TAB 4: CLEANUP ===
$tabClean = New-Object System.Windows.Forms.TabPage; $tabClean.Text = " [4] ОЧИСТКА "
$chkTmp = New-Object System.Windows.Forms.CheckBox; $chkTmp.Text = "Очистка Temp (Временные файлы)"; $chkTmp.Location = New-Object System.Drawing.Point(20, 30); $chkTmp.AutoSize=$true; $chkTmp.Checked=$true
$chkLog = New-Object System.Windows.Forms.CheckBox; $chkLog.Text = "Очистка Журналов (Event Logs)"; $chkLog.Location = New-Object System.Drawing.Point(20, 70); $chkLog.AutoSize=$true
$chkUpdCache = New-Object System.Windows.Forms.CheckBox; $chkUpdCache.Text = "Кэш обновлений (SoftwareDistribution)"; $chkUpdCache.Location = New-Object System.Drawing.Point(20, 110); $chkUpdCache.AutoSize=$true
$chkDns = New-Object System.Windows.Forms.CheckBox; $chkDns.Text = "Сброс кэша DNS"; $chkDns.Location = New-Object System.Drawing.Point(20, 150); $chkDns.AutoSize=$true
$chkBin = New-Object System.Windows.Forms.CheckBox; $chkBin.Text = "Очистить Корзину"; $chkBin.Location = New-Object System.Drawing.Point(20, 190); $chkBin.AutoSize=$true
$chkDism = New-Object System.Windows.Forms.CheckBox; $chkDism.Text = "Очистка образа (DISM)"; $chkDism.Location = New-Object System.Drawing.Point(20, 230); $chkDism.AutoSize=$true
$tabClean.Controls.AddRange(@($chkTmp, $chkLog, $chkUpdCache, $chkDns, $chkBin, $chkDism))

# Порядок вкладок: ПРЕСЕТЫ -> ТВИКИ -> МАГАЗИН -> ОЧИСТКА
$tabControl.Controls.AddRange(@($tabPresets, $tabTweaks, $tabApps, $tabClean))

# BOTTOM
$txtLog = New-Object System.Windows.Forms.RichTextBox; $txtLog.Location = New-Object System.Drawing.Point(10, 560); $txtLog.Size = New-Object System.Drawing.Size(915, 90); $txtLog.ReadOnly = $true; $txtLog.BackColor="White"
$btnRun = New-Object System.Windows.Forms.Button; $btnRun.Text = "ЗАПУСТИТЬ ВЫБРАННОЕ"; $btnRun.Location = New-Object System.Drawing.Point(600, 515); $btnRun.Size = New-Object System.Drawing.Size(325, 40); $btnRun.BackColor="DarkSlateGray"; $btnRun.ForeColor="White"; $btnRun.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
$chkRestore = New-Object System.Windows.Forms.CheckBox; $chkRestore.Text = "Создать точку восстановления (Рекомендуется)"; $chkRestore.Location = New-Object System.Drawing.Point(20, 525); $chkRestore.AutoSize=$true; $chkRestore.Checked=$true; $chkRestore.ForeColor="DarkBlue"
$form.Controls.AddRange(@($tabControl, $txtLog, $btnRun, $chkRestore))

# --- 5. LOGIC & EVENTS ---

# Загрузка JSON
$Global:Apps = @()
try {
    $json = Invoke-RestMethod $AppsJsonUrl -UseBasicParsing -TimeoutSec 5
    if ($json.ManualCategories) {
        $json.ManualCategories.PSObject.Properties | % { 
            $cat=$_.Name
            $comboCat.Items.Add($cat)
            $_.Value | % { 
                $_.PSObject.Properties.Add((New-Object PSNoteProperty("Category", $cat)))
                $_.PSObject.Properties.Add((New-Object PSNoteProperty("Display", "$($_.Name)")))
                $Global:Apps += $_ 
            }
        }
    }
} catch { Log "Ошибка загрузки Apps JSON." "Red" }
$comboCat.SelectedIndex = 0

# App Logic
$listApps.Add_ItemCheck({
    $id = ($Global:Apps | Where {$_.Display -eq $listApps.Items[$_.Index]}).Id
    if ($_.NewValue -eq 'Checked') { $Global:SelectedAppIDs.Add($id) | Out-Null }
    else { $Global:SelectedAppIDs.Remove($id) | Out-Null }
})
function Refresh-AppList {
    $cat = $comboCat.SelectedItem
    $filter = $txtSearch.Text
    if ($filter -eq "Поиск...") { $filter = "" }
    $listApps.Items.Clear()
    $subset = $Global:Apps | Where { ($cat -eq "ВСЕ (All)" -or $_.Category -eq $cat) -and ($_.Name -match $filter) }
    foreach ($app in $subset) {
        $idx = $listApps.Items.Add($app.Display)
        if ($Global:SelectedAppIDs.Contains($app.Id)) { $listApps.SetItemChecked($idx, $true) }
    }
}
$comboCat.Add_SelectedIndexChanged({ Refresh-AppList })
$txtSearch.Add_KeyUp({ Refresh-AppList })
$txtSearch.Add_Click({ if($txtSearch.Text -eq "Поиск..."){$txtSearch.Text=""} })

# PRESETS LOGIC (RESET FUNCTION)
function Reset-Checkboxes {
    $tabTweaks.Controls | % { $_.Controls | % { if($_ -is [System.Windows.Forms.CheckBox]){$_.Checked=$false} } }
    $tabClean.Controls | % { if($_ -is [System.Windows.Forms.CheckBox]){$_.Checked=$false} }
}

$btnResetSelection.Add_Click({
    Reset-Checkboxes
    Log "Сброс выбора."
})

# [SAFE]
$btnP_Safe.Add_Click({
    Reset-Checkboxes
    $chkTel.Checked=$true; $chkBing.Checked=$true; $chkSysMain.Checked=$true
    $chkTmp.Checked=$true; $chkLog.Checked=$true; $chkDns.Checked=$true
    Log "Пресет: SAFE" "Green"
    [System.Windows.Forms.MessageBox]::Show("Выбран пресет SAFE. Перейдите в другие вкладки или нажмите ЗАПУСТИТЬ.")
})

# [OFFICE] - Удаляем Xbox, оставляем Почту, Красоту
$btnP_Office.Add_Click({
    Reset-Checkboxes
    $chkTel.Checked=$true; $chkCop.Checked=$true; $chkBing.Checked=$true
    $chkXbox.Checked=$true # Удаляем Xbox для работы
    $chkNews.Checked=$true
    $chkSysMain.Checked=$true
    $chkTmp.Checked=$true; $chkLog.Checked=$true
    Log "Пресет: OFFICE" "Blue"
    [System.Windows.Forms.MessageBox]::Show("Выбран пресет OFFICE (Без игр).")
})

# [GAMER] - Оставляем Xbox, удаляем остальное, Твики скорости
$btnP_Gamer.Add_Click({
    Reset-Checkboxes
    $chkTel.Checked=$true; $chkCop.Checked=$true; $chkBing.Checked=$true
    # Xbox НЕ трогаем!
    $chkMail.Checked=$true; $chkNews.Checked=$true; $chkCort.Checked=$true; $chkOff.Checked=$true
    $chkSysMain.Checked=$true; $chkAnim.Checked=$true; $chkDVR.Checked=$true # DVR выкл для FPS
    $chkMouse.Checked=$true; $chkSticky.Checked=$true
    $chkTmp.Checked=$true
    Log "Пресет: GAMER" "Orange"
    [System.Windows.Forms.MessageBox]::Show("Выбран пресет GAMER (Игры работают, FPS выше).")
})

# [POTATO]
$btnP_Potato.Add_Click({
    $tabTweaks.Controls | % { $_.Controls | % { if($_ -is [System.Windows.Forms.CheckBox]){$_.Checked=$true} } }
    $tabClean.Controls | % { if($_ -is [System.Windows.Forms.CheckBox]){$_.Checked=$true} }
    $chkDism.Checked=$false # Слишком долго
    Log "Пресет: POTATO" "Red"
    [System.Windows.Forms.MessageBox]::Show("Выбран пресет POTATO (Максимум).")
})

# RUN
$btnRun.Add_Click({
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor; $form.Enabled = $false
    
    if ($chkRestore.Checked) { Log "Создание точки восстановления..." "DarkBlue"; Enable-ComputerRestore -Drive "C:\" -EA 0; Checkpoint-Computer -Description "PotatoPC" -RestorePointType "MODIFY_SETTINGS" -EA 0 }

    # Privacy
    if ($chkTel.Checked) { Core-KillService "DiagTrack"; Core-KillService "dmwappushservice"; Core-RegTweak "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0 }
    if ($chkCop.Checked) { Core-RegTweak "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1 }
    if ($chkBing.Checked) { Core-RegTweak "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1 }
    
    # Bloatware
    if ($chkXbox.Checked) { ("XboxApp","GamingApp","XboxGamingOverlay","Xbox.TCUI") | % { Core-RemoveApp $_ }; ("XblAuthManager","XblGameSave","XboxNetApiSvc") | % { Core-KillService $_ } }
    if ($chkMail.Checked) { Core-RemoveApp "windowscommunicationsapps" }
    if ($chkNews.Checked) { Core-RemoveApp "BingNews"; Core-RemoveApp "BingWeather"; Core-RegTweak "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa" 0 }
    if ($chkCort.Checked) { Core-RemoveApp "Cortana"; Core-RemoveApp "People" }
    if ($chkOff.Checked) { Core-RemoveApp "MicrosoftOfficeHub" }

    # Perf
    if ($chkSysMain.Checked) { $ssd = Get-PhysicalDisk | Where {$_.MediaType -eq 'SSD'}; if ($ssd) { Core-KillService "SysMain" } }
    if ($chkAnim.Checked) { Core-RegTweak "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2 }
    if ($chkDVR.Checked) { Core-RegTweak "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0; Core-KillService "BcastDVRUserService*" }
    if ($chkSticky.Checked) { Core-RegTweak "HKCU:\Control Panel\Accessibility\StickyKeys" "Flags" 506 }
    if ($chkHib.Checked) { powercfg -h off }
    if ($chkExt.Checked) { Core-RegTweak "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt" 0 }
    if ($chkMouse.Checked) { Core-RegTweak "HKCU:\Control Panel\Mouse" "MouseSpeed" 0; Core-RegTweak "HKCU:\Control Panel\Mouse" "MouseThreshold1" 0; Core-RegTweak "HKCU:\Control Panel\Mouse" "MouseThreshold2" 0 }

    # Clean
    if ($chkTmp.Checked) { Remove-Item "$env:TEMP\*" -Recurse -Force -EA 0; Log "Temp очищен." }
    if ($chkLog.Checked) { Get-WinEvent -ListLog * -EA 0 | % { Wevtutil cl $_.LogName 2>$null }; Log "Логи очищены." }
    if ($chkUpdCache.Checked) { Stop-Service wuauserv -Force -EA 0; Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -EA 0; Start-Service wuauserv -EA 0 }
    if ($chkDns.Checked) { Clear-DnsClientCache }
    if ($chkBin.Checked) { Clear-RecycleBin -Force -EA 0 }
    if ($chkDism.Checked) { Log "DISM (Ждите)..." "Orange"; Dism.exe /online /Cleanup-Image /StartComponentCleanup | Out-Null }

    $form.Enabled = $true; $form.Cursor = [System.Windows.Forms.Cursors]::Default
    [System.Windows.Forms.MessageBox]::Show("Готово!")
})

$btnAppInstall.Add_Click({ if ($Global:SelectedAppIDs.Count -gt 0) { $Global:SelectedAppIDs | % { Start-Process winget -ArgumentList "install --id $_ -e --silent --accept-package-agreements --accept-source-agreements" -Wait } } })
$btnAppUpdate.Add_Click({ Start-Process winget -ArgumentList "upgrade --all --include-unknown --accept-source-agreements" -Wait })

$form.ShowDialog()
