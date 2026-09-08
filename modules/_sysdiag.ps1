function ConvertTo-XmlText {
    param([string]$Text)
    return [System.Security.SecurityElement]::Escape($Text)
}

function Build-SysPanel {
    $sysInfo = Get-SystemInfo
    $allDisks = @()
    try {
        foreach ($ld in (Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 })) {
            try {
                $part = Get-CimInstance -Query "ASSOCIATORS OF {Win32_LogicalDisk.DeviceID='$($ld.DeviceID)'} WHERE AssocClass=Win32_LogicalDiskToPartition" | Select-Object -First 1
                $phys = Get-CimInstance -Query "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($part.DeviceID)'} WHERE AssocClass=Win32_DiskDriveToDiskPartition" | Select-Object -First 1
                $model = ($phys.Model -replace '\s+',' ').Trim()
            } catch { $model="Неизвестно"; $phys=$null }
            $allDisks += @{ Letter=$ld.DeviceID; Model=$model; FreeGB=[math]::Round($ld.FreeSpace/1GB,1); TotalGB=[math]::Round($ld.Size/1GB,1); IsSystem=($ld.DeviceID -eq "C:"); PhysDisk=$phys }
        }
    } catch {}

    $sysPanel.Children.Clear()

    # Панель инструментов сводки
    $sysTools = [System.Windows.Controls.Border]::new()
    $sysTools.Margin = [System.Windows.Thickness]::new(0,0,0,4)
    $sysTools.Padding = [System.Windows.Thickness]::new(0,0,0,6)
    $sysTools.BorderBrush = $script:Theme.CardBorder
    $sysTools.BorderThickness = $script:Theme.BorderBottom
    $sysToolsGrid = [System.Windows.Controls.Grid]::new()
    $stc1=[System.Windows.Controls.ColumnDefinition]::new(); $stc1.Width=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
    $stc2=[System.Windows.Controls.ColumnDefinition]::new(); $stc2.Width=[System.Windows.GridLength]::Auto
    $sysToolsGrid.ColumnDefinitions.Add($stc1); $sysToolsGrid.ColumnDefinitions.Add($stc2)
    $sysToolsTitle = [System.Windows.Controls.TextBlock]::new()
    $sysToolsTitle.Text = "СВОДКА СИСТЕМЫ"; $sysToolsTitle.Foreground = $script:Theme.Accent
    $sysToolsTitle.FontSize = 11; $sysToolsTitle.FontWeight = "SemiBold"; $sysToolsTitle.VerticalAlignment = "Center"
    $sysCopyBtn = [System.Windows.Controls.Button]::new()
    $sysCopyBtn.Content = (New-IconButtonContent -Text 'Копировать сводку' -Icon 'actions/copy' -Size 11)
    $sysCopyBtn.Background = $script:Theme.CardBgHover; $sysCopyBtn.Foreground = $script:Theme.TextSecondary
    $sysCopyBtn.BorderThickness = $script:Theme.BorderThin; $sysCopyBtn.BorderBrush = $script:Theme.CardBorder
    $sysCopyBtn.Cursor = [System.Windows.Input.Cursors]::Hand; $sysCopyBtn.FontSize = 11
    $sysCopyBtn.Padding = [System.Windows.Thickness]::new(10,5,10,5); $sysCopyBtn.ToolTip = "Скопировать сводку в буфер обмена"
    $sysCopyBtn.Add_Click({
        try {
            [System.Windows.Clipboard]::SetText([string]$script:SysSummaryText)
            Write-Log "Сводка системы скопирована" -Color "Green"
        } catch { Write-Log ("Не удалось скопировать: " + $_) -Color "Yellow" }
    })
    [System.Windows.Controls.Grid]::SetColumn($sysCopyBtn,1)
    $sysToolsGrid.Children.Add($sysToolsTitle) | Out-Null; $sysToolsGrid.Children.Add($sysCopyBtn) | Out-Null
    $sysTools.Child = $sysToolsGrid
    $sysPanel.Children.Add($sysTools) | Out-Null

    foreach ($item in @(
        @{ L="ОС"; V=$sysInfo.OS; Icon="devices/computer"; Btn=$null }
        @{ L="Процессор"; V=$sysInfo.CPU; Icon="devices/hw_cpu"; Btn=$null }
        @{ L="RAM"; V=$sysInfo.RAM; Icon="devices/hw_memory"; Btn=$null }
        @{ L="Windows"; V="Windows $($script:WindowsMajorVersion)"; Icon="status/info"; Btn=$null }
        @{ L="Время работы"; V=$sysInfo.Uptime; Icon="actions/power"; Btn=$null }
        @{ L="Рабочая папка"; V=$script:WorkFolder; Icon="places/folder_open"; Btn="Открыть" }
    )) {
        $row=[System.Windows.Controls.Border]::new()
        $row.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#26262e"); $row.CornerRadius=[System.Windows.CornerRadius]::new(8)
        $row.Margin=[System.Windows.Thickness]::new(0,4,0,4); $row.Padding=[System.Windows.Thickness]::new(16,12,16,12)
        $g=[System.Windows.Controls.Grid]::new()
        $c0=[System.Windows.Controls.ColumnDefinition]::new(); $c0.Width=[System.Windows.GridLength]::new(30)
        $c1=[System.Windows.Controls.ColumnDefinition]::new(); $c1.Width=[System.Windows.GridLength]::new(150)
        $c2=[System.Windows.Controls.ColumnDefinition]::new(); $c2.Width=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
        $c3=[System.Windows.Controls.ColumnDefinition]::new(); $c3.Width=[System.Windows.GridLength]::Auto
        $g.ColumnDefinitions.Add($c0); $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2); $g.ColumnDefinitions.Add($c3)
        $rowIcon = Get-IconImage -Name $item.Icon -Size 16
        if ($rowIcon) { [System.Windows.Controls.Grid]::SetColumn($rowIcon,0); $g.Children.Add($rowIcon) | Out-Null }
        $lbl=[System.Windows.Controls.TextBlock]::new(); $lbl.Text=$item.L; $lbl.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#8a8aa5"); $lbl.FontSize=13; $lbl.VerticalAlignment="Center"
        [System.Windows.Controls.Grid]::SetColumn($lbl,1)
        $val=[System.Windows.Controls.TextBlock]::new(); $val.Text=$item.V; $val.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#d0d0f0"); $val.FontSize=13; $val.FontWeight="SemiBold"; $val.TextWrapping="Wrap"; $val.VerticalAlignment="Center"
        [System.Windows.Controls.Grid]::SetColumn($val,2)
        $g.Children.Add($lbl) | Out-Null; $g.Children.Add($val) | Out-Null
        if ($item.Btn -eq "Открыть") {
            $fp=$item.V
            $ob=[System.Windows.Controls.Button]::new(); $ob.Content="Открыть"; $ob.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#2d2d35")
            $ob.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#d4d4e0"); $ob.BorderThickness=[System.Windows.Thickness]::new(0); $ob.Cursor=[System.Windows.Input.Cursors]::Hand
            $ob.FontSize=11; $ob.Padding=[System.Windows.Thickness]::new(10,5,10,5); $ob.VerticalAlignment="Center"; $ob.Margin=[System.Windows.Thickness]::new(8,0,0,0); $ob.Tag=$fp
            $ob.Add_Click({ $p=$this.Tag; if (-not (Test-Path $p)){New-Item -ItemType Directory -Path $p -Force|Out-Null}; Start-Process explorer.exe $p })
            [System.Windows.Controls.Grid]::SetColumn($ob,3); $g.Children.Add($ob) | Out-Null
        }
        $row.Child=$g; $sysPanel.Children.Add($row) | Out-Null
    }

    if ($allDisks.Count -gt 0) {
        $dh=[System.Windows.Controls.Border]::new(); $dh.Margin=[System.Windows.Thickness]::new(0,8,0,4); $dh.Padding=[System.Windows.Thickness]::new(0,0,0,6)
        $dh.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFrom("#1e1e38"); $dh.BorderThickness=[System.Windows.Thickness]::new(0,0,0,1)
        $dht=[System.Windows.Controls.TextBlock]::new(); $dht.Text="ДИСКИ"; $dht.FontSize=11; $dht.FontWeight="SemiBold"; $dht.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#6c63ff")
        $dh.Child=$dht; $sysPanel.Children.Add($dh) | Out-Null
        foreach ($disk in $allDisks) {
            $drow=[System.Windows.Controls.Border]::new(); $drow.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#26262e"); $drow.CornerRadius=[System.Windows.CornerRadius]::new(8)
            $drow.Margin=[System.Windows.Thickness]::new(0,3,0,3); $drow.Padding=[System.Windows.Thickness]::new(16,10,16,10)
            $dg=[System.Windows.Controls.Grid]::new()
            foreach ($w in @("40","*","Auto","Auto")) { $dc=[System.Windows.Controls.ColumnDefinition]::new(); $dc.Width=$w; $dg.ColumnDefinitions.Add($dc) }
            $dl=[System.Windows.Controls.TextBlock]::new(); $dl.Text=$disk.Letter; $dl.FontSize=14; $dl.FontWeight="Bold"; $dl.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#8080d0"); $dl.VerticalAlignment="Center"
            $di=[System.Windows.Controls.StackPanel]::new(); $di.VerticalAlignment="Center"
            $dm=[System.Windows.Controls.TextBlock]::new(); $dm.Text=$disk.Model; $dm.FontSize=12; $dm.FontWeight="Medium"; $dm.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#d0d0f0"); $dm.TextTrimming="CharacterEllipsis"
            $ds=[System.Windows.Controls.TextBlock]::new(); $ds.Text="$($disk.FreeGB) ГБ своб. из $($disk.TotalGB) ГБ"; $ds.FontSize=10; $ds.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#c4c4ee")
            $di.Children.Add($dm)|Out-Null; $di.Children.Add($ds)|Out-Null
            $usedPct = if ($disk.TotalGB -gt 0) { 100 - (100*$disk.FreeGB/$disk.TotalGB) } else { 0 }
            $barColor = if ($usedPct -ge 90) { "#e74c3c" } elseif ($usedPct -ge 75) { "#f0c040" } else { "#2ecc71" }
            $track=[System.Windows.Controls.Border]::new()
            $track.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a20")
            $track.CornerRadius=[System.Windows.CornerRadius]::new(2); $track.Height=4
            $track.Margin=[System.Windows.Thickness]::new(0,5,0,0); $track.ClipToBounds=$true
            $barGrid=[System.Windows.Controls.Grid]::new()
            $bcu=[System.Windows.Controls.ColumnDefinition]::new(); $bcu.Width=[System.Windows.GridLength]::new($usedPct,[System.Windows.GridUnitType]::Star)
            $bcf=[System.Windows.Controls.ColumnDefinition]::new(); $bcf.Width=[System.Windows.GridLength]::new((100-$usedPct),[System.Windows.GridUnitType]::Star)
            $barGrid.ColumnDefinitions.Add($bcu); $barGrid.ColumnDefinitions.Add($bcf)
            $fill=[System.Windows.Controls.Border]::new(); $fill.Background=[Windows.Media.BrushConverter]::new().ConvertFrom($barColor)
            $barGrid.Children.Add($fill) | Out-Null
            $track.Child=$barGrid; $di.Children.Add($track)|Out-Null
            [System.Windows.Controls.Grid]::SetColumn($di,1)
            if ($disk.IsSystem) {
                $sb=[System.Windows.Controls.Border]::new(); $sb.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a4a"); $sb.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFrom("#3a3aaa"); $sb.BorderThickness=[System.Windows.Thickness]::new(1); $sb.CornerRadius=[System.Windows.CornerRadius]::new(4); $sb.Padding=[System.Windows.Thickness]::new(6,2,6,2); $sb.VerticalAlignment="Center"; $sb.Margin=[System.Windows.Thickness]::new(8,0,0,0)
                $st=[System.Windows.Controls.TextBlock]::new(); $st.Text="СИСТЕМА"; $st.FontSize=10; $st.FontWeight="SemiBold"; $st.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#8080ff")
                $sb.Child=$st; [System.Windows.Controls.Grid]::SetColumn($sb,2); $dg.Children.Add($sb)|Out-Null
            }
            $smBtn=[System.Windows.Controls.Button]::new(); $smBtn.Content="SMART"; $smBtn.FontSize=11
            $smBtn.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#1a2a42"); $smBtn.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#7ab0e0"); $smBtn.BorderThickness=[System.Windows.Thickness]::new(0); $smBtn.Cursor=[System.Windows.Input.Cursors]::Hand; $smBtn.Padding=[System.Windows.Thickness]::new(10,4,10,4); $smBtn.VerticalAlignment="Center"; $smBtn.Margin=[System.Windows.Thickness]::new(8,0,0,0); $smBtn.Tag=$disk.PhysDisk
            $smBtn.Add_Click({
                $driveObj=$this.Tag
                try {
                    $physDisk = $null
                    if ($driveObj -and $driveObj.Model) {
                        $firstWord = $driveObj.Model.Trim().Split(' ')[0]
                        if ($firstWord) {
                            $physDisk = Get-PhysicalDisk | Where-Object { $_.FriendlyName -like "*$firstWord*" } | Select-Object -First 1
                        }
                    }
                    if (-not $physDisk) { $physDisk = Get-PhysicalDisk | Select-Object -First 1 }
                    if (-not $physDisk) { throw "Физический диск не найден" }
                    $rel=$physDisk|Get-StorageReliabilityCounter
                    $healthRu=switch($physDisk.HealthStatus){"Healthy"{"Здоров"}"Warning"{"Предупреждение"}"Unhealthy"{"Неисправен"}default{"Неизвестно"}}
                    $healthColor=switch($physDisk.HealthStatus){"Healthy"{"#2ecc71"}"Warning"{"#f39c12"}"Unhealthy"{"#e74c3c"}default{"#a0a0c0"}}
                    $tempVal  = if ($rel -and $rel.Temperature)      { "$([math]::Round($rel.Temperature)) °C" } else { "Нет данных" }
                    $tempCol  = if ($rel -and $rel.Temperature -gt 50) { "#e74c3c" } elseif ($rel -and $rel.Temperature -gt 40) { "#f39c12" } else { "#2ecc71" }
                    $powerVal = if ($rel -and $rel.PowerOnHours)     { "$($rel.PowerOnHours) ч" } else { "Нет данных" }
                    $readVal  = if ($rel -and $rel.ReadErrorsTotal)  { "$($rel.ReadErrorsTotal)" } else { "0" }
                    $readCol  = if ($rel -and $rel.ReadErrorsTotal -gt 0)  { "#f39c12" } else { "#2ecc71" }
                    $writeVal = if ($rel -and $rel.WriteErrorsTotal) { "$($rel.WriteErrorsTotal)" } else { "0" }
                    $writeCol = if ($rel -and $rel.WriteErrorsTotal -gt 0) { "#f39c12" } else { "#2ecc71" }
                    $wearVal  = if ($rel -and $rel.Wear)             { "$($rel.Wear)%" } else { "Нет данных" }
                    $fName    = ConvertTo-XmlText -Text ([string]$physDisk.FriendlyName)
                    $mediaTxt = ConvertTo-XmlText -Text ([string]$physDisk.MediaType)
                    [xml]$sx=@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="SMART" Width="460" Height="420" WindowStartupLocation="CenterScreen" Background="#202020" ResizeMode="NoResize">
  <StackPanel Margin="20">
    <TextBlock Text="$fName" Foreground="White" FontSize="14" FontWeight="Bold" Margin="0,0,0,4"/>
    <TextBlock Text="$mediaTxt  -  $([math]::Round($physDisk.Size/1GB)) ГБ" Foreground="#6a6a85" FontSize="11" Margin="0,0,0,14"/>
    <Border Background="#26262e" CornerRadius="8" Padding="14,9" Margin="0,0,0,5"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Состояние" Foreground="#8a8aa5" FontSize="12" VerticalAlignment="Center"/><TextBlock Grid.Column="1" Text="$healthRu" Foreground="$healthColor" FontSize="12" FontWeight="Bold"/></Grid></Border>
    <Border Background="#26262e" CornerRadius="8" Padding="14,9" Margin="0,0,0,5"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Температура" Foreground="#8a8aa5" FontSize="12" VerticalAlignment="Center"/><TextBlock Grid.Column="1" Text="$tempVal" Foreground="$tempCol" FontSize="12" FontWeight="Bold"/></Grid></Border>
    <Border Background="#26262e" CornerRadius="8" Padding="14,9" Margin="0,0,0,5"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Часов наработки" Foreground="#8a8aa5" FontSize="12" VerticalAlignment="Center"/><TextBlock Grid.Column="1" Text="$powerVal" Foreground="#d0d0f0" FontSize="12" FontWeight="Bold"/></Grid></Border>
    <Border Background="#26262e" CornerRadius="8" Padding="14,9" Margin="0,0,0,5"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Ошибки чтения" Foreground="#8a8aa5" FontSize="12" VerticalAlignment="Center"/><TextBlock Grid.Column="1" Text="$readVal" Foreground="$readCol" FontSize="12" FontWeight="Bold"/></Grid></Border>
    <Border Background="#26262e" CornerRadius="8" Padding="14,9" Margin="0,0,0,5"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Ошибки записи" Foreground="#8a8aa5" FontSize="12" VerticalAlignment="Center"/><TextBlock Grid.Column="1" Text="$writeVal" Foreground="$writeCol" FontSize="12" FontWeight="Bold"/></Grid></Border>
    <Border Background="#26262e" CornerRadius="8" Padding="14,9" Margin="0,0,0,14"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Износ" Foreground="#8a8aa5" FontSize="12" VerticalAlignment="Center"/><TextBlock Grid.Column="1" Text="$wearVal" Foreground="#d0d0f0" FontSize="12" FontWeight="Bold"/></Grid></Border>
    <TextBlock Text="Данные через Windows Storage API. Для детального анализа используйте CrystalDiskInfo." Foreground="#8a8aa5" FontSize="10" TextWrapping="Wrap"/>
  </StackPanel>
</Window>
"@
                    $sr=[System.Xml.XmlNodeReader]::new($sx); $sw=[Windows.Markup.XamlReader]::Load($sr); $sw.ShowDialog()|Out-Null
                } catch { [System.Windows.MessageBox]::Show("Не удалось получить SMART данные:`n$_","SMART","OK","Warning") }
            })
            $smBtn.Add_MouseEnter({ $this.Opacity=0.8 }); $smBtn.Add_MouseLeave({ $this.Opacity=1.0 })
            [System.Windows.Controls.Grid]::SetColumn($smBtn,3)
            $dg.Children.Add($dl)|Out-Null; $dg.Children.Add($di)|Out-Null; $dg.Children.Add($smBtn)|Out-Null
            $drow.Child=$dg; $sysPanel.Children.Add($drow)|Out-Null
        }
    }
    $sumLines = @(
        "PotatoPC сводка [$env:COMPUTERNAME] $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
        "ОС: $($sysInfo.OS)", "CPU: $($sysInfo.CPU)", "RAM: $($sysInfo.RAM)", "Uptime: $($sysInfo.Uptime)"
    )
    foreach ($disk in $allDisks) {
        $sumLines += ("{0} {1}: {2} ГБ своб. из {3} ГБ" -f $disk.Letter, $disk.Model, $disk.FreeGB, $disk.TotalGB)
    }
    $script:SysSummaryText = ($sumLines -join "`r`n")
}

function Build-DiagPanel {
    $diagPanel.Children.Clear()

    # ── Экспресс-аудит: всё за один проход + отчёт в файл ──
    $diagPanel.Children.Add((New-CategoryHeader -Title "Экспресс-аудит инженера")) | Out-Null
    $acard = New-Card -Large
    $acard.BorderBrush = Get-ThemeBrush "#6c63ff"; $acard.BorderThickness = $script:Theme.BorderAccentR
    Add-CardFx -Card $acard
    $ag = [System.Windows.Controls.Grid]::new()
    $ac1=[System.Windows.Controls.ColumnDefinition]::new(); $ac1.Width=[System.Windows.GridLength]::new(44)
    $ac2=[System.Windows.Controls.ColumnDefinition]::new(); $ac2.Width=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
    $ac3=[System.Windows.Controls.ColumnDefinition]::new(); $ac3.Width=[System.Windows.GridLength]::Auto
    $ag.ColumnDefinitions.Add($ac1); $ag.ColumnDefinitions.Add($ac2); $ag.ColumnDefinitions.Add($ac3)
    $aico = Get-IconImage -Name "apps/monitor" -Size 26
    if ($aico) { $aico.HorizontalAlignment = "Center"; [System.Windows.Controls.Grid]::SetColumn($aico,0); $ag.Children.Add($aico) | Out-Null }
    $atxt=[System.Windows.Controls.StackPanel]::new(); $atxt.VerticalAlignment="Center"; $atxt.Margin=[System.Windows.Thickness]::new(12,0,12,0)
    $arow=[System.Windows.Controls.StackPanel]::new(); $arow.Orientation="Horizontal"; $arow.VerticalAlignment="Center"
    $attl=[System.Windows.Controls.TextBlock]::new(); $attl.Text="Проверить всё за один проход"; $attl.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#e0e0f4"); $attl.FontSize=13; $attl.FontWeight="SemiBold"
    $arow.Children.Add($attl) | Out-Null
    $script:AuditStatusLbl=[System.Windows.Controls.TextBlock]::new(); $script:AuditStatusLbl.FontSize=11; $script:AuditStatusLbl.VerticalAlignment="Center"; $script:AuditStatusLbl.Margin=[System.Windows.Thickness]::new(10,0,0,0)
    $script:AuditStatusLbl.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#a8a8d0"); $script:AuditStatusLbl.Text=""
    $arow.Children.Add($script:AuditStatusLbl) | Out-Null
    $adsc=[System.Windows.Controls.TextBlock]::new()
    $adsc.Text="SMART, SFC-проверка, DISM, перезагрузка, обновления, журналы, дампы, службы, драйверы, Defender, диски, память, сеть. Только чтение, 5-15 мин. Отчёт сохраняется в рабочую папку."
    $adsc.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#b8b8cc"); $adsc.FontSize=11; $adsc.Margin=[System.Windows.Thickness]::new(0,3,0,0); $adsc.TextWrapping="Wrap"
    $atxt.Children.Add($arow) | Out-Null; $atxt.Children.Add($adsc) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($atxt,1); $ag.Children.Add($atxt) | Out-Null
    $abtns=[System.Windows.Controls.StackPanel]::new(); $abtns.Orientation="Horizontal"; $abtns.VerticalAlignment="Center"
    $arun=[System.Windows.Controls.Button]::new(); $arun.Content="Проверить всё"
    $arun.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#6c63ff"); $arun.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#ffffff")
    $arun.BorderThickness=[System.Windows.Thickness]::new(0); $arun.Cursor=[System.Windows.Input.Cursors]::Hand; $arun.FontSize=12; $arun.FontWeight="SemiBold"; $arun.Padding=[System.Windows.Thickness]::new(14,8,14,8)
    $arun.Add_MouseEnter({ $this.Opacity=0.85 }); $arun.Add_MouseLeave({ $this.Opacity=1.0 })
    $script:AuditOpenBtn=[System.Windows.Controls.Button]::new(); $script:AuditOpenBtn.Content="Открыть отчёт"
    $script:AuditOpenBtn.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#2d2d35"); $script:AuditOpenBtn.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#d4d4e0")
    $script:AuditOpenBtn.BorderThickness=[System.Windows.Thickness]::new(0); $script:AuditOpenBtn.Cursor=[System.Windows.Input.Cursors]::Hand; $script:AuditOpenBtn.FontSize=12; $script:AuditOpenBtn.Margin=[System.Windows.Thickness]::new(8,0,0,0); $script:AuditOpenBtn.Padding=[System.Windows.Thickness]::new(14,8,14,8)
    $script:AuditOpenBtn.IsEnabled = $false
    if ($script:LastAuditReport -and (Test-Path $script:LastAuditReport)) {
        $script:AuditOpenBtn.IsEnabled = $true
        $script:AuditStatusLbl.Text = "есть отчёт"
        $script:AuditStatusLbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#2ecc71")
    }
    $script:AuditOpenBtn.Add_Click({
        try {
            if ($script:LastAuditReport -and (Test-Path $script:LastAuditReport)) { Start-Process explorer.exe -ArgumentList "/select,`"$script:LastAuditReport`"" }
            else { Write-Log "Отчёта пока нет — запустите аудит" -Color "Yellow" }
        } catch { Write-Log "Не удалось открыть отчёт: $_" -Color "Red" }
    })
    $arun.Add_Click({
        $arun.IsEnabled = $false; $arun.Content = "Выполняется..."
        $script:AuditStatusLbl.Text = "выполняется..."
        $script:AuditStatusLbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#f0c040")
        try { Start-ExpressAudit } catch { Write-Log "Не удалось запустить аудит: $_" -Color "Red" }
        $t = New-Object System.Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromMilliseconds(500)
        $t.Add_Tick({
            $t.Stop()
            try { $arun.IsEnabled = $true; $arun.Content = "Проверить всё" } catch {}
        }.GetNewClosure())
        $t.Start()
    }.GetNewClosure())
    $abtns.Children.Add($arun) | Out-Null; $abtns.Children.Add($script:AuditOpenBtn) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($abtns,2); $ag.Children.Add($abtns) | Out-Null
    $acard.Child = $ag
    $diagPanel.Children.Add($acard) | Out-Null

    $tests = @(
        @{ Group="Быстрые проверки (без изменений)"; Title="SMART всех дисков"; Desc="Здоровье, температура, наработка и ошибки чтения/записи через Storage API."; IconSlot="devices/drive"; Color="#2da86a"
           Action={ Start-Background { $ss=@(Get-SmartAll); if ($ss.Count -eq 0) { Write-Log "SMART недоступен" -Color "Yellow"; return }; foreach ($s in $ss) { Write-Log ("{0} [{1}]: {2}{3}{4}" -f $s.Disk,$s.Media,$s.Health, $(if($s.Temp){" $($s.Temp)C"}else{""}), $(if($s.Hours){" $($s.Hours)ч"}else{""})) } } } }
        @{ Group="Быстрые проверки (без изменений)"; Title="SFC-проверка (verifyonly)"; Desc="Только проверка целостности, без восстановления. 3-10 минут."; IconSlot="actions/search"; Color="#4a90d9"
           Action={ Start-Background { Write-Log "SFC /verifyonly..."; $o=sfc /verifyonly 2>&1|Out-String; ($o -split "`n" | Where-Object {$_ -match "\S"} | Select-Object -Last 4) | ForEach-Object {Write-Log "  $_"} } } }
        @{ Group="Быстрые проверки (без изменений)"; Title="DISM CheckHealth"; Desc="Быстрая проверка образа Windows (секунды, без изменений)."; IconSlot="actions/restore"; Color="#7c63ff"
           Action={ Start-Background { $o=DISM /Online /Cleanup-Image /CheckHealth 2>&1|Out-String; ($o -split "`n" | Where-Object {$_ -match "\S"} | Select-Object -Last 4) | ForEach-Object {Write-Log "  $_"}; Write-Log "DISM CheckHealth завершён" -Color "Green" } } }
        @{ Group="Быстрые проверки (без изменений)"; Title="CHKDSK C: (чтение)"; Desc="Проверка ФС без исправлений и без перезагрузки. 2-10 минут."; IconSlot="apps/terminal"; Color="#2da86a"
           Action={ Start-Background { Write-Log "CHKDSK C: (только чтение)..."; $o=chkdsk C: 2>&1|Out-String; ($o -split "`n" | Where-Object {$_ -match "\S"} | Select-Object -Last 6) | ForEach-Object {Write-Log "  $_"} } } }
        @{ Group="Быстрые проверки (без изменений)"; Title="Ожидание перезагрузки"; Desc="CBS, WindowsUpdate, PendingFileRename, pending.xml. Мгновенно."; IconSlot="status/warn"; Color="#d4a017"
           Action={ $pr=@(Test-PendingReboot); if ($pr.Count -eq 0) { Write-Log "Перезагрузка не требуется" -Color "Green" } else { Write-Log ("Требуется перезагрузка: " + ($pr -join ", ")) -Color "Yellow" } } }
        @{ Group="Быстрые проверки (без изменений)"; Title="Сбои обновлений (14 дней)"; Desc="История Windows Update: failed/aborted за 2 недели."; IconSlot="apps/nav_updates"; Color="#4a90d9"
           Action={ $uf=@(Get-UpdateFailures -Days 14); if ($uf.Count -eq 0) { Write-Log "Сбоев обновлений за 14 дней нет" -Color "Green" } else { Write-Log ("Сбоев: " + $uf.Count) -Color "Red"; $uf | Select-Object -First 5 | ForEach-Object { Write-Log ("  {0:dd.MM} [{1}] {2}" -f $_.Date,$_.Result,$_.Title) } } } }
        @{ Group="Быстрые проверки (без изменений)"; Title="Статус Defender"; Desc="Режим, возраст сигнатур. Без сканирования."; IconSlot="status/password"; Color="#7c63ff"
           Action={ $ds=Get-DefenderStatus; if (-not $ds.Ok) { Write-Log "Defender недоступен (сторонний АВ?)" -Color "Yellow" } else { Write-Log ("Defender: $($ds.Mode), сигнатуры $($ds.SigAge) дн. назад") -Color "Green" } } }
        @{ Group="Быстрые проверки (без изменений)"; Title="Батарея"; Desc="Заряд и статус через CIM. На ПК без батареи так и скажет."; IconSlot="actions/power"; Color="#d4a017"
           Action={ try { $b=@(Get-CimInstance Win32_Battery -ErrorAction Stop); if ($b.Count -eq 0) { Write-Log "Батареи нет (стационарный ПК)" } else { $b | ForEach-Object { Write-Log ("Батарея: {0}% (статус {1})" -f $_.EstimatedChargeRemaining,$_.BatteryStatus) -Color "Green" } } } catch { Write-Log "Нет данных о батарее" -Color "Yellow" } } }
        @{ Group="Быстрые проверки (без изменений)"; Title="Сеть: шлюз / DNS / интернет"; Desc="По одному ping: шлюз, 1.1.1.1, 8.8.8.8."; IconSlot="devices/network"; Color="#4a90d9"
           Action={ Start-Background { foreach ($n in (Test-QuickNetwork)) { if ($n.Ok) { Write-Log ("Сеть {0}: {1} OK" -f $n.Name,$n.Note) -Color "Green" } else { Write-Log ("Сеть {0}: {1} НЕТ" -f $n.Name,$n.Note) -Color "Red" } } } } }
        @{ Group="Журналы и сбои"; Title="Ошибки журналов (24 ч)"; Desc="System + Application, уровни Critical/Error, топ источников."; IconSlot="actions/doc_new"; Color="#d4601a"
           Action={ Start-Background { $ee=@(Get-RecentEventErrors -Hours 24 -Max 100); Write-Log ("Ошибок System+Application за 24ч: " + $ee.Count); $ee | Group-Object Source | Sort-Object Count -Descending | Select-Object -First 8 | ForEach-Object { Write-Log ("  {0}: {1}" -f $_.Name,$_.Count) } } } }
        @{ Group="Журналы и сбои"; Title="Minidumps (BSOD)"; Desc="Последние 5 дампов из C:\\Windows\\Minidump."; IconSlot="status/err"; Color="#e74c3c"
           Action={ $dd=@(Get-MiniDumps -Max 5); if ($dd.Count -eq 0) { Write-Log "Minidump-ов нет" -Color "Green" } else { Write-Log ("Minidump-ов: " + $dd.Count) -Color "Red"; $dd | ForEach-Object { Write-Log ("  {0:dd.MM.yyyy HH:mm} {1}" -f $_.LastWriteTime,$_.Name) } } } }
        @{ Group="Журналы и сбои"; Title="Службы автозапуска"; Desc="Службы Auto, которые сейчас не работают."; IconSlot="actions/play"; Color="#d4a017"
           Action={ $fs=@(Get-FailedAutoServices); if ($fs.Count -eq 0) { Write-Log "Все службы автозапуска работают" -Color "Green" } else { Write-Log ("Не запущено: " + $fs.Count) -Color "Yellow"; $fs | Select-Object -First 8 | ForEach-Object { Write-Log ("  {0} [{1}]" -f $_.Name,$_.State) } } } }
        @{ Group="Журналы и сбои"; Title="Драйверы с ошибками"; Desc="Устройства с ConfigManagerErrorCode <> 0."; IconSlot="apps/tools"; Color="#d4601a"
           Action={ Start-Background { $dp=@(Get-DriverProblems); if ($dp.Count -eq 0) { Write-Log "Устройства без ошибок" -Color "Green" } else { Write-Log ("Устройств с ошибками: " + $dp.Count) -Color "Red"; $dp | Select-Object -First 8 | ForEach-Object { Write-Log ("  {0} (код {1})" -f $_.Name,$_.ConfigManagerErrorCode) } } } } }
        @{ Group="Глубокие тесты (долго, с изменениями)"; Title="Проверка системных файлов (SFC)"; Desc="Сканирует и восстанавливает повреждённые файлы Windows. Занимает 5-15 минут."; IconSlot="status/info"; Color="#4a90d9"
           Action={ Start-Background { sfc /scannow 2>&1|ForEach-Object{Write-Log "  $_"}; Write-Log "SFC завершён" -Color "Green" } } }
        @{ Group="Глубокие тесты (долго, с изменениями)"; Title="Восстановление Windows (DISM)"; Desc="Восстанавливает образ через Windows Update. Требует интернет. Занимает 10-30 минут."; IconSlot="actions/restore"; Color="#7c63ff"
           Action={ Start-Background { DISM /Online /Cleanup-Image /RestoreHealth 2>&1|ForEach-Object{Write-Log "  $_"}; Write-Log "DISM завершён" -Color "Green" } } }
        @{ Group="Глубокие тесты (долго, с изменениями)"; Title="Проверка диска C: (CHKDSK)"; Desc="Проверяет ФС на ошибки. Полная проверка - при перезагрузке."; IconSlot="devices/drive"; Color="#2da86a"
           Action={
               $confirm=[System.Windows.MessageBox]::Show("CHKDSK запланирован на следующую перезагрузку.`nПерезагрузить сейчас?","CHKDSK","YesNo","Question")
               Start-Process cmd -WindowStyle Hidden -ArgumentList '/c','echo Y|chkdsk C: /f /r' -Wait
               if($confirm-eq"Yes"){Write-Log "Перезагрузка через 30 сек..."; shutdown /r /t 30 /c "PotatoPC CHKDSK"}
               else{Write-Log "CHKDSK выполнится при следующей перезагрузке." -Color "Yellow"}
           } }
        @{ Group="Глубокие тесты (долго, с изменениями)"; Title="Диагностика RAM"; Desc="Windows Memory Diagnostic. Требует перезагрузку."; IconSlot="devices/computer"; Color="#d4601a"
           Action={
               $confirm=[System.Windows.MessageBox]::Show("Диагностика запустится после перезагрузки.`nПерезагрузить сейчас?","RAM","YesNo","Question")
               if($confirm-eq"Yes"){Write-Log "Запуск MdSched..."; Start-Process MdSched.exe}
               else{Write-Log "Диагностика RAM отменена." -Color "Yellow"}
           } }
    )

    $curGroup = ""
    foreach ($test in $tests) {
        if ($test.Group -and $test.Group -ne $curGroup) {
            $curGroup = $test.Group
            $diagPanel.Children.Add((New-CategoryHeader -Title $curGroup)) | Out-Null
        }
        $card=[System.Windows.Controls.Border]::new(); $card.Background=$script:Theme.CardBg; $card.CornerRadius=[System.Windows.CornerRadius]::new(10); $card.Margin=[System.Windows.Thickness]::new(0,5,0,5); $card.Padding=[System.Windows.Thickness]::new(16,14,16,14)
        $card.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFrom($test.Color+"55"); $card.BorderThickness=[System.Windows.Thickness]::new(0,0,0,2)
        $g=[System.Windows.Controls.Grid]::new()
        $c1=[System.Windows.Controls.ColumnDefinition]::new(); $c1.Width=[System.Windows.GridLength]::new(44)
        $c2=[System.Windows.Controls.ColumnDefinition]::new(); $c2.Width=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
        $c3=[System.Windows.Controls.ColumnDefinition]::new(); $c3.Width=[System.Windows.GridLength]::Auto
        $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2); $g.ColumnDefinitions.Add($c3)

        $icoImg = $null
        try { if ($test.IconSlot) { $icoImg = Get-IconImage -Name $test.IconSlot -Size 26 } } catch {}
        if ($icoImg) { $icoImg.HorizontalAlignment = "Center" }
        else {
            $icoImg = [System.Windows.Controls.TextBlock]::new()
            $icoImg.Text = "i"; $icoImg.FontSize = 26; $icoImg.FontWeight = "Bold"
            $icoImg.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom($test.Color)
            $icoImg.VerticalAlignment = "Center"; $icoImg.HorizontalAlignment = "Center"
        }
        [System.Windows.Controls.Grid]::SetColumn($icoImg,0)

        $txt=[System.Windows.Controls.StackPanel]::new(); $txt.VerticalAlignment="Center"; $txt.Margin=[System.Windows.Thickness]::new(12,0,12,0)
        $titleRow=[System.Windows.Controls.StackPanel]::new(); $titleRow.Orientation="Horizontal"
        $ttl=[System.Windows.Controls.TextBlock]::new(); $ttl.Text=$test.Title; $ttl.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#e0e0f4"); $ttl.FontSize=13; $ttl.FontWeight="SemiBold"
        $statusLbl=[System.Windows.Controls.TextBlock]::new(); $statusLbl.FontSize=11; $statusLbl.VerticalAlignment="Center"; $statusLbl.Margin=[System.Windows.Thickness]::new(10,0,0,0); $statusLbl.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#a8a8d0"); $statusLbl.Text=""
        $titleRow.Children.Add($ttl)|Out-Null; $titleRow.Children.Add($statusLbl)|Out-Null
        $dsc=[System.Windows.Controls.TextBlock]::new(); $dsc.Text=$test.Desc; $dsc.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#b8b8cc"); $dsc.FontSize=11; $dsc.Margin=[System.Windows.Thickness]::new(0,3,0,0); $dsc.TextWrapping="Wrap"
        $txt.Children.Add($titleRow)|Out-Null; $txt.Children.Add($dsc)|Out-Null
        [System.Windows.Controls.Grid]::SetColumn($txt,1)

        $btn=[System.Windows.Controls.Button]::new(); $btn.Content="Запустить"
        $btn.Background=[Windows.Media.BrushConverter]::new().ConvertFrom($test.Color); $btn.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#ffffff")
        $btn.BorderThickness=[System.Windows.Thickness]::new(0); $btn.Cursor=[System.Windows.Input.Cursors]::Hand; $btn.FontSize=12; $btn.FontWeight="SemiBold"; $btn.Padding=[System.Windows.Thickness]::new(14,8,14,8); $btn.VerticalAlignment="Center"
        $btn.Add_MouseEnter({ $this.Opacity=0.85 }); $btn.Add_MouseLeave({ $this.Opacity=1.0 })

        $capturedAction  = $test.Action
        $capturedBtn     = $btn
        $capturedLbl     = $statusLbl

        $btn.Add_Click({
            $capturedBtn.IsEnabled = $false
            $capturedBtn.Content = "Выполняется..."
            $capturedLbl.Text = "запущено"
            $capturedLbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#f0c040")

            $localAction = $capturedAction
            $localBtn    = $capturedBtn
            $localLbl    = $capturedLbl

            try { & $localAction } catch { Write-Log "X $_" -Color "Red" }

            $reenable = New-Object System.Windows.Threading.DispatcherTimer
            $reenable.Interval = [TimeSpan]::FromMilliseconds(500)
            $reenable.Add_Tick({
                $reenable.Stop()
                try {
                    $localBtn.IsEnabled = $true
                    $localBtn.Content = "Запустить"
                    $localLbl.Text = "запущено в фоне"
                    $localLbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#2ecc71")
                } catch {}
            }.GetNewClosure())
            $reenable.Start()
        }.GetNewClosure())

        [System.Windows.Controls.Grid]::SetColumn($btn,2)
        $g.Children.Add($icoImg)|Out-Null; $g.Children.Add($txt)|Out-Null; $g.Children.Add($btn)|Out-Null; $card.Child=$g
        Add-CardFx -Card $card
        $card.Add_MouseEnter({ $this.Background=$script:Theme.CardBgHover })
        $card.Add_MouseLeave({ $this.Background=$script:Theme.CardBg })
        $diagPanel.Children.Add($card)|Out-Null
    }
}