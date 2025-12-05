# ==========================================
# POTATO PC OPTIMIZER v7.0 (GUI EDITION)
# ==========================================

# --- 1. AUTO-ELEVATE ---
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (!($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    $scriptPath = $MyInvocation.MyCommand.Definition
    if ([string]::IsNullOrWhiteSpace($scriptPath)) { Write-Host "Сохраните файл!"; Read-Host; exit }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    exit
}

# --- 2. LIBRARIES & SETUP ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$BackupDir = "C:\PotatoPC_Backups"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
$AppsJsonUrl = "https://raw.githubusercontent.com/DezFix/PotatoPC/main/apps.json"

# --- 3. CORE FUNCTIONS (ЛОГИКА) ---

function Log($text, $color="Black") {
    $txtLog.SelectionColor = [System.Drawing.Color]::FromName($color)
    $txtLog.AppendText("[$([DateTime]::Now.ToString('HH:mm:ss'))] $text`r`n")
    $txtLog.ScrollToCaret()
    $form.Refresh()
}

function Core-CreateRestorePoint {
    Log "Создание точки восстановления..." "DarkBlue"
    Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
    try {
        Checkpoint-Computer -Description "PotatoPC_GUI" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Log "Точка создана успешно." "Green"
    } catch {
        Log "ОШИБКА создания точки. Проверьте защиту системы." "Red"
    }
}

function Core-KillService($Name) {
    $services = Get-Service $Name -ErrorAction SilentlyContinue
    foreach ($s in $services) {
        if ($s.Status -ne 'Stopped' -or $s.StartType -ne 'Disabled') {
            Log "Отключение службы: $($s.Name)" "DarkMagenta"
            # Бэкап
            [PSCustomObject]@{Name=$s.Name;Start=$s.StartType;Status=$s.Status} | Export-Csv "$BackupDir\Services.csv" -Append -NoType -Force
            Stop-Service $s.Name -Force -ErrorAction SilentlyContinue
            Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.Name)" "Start" 4 -Type DWord -Force -EA 0
        }
    }
}

function Core-RemoveApp($Pattern) {
    $White = @("Microsoft.WindowsStore", "Microsoft.DesktopAppInstaller", "Microsoft.Windows.Photos", "Microsoft.WindowsCalculator")
    $apps = Get-AppxPackage -AllUsers | Where {$_.Name -like "*$Pattern*" -and $_.Name -notin $White}
    foreach ($a in $apps) {
        Log "Удаление Appx: $($a.Name)" "Red"
        Remove-AppxPackage -Package $a.PackageFullName -AllUsers -EA SilentlyContinue
    }
}

function Core-SysMain {
    Log "Проверка диска для SysMain..." "Black"
    $ssd = Get-PhysicalDisk | Where {$_.MediaType -eq 'SSD'}
    if ($ssd) { Core-KillService "SysMain"; Log "SSD найден -> SysMain выключен." "Green" }
    else { Log "HDD найден -> SysMain оставлен." "DarkGoldenrod" }
}

function Core-RegTweak($path, $name, $val) {
    if (!(Test-Path $path)) { New-Item $path -Force | Out-Null }
    Set-ItemProperty $path $name $val -Type DWord -Force -EA 0
}

# --- 4. GUI CONSTRUCTION ---

# Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "PotatoPC Optimizer v7.0"
$form.Size = New-Object System.Drawing.Size(900, 650)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::WhiteSmoke

# Tabs
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(10, 10)
$tabControl.Size = New-Object System.Drawing.Size(865, 450)

# --- TAB 1: TWEAKS ---
$tabTweaks = New-Object System.Windows.Forms.TabPage
$tabTweaks.Text = " 🛠️ Твики и Оптимизация "
$tabTweaks.BackColor = "White"

# Group: Privacy
$grpPriv = New-Object System.Windows.Forms.GroupBox
$grpPriv.Text = "Приватность и Телеметрия"
$grpPriv.Location = New-Object System.Drawing.Point(10, 10)
$grpPriv.Size = New-Object System.Drawing.Size(270, 400)

$chkTelemetry = New-Object System.Windows.Forms.CheckBox; $chkTelemetry.Text = "Отключить Телеметрию"; $chkTelemetry.Location = New-Object System.Drawing.Point(10, 20); $chkTelemetry.AutoSize = $true
$chkCopilot   = New-Object System.Windows.Forms.CheckBox; $chkCopilot.Text = "Убить Copilot (AI)"; $chkCopilot.Location = New-Object System.Drawing.Point(10, 50); $chkCopilot.AutoSize = $true
$chkBing      = New-Object System.Windows.Forms.CheckBox; $chkBing.Text = "Убрать Bing из Поиска"; $chkBing.Location = New-Object System.Drawing.Point(10, 80); $chkBing.AutoSize = $true
$chkLocation  = New-Object System.Windows.Forms.CheckBox; $chkLocation.Text = "Отключить отслеживание"; $chkLocation.Location = New-Object System.Drawing.Point(10, 110); $chkLocation.AutoSize = $true
$grpPriv.Controls.AddRange(@($chkTelemetry, $chkCopilot, $chkBing, $chkLocation))

# Group: Bloatware
$grpBloat = New-Object System.Windows.Forms.GroupBox
$grpBloat.Text = "Удаление Мусора"
$grpBloat.Location = New-Object System.Drawing.Point(290, 10)
$grpBloat.Size = New-Object System.Drawing.Size(270, 400)

$chkXbox    = New-Object System.Windows.Forms.CheckBox; $chkXbox.Text = "Удалить Xbox (+Services)"; $chkXbox.Location = New-Object System.Drawing.Point(10, 20); $chkXbox.AutoSize = $true
$chkMail    = New-Object System.Windows.Forms.CheckBox; $chkMail.Text = "Удалить Почту и Календарь"; $chkMail.Location = New-Object System.Drawing.Point(10, 50); $chkMail.AutoSize = $true
$chkNews    = New-Object System.Windows.Forms.CheckBox; $chkNews.Text = "Удалить Новости/Погоду"; $chkNews.Location = New-Object System.Drawing.Point(10, 80); $chkNews.AutoSize = $true
$chkCortana = New-Object System.Windows.Forms.CheckBox; $chkCortana.Text = "Удалить Cortana/People"; $chkCortana.Location = New-Object System.Drawing.Point(10, 110); $chkCortana.AutoSize = $true
$chkOffice  = New-Object System.Windows.Forms.CheckBox; $chkOffice.Text = "Удалить Office Hub/OneNote"; $chkOffice.Location = New-Object System.Drawing.Point(10, 140); $chkOffice.AutoSize = $true
$grpBloat.Controls.AddRange(@($chkXbox, $chkMail, $chkNews, $chkCortana, $chkOffice))

# Group: Performance
$grpPerf = New-Object System.Windows.Forms.GroupBox
$grpPerf.Text = "Производительность"
$grpPerf.Location = New-Object System.Drawing.Point(570, 10)
$grpPerf.Size = New-Object System.Drawing.Size(270, 400)

$chkSysMain   = New-Object System.Windows.Forms.CheckBox; $chkSysMain.Text = "SysMain (Авто-SSD)"; $chkSysMain.Location = New-Object System.Drawing.Point(10, 20); $chkSysMain.AutoSize = $true
$chkAnim      = New-Object System.Windows.Forms.CheckBox; $chkAnim.Text = "Отключить Анимации (Visual)"; $chkAnim.Location = New-Object System.Drawing.Point(10, 50); $chkAnim.AutoSize = $true
$chkGameDVR   = New-Object System.Windows.Forms.CheckBox; $chkGameDVR.Text = "Отключить GameDVR"; $chkGameDVR.Location = New-Object System.Drawing.Point(10, 80); $chkGameDVR.AutoSize = $true
$chkPower     = New-Object System.Windows.Forms.CheckBox; $chkPower.Text = "Схема 'High Performance'"; $chkPower.Location = New-Object System.Drawing.Point(10, 110); $chkPower.AutoSize = $true
$chkRestore   = New-Object System.Windows.Forms.CheckBox; $chkRestore.Text = "Создать точку восстановления"; $chkRestore.Location = New-Object System.Drawing.Point(10, 360); $chkRestore.Checked = $true; $chkRestore.ForeColor = "DarkBlue"
$grpPerf.Controls.AddRange(@($chkSysMain, $chkAnim, $chkGameDVR, $chkPower, $chkRestore))

$tabTweaks.Controls.AddRange(@($grpPriv, $grpBloat, $grpPerf))

# --- TAB 2: APPS (WINGET) ---
$tabApps = New-Object System.Windows.Forms.TabPage; $tabApps.Text = " 📦 Магазин "
$txtSearch = New-Object System.Windows.Forms.TextBox; $txtSearch.Location = New-Object System.Drawing.Point(10, 10); $txtSearch.Size = New-Object System.Drawing.Size(600, 25); $txtSearch.Text = "Поиск (Нажмите Enter)"
$listApps = New-Object System.Windows.Forms.CheckedListBox; $listApps.Location = New-Object System.Drawing.Point(10, 40); $listApps.Size = New-Object System.Drawing.Size(600, 350); $listApps.CheckOnClick = $true
$btnAppInstall = New-Object System.Windows.Forms.Button; $btnAppInstall.Text = "Установить выбранное"; $btnAppInstall.Location = New-Object System.Drawing.Point(620, 40); $btnAppInstall.Size = New-Object System.Drawing.Size(200, 50); $btnAppInstall.BackColor = "Green"; $btnAppInstall.ForeColor = "White"
$btnAppUpdate = New-Object System.Windows.Forms.Button; $btnAppUpdate.Text = "Обновить весь софт"; $btnAppUpdate.Location = New-Object System.Drawing.Point(620, 100); $btnAppUpdate.Size = New-Object System.Drawing.Size(200, 50); $btnAppUpdate.BackColor = "DarkBlue"; $btnAppUpdate.ForeColor = "White"

$tabApps.Controls.AddRange(@($txtSearch, $listApps, $btnAppInstall, $btnAppUpdate))

# --- TAB 3: CLEAN ---
$tabClean = New-Object System.Windows.Forms.TabPage; $tabClean.Text = " 🧹 Очистка "
$chkTemp = New-Object System.Windows.Forms.CheckBox; $chkTemp.Text = "Удалить временные файлы (Temp)"; $chkTemp.Location = New-Object System.Drawing.Point(20, 30); $chkTemp.AutoSize = $true; $chkTemp.Checked = $true
$chkLogs = New-Object System.Windows.Forms.CheckBox; $chkLogs.Text = "Очистить логи событий"; $chkLogs.Location = New-Object System.Drawing.Point(20, 60); $chkLogs.AutoSize = $true
$chkUpd  = New-Object System.Windows.Forms.CheckBox; $chkUpd.Text = "Очистить кэш обновлений (SoftwareDistribution)"; $chkUpd.Location = New-Object System.Drawing.Point(20, 90); $chkUpd.AutoSize = $true
$tabClean.Controls.AddRange(@($chkTemp, $chkLogs, $chkUpd))

$tabControl.Controls.AddRange(@($tabTweaks, $tabApps, $tabClean))

# --- BOTTOM CONTROLS ---
$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.Location = New-Object System.Drawing.Point(10, 510)
$txtLog.Size = New-Object System.Drawing.Size(865, 90)
$txtLog.ReadOnly = $true
$txtLog.BackColor = "White"

$btnPresetPotato = New-Object System.Windows.Forms.Button; $btnPresetPotato.Text = "🥔 POTATO (Максимум)"; $btnPresetPotato.Location = New-Object System.Drawing.Point(10, 470); $btnPresetPotato.Size = New-Object System.Drawing.Size(150, 30); $btnPresetPotato.BackColor = "Maroon"; $btnPresetPotato.ForeColor = "White"
$btnPresetSafe   = New-Object System.Windows.Forms.Button; $btnPresetSafe.Text = "🛡️ SAFE (Безопасно)"; $btnPresetSafe.Location = New-Object System.Drawing.Point(170, 470); $btnPresetSafe.Size = New-Object System.Drawing.Size(150, 30); $btnPresetSafe.BackColor = "SeaGreen"; $btnPresetSafe.ForeColor = "White"
$btnPresetClear  = New-Object System.Windows.Forms.Button; $btnPresetClear.Text = "Сброс"; $btnPresetClear.Location = New-Object System.Drawing.Point(330, 470); $btnPresetClear.Size = New-Object System.Drawing.Size(80, 30)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "ЗАПУСТИТЬ ВЫБРАННОЕ"
$btnRun.Location = New-Object System.Drawing.Point(625, 470); $btnRun.Size = New-Object System.Drawing.Size(250, 30)
$btnRun.BackColor = "DarkSlateGray"; $btnRun.ForeColor = "White"
$btnRun.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)

$form.Controls.AddRange(@($tabControl, $txtLog, $btnPresetPotato, $btnPresetSafe, $btnPresetClear, $btnRun))

# --- 5. LOGIC & EVENTS ---

# JSON Loader
$Global:Apps = @()
try {
    $json = Invoke-RestMethod $AppsJsonUrl -UseBasicParsing -TimeoutSec 5
    if ($json.ManualCategories) {
        $json.ManualCategories.PSObject.Properties | % { $cat=$_.Name; $_.Value | % { 
            $_.PSObject.Properties.Add((New-Object PSNoteProperty("Display", "$($_.Name) [$cat]"))); 
            $Global:Apps += $_ 
        }}
    }
} catch { Log "Ошибка загрузки JSON. Интернет?" "Red" }

function Refresh-AppList($filter) {
    $listApps.Items.Clear()
    $Global:Apps | Where { $_.Name -match $filter } | % { $listApps.Items.Add($_.Display) }
}
Refresh-AppList ""

# Events
$txtSearch.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { Refresh-AppList $txtSearch.Text } })

$btnPresetSafe.Add_Click({
    $chkRestore.Checked=$true; $chkTemp.Checked=$true; $chkLogs.Checked=$true
    $chkTelemetry.Checked=$true; $chkBing.Checked=$true; $chkSysMain.Checked=$true
    $chkXbox.Checked=$false; $chkMail.Checked=$false; $chkAnim.Checked=$false
    Log "Пресет SAFE выбран." "Green"
})

$btnPresetPotato.Add_Click({
    # Select ALL
    $tabTweaks.Controls | % { $_.Controls | % { if($_ -is [System.Windows.Forms.CheckBox]){$_.Checked = $true} } }
    $tabClean.Controls | % { if($_ -is [System.Windows.Forms.CheckBox]){$_.Checked = $true} }
    Log "Пресет POTATO (Разгон) выбран!" "Red"
})

$btnPresetClear.Add_Click({
    $tabTweaks.Controls | % { $_.Controls | % { if($_ -is [System.Windows.Forms.CheckBox]){$_.Checked = $false} } }
    Log "Сброс выбора."
})

$btnAppUpdate.Add_Click({
    Log "Запуск обновления всех приложений..." "Blue"
    Start-Process winget -ArgumentList "upgrade --all --include-unknown" -NoNewWindow -Wait
    Log "Обновление завершено." "Green"
})

$btnAppInstall.Add_Click({
    foreach ($item in $listApps.CheckedItems) {
        $name = $item.Split("[")[0].Trim()
        $id = ($Global:Apps | Where {$_.Name -eq $name} | Select -First 1).Id
        Log "Установка: $name ($id)" "Blue"
        Start-Process winget -ArgumentList "install --id $id -e --silent --accept-package-agreements --accept-source-agreements" -NoNewWindow -Wait
    }
    Log "Установка завершена." "Green"
})

$btnRun.Add_Click({
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $btnRun.Enabled = $false
    
    # 1. Restore Point
    if ($chkRestore.Checked) { Core-CreateRestorePoint }

    # 2. Privacy
    if ($chkTelemetry.Checked) { 
        Core-KillService "DiagTrack"; Core-KillService "dmwappushservice"
        Core-RegTweak "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0
    }
    if ($chkCopilot.Checked) { Core-RegTweak "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1 }
    if ($chkBing.Checked) { Core-RegTweak "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1 }
    if ($chkLocation.Checked) { Core-KillService "lfsvc"; Core-KillService "MapsBroker" }

    # 3. Bloatware
    if ($chkXbox.Checked) { 
        ("XboxApp","GamingApp","XboxGamingOverlay","Xbox.TCUI") | % { Core-RemoveApp $_ }
        ("XblAuthManager","XblGameSave","XboxNetApiSvc") | % { Core-KillService $_ }
    }
    if ($chkMail.Checked) { Core-RemoveApp "windowscommunicationsapps" }
    if ($chkNews.Checked) { Core-RemoveApp "BingNews"; Core-RemoveApp "BingWeather"; Core-RegTweak "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa" 0 }
    if ($chkCortana.Checked) { Core-RemoveApp "Cortana"; Core-RemoveApp "People" }
    if ($chkOffice.Checked) { Core-RemoveApp "MicrosoftOfficeHub"; Core-RemoveApp "Office.OneNote" }

    # 4. Performance
    if ($chkSysMain.Checked) { Core-SysMain }
    if ($chkGameDVR.Checked) { 
        Core-RegTweak "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0 
        Core-KillService "BcastDVRUserService*"
    }
    if ($chkAnim.Checked) { Core-RegTweak "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2 }
    if ($chkPower.Checked) { 
        powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null | Out-Null
        powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
    }

    # 5. Clean
    if ($chkTemp.Checked) { Remove-Item "$env:TEMP\*" -Recurse -Force -EA 0; Log "Temp очищен." }
    if ($chkLogs.Checked) { Get-WinEvent -ListLog * -EA 0 | % { Wevtutil cl $_.LogName 2>$null }; Log "Логи очищены." }
    if ($chkUpd.Checked) { 
        Stop-Service wuauserv -Force -EA 0
        Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -EA 0
        Start-Service wuauserv -EA 0
        Log "Кэш обновлений очищен."
    }

    $btnRun.Enabled = $true
    $form.Cursor = [System.Windows.Forms.Cursors]::Default
    [System.Windows.Forms.MessageBox]::Show("Готово! Перезагрузите ПК.")
})

# --- START ---
$form.ShowDialog()
