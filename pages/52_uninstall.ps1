# PAGE: uninstall
# TITLE: Удаление программ
# ICON: trash
# ORDER: 52

# Деинсталлятор: программы из реестра (все пользователи, 32/64 бита) и
# приложения Microsoft Store. После удаления ищет остатки: папки, ключи
# реестра и ярлыки. Файлы уходят в Корзину, реестр - с резервной копией .reg.

$script:UnUi = $null

function Split-CommandLine {
    # "C:\Path\uninst.exe" /S  ->  @('C:\Path\uninst.exe', '/S')
    param([string]$Cmd)
    $c = [Environment]::ExpandEnvironmentVariables($Cmd.Trim())
    if ($c.StartsWith('"')) {
        $e = $c.IndexOf('"', 1)
        if ($e -gt 1) { return @($c.Substring(1, $e - 1), $c.Substring($e + 1).Trim()) }
    }
    $m = [regex]::Match($c, '^(.+?\.(exe|com|bat|cmd))(\s+(.*))?$', 'IgnoreCase')
    if ($m.Success) { return @($m.Groups[1].Value, $m.Groups[4].Value) }
    $parts = $c -split '\s+', 2
    return @($parts[0], $(if ($parts.Count -gt 1) { $parts[1] } else { '' }))
}

function Get-CleanAppName {
    # «7-Zip 24.08 (x64)» -> «7-Zip»: для поиска остатков по имени папки.
    param([string]$Name)
    $n = $Name
    # Хвостовые скобки: (x64), (64-bit x64), (x64 ru), (Remove only)...
    while ($n -match '\s*\([^()]*\)\s*$') { $n = $n -replace '\s*\([^()]*\)\s*$', '' }
    $n = $n -replace '\s+v?\d+(\.\d+)+.*$', '' -replace '\s+(x64|x86|amd64|arm64)$', ''
    return $n.Trim(' ', '-', '_')
}

function Get-InstalledPrograms {
    # Фон. Классические программы из реестра.
    param([switch]$WithIcons)
    $keys = @(
        @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'Все пользователи' },
        @{ P = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'Все пользователи (32-бит)' },
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'Только этот пользователь' }
    )
    $seen = @{}
    $out = New-Object System.Collections.ArrayList
    foreach ($k in $keys) {
        foreach ($sub in @(Get-ChildItem -LiteralPath $k.P -ErrorAction SilentlyContinue)) {
            $v = $null
            try { $v = Get-ItemProperty -LiteralPath $sub.PSPath -ErrorAction Stop } catch { continue }
            $name = [string]$v.DisplayName
            if (-not $name) { continue }
            if ([int]$v.SystemComponent -eq 1) { continue }
            if ($v.ParentKeyName -or ([string]$v.ReleaseType -match '(?i)update|hotfix')) { continue }
            $un = [string]$v.UninstallString
            $quiet = [string]$v.QuietUninstallString
            if (-not $un -and -not $quiet) { continue }
            $dup = ($name + '|' + [string]$v.DisplayVersion).ToLowerInvariant()
            if ($seen.ContainsKey($dup)) { continue }
            $seen[$dup] = $true
            $msi = ''
            if ([int]$v.WindowsInstaller -eq 1 -and $sub.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$') { $msi = $sub.PSChildName }
            elseif ($un -match '(?i)msiexec(\.exe)?\s.*?(\{[0-9A-Fa-f-]{36}\})') { $msi = $Matches[2] }
            $date = $null
            if ([string]$v.InstallDate -match '^(\d{4})(\d{2})(\d{2})$') { try { $date = Get-Date -Year $Matches[1] -Month $Matches[2] -Day $Matches[3] -Hour 0 -Minute 0 -Second 0 } catch {} }
            $exe = ''
            if (-not $msi -and $un) { $exe = (Split-CommandLine $un)[0] }
            $broken = (-not $msi) -and $exe -and -not (Test-Path -LiteralPath $exe)
            $icon = $null
            if ($WithIcons) {
                $iconPath = Find-ProgramIconPath -DisplayIcon ([string]$v.DisplayIcon) -Msi $msi -Location ([string]$v.InstallLocation).Trim('"', ' ') -Exe $exe -Name $name
                if ($iconPath) { $icon = ConvertTo-IconPng -Path $iconPath }
            }
            [void]$out.Add(@{
                Kind = 'win32'; Id = [string]$sub.PSPath; Name = $name; Publisher = ([string]$v.Publisher).Trim(); Version = [string]$v.DisplayVersion
                Date = $date; Size = $(if ($v.EstimatedSize) { [double]$v.EstimatedSize * 1KB } else { 0 }); Uninstall = $un; Quiet = $quiet; Msi = $msi
                Location = ([string]$v.InstallLocation).Trim('"', ' '); KeyPath = [string]$sub.PSPath; Scope = $k.Scope; Broken = $broken; Icon = $icon
            })
        }
    }
    return @($out)
}

function Get-StoreAppsList {
    # Фон. Приложения Microsoft Store, которые можно удалить.
    param([switch]$WithIcons)
    $out = @()
    foreach ($p in @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { -not $_.IsFramework -and -not $_.NonRemovable -and $_.SignatureKind -eq 'Store' -and -not $_.IsResourcePackage })) {
        $name = [string]$p.Name
        $pretty = ($name -replace '^[A-Za-z0-9]+\.', '' -replace '([a-z])([A-Z])', '$1 $2').Trim()
        $m = $null
        try {
            $m = Get-AppxPackageManifest -Package $p.PackageFullName -ErrorAction Stop
            $dn = [string]$m.Package.Properties.DisplayName
            if ($dn -and $dn -notlike 'ms-resource:*') { $pretty = $dn }
        } catch {}
        $size = 0
        $icon = $null
        if ($WithIcons -and $m) { $icon = Get-StoreAppIconPng -InstallLocation ([string]$p.InstallLocation) -Logo ([string]$m.Package.Properties.Logo) }
        $out += @{ Kind = 'store'; Id = [string]$p.PackageFullName; Name = $pretty; Publisher = ([string]$p.Publisher -replace '^CN=([^,]+).*$', '$1'); Version = [string]$p.Version
            Date = $(try { (Get-Item -LiteralPath $p.InstallLocation -ErrorAction Stop).CreationTime } catch { $null }); Size = $size; Package = [string]$p.PackageFullName; Family = [string]$p.PackageFamilyName; Broken = $false; Icon = $icon }
    }
    return $out
}

function Wait-UninstallerChildren {
    # Многие деинсталляторы (NSIS, Inno Setup) копируют себя во временную папку,
    # запускают копию и сразу выходят. Ждём и её, чтобы искать остатки после.
    param([datetime]$Since, [int]$MaxSec = 900)
    $deadline = (Get-Date).AddSeconds($MaxSec)
    $tmp = [System.IO.Path]::GetTempPath()
    while ((Get-Date) -lt $deadline -and -not (Test-JobCancel)) {
        $kids = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            try { $_.StartTime -ge $Since -and $_.Path -and ($_.Path.StartsWith($tmp, 'OrdinalIgnoreCase') -or $_.Name -match '^(Un_[A-Z]|Au_|unins\d+|_iu14D2N|uninst|uninstall)') } catch { $false }
        })
        if ($kids.Count -eq 0) { return }
        Start-Sleep -Milliseconds 800
    }
}

function Invoke-ProgramUninstall {
    # Фон. Удаляет одну программу. Возвращает @{ Ok; Gone }.
    param($P, [bool]$Silent = $false)
    $t0 = Get-Date
    if ($P.Kind -eq 'store') {
        try { Remove-AppxPackage -Package $P.Package -ErrorAction Stop; Write-Log ('Удалено: ' + $P.Name) 'ok'; Add-History -Kind 'uninstall' -Name ('Удалено приложение Store: ' + $P.Name); return @{ Ok = $true; Gone = $true } }
        catch { Write-Log ('Не удалось удалить ' + $P.Name + ': ' + $_.Exception.Message) 'err'; return @{ Ok = $false; Gone = $false } }
    }
    $exe = ''; $arg = ''
    if ($P.Msi) {
        $exe = Join-Path $env:WINDIR 'System32\msiexec.exe'
        $arg = '/x ' + $P.Msi + $(if ($Silent) { ' /qn /norestart' } else { ' /norestart' })
    } elseif ($Silent -and $P.Quiet) {
        $parts = Split-CommandLine $P.Quiet; $exe = $parts[0]; $arg = $parts[1]
    } else {
        $parts = Split-CommandLine $P.Uninstall; $exe = $parts[0]; $arg = $parts[1]
    }
    if (-not $P.Msi -and -not (Test-Path -LiteralPath $exe)) {
        Write-Log ('Деинсталлятор не найден: ' + $exe + '. Можно убрать запись и остатки вручную.') 'warn'
        return @{ Ok = $false; Gone = $false; Broken = $true }
    }
    Write-Log ('Удаляю: ' + $P.Name + $(if (-not $Silent -or (-not $P.Msi -and -not $P.Quiet)) { ' - следуйте окну деинсталлятора' } else { ' (тихо)' }))
    $code = -1
    try {
        $proc = Start-Process -FilePath $exe -ArgumentList $arg -PassThru -ErrorAction Stop
        try { if ($Job) { $Job.ChildPid = $proc.Id } } catch {}
        while (-not $proc.HasExited) {
            if (Test-JobCancel) { break }
            Start-Sleep -Milliseconds 500
        }
        try { $code = $proc.ExitCode } catch {}
        Wait-UninstallerChildren -Since $t0
    } catch { Write-Log ('Не удалось запустить деинсталлятор: ' + $_.Exception.Message) 'err'; return @{ Ok = $false; Gone = $false } }
    finally { try { if ($Job) { $Job.ChildPid = 0 } } catch {} }
    Start-Sleep -Seconds 1
    $gone = -not (Test-Path -LiteralPath $P.KeyPath)
    if ($gone) { Write-Log ('Удалено: ' + $P.Name) 'ok'; Add-History -Kind 'uninstall' -Name ('Удалена программа: ' + $P.Name) }
    elseif ($code -eq 1602) { Write-Log ('Удаление «' + $P.Name + '» отменено') 'warn' }
    else { Write-Log ('«' + $P.Name + '» всё ещё в списке (код ' + $code + '). Возможно, удаление было отменено или нужна перезагрузка.') 'warn' }
    return @{ Ok = $gone; Gone = $gone; Code = $code }
}

function Find-ProgramLeftovers {
    # Фон. Остатки удалённой программы. Сами системные папки и папки
    # производителя целиком не отмечаются - только с совпадением по имени.
    param($P)
    $out = New-Object System.Collections.ArrayList
    $name = Get-CleanAppName $P.Name
    $pub = ([string]$P.Publisher -replace '(?i),?\s*(inc|llc|ltd|gmbh|corp(oration)?|co|s\.?a\.?|limited)\.?$', '').Trim(' ', '.', ',')
    if ($name.Length -lt 3) { return @() }
    $add = { param($Type, $Path, $Checked, $Why) if (-not ($out | Where-Object { $_.Path -eq $Path })) { [void]$out.Add(@{ Type = $Type; Path = $Path; Checked = $Checked; Why = $Why }) } }
    $protected = @($env:WINDIR, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA, $env:USERPROFILE, (Join-Path $env:LOCALAPPDATA 'Programs'), (Join-Path $env:ProgramFiles 'Common Files'), (Join-Path ${env:ProgramFiles(x86)} 'Common Files')) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\').ToLowerInvariant() }
    $skipNames = @('microsoft', 'windows', 'common files', 'microsoft shared', 'windowsapps', 'packages', 'temp', 'programs', 'google', 'mozilla', 'intel', 'nvidia', 'amd', 'realtek', 'package cache')
    $isSafeDir = {
        param($d)
        if (-not $d) { return $false }
        $l = $d.TrimEnd('\').ToLowerInvariant()
        if ($protected -contains $l) { return $false }
        if ($l -match '\\windows(\\|$)' -and $l.StartsWith(([string]$env:WINDIR).ToLowerInvariant())) { return $false }
        return $true
    }
    $bases = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA, (Join-Path $env:LOCALAPPDATA 'Programs')) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    $userDirs = @('Desktop', 'MyDocuments', 'MyMusic', 'MyPictures', 'MyVideos') | ForEach-Object { [Environment]::GetFolderPath($_) } | Where-Object { $_ }
    $userDirs += (Join-Path $env:USERPROFILE 'Downloads')
    # 1. Папка установки, если осталась. Отмечаем, только если она в стандартном
    #    месте: запись в реестре может указывать куда угодно.
    if ($P.Location -and $P.Location -notmatch '^[A-Za-z]:\\?$' -and (Test-Path -LiteralPath $P.Location) -and (& $isSafeDir $P.Location)) {
        $loc = $P.Location.TrimEnd('\')
        $leaf = Split-Path $loc -Leaf
        $inUser = @($userDirs | Where-Object { $loc.StartsWith($_, 'OrdinalIgnoreCase') }).Count -gt 0
        $inBase = @($bases | Where-Object { $loc.StartsWith($_.TrimEnd('\') + '\', 'OrdinalIgnoreCase') }).Count -gt 0
        if (-not $inUser -and $skipNames -notcontains $leaf.ToLowerInvariant()) {
            if ($inBase) { & $add 'folder' $loc $true 'папка установки' }
            else { & $add 'folder' $loc $false 'папка установки вне стандартных мест - проверьте' }
        }
    }
    # 2. Папки с именем программы / производителя
    foreach ($b in $bases) {
        $c1 = Join-Path $b $name
        if ((Test-Path -LiteralPath $c1) -and (& $isSafeDir $c1)) { & $add 'folder' $c1 $true 'папка с именем программы' }
        if ($pub -and $pub.Length -ge 3 -and $skipNames -notcontains $pub.ToLowerInvariant()) {
            $c2 = Join-Path (Join-Path $b $pub) $name
            if (Test-Path -LiteralPath $c2) { & $add 'folder' $c2 $true 'папка производителя / программы' }
            $c3 = Join-Path $b $pub
            if ((Test-Path -LiteralPath $c3) -and (& $isSafeDir $c3)) {
                $inside = @(Get-ChildItem -LiteralPath $c3 -Force -ErrorAction SilentlyContinue)
                $why = if ($inside.Count -le 1) { 'папка производителя (внутри почти пусто)' } else { 'папка производителя - там могут быть его другие программы' }
                & $add 'folder' $c3 ($inside.Count -le 1) $why
            }
        }
    }
    # 3. Ярлыки в меню «Пуск» и на рабочих столах
    $menus = @((Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'), (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'))
    foreach ($m in $menus) {
        foreach ($cand in @((Join-Path $m $name), (Join-Path $m ($name + '.lnk')))) { if (Test-Path -LiteralPath $cand) { & $add 'shortcut' $cand $true 'ярлык в меню «Пуск»' } }
    }
    foreach ($desk in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'))) {
        if (-not $desk) { continue }
        foreach ($lnk in @(Get-ChildItem -LiteralPath $desk -Filter '*.lnk' -ErrorAction SilentlyContinue)) {
            if ($lnk.BaseName -notlike ($name + '*')) { continue }
            try { $t = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk.FullName).TargetPath; if ($t -and -not (Test-Path -LiteralPath $t)) { & $add 'shortcut' $lnk.FullName $true 'ярлык на рабочем столе ведёт в никуда' } } catch {}
        }
    }
    # 4. Реестр
    $regs = @()
    foreach ($root in @('HKCU:\Software', 'HKLM:\SOFTWARE', 'HKLM:\SOFTWARE\WOW6432Node')) {
        $regs += (Join-Path $root $name)
        if ($pub -and $pub.Length -ge 3 -and $skipNames -notcontains $pub.ToLowerInvariant()) { $regs += (Join-Path (Join-Path $root $pub) $name) }
    }
    foreach ($r in $regs) { if (Test-Path -LiteralPath $r) { & $add 'registry' $r $true 'ключ настроек программы' } }
    if ($P.KeyPath -and (Test-Path -LiteralPath $P.KeyPath)) { & $add 'registry' $P.KeyPath ([bool]$P.Broken) 'запись в списке программ (деинсталлятор не убрал её)' }
    foreach ($x in $out) { $x.Display = $(if ($x.Type -eq 'registry') { try { Convert-Path -LiteralPath $x.Path -ErrorAction Stop } catch { $x.Path } } else { $x.Path }) }
    return @($out)
}

function Remove-ProgramLeftovers {
    # Фон. Папки и ярлыки - в Корзину, реестр - с копией .reg.
    param($Items, [string]$AppName)
    Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
    $bk = Join-Path $BackupFolder ('uninstall-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $ok = 0
    foreach ($it in @($Items)) {
        try {
            switch ($it.Type) {
                'registry' {
                    if (-not (Test-Path -LiteralPath $bk)) { New-Item -ItemType Directory -Path $bk -Force -ErrorAction Stop | Out-Null }
                    $native = (Convert-Path -LiteralPath $it.Path) -replace '^HKEY_LOCAL_MACHINE', 'HKLM' -replace '^HKEY_CURRENT_USER', 'HKCU'
                    $file = Join-Path $bk (($native -replace '[\\: ]', '_') + '.reg')
                    & reg.exe export $native $file /y | Out-Null
                    Remove-Item -LiteralPath $it.Path -Recurse -Force -ErrorAction Stop
                }
                default {
                    if (Test-Path -LiteralPath $it.Path -PathType Container) {
                        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($it.Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
                    } else {
                        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($it.Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
                    }
                }
            }
            $ok++
            Write-Log ('Удалено: ' + $it.Path)
        } catch { Write-Log ('Не удалено: ' + $it.Path + ' - ' + $_.Exception.Message) 'warn' }
    }
    Write-Log ('Остатков удалено: ' + $ok + ' из ' + @($Items).Count + '. Файлы - в Корзине' + $(if (Test-Path -LiteralPath $bk) { ', копия реестра: ' + $bk } else { '' })) 'ok'
    Add-History -Kind 'uninstall' -Name ('Остатки «' + $AppName + '»: удалено ' + $ok) -Ref $bk
}

# --- Интерфейс ---

function Build-Page_uninstall {
    $ui = @{ Rows = @{}; Kind = 'win32'; Sort = 'size'; Items = @(); Left = @{} }
    $script:UnUi = $ui
    $ui.Search = New-TextInput -Placeholder 'Поиск по названию или издателю' -Width 280
    $ui.Search.Add_TextChanged({ Update-UninstallFilter })
    $refresh = New-Button -Text 'Обновить' -Icon 'refresh' -OnClick { Update-UninstallPage }
    $ui.SilentChk = New-CheckBox -Text 'Тихо, если программа умеет' -ToolTip 'Без окон деинсталлятора. Работает для MSI и программ, которые сообщают тихую команду удаления'
    $ui.LeftChk = New-CheckBox -Text 'Искать остатки' -Checked $true -ToolTip 'После удаления найти оставшиеся папки, ярлыки и ключи реестра'
    $ui.GoBtn = New-Button -Text 'Удалить выбранные' -Icon 'trash' -Kind Primary -OnClick { Start-Uninstall }
    $ui.GoBtn.IsEnabled = $false
    # Через -Right: панель сама ставит отступы между элементами
    $ab = New-ActionBar -Right @($ui.SilentChk, $ui.LeftChk, $ui.GoBtn)
    $ui.LeftChk.Margin = New-Thickness 22, 0, 0, 0
    $ui.GoBtn.Margin = New-Thickness 22, 0, 0, 0
    $ui.Bar = $ab
    $L = New-PageLayout -Title 'Удаление программ' -Subtitle 'Удаление программ и приложений Store с поиском остатков' -HeaderRight @($ui.Search, $refresh) -ActionBar $ab.Root
    $ui.Count = New-StatCard -Label 'Программ' -Value '…'
    $ui.Total = New-StatCard -Label 'Занимают на диске' -Value '…'
    $ui.Recent = New-StatCard -Label 'Установлено за 30 дней' -Value '…'
    [void]$L.Body.Children.Add((New-Grid -Columns 3 -Items @($ui.Count.Root, $ui.Total.Root, $ui.Recent.Root)))
    $chips = New-Object System.Windows.Controls.WrapPanel
    $ui.KindChips = @{}
    foreach ($k in @(@('win32', 'Программы'), @('store', 'Приложения Store'))) {
        $b = New-Button -Text $k[1] -Kind Chip -Tag $k[0] -OnClick { $script:UnUi.Kind = $this.Tag; Update-UninstallChips; Update-UninstallList }
        $ui.KindChips[$k[0]] = $b
        [void]$chips.Children.Add($b)
    }
    [void]$chips.Children.Add((New-Text -Text 'Сортировка:' -Size 13 -Color 'Muted' -Margin (14, 0, 10, 8)))
    $ui.SortChips = @{}
    foreach ($k in @(@('size', 'по размеру'), @('name', 'по имени'), @('date', 'по дате'))) {
        $b = New-Button -Text $k[1] -Kind Chip -Tag $k[0] -OnClick { $script:UnUi.Sort = $this.Tag; Update-UninstallChips; Update-UninstallList }
        $ui.SortChips[$k[0]] = $b
        [void]$chips.Children.Add($b)
    }
    [void]$L.Body.Children.Add($chips)
    $ui.LeftSec = New-Section -Title 'Остатки после удаления'
    $ui.LeftSec.Root.Visibility = 'Collapsed'
    [void]$L.Body.Children.Add($ui.LeftSec.Root)
    $ui.List = New-Section -Title 'Установленные программы'
    [void]$ui.List.Body.Children.Add((New-Placeholder))
    [void]$L.Body.Children.Add($ui.List.Root)
    Update-UninstallChips
    return $L.Root
}

function Show-Page_uninstall {
    param($Arg)
    if (-not $script:UnUi.Loaded) { Update-UninstallPage }
}

function Update-UninstallChips {
    $ui = $script:UnUi
    foreach ($k in $ui.KindChips.Keys) { Set-ChipActive -Button $ui.KindChips[$k] -Active ($k -eq $ui.Kind) }
    foreach ($k in $ui.SortChips.Keys) { Set-ChipActive -Button $ui.SortChips[$k] -Active ($k -eq $ui.Sort) }
}

function Update-UninstallPage {
    $ui = $script:UnUi
    if ($ui.Busy) { return }
    $ui.Busy = $true
    $ui.Loaded = $true
    $ui.List.Body.Children.Clear()
    [void]$ui.List.Body.Children.Add((New-Placeholder 'Собираю список программ…'))
    Start-BgTask -Name 'Список программ' -Script {
        return @{ Win = @(Get-InstalledPrograms -WithIcons); Store = @(Get-StoreAppsList -WithIcons) }
    } -OnDone {
        param($r, $err)
        $ui = $script:UnUi
        $ui.Busy = $false
        if (-not $r) { Write-Log ('Список программ не прочитался: ' + $err) 'err'; return }
        $ui.Items = @($r.Win) + @($r.Store)
        Set-ButtonText -Button $ui.KindChips['win32'] -Text ('Программы  ' + @($r.Win).Count)
        Set-ButtonText -Button $ui.KindChips['store'] -Text ('Приложения Store  ' + @($r.Store).Count)
        $sum = 0.0; foreach ($p in $r.Win) { $sum += $p.Size }
        $ui.Count.Value.Text = [string](@($r.Win).Count + @($r.Store).Count)
        $ui.Count.Sub.Text = [string]@($r.Win).Count + ' программ, ' + @($r.Store).Count + ' из Store'
        $ui.Total.Value.Text = Format-Size $sum
        $ui.Total.Sub.Text = 'по данным самих программ'
        $recent = @($r.Win | Where-Object { $_.Date -and $_.Date -gt (Get-Date).AddDays(-30) })
        $ui.Recent.Value.Text = [string]$recent.Count
        $ui.Recent.Sub.Text = if ($recent.Count) { (($recent | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ', ') } else { 'ничего нового' }
        Update-UninstallList
    } | Out-Null
}

function Update-UninstallList {
    $ui = $script:UnUi
    $checked = @{}
    foreach ($k in $ui.Rows.Keys) { if ($ui.Rows[$k].Check.IsChecked) { $checked[$k] = $true } }
    $ui.Rows = @{}
    $body = $ui.List.Body
    $body.Children.Clear()
    $list = @($ui.Items | Where-Object { $_.Kind -eq $ui.Kind })
    $sorted = switch ($ui.Sort) {
        'name' { @($list | Sort-Object { $_.Name }) }
        'date' { @($list | Sort-Object { if ($_.Date) { $_.Date } else { [datetime]::MinValue } } -Descending) }
        default { @($list | Sort-Object { $_.Size } -Descending) }
    }
    $ui.List.Header.Text = $(if ($ui.Kind -eq 'store') { 'Приложения Microsoft Store' } else { 'Установленные программы' }) + ' · ' + $sorted.Count
    if ($sorted.Count -eq 0) { [void]$body.Children.Add((New-Placeholder 'Пусто.')) }
    foreach ($p in $sorted) {
        $chk = New-CheckBox -Checked ([bool]$checked[$p.Id]) -Tag $p.Id -OnChange { Update-UninstallSelection }
        $sub = @()
        if ($p.Publisher) { $sub += $p.Publisher }
        if ($p.Version) { $sub += $p.Version }
        if ($p.Date) { $sub += 'установлено ' + $p.Date.ToString('dd.MM.yyyy') }
        $main = New-TitleBlock -Title $p.Name -Sub ($sub -join ' · ')
        $right = @()
        if ($p.Broken) { $right += New-Badge 'Деинсталлятор потерян' 'warn' }
        $size = New-Text -Text $(if ($p.Size -gt 0) { Format-Size $p.Size } else { '' }) -Size 13 -Weight 'SemiBold'
        $size.Width = 80; $size.TextAlignment = 'Right'
        $right += $size
        $one = New-Button -Text $(if ($p.Broken) { 'Убрать' } else { 'Удалить' }) -Kind SmallDanger -Tag $p -OnClick { Start-Uninstall -Single $this.Tag }
        $right += $one
        $left = New-Stack -Orientation Horizontal -Children @($chk, (New-AppIcon -Name $p.Name -Png $p.Icon -Size 34))
        $left.Children[1].Margin = New-Thickness 12, 0, 0, 0
        $row = New-Row -Left $left -Main $main -Right $right -Padding (16, 8, 12, 8)
        $row.ToolTip = $(if ($p.Kind -eq 'store') { $p.Package } else { $p.Uninstall })
        [void]$body.Children.Add($row)
        $ui.Rows[$p.Id] = @{ Check = $chk; Row = $row; Item = $p }
    }
    Update-UninstallFilter
    Update-UninstallSelection
}

function Update-UninstallFilter {
    $ui = $script:UnUi
    $q = ([string]$ui.Search.Text).Trim().ToLowerInvariant()
    foreach ($r in $ui.Rows.Values) {
        $ok = (-not $q) -or (($r.Item.Name + ' ' + $r.Item.Publisher).ToLowerInvariant().Contains($q))
        $r.Row.Visibility = if ($ok) { 'Visible' } else { 'Collapsed' }
    }
}

function Update-UninstallSelection {
    $ui = $script:UnUi
    if (-not $ui.Bar) { return }
    $sel = @($ui.Rows.Values | Where-Object { $_.Check.IsChecked })
    $size = 0.0; foreach ($s in $sel) { $size += $s.Item.Size }
    $ui.Bar.Text.Text = [string]$sel.Count + ' выбрано' + $(if ($size -gt 0) { ' · ' + (Format-Size $size) } else { '' })
    $ui.GoBtn.IsEnabled = ($sel.Count -gt 0) -and -not $ui.Running
}

function Start-Uninstall {
    param($Single = $null)
    $ui = $script:UnUi
    $sel = if ($Single) { @($Single) } else { @($ui.Rows.Values | Where-Object { $_.Check.IsChecked } | ForEach-Object { $_.Item }) }
    if ($sel.Count -eq 0 -or $ui.Running) { return }
    $broken = @($sel | Where-Object { $_.Broken })
    $msg = 'Удалить (' + $sel.Count + "):`n  • " + (($sel | ForEach-Object { $_.Name }) -join "`n  • ")
    if ($broken.Count) { $msg += "`n`nУ этих программ деинсталлятор потерян - уберу запись из списка и поищу остатки:`n  • " + (($broken | ForEach-Object { $_.Name }) -join "`n  • ") }
    if (-not $ui.SilentChk.IsChecked) { $msg += "`n`nОкна деинсталляторов будут появляться по очереди - пройдите их до конца." }
    if (-not (Show-Confirm -Message $msg -Title 'Удаление программ' -Warning)) { return }
    $ui.Running = $true
    Update-UninstallSelection
    Start-BgTask -Name 'Удаление программ' -Vars @{ Sel = $sel; Silent = [bool]$ui.SilentChk.IsChecked; Scan = [bool]$ui.LeftChk.IsChecked } -Script {
        [void](New-RestorePoint -Description 'PotatoPC: удаление программ')
        $left = @()
        $i = 0
        foreach ($p in $Sel) {
            if (Test-JobCancel) { break }
            $i++
            Set-JobProgress (($i - 1) / [Math]::Max(1, $Sel.Count)) $p.Name
            if ($p.Broken) { $r = @{ Gone = $true } } else { $r = Invoke-ProgramUninstall -P $p -Silent $Silent }
            if ($Scan -and $p.Kind -eq 'win32' -and ($r.Gone -or $p.Broken)) {
                foreach ($x in @(Find-ProgramLeftovers -P $p)) { $x.App = $p.Name; $left += $x }
            }
        }
        return @{ Left = $left }
    } -OnDone {
        param($r)
        $ui = $script:UnUi
        $ui.Running = $false
        if ($r -and @($r.Left).Count) { Set-Leftovers -Items @($r.Left) }
        elseif ($r) { Write-Log 'Остатков не найдено' 'ok' }
        $ui.Loaded = $false
        Update-UninstallPage
        if ($script:PgUi) { $script:PgUi.InstLoaded = $false; $script:PgUi.UpdLoaded = $false }
        if ($script:StUi) { $script:StUi.Loaded = $false }
    } | Out-Null
}

function Set-Leftovers {
    param($Items)
    $ui = $script:UnUi
    $ui.Left = @{}
    $sec = $ui.LeftSec
    $sec.Root.Visibility = 'Visible'
    $sec.Header.Text = 'Остатки после удаления · ' + $Items.Count
    $sec.Body.Children.Clear()
    $i = 0
    foreach ($x in $Items) {
        $i++
        $chk = New-CheckBox -Checked ([bool]$x.Checked) -Tag $i
        $badge = switch ($x.Type) { 'registry' { New-Badge 'Реестр' 'info' } 'shortcut' { New-Badge 'Ярлык' 'muted' } default { New-Badge 'Папка' 'warn' } }
        $row = New-Row -Left $chk -Main (New-TitleBlock -Title $(if ($x.Display) { $x.Display } else { $x.Path }) -Sub ($x.App + ' · ' + $x.Why)) -Right @($badge) -Padding (16, 8, 16, 8)
        [void]$sec.Body.Children.Add($row)
        $ui.Left[$i] = @{ Check = $chk; Item = $x }
    }
    $btns = New-Stack -Orientation Horizontal -Margin (16, 8, 16, 12)
    $del = New-Button -Text 'Удалить отмеченное' -Icon 'trash' -Kind Danger -OnClick {
        $sel = @($script:UnUi.Left.Values | Where-Object { $_.Check.IsChecked } | ForEach-Object { $_.Item })
        if ($sel.Count -eq 0) { return }
        if (-not (Show-Confirm -Message ('Удалить ' + $sel.Count + ' остатков? Папки и ярлыки уйдут в Корзину, ключи реестра - с резервной копией.'))) { return }
        $app = (@($sel | ForEach-Object { $_.App } | Select-Object -Unique) -join ', ')
        Start-BgTask -Name 'Удаление остатков' -Vars @{ I = $sel; A = $app } -Script { Remove-ProgramLeftovers -Items $I -AppName $A } -OnDone { $script:UnUi.LeftSec.Root.Visibility = 'Collapsed' } | Out-Null
    }
    $skip = New-Button -Text 'Оставить' -Kind Ghost -OnClick { $script:UnUi.LeftSec.Root.Visibility = 'Collapsed' }
    $skip.Margin = New-Thickness 10, 0, 0, 0
    [void]$btns.Children.Add($del); [void]$btns.Children.Add($skip)
    [void]$sec.Body.Children.Add($btns)
    [void]$sec.Body.Children.Add((New-Text -Text 'Отмечено только то, что точно относится к программе. Папки производителя, в которых могут быть его другие программы, не отмечены - проверьте сами.' -Size 12 -Color 'Muted' -Wrap -Margin (16, 0, 16, 12)))
    $sec.Root.BringIntoView()
}
