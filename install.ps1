Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

# --- ПРОВЕРКА ПРАВ АДМИНИСТРАТОРА ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    [Windows.Forms.MessageBox]::Show("Запустите программу от имени АДМИНИСТРАТОРА!", "Ошибка доступа")
    exit
}

# --- ЗАГРУЗКА ДАННЫХ ---
$JsonUrl = "https://raw.githubusercontent.com/DezFix/PotatoPC/main/apps.json"
try { 
    $AppData = Invoke-RestMethod -Uri $JsonUrl 
    $AppLookup = @{}
    foreach ($cat in $AppData.ManualCategories.PSObject.Properties) {
        foreach ($app in $cat.Value) {
            $AppLookup[$app.Id] = @{ Name = $app.Name; Desc = $app.Description }
        }
    }
} catch { $AppData = $null }

$Global:UpdatesList = @()
$C_BG     = [Drawing.Color]::FromArgb(20, 20, 20)
$C_Panel  = [Drawing.Color]::FromArgb(40, 40, 40)
$C_Accent = [Drawing.Color]::Yellow
$C_Green  = [Drawing.Color]::Lime

# --- ОКНО ---
$Form = New-Object Windows.Forms.Form
$Form.Text = "WICKED RAVEN : SOFTWARE MANAGER"
$Form.Size = New-Object Drawing.Size(960, 920)
$Form.StartPosition = "CenterScreen"
$Form.BackColor = $C_BG
$Form.ForeColor = [Drawing.Color]::White
$Form.FormBorderStyle = "FixedSingle"
$Form.MaximizeBox = $false

$ToolTip = New-Object Windows.Forms.ToolTip
$ToolTip.InitialDelay = 500

$Header = New-Object Windows.Forms.Label
$Header.Text = "WICKED RAVEN SOFTWARE MANAGER"
$Header.Font = New-Object Drawing.Font("Consolas", 18, [Drawing.FontStyle]::Bold)
$Header.ForeColor = $C_Accent ; $Header.TextAlign = "MiddleCenter" ; $Header.Size = New-Object Drawing.Size(940, 50) ; $Header.Location = New-Object Drawing.Point(0, 10)
$Form.Controls.Add($Header)

$TabControl = New-Object Windows.Forms.TabControl
$TabControl.Size = New-Object Drawing.Size(900, 550) ; $TabControl.Location = New-Object Drawing.Point(25, 70)
$Form.Controls.Add($TabControl)

$LogBox = New-Object Windows.Forms.TextBox
$LogBox.Multiline = $true ; $LogBox.ReadOnly = $true ; $LogBox.ScrollBars = "Vertical" ; $LogBox.Size = New-Object Drawing.Size(900, 220) ; $LogBox.Location = New-Object Drawing.Point(25, 640)
$LogBox.BackColor = [Drawing.Color]::Black ; $LogBox.ForeColor = $C_Green ; $LogBox.Font = New-Object Drawing.Font("Consolas", 10) ; $LogBox.BorderStyle = "FixedSingle"
$Form.Controls.Add($LogBox)

function Write-Log($Text) { 
    $LogBox.AppendText("[( $(Get-Date -Format 'HH:mm:ss') )] $Text`r`n") 
    $LogBox.ScrollToCaret() 
    [System.Windows.Forms.Application]::DoEvents() 
}

# --- ИСПРАВЛЕННАЯ ЛОГИКА ГАЛОЧЕК ---
$script:InternalCheck = $false
function Add-SmartCheck($tree) {
    $tree.Add_AfterCheck({
        param($sender, $e)
        if ($script:InternalCheck) { return }
        $script:InternalCheck = $true
        
        # Рекурсивная функция для детей
        function Update-Children($node, $state) {
            foreach ($child in $node.Nodes) {
                $child.Checked = $state
                Update-Children $child $state
            }
        }
        
        # Рекурсивная функция для родителей
        function Update-Parent($node) {
            $parent = $node.Parent
            if ($null -eq $parent) { return }
            
            $anyUnchecked = $false
            foreach ($sibling in $parent.Nodes) {
                if (-not $sibling.Checked) { $anyUnchecked = $true; break }
            }
            # Если хоть один не выбран - папка не выбрана. Если все выбраны - папка выбрана.
            $parent.Checked = (-not $anyUnchecked)
            Update-Parent $parent
        }

        try {
            Update-Children $e.Node $e.Node.Checked
            Update-Parent $e.Node
        } finally {
            $script:InternalCheck = $false
        }
    })
}

# ==============================================================================
# ВКЛАДКА 1: УПРАВЛЕНИЕ ПО
# ==============================================================================
$T_Main = New-Object Windows.Forms.TabPage ; $T_Main.Text = " УПРАВЛЕНИЕ ПО " ; $T_Main.BackColor = $C_Panel
$TabControl.Controls.Add($T_Main)

# Исправленное поле поиска (без лишних эффектов)
$L_Search = New-Object Windows.Forms.Label ; $L_Search.Text = "ПОИСК:" ; $L_Search.Location = New-Object Drawing.Point(15, 18) ; $L_Search.Size = New-Object Drawing.Size(60, 20) ; $L_Search.ForeColor = $C_Accent ; $L_Search.Font = New-Object Drawing.Font("Segoe UI", 10, [Drawing.FontStyle]::Bold)
$T_Main.Controls.Add($L_Search)

$SearchBox = New-Object Windows.Forms.TextBox
$SearchBox.Size = New-Object Drawing.Size(340, 25)
$SearchBox.Location = New-Object Drawing.Point(80, 16)
$SearchBox.BackColor = [Drawing.Color]::Black
$SearchBox.ForeColor = [Drawing.Color]::White
$SearchBox.BorderStyle = "FixedSingle" # Убирает 3D эффект и возможные баги отрисовки
$T_Main.Controls.Add($SearchBox)

$TreeApps = New-Object Windows.Forms.TreeView ; $TreeApps.CheckBoxes = $true ; $TreeApps.Size = New-Object Drawing.Size(415, 340) ; $TreeApps.Location = New-Object Drawing.Point(15, 85) ; $TreeApps.BackColor = $C_BG ; $TreeApps.ForeColor = [Drawing.Color]::White ; $TreeApps.BorderStyle = "FixedSingle"
$T_Main.Controls.Add($TreeApps) ; Add-SmartCheck $TreeApps

$TreeApps.Add_MouseMove({
    $node = $TreeApps.GetNodeAt($args[1].Location)
    if ($node -and $node.Tag -and $AppLookup.ContainsKey($node.Tag)) { $ToolTip.SetToolTip($TreeApps, $AppLookup[$node.Tag].Desc) } else { $ToolTip.SetToolTip($TreeApps, "") }
})

$ListViewUpd = New-Object Windows.Forms.ListView ; $ListViewUpd.View = "Details" ; $ListViewUpd.CheckBoxes = $true ; $ListViewUpd.FullRowSelect = $true ; $ListViewUpd.Size = New-Object Drawing.Size(415, 340) ; $ListViewUpd.Location = New-Object Drawing.Point(445, 85) ; $ListViewUpd.BackColor = $C_BG ; $ListViewUpd.ForeColor = [Drawing.Color]::White ; $ListViewUpd.BorderStyle = "FixedSingle"
$ListViewUpd.Columns.Add("Программа", 180) | Out-Null ; $ListViewUpd.Columns.Add("Установлено", 100) | Out-Null ; $ListViewUpd.Columns.Add("Доступно", 100) | Out-Null
$T_Main.Controls.Add($ListViewUpd)

$BtnScan = New-Object Windows.Forms.Button ; $BtnScan.Text = "СКАНЕР ОБНОВЛЕНИЙ" ; $BtnScan.Size = New-Object Drawing.Size(150, 25) ; $BtnScan.Location = New-Object Drawing.Point(445, 15) ; $BtnScan.FlatStyle = "Flat" ; $BtnScan.BackColor = [Drawing.Color]::Gray ; $T_Main.Controls.Add($BtnScan)
$BtnStart = New-Object Windows.Forms.Button ; $BtnStart.Text = "ВЫПОЛНИТЬ ВЫБРАННЫЕ ДЕЙСТВИЯ" ; $BtnStart.Size = New-Object Drawing.Size(845, 40) ; $BtnStart.Location = New-Object Drawing.Point(15, 440) ; $BtnStart.FlatStyle = "Flat" ; $BtnStart.BackColor = [Drawing.Color]::DarkGreen ; $BtnStart.Font = New-Object Drawing.Font("Segoe UI", 10, [Drawing.FontStyle]::Bold) ; $T_Main.Controls.Add($BtnStart)

# Кнопки выделить/снять
$BtnTAll = New-Object Windows.Forms.Button ; $BtnTAll.Text = "Выделить всё" ; $BtnTAll.Size = New-Object Drawing.Size(100, 22) ; $BtnTAll.Location = New-Object Drawing.Point(15, 55) ; $BtnTAll.FlatStyle = "Flat" ; $T_Main.Controls.Add($BtnTAll)
$BtnTNone = New-Object Windows.Forms.Button ; $BtnTNone.Text = "Снять всё" ; $BtnTNone.Size = New-Object Drawing.Size(100, 22) ; $BtnTNone.Location = New-Object Drawing.Point(120, 55) ; $BtnTNone.FlatStyle = "Flat" ; $T_Main.Controls.Add($BtnTNone)
$BtnUAll = New-Object Windows.Forms.Button ; $BtnUAll.Text = "Выделить всё" ; $BtnUAll.Size = New-Object Drawing.Size(100, 22) ; $BtnUAll.Location = New-Object Drawing.Point(445, 55) ; $BtnUAll.FlatStyle = "Flat" ; $T_Main.Controls.Add($BtnUAll)
$BtnUNone = New-Object Windows.Forms.Button ; $BtnUNone.Text = "Снять всё" ; $BtnUNone.Size = New-Object Drawing.Size(100, 22) ; $BtnUNone.Location = New-Object Drawing.Point(550, 55) ; $BtnUNone.FlatStyle = "Flat" ; $T_Main.Controls.Add($BtnUNone)

# ==============================================================================
# ВКЛАДКА 2: ПРЕСЕТЫ
# ==============================================================================
$T_Presets = New-Object Windows.Forms.TabPage ; $T_Presets.Text = " ПРЕСЕТЫ " ; $T_Presets.BackColor = $C_Panel
$TabControl.Controls.Add($T_Presets)

$TreePresets = New-Object Windows.Forms.TreeView ; $TreePresets.CheckBoxes = $true ; $TreePresets.Size = New-Object Drawing.Size(860, 380) ; $TreePresets.Location = New-Object Drawing.Point(15, 15) ; $TreePresets.BackColor = $C_BG ; $TreePresets.ForeColor = [Drawing.Color]::White ; $TreePresets.BorderStyle = "FixedSingle"
$T_Presets.Controls.Add($TreePresets) ; Add-SmartCheck $TreePresets

$TreePresets.Add_MouseMove({
    $node = $TreePresets.GetNodeAt($args[1].Location)
    if ($node -and $node.Tag -and $AppLookup.ContainsKey($node.Tag)) { $ToolTip.SetToolTip($TreePresets, $AppLookup[$node.Tag].Desc) } else { $ToolTip.SetToolTip($TreePresets, "") }
})

$BtnGoPresets = New-Object Windows.Forms.Button ; $BtnGoPresets.Text = "УСТАНОВИТЬ ВЫБРАННЫЕ ПРЕСЕТЫ" ; $BtnGoPresets.Size = New-Object Drawing.Size(860, 45) ; $BtnGoPresets.Location = New-Object Drawing.Point(15, 410) ; $BtnGoPresets.FlatStyle = "Flat" ; $BtnGoPresets.BackColor = [Drawing.Color]::DarkSlateBlue ; $BtnGoPresets.Font = New-Object Drawing.Font("Segoe UI", 11, [Drawing.FontStyle]::Bold)
$T_Presets.Controls.Add($BtnGoPresets)

# ==============================================================================
# ВКЛАДКА 3: INFO
# ==============================================================================
$T_Info = New-Object Windows.Forms.TabPage ; $T_Info.Text = " [?] INFO " ; $T_Info.BackColor = $C_Panel
$TabControl.Controls.Add($T_Info)
$InfoBox = New-Object Windows.Forms.RichTextBox ; $InfoBox.Size = New-Object Drawing.Size(860, 490) ; $InfoBox.Location = New-Object Drawing.Point(10, 10) ; $InfoBox.BackColor = $C_BG ; $InfoBox.ForeColor = [Drawing.Color]::White ; $InfoBox.ReadOnly = $true ; $InfoBox.BorderStyle = "None" ; $InfoBox.Font = New-Object Drawing.Font("Consolas", 11) ; $T_Info.Controls.Add($InfoBox)
$InfoBox.Text = "ИНСТРУКЦИЯ:`r`n1. ПОИСК фильтрует списки мгновенно.`r`n2. Галочка на папке выделяет всё содержимое.`r`n3. Описания всплывают при наведении.`r`n`nWinGet ручная установка: https://github.com/microsoft/winget-cli/releases"

# ==============================================================================
# ЛОГИКА ФУНКЦИЙ
# ==============================================================================
function Refresh-Tree($Filter = "") {
    $TreeApps.Nodes.Clear()
    if ($null -eq $AppData) { return }
    foreach ($cat in $AppData.ManualCategories.PSObject.Properties) {
        $P = New-Object Windows.Forms.TreeNode($cat.Name) ; $P.ForeColor = [Drawing.Color]::Cyan
        $show = $false
        foreach ($app in $cat.Value) {
            if ($app.Name -match $Filter -or $app.Id -match $Filter) {
                $n = $P.Nodes.Add($app.Name) ; $n.Tag = $app.Id ; $show = $true
            }
        }
        if ($show) { $TreeApps.Nodes.Add($P) | Out-Null ; if($Filter){$P.Expand()} }
    }
}

function Refresh-Updates-View($Filter = "") {
    $ListViewUpd.Items.Clear()
    foreach ($upd in $Global:UpdatesList) {
        if ($upd.Name -match $Filter) {
            $item = New-Object Windows.Forms.ListViewItem($upd.Name)
            $item.Tag = $upd.ID ; $item.SubItems.Add($upd.CurVer) | Out-Null ; $item.SubItems.Add($upd.NewVer) | Out-Null
            $item.Checked = $true ; $ListViewUpd.Items.Add($item) | Out-Null
        }
    }
}

function Load-Presets {
    $TreePresets.Nodes.Clear()
    if ($null -eq $AppData.Presets) { return }
    foreach ($p in $AppData.Presets.PSObject.Properties) {
        $PN = New-Object Windows.Forms.TreeNode($p.Name) ; $PN.ForeColor = $C_Accent
        foreach ($id in $p.Value) {
            $name = if ($AppLookup[$id]) { $AppLookup[$id].Name } else { $id }
            $CN = $PN.Nodes.Add($name) ; $CN.Tag = $id
        }
        $TreePresets.Nodes.Add($PN) | Out-Null
    }
}

$SearchBox.Add_TextChanged({ Refresh-Tree $SearchBox.Text ; Refresh-Updates-View $SearchBox.Text })

$BtnScan.Add_Click({
    $ListViewUpd.Items.Clear() ; $Global:UpdatesList = @()
    Write-Log "Сканирую обновления..."
    $raw = winget upgrade --accept-source-agreements | Select-String -Pattern '^\S+'
    foreach ($line in $raw) {
        $str = $line.ToString().Trim()
        if ($str.StartsWith("Name") -or $str.StartsWith("---") -or $str.StartsWith("Имя")) { continue }
        $p = $str -split '\s{2,}'
        if ($p.Count -ge 2) {
            $Global:UpdatesList += [PSCustomObject]@{
                Name = $p[0]; ID = $p[1]; CurVer = if($p[2]){$p[2]}else{"-"}; NewVer = if($p[3]){$p[3]}else{"New"}
            }
        }
    }
    Refresh-Updates-View $SearchBox.Text
    Write-Log "Найдено: $($Global:UpdatesList.Count)"
})

# Кнопки выделить всё
$BtnTAll.Add_Click({ $script:InternalCheck = $true; foreach($n in $TreeApps.Nodes){ $n.Checked = $true; foreach($s in $n.Nodes){$s.Checked = $true} }; $script:InternalCheck = $false })
$BtnTNone.Add_Click({ $script:InternalCheck = $true; foreach($n in $TreeApps.Nodes){ $n.Checked = $false; foreach($s in $n.Nodes){$s.Checked = $false} }; $script:InternalCheck = $false })
$BtnUAll.Add_Click({ foreach($item in $ListViewUpd.Items){ $item.Checked = $true } })
$BtnUNone.Add_Click({ foreach($item in $ListViewUpd.Items){ $item.Checked = $false } })

$BtnStart.Add_Click({
    Write-Log "--- СТАРТ ЗАДАЧ ---"
    $ids = @()
    foreach($n in $TreeApps.Nodes){ foreach($s in $n.Nodes){ if($s.Checked){ $ids += $s.Tag }}}
    foreach($id in $ids){ Write-Log "Установка: $id" ; Start-Process winget -ArgumentList "install --id $id --silent --accept-package-agreements" -Wait -NoNewWindow }
    foreach($item in $ListViewUpd.Items){ if($item.Checked){ Write-Log "Обновление: $($item.Tag)" ; Start-Process winget -ArgumentList "upgrade --id $($item.Tag) --silent --accept-package-agreements" -Wait -NoNewWindow }}
    Write-Log "--- ГОТОВО ---"
})

$BtnGoPresets.Add_Click({
    Write-Log "--- ЗАПУСК ПРЕСЕТОВ ---"
    $ids = @()
    foreach($n in $TreePresets.Nodes){ foreach($s in $n.Nodes){ if($s.Checked){ $ids += $s.Tag }}}
    foreach($id in ($ids | Select-Object -Unique)){ Write-Log "Установка: $id" ; Start-Process winget -ArgumentList "install --id $id --silent --accept-package-agreements" -Wait -NoNewWindow }
    Write-Log "--- ПРЕСЕТЫ ВЫПОЛНЕНЫ ---"
})

Refresh-Tree ; Load-Presets ; Write-Log "WICKED RAVEN MANAGER ГОТОВ." ; $Form.ShowDialog()
