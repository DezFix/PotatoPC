# ==========================================
# POTATO PC OPTIMIZER v10.0 (ANTI-FREEZE)
# ==========================================

# 1. ПОДКЛЮЧЕНИЕ
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 2. АДМИН БАННЕР
function Show-AdminWarning {
    $frm = New-Object System.Windows.Forms.Form
    $frm.Text = "НЕТ ДОСТУПА"; $frm.Size = New-Object System.Drawing.Size(400, 200); $frm.StartPosition = "CenterScreen"
    $frm.BackColor = "DarkRed"; $frm.ForeColor = "White"
    $lbl = New-Object System.Windows.Forms.Label; $lbl.Text = "Запустите от имени Администратора!"; $lbl.AutoSize=$true; $lbl.Location = New-Object System.Drawing.Point(50, 50); $lbl.Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)
    $btn = New-Object System.Windows.Forms.Button; $btn.Text = "OK"; $btn.Location = New-Object System.Drawing.Point(140, 100); $btn.ForeColor="Black"; $btn.Add_Click({$frm.Close()})
    $frm.Controls.AddRange(@($lbl, $btn)); $frm.ShowDialog() | Out-Null
}

$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (!($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) { Show-AdminWarning; exit }

# --- НАСТРОЙКИ ---
$WorkDir   = "C:\PotatoPC"
$BackupDir = "$WorkDir\Backups"
$TempDir   = "$WorkDir\Temp"
$AppsJsonUrl = "https://raw.githubusercontent.com/DezFix/PotatoPC/main/apps.json"

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
$Global:SelectedAppIDs = new-object System.Collections.Generic.HashSet[string]

# --- ФУНКЦИИ ---
function Log($text, $color="Black") {
    $txtLog.SelectionColor = [System.Drawing.Color]::FromName($color)
    $txtLog.AppendText("[$([DateTime]::Now.ToString('HH:mm:ss'))] $text`r`n")
    $txtLog.ScrollToCaret()
    # ВАЖНО: Обновляем интерфейс, чтобы не висло
    [System.Windows.Forms.Application]::DoEvents()
}

function Fix-Winget {
    Log "Восстановление WinGet..." "DarkMagenta"
    try {
        $urls = @(
            "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx",
            "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx",
            "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        )
        $files = @("$TempDir\vclibs.appx", "$TempDir\ui.xaml.appx", "$TempDir\winget.msixbundle")
        
        for($i=0; $i -lt 3; $i++) {
            Invoke-WebRequest -Uri $urls[$i] -OutFile $files[$i] -UseBasicParsing
            Add-AppxPackage -Path $files[$i] -ErrorAction SilentlyContinue
        }
        Log "WinGet установлен." "Green"
        return $true
    } catch { Log "Ошибка WinGet: $($_.Exception.Message)" "Red"; return $false }
}

function Core-KillService($Name) {
    # Получаем службы без ошибки, если их нет
    $services = Get-Service $Name -ErrorAction SilentlyContinue
    if (!$services) { return } # Если службы нет - выходим молча

    foreach ($s in $services) {
        if ($s.Status -ne 'Stopped' -or $s.StartType -ne 'Disabled') {
            Log "Стоп служба: $($s.Name)" "DarkMagenta"
            try {
                Stop-Service $s.Name -Force -ErrorAction Stop
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.Name)" "Start" 4 -Type DWord -Force
            } catch {
                Log "Не удалось остановить $($s.Name)" "Gray"
            }
        }
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Core-RemoveApp($Pattern) {
    $White = @("Microsoft.WindowsStore", "Microsoft.DesktopAppInstaller", "Microsoft.Windows.Photos", "Microsoft.WindowsCalculator")
    
    # Сначала ищем, есть ли приложение вообще
    $apps = Get-AppxPackage -AllUsers | Where-Object {$_.Name -like "*$Pattern*" -and $_.Name -notin $White}
    
    if ($apps) {
        foreach ($a in $apps) {
            Log "Удаление: $($a.Name)" "Red"
            try {
                Remove-AppxPackage -Package $a.PackageFullName -AllUsers -ErrorAction Stop
            } catch {
                Log "Ошибка при удалении $($a.Name): $($_.Exception.Message)" "Gray"
            }
            [System.Windows.Forms.Application]::DoEvents()
        }
    } else {
        # Раскомментируй строку ниже, если хочешь видеть пропуски в логе
        # Log "Скип: $Pattern (Не найдено)" "Gray"
    }
}

function Core-RegTweak($path, $name, $val) {
    if (!(Test-Path $path)) { New-Item $path -Force | Out-Null }
    Set-ItemProperty $path $name $val -Type DWord -Force -ErrorAction SilentlyContinue
}

# --- GUI ---
$Global:ToolTip = New-Object System.Windows.Forms.ToolTip
$Global:ToolTip.AutoPopDelay = 15000; $Global:ToolTip.InitialDelay = 100

function Add-Item($panel, $text, $desc, $yRaw, $varName) {
    $y = [int]$yRaw
    $chk = New-Object System.Windows.Forms.CheckBox; $chk.Text = $text; $chk.Location = New-Object System.Drawing.Point(15, $y); $chk.AutoSize = $true
    $panel.Controls.Add($chk)
    $lbl = New-Object System.Windows.Forms.Label; $lbl.Text = "[?]"; $lbl.ForeColor = "DodgerBlue"; $lbl.Cursor = [System.Windows.Forms.Cursors]::Hand; $lbl.Location = New-Object System.Drawing.Point(235, $y+3); $lbl.AutoSize = $true
    $Global:ToolTip.SetToolTip($lbl, $desc)
    $panel.Controls.Add($lbl)
    Set-Variable -Name $varName -Value $chk -Scope Script
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "PotatoPC Optimizer v10.0 (Anti-Freeze)"; $form.Size = New-Object System.Drawing.Size(950, 700); $form.StartPosition = "CenterScreen"; $form.FormBorderStyle = "FixedSingle"; $form.MaximizeBox = $false; $form.BackColor = "WhiteSmoke"

$tabs = New-Object System.Windows.Forms.TabControl; $tabs.Location = New-Object System.Drawing.Point(10, 10); $tabs.Size = New-Object System.Drawing.Size(915, 500)

# 1. PRESETS
$tp1 = New-Object System.Windows.Forms.TabPage; $tp1.Text = " [1] ПРЕСЕТЫ "
$l1 = New-Object System.Windows.Forms.Label; $l1.Text = "Выберите режим:"; $l1.Location = "20, 20"; $l1.AutoSize=$true; $l1.Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)

$bp1 = New-Object System.Windows.Forms.Button; $bp1.Text = "[ SAFE ]`nБезопасный"; $bp1.Location = "50, 60"; $bp1.Size = "200, 60"; $bp1.BackColor = "SeaGreen"; $bp1.ForeColor = "White"
$lp1 = New-Object System.Windows.Forms.Label; $lp1.Text = "Только мусор. Безопасно."; $lp1.Location = "270, 70"; $lp1.AutoSize=$true

$bp2 = New-Object System.Windows.Forms.Button; $bp2.Text = "[ OFFICE ]`nОфисный"; $bp2.Location = "50, 140"; $bp2.Size = "200, 60"; $bp2.BackColor = "SteelBlue"; $bp2.ForeColor = "White"
$lp2 = New-Object System.Windows.Forms.Label; $lp2.Text = "Без игр. Оставляет Почту."; $lp2.Location = "270, 150"; $lp2.AutoSize=$true

$bp3 = New-Object System.Windows.Forms.Button; $bp3.Text = "[ GAMER ]`nИгровой"; $bp3.Location = "50, 220"; $bp3.Size = "200, 60"; $bp3.BackColor = "DarkOrange"; $bp3.ForeColor = "White"
$lp3 = New-Object System.Windows.Forms.Label; $lp3.Text = "С играми. Оптимизация FPS."; $lp3.Location = "270, 230"; $lp3.AutoSize=$true

$bp4 = New-Object System.Windows.Forms.Button; $bp4.Text = "[ POTATO ]`nМаксимум"; $bp4.Location = "50, 300"; $bp4.Size = "200, 60"; $bp4.BackColor = "Maroon"; $bp4.ForeColor = "White"
$lp4 = New-Object System.Windows.Forms.Label; $lp4.Text = "Отключает всё. Для слабых ПК."; $lp4.Location = "270, 310"; $lp4.AutoSize=$true

$tp1.Controls.AddRange(@($l1, $bp1, $lp1, $bp2, $lp2, $bp3, $lp3, $bp4, $lp4))

# 2. TWEAKS
$tp2 = New-Object System.Windows.Forms.TabPage; $tp2.Text = " [2] ТВИКИ "
$g1 = New-Object System.Windows.Forms.GroupBox; $g1.Text = "Приватность"; $g1.Location = "10, 10"; $g1.Size = "280, 400"
Add-Item $g1 "Откл. Телеметрию" "Отключает слежку." 25 "chkTel"
Add-Item $g1 "Убрать Copilot" "Откл. ИИ." 55 "chkCop"
Add-Item $g1 "Убрать Bing" "Поиск в Пуске." 85 "chkBing"

$g2 = New-Object System.Windows.Forms.GroupBox; $g2.Text = "Удаление"; $g2.Location = "300, 10"; $g2.Size = "280, 400"
Add-Item $g2 "Удалить Xbox" "Ломает Store игры!" 25 "chkXbox"
Add-Item $g2 "Удалить Почту" "Почта/Календарь." 55 "chkMail"
Add-Item $g2 "Удалить Новости" "Виджет погоды." 85 "chkNews"
Add-Item $g2 "Удалить Cortana" "Голосовой помощник." 115 "chkCort"
Add-Item $g2 "Удалить Office" "Приложение My Office." 145 "chkOff"

$g3 = New-Object System.Windows.Forms.GroupBox; $g3.Text = "Скорость"; $g3.Location = "590, 10"; $g3.Size = "280, 400"
Add-Item $g3 "SysMain (SSD)" "Superfetch." 25 "chkSysMain"
Add-Item $g3 "Откл. Анимации" "Визуал." 55 "chkAnim"
Add-Item $g3 "Откл. GameDVR" "Запись экрана." 85 "chkDVR"
Add-Item $g3 "Откл. Залипание" "Shift x5." 115 "chkSticky"
Add-Item $g3 "Откл. Гибернацию" "Место на диске." 145 "chkHib"
Add-Item $g3 "Показ расширений" ".exe, .txt" 175 "chkExt"
Add-Item $g3 "Fix Мыши" "Акселерация." 205 "chkMouse"

$brst = New-Object System.Windows.Forms.Button; $brst.Text = "Сбросить галочки"; $brst.Location = "10, 420"; $brst.Size = "200, 30"
$tp2.Controls.AddRange(@($g1, $g2, $g3, $brst))

# 3. APPS
$tp3 = New-Object System.Windows.Forms.TabPage; $tp3.Text = " [3] МАГАЗИН "
$lc = New-Object System.Windows.Forms.Label; $lc.Text = "Категория:"; $lc.Location = "10, 13"; $lc.AutoSize=$true
$cc = New-Object System.Windows.Forms.ComboBox; $cc.Location = "80, 10"; $cc.Size = "200, 25"; $cc.DropDownStyle = "DropDownList"; $cc.Items.Add("ВСЕ (All)")
$ts = New-Object System.Windows.Forms.TextBox; $ts.Location = "300, 10"; $ts.Size = "300, 25"; $ts.Text = "Поиск..."
$la = New-Object System.Windows.Forms.CheckedListBox; $la.Location = "10, 45"; $la.Size = "590, 400"; $la.CheckOnClick = $true
$bi = New-Object System.Windows.Forms.Button; $bi.Text = "Установить"; $bi.Location = "620, 45"; $bi.Size = "250, 50"; $bi.BackColor = "Green"; $bi.ForeColor = "White"
$bu = New-Object System.Windows.Forms.Button; $bu.Text = "Обновить ВСЁ"; $bu.Location = "620, 110"; $bu.Size = "250, 50"; $bu.BackColor = "DarkBlue"; $bu.ForeColor = "White"
$tp3.Controls.AddRange(@($lc, $cc, $ts, $la, $bi, $bu))

# 4. CLEAN
$tp4 = New-Object System.Windows.Forms.TabPage; $tp4.Text = " [4] ОЧИСТКА "
Add-Item $tp4 "Очистка Temp" "Временные файлы." 30 "chkTmp"; $chkTmp.Checked=$true
Add-Item $tp4 "Очистка Логов" "Журналы событий." 60 "chkLog"
Add-Item $tp4 "Очистка Upd Cache" "Кэш обновлений." 90 "chkUpdCache"
Add-Item $tp4 "Сброс DNS" "Сеть." 120 "chkDns"
Add-Item $tp4 "Очистить Корзину" "Корзина." 150 "chkBin"
Add-Item $tp4 "DISM Очистка" "Образ Windows (Долго)." 180 "chkDism"

$tabs.Controls.AddRange(@($tp1, $tp2, $tp3, $tp4))

# FOOTER
$log = New-Object System.Windows.Forms.RichTextBox; $log.Location = "10, 560"; $log.Size = "915, 90"; $log.ReadOnly = $true; $log.BackColor="White"
$brun = New-Object System.Windows.Forms.Button; $brun.Text = "ЗАПУСТИТЬ ВЫБРАННОЕ"; $brun.Location = "400, 515"; $brun.Size = "325, 40"; $brun.BackColor="DarkSlateGray"; $brun.ForeColor="White"; $brun.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
$crest = New-Object System.Windows.Forms.CheckBox; $crest.Text = "Точка восстановления"; $crest.Location = "20, 525"; $crest.AutoSize=$true; $crest.Checked=$true; $crest.ForeColor="DarkBlue"
$breboot = New-Object System.Windows.Forms.Button; $breboot.Text = "Перезагрузка"; $breboot.Location = "740, 515"; $breboot.Size = "180, 40"; $breboot.BackColor="Maroon"; $breboot.ForeColor="White"
$form.Controls.AddRange(@($tabs, $log, $brun, $crest, $breboot))

# --- LOGIC ---

function Reset-Checkboxes {
    $tp2.Controls | % { if($_ -is [System.Windows.Forms.GroupBox]){ $_.Controls | % { if($_ -is [System.Windows.Forms.CheckBox]){$_.Checked=$false} } } }
    $tp4.Controls | % { if($_ -is [System.Windows.Forms.CheckBox]){$_.Checked=$false} }
}
$brst.Add_Click({ Reset-Checkboxes; Log "Сброс." })

$bp1.Add_Click({ Reset-Checkboxes; $chkTel.Checked=$true; $chkBing.Checked=$true; $chkSysMain.Checked=$true; $chkTmp.Checked=$true; $chkLog.Checked=$true; Log "Пресет: SAFE"; [System.Windows.Forms.MessageBox]::Show("SAFE режим.") })
$bp2.Add_Click({ Reset-Checkboxes; $chkTel.Checked=$true; $chkCop.Checked=$true; $chkBing.Checked=$true; $chkXbox.Checked=$true; $chkNews.Checked=$true; $chkSysMain.Checked=$true; $chkTmp.Checked=$true; Log "Пресет: OFFICE"; [System.Windows.Forms.MessageBox]::Show("OFFICE режим.") })
$bp3.Add_Click({ Reset-Checkboxes; $chkTel.Checked=$true; $chkCop.Checked=$true; $chkBing.Checked=$true; $chkMail.Checked=$true; $chkNews.Checked=$true; $chkCort.Checked=$true; $chkOff.Checked=$true; $chkSysMain.Checked=$true; $chkAnim.Checked=$true; $chkDVR.Checked=$true; $chkMouse.Checked=$true; $chkSticky.Checked=$true; $chkTmp.Checked=$true; Log "Пресет: GAMER"; [System.Windows.Forms.MessageBox]::Show("GAMER режим.") })
$bp4.Add_Click({ Reset-Checkboxes; $tp2.Controls | % { if($_ -is [System.Windows.Forms.GroupBox]){ $_.Controls | % { if($_ -is [System.Windows.Forms.CheckBox]){$_.Checked=$true} } } }; $tp4.Controls | % { if($_ -is [System.Windows.Forms.CheckBox]){$_.Checked=$true} }; $chkDism.Checked=$false; Log "Пресет: POTATO"; [System.Windows.Forms.MessageBox]::Show("POTATO режим.") })

$Global:Apps = @()
try { $json = Invoke-RestMethod $AppsJsonUrl -UseBasicParsing -TimeoutSec 10; if ($json.ManualCategories) { foreach ($catObj in $json.ManualCategories) { $catName = $catObj.Name; $cc.Items.Add($catName); foreach ($app in $catObj.Value) { $app | Add-Member -MemberType NoteProperty -Name "Category" -Value $catName -Force; $app | Add-Member -MemberType NoteProperty -Name "Display" -Value "$($app.Name)" -Force; $Global:Apps += $app } } } } catch { Log "Ошибка Apps JSON." "Red" }
$cc.SelectedIndex = 0
$la.Add_ItemCheck({ $id = ($Global:Apps | Where {$_.Display -eq $la.Items[$_.Index]}).Id; if ($_.NewValue -eq 'Checked') { $Global:SelectedAppIDs.Add($id)|Out-Null } else { $Global:SelectedAppIDs.Remove($id)|Out-Null } })
function Refresh-Apps { $cat=$cc.SelectedItem; $f=$ts.Text; if($f-eq"Поиск..."){$f=""}; $la.Items.Clear(); $sub=$Global:Apps | Where { ($cat -eq "ВСЕ (All)" -or $_.Category -eq $cat) -and ($_.Name -match $f) }; foreach($a in $sub){ $idx=$la.Items.Add($a.Display); if($Global:SelectedAppIDs.Contains($a.Id)){$la.SetItemChecked($idx,$true)} } }
$cc.Add_SelectedIndexChanged({Refresh-Apps}); $ts.Add_KeyUp({Refresh-Apps}); $ts.Add_Click({if($ts.Text-eq"Поиск..."){$ts.Text=""}})

$bi.Add_Click({ if(!(Get-Command winget -EA 0)){ if(!(Fix-Winget)){ return } }; if ($Global:SelectedAppIDs.Count -gt 0) { $Global:SelectedAppIDs | % { Log "Установка: $_" "Blue"; Start-Process winget -ArgumentList "install --id $_ -e --silent --accept-package-agreements --accept-source-agreements" -Wait; [System.Windows.Forms.Application]::DoEvents() } } })
$bu.Add_Click({ if(!(Get-Command winget -EA 0)){ if(!(Fix-Winget)){ return } }; Log "Обновление..." "Blue"; Start-Process winget -ArgumentList "upgrade --all --include-unknown --accept-source-agreements" -Wait; Log "Готово." "Green" })

$brun.Add_Click({
    $form.Cursor=[System.Windows.Forms.Cursors]::WaitCursor; $form.Enabled=$false
    if ($crest.Checked) { Log "Точка восстановления..." "Blue"; Enable-ComputerRestore -Drive "C:\" -EA 0; Checkpoint-Computer -Description "PotatoPC" -RestorePointType "MODIFY_SETTINGS" -EA 0 }
    
    if($chkTel.Checked){Core-KillService "DiagTrack";Core-KillService "dmwappushservice";Core-RegTweak "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0}
    if($chkCop.Checked){Core-RegTweak "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1}
    if($chkBing.Checked){Core-RegTweak "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1}
    
    if($chkXbox.Checked){@("XboxApp","GamingApp","XboxGamingOverlay","Xbox.TCUI")|%{Core-RemoveApp $_};@("XblAuthManager","XblGameSave","XboxNetApiSvc")|%{Core-KillService $_}}
    if($chkMail.Checked){Core-RemoveApp "windowscommunicationsapps"}
    if($chkNews.Checked){Core-RemoveApp "BingNews";Core-RemoveApp "BingWeather";Core-RegTweak "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa" 0}
    if($chkCort.Checked){Core-RemoveApp "Cortana";Core-RemoveApp "People"}
    if($chkOff.Checked){Core-RemoveApp "MicrosoftOfficeHub"}
    
    if($chkSysMain.Checked){$ssd=Get-PhysicalDisk|Where{$_.MediaType-eq'SSD'};if($ssd){Core-KillService "SysMain"}}
    if($chkAnim.Checked){Core-RegTweak "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2}
    if($chkDVR.Checked){Core-RegTweak "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0;Core-KillService "BcastDVRUserService*"}
    if($chkSticky.Checked){Core-RegTweak "HKCU:\Control Panel\Accessibility\StickyKeys" "Flags" 506}
    if($chkHib.Checked){powercfg -h off}
    if($chkExt.Checked){Core-RegTweak "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt" 0}
    if($chkMouse.Checked){Core-RegTweak "HKCU:\Control Panel\Mouse" "MouseSpeed" 0;Core-RegTweak "HKCU:\Control Panel\Mouse" "MouseThreshold1" 0;Core-RegTweak "HKCU:\Control Panel\Mouse" "MouseThreshold2" 0}

    if($chkTmp.Checked){Remove-Item "$env:TEMP\*" -Recurse -Force -EA 0}
    if($chkLog.Checked){Get-WinEvent -ListLog * -EA 0 | % { Wevtutil cl $_.LogName 2>$null }}
    if($chkUpdCache.Checked){Stop-Service wuauserv -Force -EA 0; Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -EA 0; Start-Service wuauserv -EA 0}
    if($chkDns.Checked){Clear-DnsClientCache}
    if($chkBin.Checked){Clear-RecycleBin -Force -EA 0}
    if($chkDism.Checked){Log "DISM (Ждите)..." "Orange"; Dism.exe /online /Cleanup-Image /StartComponentCleanup | Out-Null}

    $form.Enabled=$true; $form.Cursor=[System.Windows.Forms.Cursors]::Default; Log "Готово." "Green"; [System.Windows.Forms.MessageBox]::Show("Завершено!")
})
$breboot.Add_Click({ Restart-Computer -Force })

$form.ShowDialog()
