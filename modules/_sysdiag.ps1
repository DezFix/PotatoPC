function Build-SysPanel {
    $sysInfo = Get-SystemInfo
    $headerOsText.Text = $sysInfo.OS
    $allDisks = @()
    try {
        foreach ($ld in (Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 })) {
            try {
                $part = Get-WmiObject -Query "ASSOCIATORS OF {Win32_LogicalDisk.DeviceID='$($ld.DeviceID)'} WHERE AssocClass=Win32_LogicalDiskToPartition" | Select-Object -First 1
                $phys = Get-WmiObject -Query "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($part.DeviceID)'} WHERE AssocClass=Win32_DiskDriveToDiskPartition" | Select-Object -First 1
                $model = ($phys.Model -replace '\s+',' ').Trim()
            } catch { $model="Неизвестно"; $phys=$null }
            $allDisks += @{ Letter=$ld.DeviceID; Model=$model; FreeGB=[math]::Round($ld.FreeSpace/1GB,1); TotalGB=[math]::Round($ld.Size/1GB,1); IsSystem=($ld.DeviceID -eq "C:"); PhysDisk=$phys }
        }
    } catch {}

    $sysPanel.Children.Clear()
    foreach ($item in @(
        @{ L="ОС"; V=$sysInfo.OS; Btn=$null }
        @{ L="Процессор"; V=$sysInfo.CPU; Btn=$null }
        @{ L="RAM"; V=$sysInfo.RAM; Btn=$null }
        @{ L="Windows"; V="Windows $($script:WindowsMajorVersion)"; Btn=$null }
        @{ L="Время работы"; V=$sysInfo.Uptime; Btn=$null }
        @{ L="Рабочая папка"; V=$script:WorkFolder; Btn="Открыть" }
    )) {
        $row=[System.Windows.Controls.Border]::new()
        $row.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e"); $row.CornerRadius=[System.Windows.CornerRadius]::new(8)
        $row.Margin=[System.Windows.Thickness]::new(0,4,0,4); $row.Padding=[System.Windows.Thickness]::new(16,12,16,12)
        $g=[System.Windows.Controls.Grid]::new()
        $c1=[System.Windows.Controls.ColumnDefinition]::new(); $c1.Width="210"
        $c2=[System.Windows.Controls.ColumnDefinition]::new(); $c2.Width="*"
        $c3=[System.Windows.Controls.ColumnDefinition]::new(); $c3.Width="Auto"
        $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2); $g.ColumnDefinitions.Add($c3)
        $lbl=[System.Windows.Controls.TextBlock]::new(); $lbl.Text=$item.L; $lbl.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#9898b0"); $lbl.FontSize=13; $lbl.VerticalAlignment="Center"
        $val=[System.Windows.Controls.TextBlock]::new(); $val.Text=$item.V; $val.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#d0d0f0"); $val.FontSize=13; $val.FontWeight="SemiBold"; $val.TextWrapping="Wrap"; $val.VerticalAlignment="Center"
        [System.Windows.Controls.Grid]::SetColumn($val,1)
        $g.Children.Add($lbl) | Out-Null; $g.Children.Add($val) | Out-Null
        if ($item.Btn -eq "Открыть") {
            $fp=$item.V
            $ob=[System.Windows.Controls.Button]::new(); $ob.Content="Открыть"; $ob.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#2a2a42")
            $ob.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#c0c0dd"); $ob.BorderThickness=[System.Windows.Thickness]::new(0); $ob.Cursor=[System.Windows.Input.Cursors]::Hand
            $ob.FontSize=11; $ob.Padding=[System.Windows.Thickness]::new(10,5,10,5); $ob.VerticalAlignment="Center"; $ob.Margin=[System.Windows.Thickness]::new(8,0,0,0); $ob.Tag=$fp
            $ob.Add_Click({ $p=$this.Tag; if (-not (Test-Path $p)){New-Item -ItemType Directory -Path $p -Force|Out-Null}; Start-Process explorer.exe $p })
            [System.Windows.Controls.Grid]::SetColumn($ob,2); $g.Children.Add($ob) | Out-Null
        }
        $row.Child=$g; $sysPanel.Children.Add($row) | Out-Null
    }

    if ($allDisks.Count -gt 0) {
        $dh=[System.Windows.Controls.Border]::new(); $dh.Margin=[System.Windows.Thickness]::new(0,8,0,4); $dh.Padding=[System.Windows.Thickness]::new(0,0,0,6)
        $dh.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFrom("#1e1e38"); $dh.BorderThickness=[System.Windows.Thickness]::new(0,0,0,1)
        $dht=[System.Windows.Controls.TextBlock]::new(); $dht.Text="ДИСКИ"; $dht.FontSize=11; $dht.FontWeight="SemiBold"; $dht.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#6c63ff")
        $dh.Child=$dht; $sysPanel.Children.Add($dh) | Out-Null
        foreach ($disk in $allDisks) {
            $drow=[System.Windows.Controls.Border]::new(); $drow.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e"); $drow.CornerRadius=[System.Windows.CornerRadius]::new(8)
            $drow.Margin=[System.Windows.Thickness]::new(0,3,0,3); $drow.Padding=[System.Windows.Thickness]::new(16,10,16,10)
            $dg=[System.Windows.Controls.Grid]::new()
            foreach ($w in @("40","*","Auto","Auto")) { $dc=[System.Windows.Controls.ColumnDefinition]::new(); $dc.Width=$w; $dg.ColumnDefinitions.Add($dc) }
            $dl=[System.Windows.Controls.TextBlock]::new(); $dl.Text=$disk.Letter; $dl.FontSize=14; $dl.FontWeight="Bold"; $dl.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#8080d0"); $dl.VerticalAlignment="Center"
            $di=[System.Windows.Controls.StackPanel]::new(); $di.VerticalAlignment="Center"
            $dm=[System.Windows.Controls.TextBlock]::new(); $dm.Text=$disk.Model; $dm.FontSize=12; $dm.FontWeight="Medium"; $dm.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#d0d0f0"); $dm.TextTrimming="CharacterEllipsis"
            $ds=[System.Windows.Controls.TextBlock]::new(); $ds.Text="$($disk.FreeGB) ГБ своб. из $($disk.TotalGB) ГБ"; $ds.FontSize=10; $ds.Foreground=[Windows.Media.BrushConverter]::new().ConvertFrom("#c4c4ee")
            $di.Children.Add($dm)|Out-Null; $di.Children.Add($ds)|Out-Null; [System.Windows.Controls.Grid]::SetColumn($di,1)
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
                    $physDisk=Get-PhysicalDisk|Where-Object{$driveObj-and($_.FriendlyName-like "*$($driveObj.Model.Trim().Split(' ')[0])*")}|Select-Object -First 1
                    if(-not $physDisk){$physDisk=Get-PhysicalDisk|Select-Object -First 1}
                    $rel=$physDisk|Get-StorageReliabilityCounter
                    $healthRu=switch($physDisk.HealthStatus){"Healthy"{"Здоров"}"Warning"{"Предупреждение"}"Unhealthy"{"Неисправен"}default{"Неизвестно"}}
                    $healthColor=switch($physDisk.HealthStatus){"Healthy"{"#2ecc71"}"Warning"{"#f39c12"}"Unhealthy"{"#e74c3c"}default{"#a0a0c0"}}
                    [xml]$sx=@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="SMART" Width="460" Height="420" WindowStartupLocation="CenterScreen" Background="#12121f" ResizeMode="NoResize">
  <StackPanel Margin="20">
    <TextBlock Text="$($physDisk.FriendlyName)" Foreground="White" FontSize="14" FontWeight="Bold" Margin="0,0,0,4"/>
    <TextBlock Text="$($physDisk.MediaType)  -  $([math]::Round($physDisk.Size/1GB)) ГБ" Foreground="#606080" FontSize="11" Margin="0,0,0,14"/>
    <Border Background="#1a1a2e" CornerRadius="8" Padding="14,9" Margin="0,0,0,5"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Состояние" Foreground="#808090" FontSize="12" VerticalAlignment="Center"/><TextBlock Grid.Column="1" Text="$healthRu" Foreground="$healthColor" FontSize="12" FontWeight="Bold"/></Grid></Border>
    <Border Background="#1a1a2e" CornerRadius="8" Padding="14,9" Margin="0,0,0,5"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Температура" Foreground="#808090" FontSize="12" VerticalAlignment="Center"/><TextBlock Grid.Column="1" Text="$(if($rel.Temperature){"$($rel.Temperature) °C"}else{"Нет данных"})" Foreground="$(if($rel.Temperature -gt 50){"#e74c3c"}elseif($rel.Temperature -gt 40){"#f39c12"}else{"#2ecc71"})" FontSize="12" FontWeight="Bold"/></Grid></Border>
    <Border Background="#1a1a2e" CornerRadius="8" Padding="14,9" Margin="0,0,0,5"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Часов наработки" Foreground="#808090" FontSize="12" VerticalAlignment="Center"/><TextBlock Grid.Column="1" Text="$(if($rel.PowerOnHours){"$($rel.PowerOnHours) ч"}else{"Нет данных"})" Foreground="#d0d0f0" FontSize="12" FontWeight="Bold"/></Grid></Border>
    <Border Background="#1a1a2e" CornerRadius="8" Padding="14,9" Margin="0,0,0,5"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Ошибки чтения" Foreground="#808090" FontSize="12" VerticalAlignment="Center"/><TextBlock Grid.Column="1" Text="$(if($rel.ReadErrorsTotal){"$($rel.ReadErrorsTotal)"}else{"0"})" Foreground="$(if($rel.ReadErrorsTotal -gt 0){"#f39c12"}else{"#2ecc71"})" FontSize="12" FontWeight="Bold"/></Grid></Border>
    <Border Background="#1a1a2e" CornerRadius="8" Padding="14,9" Margin="0,0,0,5"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Ошибки записи" Foreground="#808090" FontSize="12" VerticalAlignment="Center"/><TextBlock Grid.Column="1" Text="$(if($rel.WriteErrorsTotal){"$($rel.WriteErrorsTotal)"}else{"0"})" Foreground="$(if($rel.WriteErrorsTotal -gt 0){"#f39c12"}else{"#2ecc71"})" FontSize="12" FontWeight="Bold"/></Grid></Border>
    <Border Background="#1a1a2e" CornerRadius="8" Padding="14,9" Margin="0,0,0,14"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Износ" Foreground="#808090" FontSize="12" VerticalAlignment="Center"/><TextBlock Grid.Column="1" Text="$(if($rel.Wear){"$($rel.Wear)%"}else{"Нет данных"})" Foreground="#d0d0f0" FontSize="12" FontWeight="Bold"/></Grid></Border>
    <TextBlock Text="Данные через Windows Storage API. Для детального анализа используйте CrystalDiskInfo." Foreground="#9898c8" FontSize="10" TextWrapping="Wrap"/>
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
}

function Build-DiagPanel {
    $diagPanel.Children.Clear()

    $tests = @(
        @{ Title="Проверка системных файлов (SFC)"; Desc="Сканирует и восстанавливает повреждённые файлы Windows. Занимает 5-15 минут."; Icon="S"; Color="#4a90d9"
           Action={ [System.Threading.Tasks.Task]::Run([Action]{ sfc /scannow 2>&1|ForEach-Object{Write-Log "  $_"}; Write-Log "SFC завершён" -Color "Green" }) | Out-Null } }
        @{ Title="Восстановление Windows (DISM)"; Desc="Восстанавливает образ через Windows Update. Требует интернет. Занимает 10-30 минут."; Icon="D"; Color="#7c63ff"
           Action={ [System.Threading.Tasks.Task]::Run([Action]{ DISM /Online /Cleanup-Image /RestoreHealth 2>&1|ForEach-Object{Write-Log "  $_"}; Write-Log "DISM завершён" -Color "Green" }) | Out-Null } }
        @{ Title="Проверка диска C: (CHKDSK)"; Desc="Проверяет ФС на ошибки. Полная проверка - при перезагрузке."; Icon="C"; Color="#2da86a"
           Action={
               $confirm=[System.Windows.MessageBox]::Show("CHKDSK запланирован на следующую перезагрузку.`nПерезагрузить сейчас?","CHKDSK","YesNo","Question")
               Start-Process -WindowStyle Hidden -NoNewWindow cmd -ArgumentList "/c echo Y | chkdsk C: /f /r" -Wait
               if($confirm-eq"Yes"){Write-Log "Перезагрузка через 30 сек..."; shutdown /r /t 30 /c "PotatoPC CHKDSK"}
               else{Write-Log "CHKDSK выполнится при следующей перезагрузке." -Color "Yellow"}
           } }
        @{ Title="Диагностика RAM"; Desc="Windows Memory Diagnostic. Требует перезагрузку."; Icon="R"; Color="#d4601a"
           Action={
               $confirm=[System.Windows.MessageBox]::Show("Диагностика запустится после перезагрузки.`nПерезагрузить сейчас?","RAM","YesNo","Question")
               if($confirm-eq"Yes"){Write-Log "Запуск MdSched..."; MdSched.exe}
               else{Write-Log "Диагностика RAM отменена." -Color "Yellow"}
           } }
    )

    foreach ($test in $tests) {
        $card=[System.Windows.Controls.Border]::new(); $card.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e"); $card.CornerRadius=[System.Windows.CornerRadius]::new(10); $card.Margin=[System.Windows.Thickness]::new(0,5,0,5); $card.Padding=[System.Windows.Thickness]::new(16,14,16,14)
        $card.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFrom($test.Color+"55"); $card.BorderThickness=[System.Windows.Thickness]::new(0,0,0,2)
        $g=[System.Windows.Controls.Grid]::new()
        $c1=[System.Windows.Controls.ColumnDefinition]::new(); $c1.Width=[System.Windows.GridLength]::new(44)
        $c2=[System.Windows.Controls.ColumnDefinition]::new(); $c2.Width=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
        $c3=[System.Windows.Controls.ColumnDefinition]::new(); $c3.Width=[System.Windows.GridLength]::Auto
        $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2); $g.ColumnDefinitions.Add($c3)

        $ico=[System.Windows.Controls.TextBlock]::new(); $ico.Text=$test.Icon; $ico.FontSize=26; $ico.VerticalAlignment="Center"; $ico.HorizontalAlignment="Center"
        [System.Windows.Controls.Grid]::SetColumn($ico,0)

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

            [System.Threading.Tasks.Task]::Run([Action]{
                Start-Sleep -Milliseconds 500
                $localBtn.Dispatcher.Invoke([action]{
                    $localBtn.IsEnabled = $true
                    $localBtn.Content = "Запустить"
                    $localLbl.Text = "запущено в фоне"
                    $localLbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#2ecc71")
                })
            }) | Out-Null
        }.GetNewClosure())

        [System.Windows.Controls.Grid]::SetColumn($btn,2)
        $g.Children.Add($ico)|Out-Null; $g.Children.Add($txt)|Out-Null; $g.Children.Add($btn)|Out-Null; $card.Child=$g
        $card.Add_MouseEnter({ $this.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#1e1e35") })
        $card.Add_MouseLeave({ $this.Background=[Windows.Media.BrushConverter]::new().ConvertFrom("#1a1a2e") })
        $diagPanel.Children.Add($card)|Out-Null
    }
}
