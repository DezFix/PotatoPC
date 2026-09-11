$script:ScanCheckboxes = @{}
$script:ScanRunning = $false
$script:ScanHandle = $null
$script:ScanControl = $null

function Get-YaraRulesDir {
    try {
        $rootHint = $null
        try { $rootHint = $script:ModuleDir } catch {}
        if ($rootHint) {
            $cand = Join-Path (Split-Path $rootHint -Parent) 'protect\rules'
            if (Test-Path $cand) { return $cand }
        }
    } catch {}
    return ''
}

function Get-YaraStatus {
    $exe = Join-Path $script:WorkFolder 'tools\yara64.exe'
    $st = @{ Exe = ''; Version = ''; RulesCount = 0 }
    try {
        if (Test-Path $exe) {
            $st.Exe = $exe
            try { $st.Version = ((& $exe --version 2>$null | Out-String).Trim() -split '\s+')[-1] } catch {}
        }
        $rd = Get-YaraRulesDir
        if ($rd) { $st.RulesCount = @(Get-ChildItem -LiteralPath $rd -Filter '*.yar' -File -ErrorAction SilentlyContinue).Count }
    } catch {}
    return $st
}

function Ensure-YaraEngine {
    # Фон, самодостаточная: качает движок один раз. Возвращает путь или ''.
    param([string]$ToolsDir)
    $engineUrl = 'https://github.com/VirusTotal/yara/releases/download/v4.5.5/yara-4.5.5-2368-win64.zip'
    try {
        $exe = Join-Path $ToolsDir 'yara64.exe'
        if (Test-Path $exe) { return $exe }
        if (-not (Test-Path $ToolsDir)) { New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null }
        Write-Log 'Качаю движок YARA (разово, ~5 МБ)...'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $zip = Join-Path $ToolsDir 'yara.zip'
        Invoke-WebRequest -Uri $engineUrl -OutFile $zip -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
        $tmp = Join-Path $ToolsDir 'unz'
        if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        Expand-Archive -Path $zip -DestinationPath $tmp -Force -ErrorAction Stop
        $found = Get-ChildItem -LiteralPath $tmp -Filter 'yara64.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $found) { throw 'yara64.exe нет в архиве' }
        Move-Item -LiteralPath $found.FullName -Destination $exe -Force -ErrorAction Stop
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        Write-Log 'Движок готов.' -Color 'Green'
        return $exe
    } catch {
        Write-Log ("Не вышло скачать движок: " + $_) -Color 'Red'
        return ''
    }
}

function Combine-YaraRules {
    # Фон: склеивает правила в один файл (все без include). Возвращает путь или ''.
    param([string]$RulesDir, [string]$OutFile)
    try {
        $files = @(Get-ChildItem -LiteralPath $RulesDir -Filter '*.yar' -File -ErrorAction Stop)
        if ($files.Count -eq 0) { return '' }
        $enc = New-Object System.Text.UTF8Encoding $false
        $sb = New-Object System.Text.StringBuilder
        foreach ($f in ($files | Sort-Object Name)) {
            try {
                $sb.AppendLine() | Out-Null
                $sb.Append([System.IO.File]::ReadAllText($f.FullName)) | Out-Null
                $sb.AppendLine() | Out-Null
            } catch {}
        }
        [System.IO.File]::WriteAllText($OutFile, $sb.ToString(), $enc)
        return $OutFile
    } catch { return '' }
}

function Update-ScanCount {
    $sel = @($script:ScanCheckboxes.Values | Where-Object { $_.Box.IsChecked }).Count
    $total = $script:ScanCheckboxes.Count
    if ($scanCountText) { $scanCountText.Text = "Выбрано: $sel из $total" }
    try { Update-HeaderCount } catch {}
}

function Build-ProtectPanel {
    if ($null -eq $protectPanel) { [Console]::WriteLine('PotatoPC: этот файл — часть приложения. Запускай menu.ps1'); return }
    $protectPanel.Children.Clear()
    $script:ScanCheckboxes = @{}

    $st = Get-YaraStatus
    $ds = $null
    try { $ds = Get-DefenderStatus } catch {}
    $fwOff = 0
    try { $fwOff = @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { -not $_.Enabled }).Count } catch {}

    $protectPanel.Children.Add((New-CategoryHeader -Title "Состояние")) | Out-Null
    $rows = @(
        @{ L = "Defender"; V = $(if ($ds -and $ds.Ok) { if ($null -ne $ds.SigAge) { "активен, базы $($ds.SigAge) дн." } else { "активен" } } else { "недоступен" }); Good = [bool]($ds -and $ds.Ok -and ($null -eq $ds.SigAge -or $ds.SigAge -le 7)) },
        @{ L = "Движок YARA"; V = $(if ($st.Exe) { "есть ($($st.Version))" } else { "скачается при проверке" }); Good = [bool]$st.Exe },
        @{ L = "Правила"; V = "$($st.RulesCount) файлов"; Good = ($st.RulesCount -gt 0) },
        @{ L = "Брандмауэр"; V = $(if ($fwOff -eq 0) { "включён везде" } else { "выключен: $fwOff" }); Good = ($fwOff -eq 0) }
    )
    foreach ($r in $rows) {
        $b = New-Card
        $g = [System.Windows.Controls.Grid]::new()
        $c1 = [System.Windows.Controls.ColumnDefinition]::new(); $c1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $c2 = [System.Windows.Controls.ColumnDefinition]::new(); $c2.Width = [System.Windows.GridLength]::Auto
        $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2)
        $t1 = [System.Windows.Controls.TextBlock]::new()
        $t1.Text = [string]$r.L; $t1.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#8a8aa5")
        $t1.FontSize = 12; $t1.VerticalAlignment = "Center"
        [System.Windows.Controls.Grid]::SetColumn($t1, 0)
        $g.Children.Add($t1) | Out-Null
        $t2 = [System.Windows.Controls.TextBlock]::new()
        $t2.Text = [string]$r.V; $t2.FontSize = 12; $t2.FontWeight = "SemiBold"; $t2.VerticalAlignment = "Center"
        $t2.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom($(if ($r.Good) { "#2ecc71" } else { "#f0c040" }))
        [System.Windows.Controls.Grid]::SetColumn($t2, 1)
        $g.Children.Add($t2) | Out-Null
        $b.Child = $g
        $protectPanel.Children.Add($b) | Out-Null
    }

    $protectPanel.Children.Add((New-CategoryHeader -Title "Находки")) | Out-Null
    $script:ScanResultsBox = [System.Windows.Controls.StackPanel]::new()
    $hint = [System.Windows.Controls.TextBlock]::new()
    $hint.Text = "Пока пусто — нажми «Проверить»."
    $hint.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#8a8ab0")
    $hint.FontSize = 12; $hint.TextAlignment = "Center"; $hint.Margin = [System.Windows.Thickness]::new(0,20,0,20)
    $script:ScanResultsBox.Children.Add($hint) | Out-Null
    $protectPanel.Children.Add($script:ScanResultsBox) | Out-Null
    Update-ScanCount
}

function Render-ScanHits {
    param($Items)
    if ($null -eq $protectPanel -or $null -eq $script:ScanResultsBox) { return }
    $script:ScanResultsBox.Children.Clear()
    $script:ScanCheckboxes = @{}
    $list = @($Items)
    if ($list.Count -eq 0) {
        $t = [System.Windows.Controls.TextBlock]::new()
        $t.Text = "Чисто — ничего не найдено."
        $t.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#2ecc71")
        $t.FontSize = 12; $t.TextAlignment = "Center"; $t.Margin = [System.Windows.Thickness]::new(0,20,0,20)
        $script:ScanResultsBox.Children.Add($t) | Out-Null
    }
    $i = 0
    foreach ($h in $list) {
        $key = "h$i"
        $i++
        $card = New-Card
        $g = [System.Windows.Controls.Grid]::new()
        $c1 = [System.Windows.Controls.ColumnDefinition]::new(); $c1.Width = [System.Windows.GridLength]::new(28)
        $c2 = [System.Windows.Controls.ColumnDefinition]::new(); $c2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2)
        $cb = [System.Windows.Controls.CheckBox]::new()
        $cb.VerticalAlignment = "Center"; $cb.Tag = $key
        $cb.Add_Checked({ Update-ScanCount }); $cb.Add_Unchecked({ Update-ScanCount })
        [System.Windows.Controls.Grid]::SetColumn($cb, 0)
        $g.Children.Add($cb) | Out-Null
        $stk = [System.Windows.Controls.StackPanel]::new(); $stk.VerticalAlignment = "Center"
        $nm = [System.Windows.Controls.TextBlock]::new()
        $nm.Text = [string]$h.Rule; $nm.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#f87171")
        $nm.FontSize = 12; $nm.FontWeight = "SemiBold"
        $fp = [System.Windows.Controls.TextBlock]::new()
        $fp.Text = [string]$h.File; $fp.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom("#9898c8")
        $fp.FontSize = 10; $fp.TextTrimming = "CharacterEllipsis"
        $stk.Children.Add($nm) | Out-Null; $stk.Children.Add($fp) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($stk, 1)
        $g.Children.Add($stk) | Out-Null
        $card.Child = $g
        $script:ScanResultsBox.Children.Add($card) | Out-Null
        $script:ScanCheckboxes[$key] = @{ Box = $cb; Rule = [string]$h.Rule; File = [string]$h.File }
    }
    Update-ScanCount
}

function Start-YaraScan {
    if ($script:ScanRunning) {
        try { if ($script:ScanControl) { $script:ScanControl.Abort = $true } } catch {}
        try { if ($script:ScanHandle -and $script:ScanHandle.Stop) { & $script:ScanHandle.Stop } } catch {}
        Write-Log "Остановка запрошена..." -Color "Yellow"
        return
    }
    $rulesDir = Get-YaraRulesDir
    if (-not $rulesDir) { Write-Log "Нет папки правил (protect/rules)" -Color "Red"; return }
    $toolsDir = Join-Path $script:WorkFolder 'tools'
    $scanBtnSaved = $false
    try {
        $scanBtnSaved = $true
        $script:ScanBtnText = $scanBtn.Content
    } catch {}
    $script:ScanControl = [hashtable]::Synchronized(@{ Abort = $false })
    $script:ScanRunning = $true
    try {
        $scanBtn.Content = "⏹ Стоп"
        $scanBtn.Style = $window.FindResource("BtnDanger")
    } catch {}
    Write-Log "══ Проверка YARA запущена ══"
    Set-Progress
    $script:ScanHandle = Invoke-Async -ScriptBlock {
        try {
            $exe = Ensure-YaraEngine -ToolsDir $toolsDir
            if (-not $exe) { throw "Нет движка" }
            $combined = Join-Path $toolsDir 'potato.yar'
            $cf = Combine-YaraRules -RulesDir $rulesDir -OutFile $combined
            if (-not $cf) { throw "Нет правил" }
            $targets = @()
            foreach ($d in @($env:TEMP, (Join-Path $env:USERPROFILE 'Downloads'), (Join-Path $env:USERPROFILE 'Desktop'),
                "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
                "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp")) {
                if ($d -and (Test-Path -LiteralPath $d)) { $targets += $d }
            }
            $hits = @()
            $n = 0
            $total = @($targets).Count
            $skipNames = @('opencode', 'PotatoPC')
            foreach ($t in $targets) {
                if ($Control -and $Control.Abort) { throw "STOPPED_BY_USER" }
                $n++
                Write-Log ("── " + $t)
                try {
                    $entries = @(Get-ChildItem -LiteralPath $t -Force -ErrorAction SilentlyContinue)
                    $eti = 0
                    $etotal = [Math]::Max(1, $entries.Count)
                    foreach ($e in $entries) {
                        if ($Control -and $Control.Abort) { throw "STOPPED_BY_USER" }
                        if ($skipNames -contains $e.Name) { $eti++; continue }
                        if (-not $e.PSIsContainer) {
                            try { if ($e.Length -gt 200MB) { $eti++; continue } } catch {}
                        }
                        $eti++
                        Set-Progress (([double]($n - 1) + [double]$eti / [double]$etotal) / [double]([Math]::Max(1, $total)))
                        try {
                            $out = @(& $exe -w -r $cf $e.FullName 2>&1 | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | Out-String -Stream | Where-Object { $_ -match '\S' })
                            foreach ($ln in $out) {
                                if ($ln -match '^([A-Za-z_][A-Za-z0-9_]*)\s+(.+)$') {
                                    $rn = $Matches[1].Trim()
                                    $fp = $Matches[2].Trim()
                                    if ($rn -and $fp -and (Test-Path -LiteralPath $fp -PathType Leaf)) {
                                        $hits += @{ Rule = $rn; File = $fp }
                                        Write-Log ("  ✗ {0}: {1}" -f $rn, (Split-Path $fp -Leaf)) -Color "Red"
                                    }
                                }
                            }
                        } catch {
                            Write-Log ("  Не вышло проверить: " + $_) -Color "Yellow"
                        }
                    }
                } catch {
                    if ("$_" -like "*STOPPED_BY_USER*") { throw }
                    Write-Log ("  Не вышло проверить: " + $_) -Color "Yellow"
                }
            }
            Set-BgResult -Key 'scanHits' -Value @{ Items = $hits }
            if ($hits.Count -eq 0) { Write-Log "Чисто." -Color "Green" }
            else { Write-Log ("Находок: " + $hits.Count + " — выбери и отправь в карантин") -Color "Yellow" }
            Write-Log "══════════════════════════════════════"
        } catch {
            if ("$_" -like "*STOPPED_BY_USER*") { Write-Log "⏹ Остановлено пользователем" -Color "Yellow" }
            else { Write-Log ("✗ Проверка упала: " + $_) -Color "Red" }
        } finally { Clear-Progress }
    } -Variables @{ rulesDir = $rulesDir; toolsDir = $toolsDir; Control = $script:ScanControl } -OnComplete {
        Invoke-OnUI {
            $script:ScanRunning = $false
            $script:ScanHandle = $null
            try {
                if ($scanBtnSaved) { $scanBtn.Content = $script:ScanBtnText }
                $scanBtn.Style = $window.FindResource("BtnPrimary")
            } catch {}
        }
    }
}

function Reset-ScanButton {
    try {
        if ($script:ScanBtnText) { $scanBtn.Content = $script:ScanBtnText }
        $scanBtn.Style = $window.FindResource("BtnPrimary")
    } catch {}
    $script:ScanRunning = $false
    $script:ScanHandle = $null
}

function Start-Quarantine {
    $sel = @($script:ScanCheckboxes.GetEnumerator() | Where-Object { $_.Value.Box.IsChecked })
    if ($sel.Count -eq 0) { Write-Log "⚠ Ничего не выбрано" -Color "Yellow"; return }
    $qRoot = Join-Path $script:WorkFolder ('quarantine\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    try { New-Item -ItemType Directory -Path $qRoot -Force | Out-Null } catch {}
    $n = 0
    $mapLines = @()
    foreach ($kv in $sel) {
        $f = $kv.Value.File
        try {
            if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { Write-Log ("  Уже нет: " + $f) -Color "Yellow"; continue }
            $dst = Join-Path $qRoot (Split-Path $f -Leaf)
            $k = 1
            while (Test-Path -LiteralPath $dst) { $k++; $dst = Join-Path $qRoot ([System.IO.Path]::GetFileNameWithoutExtension($f) + "_$k" + [System.IO.Path]::GetExtension($f)) }
            Move-Item -LiteralPath $f -Destination $dst -Force -ErrorAction Stop
            $mapLines += ((Get-Date -Format 'yyyy-MM-dd HH:mm') + ' | ' + $kv.Value.Rule + ' | ' + $f + ' -> ' + $dst)
            $n++
            Write-Log ("  В карантине: " + (Split-Path $f -Leaf)) -Color "Green"
        } catch {
            Write-Log ("  ✗ Не вышло: " + $f) -Color "Red"
        }
    }
    try { $mapLines | Out-File -FilePath (Join-Path $qRoot 'map.txt') -Encoding UTF8 -Force } catch {}
    Write-Log ("Карантин: $n файлов. Карта: " + $qRoot) -Color "Green"
    try { Render-ScanHits -Items @() } catch {}
}
