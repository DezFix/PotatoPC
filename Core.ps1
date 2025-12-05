# ==========================================
# POTATO PC OPTIMIZER v11.0 (MODULAR)
# ==========================================

# 1. ПРОВЕРКА АДМИНА
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (!($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    $frm = New-Object System.Windows.Forms.Form
    $frm.Text="ERROR"; $frm.Size="400,200"; $frm.StartPosition="CenterScreen"; $frm.BackColor="DarkRed"
    $lbl = New-Object System.Windows.Forms.Label; $lbl.Text="ЗАПУСТИТЕ ОТ АДМИНИСТРАТОРА!"; $lbl.ForeColor="White"; $lbl.AutoSize=$true; $lbl.Location="50,50"; $lbl.Font="Arial,12,Bold"
    $btn = New-Object System.Windows.Forms.Button; $btn.Text="OK"; $btn.Location="140,100"; $btn.Add_Click({$frm.Close()})
    $frm.Controls.AddRange(@($lbl,$btn)); $frm.ShowDialog(); exit
}

# 2. ЗАГРУЗКА МОДУЛЕЙ
$WorkDir = "C:\PotatoPC"; $TempDir = "$WorkDir\Temp"; $BackupDir = "$WorkDir\Backups"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

# --- ССЫЛКИ (ПОМЕНЯЙ LogicUrl НА СВОЮ!) ---
$LogicUrl   = "https://raw.githubusercontent.com/DezFix/PotatoPC/main/Logic.ps1" 
$AppsJsonUrl = "https://raw.githubusercontent.com/DezFix/PotatoPC/main/apps.json"
$LogicFile  = "$TempDir\Logic.ps1"

# Скачиваем и подключаем логику
try {
    $LogicContent = Invoke-RestMethod -Uri $LogicUrl -UseBasicParsing
    $LogicContent | Out-File -FilePath $LogicFile -Encoding UTF8 -Force
    . $LogicFile # Импорт функций из Logic.ps1
} catch {
    [System.Windows.Forms.MessageBox]::Show("Не удалось загрузить Logic.ps1. Проверьте интернет!")
    exit
}

# 3. ПОСТРОЕНИЕ ИНТЕРФЕЙСА (GUI)
$Global:ToolTip = New-Object System.Windows.Forms.ToolTip
$Global:ToolTip.AutoPopDelay = 15000; $Global:ToolTip.InitialDelay = 100

function Add-Item($panel, $text, $desc, $yRaw, $varName) {
    $y = [int]$yRaw
    $chk = New-Object System.Windows.Forms.CheckBox; $chk.Text=$text; $chk.Location="15,$y"; $chk.AutoSize=$true
    $panel.Controls.Add($chk)
    $lbl = New-Object System.Windows.Forms.Label; $lbl.Text="[?]"; $lbl.ForeColor="DodgerBlue"; $lbl.Cursor="Hand"; $lbl.Location="235,$($y+3)"; $lbl.AutoSize=$true
    $Global:ToolTip.SetToolTip($lbl, $desc)
    $panel.Controls.Add($lbl)
    Set-Variable -Name $varName -Value $chk -Scope Script
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "PotatoPC Optimizer v11.0"; $form.Size = "950,700"; $form.StartPosition = "CenterScreen"; $form.FormBorderStyle="FixedSingle"; $form.MaximizeBox=$false; $form.BackColor="WhiteSmoke"

$tabs = New-Object System.Windows.Forms.TabControl; $tabs.Location="10,10"; $tabs.Size="915,500"
$log = New-Object System.Windows.Forms.RichTextBox; $log.Location="10,560"; $log.Size="915,90"; $log.ReadOnly=$true; $log.BackColor="White"

# --- TAB 1: PRESETS ---
$tp1 = New-Object System.Windows.Forms.TabPage; $tp1.Text=" [1] ПРЕСЕТЫ "
$l1 = New-Object System.Windows.Forms.Label; $l1.Text="Выберите режим:"; $l1.Location="20,20"; $l1.AutoSize=$true; $l1.Font="Arial,12,Bold"

$bp1 = New-Object System.Windows.Forms.Button; $bp1.Text="[ SAFE ]`nБезопасный"; $bp1.Location="50,60"; $bp1.Size="200,60"; $bp1.BackColor="SeaGreen"; $bp1.ForeColor="White"
$lp1 = New-Object System.Windows.Forms.Label; $lp1.Text="Только мусор. Безопасно."; $lp1.Location="270,70"; $lp1.AutoSize=$true

$bp2 = New-Object System.Windows.Forms.Button; $bp2.Text="[ OFFICE ]`nОфисный"; $bp2.Location="50,140"; $bp2.Size="200,60"; $bp2.BackColor="SteelBlue"; $bp2.ForeColor="White"
$lp2 = New-Object System.Windows.Forms.Label; $lp2.Text="Без игр. Оставляет Почту."; $lp2.Location="270,150"; $lp2.AutoSize=$true

$bp3 = New-Object System.Windows.Forms.Button; $bp3.Text="[ GAMER ]`nИгровой"; $bp3.Location="50,220"; $bp3.Size="200,60"; $bp3.BackColor="DarkOrange"; $bp3.ForeColor="White"
$lp3 = New-Object System.Windows.Forms.Label; $lp3.Text="С играми. Оптимизация FPS."; $lp3.Location="270,230"; $lp3.AutoSize=$true

$bp4 = New-Object System.Windows.Forms.Button; $bp4.Text="[ POTATO ]`nМаксимум"; $bp4.Location="50,300"; $bp4.Size="200,60"; $bp4.BackColor="Maroon"; $bp4.ForeColor="White"
$lp4 = New-Object System.Windows.Forms.Label; $lp4.Text="Отключает всё. Для слабых ПК."; $lp4.Location="270,310"; $lp4.AutoSize=$true

$tp1.Controls.AddRange(@($l1, $bp1, $lp1, $bp2, $lp2, $bp3, $lp3, $bp4, $lp4))

# --- TAB 2: TWEAKS ---
$tp2 = New-Object System.Windows.Forms.TabPage; $tp2.Text=" [2] ТВИКИ "
$g1 = New-Object System.Windows.Forms.GroupBox; $g1.Text="Приватность"; $g1.Location="10,10"; $g1.Size="280,400"
Add-Item $g1 "Откл. Телеметрию" "Слежка." 25 "chkTel"
Add-Item $g1 "Убрать Copilot" "ИИ." 55 "chkCop"
Add-Item $g1 "Убрать Bing" "Поиск." 85 "chkBing"

$g2 = New-Object System.Windows.Forms.GroupBox; $g2.Text="Удаление"; $g2.Location="300,10"; $g2.Size="280,400"
Add-Item $g2 "Удалить Xbox" "Ломает Store!" 25 "chkXbox"
Add-Item $g2 "Удалить Почту" "Почта." 55 "chkMail"
Add-Item $g2 "Удалить Новости" "Погода." 85 "chkNews"
Add-Item $g2 "Удалить Cortana" "Голос." 115 "chkCort"
Add-Item $g2 "Удалить Office" "My Office." 145 "chkOff"

$g3 = New-Object System.Windows.Forms.GroupBox; $g3.Text="Скорость"; $g3.Location="590,10"; $g3.Size="280,400"
Add-Item $g3 "SysMain (SSD)" "Superfetch." 25 "chkSysMain"
Add-Item $g3 "Откл. Анимации" "Визуал." 55 "chkAnim"
Add-Item $g3 "Откл. GameDVR" "Запись экрана." 85 "chkDVR"
Add-Item $g3 "Откл. Залипание" "Shift x5." 115 "chkSticky"
Add-Item $g3 "Откл. Гибернацию" "Место на диске." 145 "chkHib"
Add-Item $g3 "Показ расширений" ".exe" 175 "chkExt"
Add-Item $g3 "Fix Мыши" "Акселерация." 205 "chkMouse"

$brst = New-Object System.Windows.Forms.Button; $brst.Text="Сброс"; $brst.Location="10,420"; $brst.Size="200,30"
$tp2.Controls.AddRange(@($g1, $g2, $g3, $brst))

# --- TAB 3: APPS ---
$tp3 = New-Object System.Windows.Forms.TabPage; $tp3.Text=" [3] МАГАЗИН "
$cc = New-Object System.Windows.Forms.ComboBox; $cc.Location="10,10"; $cc.Size="200,25"; $cc.DropDownStyle="DropDownList"; $cc.Items.Add("ВСЕ (All)")
$ts = New-Object System.Windows.Forms.TextBox; $ts.Location="220,10"; $ts.Size="380,25"; $ts.Text="Поиск..."
$la = New-Object System.Windows.Forms.CheckedListBox; $la.Location="10,45"; $la.Size="590,400"; $la.CheckOnClick=$true
$bi = New-Object System.Windows.Forms.Button; $bi.Text="Установить"; $bi.Location="620,45"; $bi.Size="250,50"; $bi.BackColor="Green"; $bi.ForeColor="White"
$bu = New-Object System.Windows.Forms.Button; $bu.Text="Обновить ВСЁ"; $bu.Location="620,110"; $bu.Size="250,50"; $bu.BackColor="DarkBlue"; $bu.ForeColor="White"
$tp3.Controls.AddRange(@($cc, $ts, $la, $bi, $bu))

# --- TAB 4: CLEAN ---
$tp4 = New-Object System.Windows.Forms.TabPage; $tp4.Text=" [4] ОЧИСТКА "
Add-Item $tp4 "Очистка Temp" "Временные файлы." 30 "chkTmp"; $chkTmp.Checked=$true
Add-Item $tp4 "Очистка Логов" "Журналы событий." 60 "chkLog"
Add-Item $tp4 "Очистка Upd Cache" "Кэш обновлений." 90 "chkUpdCache"
Add-Item $tp4 "Сброс DNS" "Сеть." 120 "chkDns"
Add-Item $tp4 "Очистить Корзину" "Корзина." 150 "chkBin"
Add-Item $tp4 "DISM Очистка" "Образ Windows." 180 "chkDism"
$tabs.Controls.AddRange(@($tp1, $tp2, $tp3, $tp4))

# FOOTER
$brun = New-Object System.Windows.Forms.Button; $brun.Text="ЗАПУСТИТЬ ВЫБРАННОЕ"; $brun.Location="400,515"; $brun.Size="325,40"; $brun.BackColor="DarkSlateGray"; $brun.ForeColor="White"; $brun.Font="Arial,10,Bold"
$crest = New-Object System.Windows.Forms.CheckBox; $crest.Text="Точка восстановления"; $crest.Location="20,525"; $crest.AutoSize=$true; $crest.Checked=$true
$breboot = New-Object System.Windows.Forms.Button; $breboot.Text="Перезагрузка"; $breboot.Location="740,515"; $breboot.Size="180,40"; $breboot.BackColor="Maroon"; $breboot.ForeColor="White"
$form.Controls.AddRange(@($tabs, $log, $brun, $crest, $breboot))

# --- LOGIC CONNECTION ---
$Global:SelectedAppIDs = new-object System.Collections.Generic.HashSet[string]
$Global:Apps = @()

# Load Apps
try { 
    $json = Invoke-RestMethod $AppsJsonUrl -UseBasicParsing -TimeoutSec 5
    if ($json.ManualCategories) { 
        foreach ($catObj in $json.ManualCategories) { 
            $catName = $catObj.Name; $cc.Items.Add($catName)
            foreach ($app in $catObj.Value) {
                $app | Add-Member -MemberType NoteProperty -Name "Category" -Value $catName -Force
                $app | Add-Member -MemberType NoteProperty -Name "Display" -Value "$($app.Name)" -Force
                $Global:Apps += $app
            }
        }
    }
} catch { Log $log "Error loading Apps JSON" "Red" }
$cc.SelectedIndex = 0

# App Events
$la.Add_ItemCheck({ $id = ($Global:Apps | Where {$_.Display -eq $la.Items[$_.Index]}).Id; if ($_.NewValue -eq 'Checked') { $Global:SelectedAppIDs.Add($id)|Out-Null } else { $Global:SelectedAppIDs.Remove($id)|Out-Null } })
function Refresh-Apps { $cat=$cc.SelectedItem; $f=$ts.Text; if($f-eq"Поиск..."){$f=""}; $la.Items.Clear(); $sub=$Global:Apps | Where { ($cat -eq "ВСЕ (All)" -or $_.Category -eq $cat) -and ($_.Name -match $f) }; foreach($a in $sub){ $idx=$la.Items.Add($a.Display); if($Global:SelectedAppIDs.Contains($a.Id)){$la.SetItemChecked($idx,$true)} } }
$cc.Add_SelectedIndexChanged({Refresh-Apps}); $ts.Add_KeyUp({Refresh-Apps}); $ts.Add_Click({if($ts.Text-eq"Поиск..."){$ts.Text=""}})

# Presets & Reset
function Reset-Checkboxes { $tp2.Controls | % { if($_ -is [System.Windows.Forms.GroupBox]){ $_.Controls | % { if($_ -is [System.Windows.Forms.CheckBox]){$_.Checked=$false} } } }; $tp4.Controls | % { if($_ -is [System.Windows.Forms.CheckBox]){$_.Checked=$false} } }
$brst.Add_Click({ Reset-Checkboxes })
$bp1.Add_Click({ Reset-Checkboxes; $chkTel.Checked=$true; $chkBing.Checked=$true; $chkSysMain.Checked=$true; $chkTmp.Checked=$true; $chkLog.Checked=$true; Log $log "SAFE Mode" "Green" })
$bp2.Add_Click({ Reset-Checkboxes; $chkTel.Checked=$true; $chkCop.Checked=$true; $chkBing.Checked=$true; $chkXbox.Checked=$true; $chkNews.Checked=$true; $chkSysMain.Checked=$true; $chkTmp.Checked=$true; Log $log "OFFICE Mode" "Blue" })
$bp3.Add_Click({ Reset-Checkboxes; $chkTel.Checked=$true; $chkCop.Checked=$true; $chkBing.Checked=$true; $chkMail.Checked=$true; $chkNews.Checked=$true; $chkCort.Checked=$true; $chkOff.Checked=$true; $chkSysMain.Checked=$true; $chkAnim.Checked=$true; $chkDVR.Checked=$true; $chkMouse.Checked=$true; $chkSticky.Checked=$true; $chkTmp.Checked=$true; Log $log "GAMER Mode" "Orange" })
$bp4.Add_Click({ Reset-Checkboxes; $tp2.Controls | % { if($_ -is [System.Windows.Forms.GroupBox]){ $_.Controls | % { if($_ -is [System.Windows.Forms.CheckBox]){$_.Checked=$true} } } }; $tp4.Controls | % { if($_ -is [System.Windows.Forms.CheckBox]){$_.Checked=$true} }; $chkDism.Checked=$false; Log $log "POTATO Mode" "Red" })

# Apps Buttons
$bi.Add_Click({ 
    if(!(Get-Command winget -EA 0)){ if(!(Fix-Winget $TempDir)){ return } }
    if ($Global:SelectedAppIDs.Count -gt 0) { $Global:SelectedAppIDs | % { Log $log "Install: $_" "Blue"; Start-Process winget -ArgumentList "install --id $_ -e --silent --accept-package-agreements --accept-source-agreements" -Wait } } 
})
$bu.Add_Click({ if(!(Get-Command winget -EA 0)){ if(!(Fix-Winget $TempDir)){ return } }; Log $log "Updating..." "Blue"; Start-Process winget -ArgumentList "upgrade --all --include-unknown --accept-source-agreements" -Wait; Log $log "Updated." "Green" })

# RUN BUTTON
$brun.Add_Click({
    $form.Cursor="WaitCursor"; $form.Enabled=$false
    if ($crest.Checked) { Log $log "Restore Point..." "Blue"; Enable-ComputerRestore -Drive "C:\" -EA 0; Checkpoint-Computer -Description "PotatoPC" -RestorePointType "MODIFY_SETTINGS" -EA 0 }
    
    # Calls to Logic.ps1 functions
    if($chkTel.Checked){Core-KillService "DiagTrack" $BackupDir $log; Core-KillService "dmwappushservice" $BackupDir $log; Core-RegTweak "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0}
    if($chkCop.Checked){Core-RegTweak "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1}
    if($chkBing.Checked){Core-RegTweak "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1}
    
    if($chkXbox.Checked){Core-RemoveApp "Xbox" $log; Core-KillService "XblAuthManager" $BackupDir $log}
    if($chkMail.Checked){Core-RemoveApp "windowscommunicationsapps" $log}
    if($chkNews.Checked){Core-RemoveApp "BingNews" $log; Core-RemoveApp "BingWeather" $log}
    if($chkCort.Checked){Core-RemoveApp "Cortana" $log; Core-RemoveApp "People" $log}
    if($chkOff.Checked){Core-RemoveApp "MicrosoftOfficeHub" $log}
    
    if($chkSysMain.Checked){$ssd=Get-PhysicalDisk|Where{$_.MediaType-eq'SSD'};if($ssd){Core-KillService "SysMain" $BackupDir $log}}
    if($chkAnim.Checked){Core-RegTweak "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2}
    if($chkDVR.Checked){Core-RegTweak "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0; Core-KillService "BcastDVRUserService*" $BackupDir $log}
    if($chkSticky.Checked){Core-RegTweak "HKCU:\Control Panel\Accessibility\StickyKeys" "Flags" 506}
    if($chkHib.Checked){powercfg -h off}
    if($chkExt.Checked){Core-RegTweak "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt" 0}
    if($chkMouse.Checked){Core-RegTweak "HKCU:\Control Panel\Mouse" "MouseSpeed" 0}

    if($chkTmp.Checked){Remove-Item "$env:TEMP\*" -Recurse -Force -EA 0}
    if($chkLog.Checked){Get-WinEvent -ListLog * -EA 0 | % { Wevtutil cl $_.LogName 2>$null }}
    if($chkUpdCache.Checked){Stop-Service wuauserv -Force -EA 0; Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -EA 0; Start-Service wuauserv -EA 0}
    if($chkDns.Checked){Clear-DnsClientCache}
    if($chkBin.Checked){Clear-RecycleBin -Force -EA 0}
    if($chkDism.Checked){Log $log "DISM..." "Orange"; Dism.exe /online /Cleanup-Image /StartComponentCleanup | Out-Null}

    $form.Enabled=$true; $form.Cursor="Default"; Log $log "Done." "Green"; [System.Windows.Forms.MessageBox]::Show("Готово!")
})
$breboot.Add_Click({ Restart-Computer -Force })

$form.ShowDialog()

