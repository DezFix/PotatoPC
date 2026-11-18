# PAGE: registry
# TITLE: Реестр
# ICON: key
# ORDER: 35

# Проверка реестра - НЕ «чистка» в стиле CCleaner. Ищем только записи, которые
# вызывают видимые проблемы или оставлены вирусами:
#   - подозрительное: политики, отключающие диспетчер задач и т.п., перехват
#     запуска программ (IFEO), подмена оболочки Winlogon, AppInit_DLLs;
#   - автозагрузка и задачи, которые запускают несуществующие файлы;
#   - пункты контекстного меню, ассоциации и App Paths удалённых программ;
#   - записи программ, которых уже нет.
# Битым считается только то, где путь проверен и файла нет на несъёмном диске.
# Драйверы, службы, COM-регистрации без явного битого пути не трогаем вообще.
# Перед изменением всё сохраняется (.reg и XML задач), откат - со страницы «История».

$script:RgUi = $null

# ---------- Фон: вспомогательное ----------

function Get-RegNative {
    param([string]$Path)
    return ($Path -replace '^Registry::', '' -replace '^HKLM:\\?', 'HKEY_LOCAL_MACHINE\' -replace '^HKCU:\\?', 'HKEY_CURRENT_USER\')
}

function Get-RegValue {
    param([string]$Key, [string]$Name)
    try { return (Get-ItemProperty -LiteralPath $Key -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}

function Get-RegDefault {
    param([string]$Key)
    try { return [string](Get-ItemProperty -LiteralPath $Key -ErrorAction Stop).'(default)' } catch { return '' }
}

function Get-CommandTarget {
    # Файл, который реально запускается командой. '' - проверить нельзя (не трогаем).
    param([string]$Cmd)
    if (-not $Cmd) { return '' }
    $parts = Split-CommandLine $Cmd
    $exe = ([string]$parts[0]).Trim().Trim('"')
    $leaf = [System.IO.Path]::GetFileName($exe)
    if ($leaf -match '^(?i)(rundll32|regsvr32)(\.exe)?$') {
        $a = ([string]$parts[1]) -replace '^\s*(/\w+\s+)*', ''
        $exe = [Environment]::ExpandEnvironmentVariables((($a -split ',')[0]).Trim().Trim('"'))
    } elseif ($leaf -match '^(?i)(cmd|powershell|pwsh|wscript|cscript|mshta|explorer|conhost)(\.exe)?$') {
        return ''
    }
    if ($exe -notmatch '^[A-Za-z]:\\') { return '' }
    return $exe
}

function Test-TargetMissing {
    # $true только если файла точно нет: диск несъёмный и подключён.
    param([string]$Path)
    if (-not $Path -or $Path -notmatch '^[A-Za-z]:\\') { return $false }
    try {
        $d = New-Object System.IO.DriveInfo ($Path.Substring(0, 1))
        if (-not $d.IsReady -or [string]$d.DriveType -ne 'Fixed') { return $false }
    } catch { return $false }
    if ([System.IO.File]::Exists($Path) -or [System.IO.Directory]::Exists($Path)) { return $false }
    if (-not [System.IO.Path]::HasExtension($Path) -and [System.IO.File]::Exists($Path + '.exe')) { return $false }
    if ($Path -match '(?i)\\system32\\' -and -not [Environment]::Is64BitProcess) {
        if ([System.IO.File]::Exists(($Path -replace '(?i)\\system32\\', '\Sysnative\'))) { return $false }
    }
    return $true
}

function Get-ClassesRealKeys {
    # HKCR - это сумма HKCU\Software\Classes и HKLM\Software\Classes. Удалять надо там, где лежит.
    param([string]$Sub)
    return @(@("Registry::HKEY_CURRENT_USER\Software\Classes\$Sub", "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\$Sub") | Where-Object { Test-Path -LiteralPath $_ })
}

function Get-ClsidDllMissing {
    # Путь к DLL обработчика, если он зарегистрирован и файла нет. Иначе ''.
    param([string]$Clsid)
    $miss = ''
    foreach ($root in @('Registry::HKEY_CLASSES_ROOT\CLSID', 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Classes\CLSID')) {
        $k = "$root\$Clsid\InprocServer32"
        if (-not (Test-Path -LiteralPath $k)) { if (Test-Path -LiteralPath "$root\$Clsid") { return '' } else { continue } }
        $p = [Environment]::ExpandEnvironmentVariables((Get-RegDefault $k)).Trim('"')
        if (-not $p -or $p -notmatch '^[A-Za-z]:\\') { return '' }
        if (-not (Test-TargetMissing $p)) { return '' }
        $miss = $p
    }
    return $miss
}

# ---------- Фон: проверка ----------

function Invoke-RegistryScan {
    $items = New-Object System.Collections.ArrayList
    $add = {
        param($Cat, $Title, $Detail, $Badge, $Checked, $Actions)
        [void]$items.Add(@{ Id = $items.Count + 1; Cat = $Cat; Title = $Title; Detail = $Detail; Badge = $Badge; Checked = [bool]$Checked; Actions = @($Actions) })
    }
    $HKLM = 'Registry::HKEY_LOCAL_MACHINE'; $HKCU = 'Registry::HKEY_CURRENT_USER'; $HKCR = 'Registry::HKEY_CLASSES_ROOT'

    # --- 1. Подозрительное ---
    Set-JobProgress 0.05 'Политики и перехваты'
    $pol = @(
        @('Software\Microsoft\Windows\CurrentVersion\Policies\System', 'DisableTaskMgr', 'Диспетчер задач отключён политикой'),
        @('Software\Microsoft\Windows\CurrentVersion\Policies\System', 'DisableRegistryTools', 'Редактор реестра отключён политикой'),
        @('Software\Policies\Microsoft\Windows\System', 'DisableCMD', 'Командная строка отключена политикой'),
        @('Software\Microsoft\Windows\CurrentVersion\Policies\Explorer', 'NoRun', 'Окно «Выполнить» отключено политикой'),
        @('Software\Microsoft\Windows\CurrentVersion\Policies\Explorer', 'NoControlPanel', 'Панель управления и «Параметры» отключены политикой'),
        @('Software\Microsoft\Windows\CurrentVersion\Policies\Explorer', 'NoFolderOptions', '«Параметры папок» отключены политикой')
    )
    foreach ($p in $pol) {
        foreach ($root in @($HKCU, $HKLM)) {
            $k = $root + '\' + $p[0]
            $v = Get-RegValue $k $p[1]
            if ($null -ne $v -and [int]$v -ne 0) {
                & $add 'danger' $p[2] ((Get-RegNative $k) + ' · ' + $p[1] + ' = ' + $v + ' - если ПК не рабочий в организации, это след вируса или «оптимизатора»') 'Вернуть' $true @(@{ T = 'delvalue'; K = $k; N = $p[1] })
            }
        }
    }
    $thirdAv = $false
    try { $thirdAv = @((Get-AntivirusState).Products | Where-Object { $_.Name -notmatch '(?i)defender' }).Count -gt 0 } catch {}
    foreach ($p in @(@('SOFTWARE\Policies\Microsoft\Windows Defender', 'DisableAntiSpyware', 'Защитник Windows отключён политикой'), @('SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection', 'DisableRealtimeMonitoring', 'Защита в реальном времени отключена политикой'))) {
        $k = $HKLM + '\' + $p[0]
        $v = Get-RegValue $k $p[1]
        if ($null -ne $v -and [int]$v -ne 0) {
            & $add 'danger' $p[2] ((Get-RegNative $k) + ' · ' + $p[1] + ' = ' + $v + $(if ($thirdAv) { ' - установлен другой антивирус, возможно это он' } else { ' - другого антивируса нет, компьютер без защиты' })) 'Вернуть' (-not $thirdAv) @(@{ T = 'delvalue'; K = $k; N = $p[1] })
        }
    }
    # IFEO: перехват запуска программы через «отладчик»
    foreach ($base in @("$HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options", "$HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Image File Execution Options")) {
        foreach ($k in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)) {
            $dbg = [string](Get-RegValue $k.PSPath 'Debugger')
            if (-not $dbg) { continue }
            $name = $k.PSChildName
            $t = Get-CommandTarget $dbg
            $missing = Test-TargetMissing $t
            if ($name -eq 'taskmgr.exe' -and $dbg -match '(?i)procexp|processhacker|systeminformer' -and -not $missing) { continue }
            $evil = $missing -or $dbg -match '(?i)(svchost|ntsd|rundll32|dllhost|conhost|systray|\bcmd(\.exe)?\b|\.bat|\.vbs|\.js\b)'
            & $add 'danger' ('Запуск ' + $name + ' перехвачен (IFEO)') ('Image File Execution Options\' + $name + ' · Debugger = ' + $dbg + $(if ($evil) { ' - программа не запустится' } else { ' - проверьте, ставили ли вы это сами' })) 'Убрать' $evil @(@{ T = 'delvalue'; K = $k.PSPath; N = 'Debugger' })
        }
    }
    # Winlogon: оболочка и userinit
    $wl = "$HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    $shell = [string](Get-RegValue $wl 'Shell')
    if ($shell -and $shell.Trim() -notmatch '^(?i)explorer(\.exe)?$') {
        & $add 'danger' 'Оболочка Windows подменена' ('Winlogon · Shell = ' + $shell + ' (должно быть explorer.exe)') 'Вернуть' $true @(@{ T = 'setvalue'; K = $wl; N = 'Shell'; V = 'explorer.exe'; Kind = 'String' })
    }
    $uinit = [string](Get-RegValue $wl 'Userinit')
    $okUi = ($env:WINDIR + '\system32\userinit.exe')
    if ($uinit -and ($uinit.Trim().TrimEnd(',').Trim()) -ne $okUi -and ($uinit.Trim().TrimEnd(',').Trim()) -notmatch '^(?i)(C:\\Windows\\system32\\)?userinit(\.exe)?$') {
        & $add 'danger' 'Вход в систему запускает лишнее (Userinit)' ('Winlogon · Userinit = ' + $uinit + ' (должно быть ' + $okUi + ',)') 'Вернуть' $true @(@{ T = 'setvalue'; K = $wl; N = 'Userinit'; V = ($okUi + ','); Kind = 'String' })
    }
    $wlu = "$HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"
    $ushell = [string](Get-RegValue $wlu 'Shell')
    if ($ushell) { & $add 'danger' 'Оболочка подменена для вашей учётной записи' ('HKCU\…\Winlogon · Shell = ' + $ushell) 'Убрать' $true @(@{ T = 'delvalue'; K = $wlu; N = 'Shell' }) }
    $win = "$HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows"
    $ai = [string](Get-RegValue $win 'AppInit_DLLs')
    if ($ai.Trim() -and [int](Get-RegValue $win 'LoadAppInit_DLLs') -eq 1) {
        & $add 'danger' 'Библиотеки внедряются во все программы (AppInit_DLLs)' ('AppInit_DLLs = ' + $ai + ' - так работают и вирусы, и некоторые старые программы. Исправление выключает загрузку, список не удаляется.') 'Выключить' $false @(@{ T = 'setvalue'; K = $win; N = 'LoadAppInit_DLLs'; V = 0; Kind = 'DWord' })
    }

    # --- 2. Автозагрузка в никуда ---
    Set-JobProgress 0.25 'Автозагрузка'
    $runs = @("$HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run", "$HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
        "$HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run", "$HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce",
        "$HKCU\Software\Microsoft\Windows\CurrentVersion\Run", "$HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce")
    foreach ($k in $runs) {
        $p = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue
        if (-not $p) { continue }
        foreach ($prop in $p.PSObject.Properties) {
            if ($prop.Name -like 'PS*' -or $prop.Name -eq '(default)') { continue }
            $t = Get-CommandTarget ([string]$prop.Value)
            if (Test-TargetMissing $t) {
                & $add 'run' $prop.Name ((Get-RegNative $k) -replace '\\SOFTWARE\\(WOW6432Node\\)?Microsoft\\Windows\\CurrentVersion\\', '\…\' -replace 'HKEY_LOCAL_MACHINE', 'HKLM' -replace 'HKEY_CURRENT_USER', 'HKCU' -replace '\\Software\\Microsoft\\Windows\\CurrentVersion\\', '\…\') 'Run' $true @(@{ T = 'delvalue'; K = $k; N = $prop.Name })
                $items[$items.Count - 1].Detail += ' → ' + $t + ' - файла нет'
            }
        }
    }
    foreach ($task in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' })) {
        foreach ($a in @($task.Actions)) {
            if (-not $a.Execute) { continue }
            $cmd = '"' + [Environment]::ExpandEnvironmentVariables(([string]$a.Execute).Trim('"')) + '" ' + [string]$a.Arguments
            $t = Get-CommandTarget $cmd
            if (Test-TargetMissing $t) {
                & $add 'run' ('Задача «' + $task.TaskName + '»') ('планировщик ' + $task.TaskPath + ' → ' + $t + ' - файла нет') 'Задача' $true @(@{ T = 'deltask'; P = [string]$task.TaskPath; N = [string]$task.TaskName })
                break
            }
        }
    }

    # --- 3. Контекстное меню, ассоциации, App Paths ---
    Set-JobProgress 0.45 'Контекстное меню'
    foreach ($scope in @('*', 'Directory', 'Directory\Background', 'Folder', 'Drive', 'AllFilesystemObjects')) {
        foreach ($h in @(Get-ChildItem -LiteralPath "$HKCR\$scope\shellex\ContextMenuHandlers" -ErrorAction SilentlyContinue)) {
            $clsid = Get-RegDefault $h.PSPath
            if ($clsid -notmatch '^\{[0-9A-Fa-f-]{36}\}$') { $clsid = $h.PSChildName }
            if ($clsid -notmatch '^\{[0-9A-Fa-f-]{36}\}$') { continue }
            $miss = Get-ClsidDllMissing $clsid
            if (-not $miss) { continue }
            $sub = "$scope\shellex\ContextMenuHandlers\" + $h.PSChildName
            $real = @(Get-ClassesRealKeys $sub)
            if (-not $real.Count) { continue }
            & $add 'menu' ('«' + $h.PSChildName + '» в меню ' + $(switch ($scope) { '*' { 'файлов' } 'Directory\Background' { 'фона папки' } 'Drive' { 'дисков' } default { 'папок' } })) ('HKCR\' + $sub + ' → ' + $miss + ' - файла нет. Из-за таких записей правый клик открывается с задержкой.') 'Меню' $true @($real | ForEach-Object { @{ T = 'delkey'; K = $_ } })
        }
        foreach ($v in @(Get-ChildItem -LiteralPath "$HKCR\$scope\shell" -ErrorAction SilentlyContinue)) {
            $cmd = Get-RegDefault ($v.PSPath + '\command')
            $t = Get-CommandTarget $cmd
            if (-not (Test-TargetMissing $t)) { continue }
            $sub = "$scope\shell\" + $v.PSChildName
            $real = @(Get-ClassesRealKeys $sub)
            if (-not $real.Count) { continue }
            $label = [string](Get-RegValue $v.PSPath 'MUIVerb'); if (-not $label -or $label -like '@*') { $label = Get-RegDefault $v.PSPath }; if (-not $label -or $label -like '@*') { $label = $v.PSChildName }
            & $add 'menu' ('«' + ($label -replace '&', '') + '» в контекстном меню') ('HKCR\' + $sub + ' → ' + $t + ' - программа удалена') 'Меню' $true @($real | ForEach-Object { @{ T = 'delkey'; K = $_ } })
        }
    }
    Set-JobProgress 0.6 'Ассоциации файлов'
    $progs = @{}
    $fe = "$HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts"
    foreach ($e in @(Get-ChildItem -LiteralPath $HKCR -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like '.*' })) {
        if (Test-JobCancel) { break }
        $ext = $e.PSChildName
        $uc = [string](Get-RegValue "$fe\$ext\UserChoice" 'ProgId')
        $pid0 = if ($uc) { $uc } else { Get-RegDefault $e.PSPath }
        if (-not $pid0 -or $pid0 -like 'AppX*' -or $pid0 -like 'Applications\*') { continue }
        if (-not $progs.ContainsKey($pid0)) { $progs[$pid0] = @{ Exts = @(); Uc = @() } }
        $progs[$pid0].Exts += $ext
        if ($uc) { $progs[$pid0].Uc += $ext }
    }
    foreach ($pg in $progs.Keys) {
        $cmd = Get-RegDefault "$HKCR\$pg\shell\open\command"
        if (-not $cmd) { $dv = Get-RegDefault "$HKCR\$pg\shell"; if ($dv) { $cmd = Get-RegDefault "$HKCR\$pg\shell\$dv\command" } }
        $t = Get-CommandTarget $cmd
        if (-not (Test-TargetMissing $t)) { continue }
        $acts = @(Get-ClassesRealKeys $pg | ForEach-Object { @{ T = 'delkey'; K = $_ } })
        foreach ($x in $progs[$pg].Uc) { $acts += @{ T = 'delkey'; K = "$fe\$x\UserChoice" } }
        if (-not $acts.Count) { continue }
        $exts = @($progs[$pg].Exts)
        & $add 'menu' ((($exts | Select-Object -First 4) -join ', ') + $(if ($exts.Count -gt 4) { ' и ещё ' + ($exts.Count - 4) }) + ' открываются удалённой программой') ($pg + ' → ' + $t + ' - файла нет. После исправления Windows спросит, чем открывать.') 'Ассоциация' $true $acts
    }
    Set-JobProgress 0.75 'App Paths'
    foreach ($base in @("$HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths", "$HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths", "$HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths")) {
        foreach ($k in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)) {
            $p = [Environment]::ExpandEnvironmentVariables((Get-RegDefault $k.PSPath)).Trim('"')
            if (Test-TargetMissing $p) {
                $short = (Get-RegNative $k.PSPath) -replace '^HKEY_LOCAL_MACHINE', 'HKLM' -replace '^HKEY_CURRENT_USER', 'HKCU'
                & $add 'menu' ('App Paths: ' + $k.PSChildName) ($short + ' → ' + $p + ' - файла нет') 'App Paths' $true @(@{ T = 'delkey'; K = $k.PSPath })
            }
        }
    }

    # --- 4. Программы, которых уже нет ---
    Set-JobProgress 0.85 'Список программ'
    try {
        foreach ($p in @(Get-InstalledPrograms)) {
            if (-not $p.Broken) { continue }
            if ($p.Location -and (Test-Path -LiteralPath $p.Location)) { continue }
            & $add 'apps' $p.Name ('деинсталлятор потерян, папки программы нет · ' + (Get-RegNative $p.KeyPath)) 'Программа' $true @(@{ T = 'delkey'; K = $p.KeyPath })
        }
    } catch {}

    # --- Размер файлов реестра ---
    Set-JobProgress 0.95 'Размер реестра'
    $hives = @(@('SOFTWARE', (Join-Path $env:WINDIR 'System32\config\SOFTWARE'), 1.5GB), @('SYSTEM', (Join-Path $env:WINDIR 'System32\config\SYSTEM'), 200MB),
        @('NTUSER.DAT', (Join-Path $env:USERPROFILE 'NTUSER.DAT'), 200MB), @('UsrClass.dat', (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\UsrClass.dat'), 500MB))
    $size = 0.0; $big = @()
    foreach ($h in $hives) {
        try { $len = (Get-Item -LiteralPath $h[1] -Force -ErrorAction Stop).Length; $size += $len; if ($len -gt $h[2]) { $big += $h[0] + ' - ' + (Format-Size $len) } } catch {}
    }
    Add-History -Kind 'registry' -Name ('Проверка реестра: найдено ' + $items.Count) -Result 'ok'
    return @{ Items = @($items); Size = $size; Big = $big; Time = Get-Date }
}

# ---------- Фон: исправление и откат ----------

function Invoke-RegistryFixes {
    param($Items)
    $dir = Join-Path $BackupFolder ('registry-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
    $exported = @{}
    $tasks = @()
    $n = 0; $ok = 0
    foreach ($it in @($Items)) {
        $good = $true
        foreach ($a in @($it.Actions)) {
            try {
                if ($a.T -eq 'deltask') {
                    $n++
                    $xml = Export-ScheduledTask -TaskName $a.N -TaskPath $a.P -ErrorAction Stop
                    $f = Join-Path $dir ('task-' + $n + '.xml')
                    [System.IO.File]::WriteAllText($f, [string]$xml, [System.Text.Encoding]::Unicode)
                    $tasks += @{ Path = $a.P; Name = $a.N; File = [System.IO.Path]::GetFileName($f) }
                    Unregister-ScheduledTask -TaskName $a.N -TaskPath $a.P -Confirm:$false -ErrorAction Stop
                    continue
                }
                if (-not (Test-Path -LiteralPath $a.K)) { continue }
                $native = Get-RegNative $a.K
                if (-not $exported.ContainsKey($native)) {
                    $n++
                    $f = Join-Path $dir ($n.ToString('000') + '.reg')
                    $r = Invoke-ProcessLive -FilePath (Join-Path $env:WINDIR 'System32\reg.exe') -Arguments ('export "' + $native + '" "' + $f + '" /y') -TimeoutSec 60 -Quiet
                    if ($r.Code -ne 0) { throw ('не удалось сохранить копию ' + $native) }
                    $exported[$native] = $f
                }
                switch ($a.T) {
                    'delvalue' { Remove-ItemProperty -LiteralPath $a.K -Name $a.N -ErrorAction Stop }
                    'setvalue' { Set-ItemProperty -LiteralPath $a.K -Name $a.N -Value $a.V -Type $a.Kind -ErrorAction Stop }
                    'delkey' { Remove-Item -LiteralPath $a.K -Recurse -Force -ErrorAction Stop }
                }
            } catch {
                $good = $false
                Write-Log ('   не исправлено: ' + $it.Title + ' - ' + $_.Exception.Message) 'warn'
            }
        }
        if ($good) { $ok++; Write-Log ('Исправлено: ' + $it.Title) }
    }
    if ($tasks.Count) { ConvertTo-Json -InputObject @($tasks) -Depth 3 | Set-Content -LiteralPath (Join-Path $dir 'tasks.json') -Encoding UTF8 -ErrorAction SilentlyContinue }
    Write-Log ('Исправлено ' + $ok + ' из ' + @($Items).Count + '. Копия: ' + $dir) 'ok'
    Add-History -Kind 'registry' -Name ('Реестр: исправлено ' + $ok + ' записей') -Detail ((@($Items) | ForEach-Object { $_.Title }) -join '; ') -Ref $dir
    return $ok
}

function Restore-RegistryBackup {
    # Фон. Возвращает всё из папки копии: .reg и задачи планировщика.
    param([string]$Folder)
    if (-not (Test-Path -LiteralPath $Folder)) { Write-Log ('Папка копии не найдена: ' + $Folder) 'err'; return $false }
    $ok = $true
    foreach ($f in @(Get-ChildItem -LiteralPath $Folder -Filter '*.reg' -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $r = Invoke-ProcessLive -FilePath (Join-Path $env:WINDIR 'System32\reg.exe') -Arguments ('import "' + $f.FullName + '"') -TimeoutSec 60 -Quiet
        if ($r.Code -eq 0) { Write-Log ('Восстановлено: ' + $f.Name) } else { $ok = $false; Write-Log ('Не восстановлено: ' + $f.Name) 'warn' }
    }
    $tj = Join-Path $Folder 'tasks.json'
    if (Test-Path -LiteralPath $tj) {
        try {
            foreach ($t in @(Get-Content -LiteralPath $tj -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)) {
                try {
                    $xml = [System.IO.File]::ReadAllText((Join-Path $Folder $t.File))
                    Register-ScheduledTask -Xml $xml -TaskName $t.Name -TaskPath $t.Path -Force -ErrorAction Stop | Out-Null
                    Write-Log ('Задача возвращена: ' + $t.Name)
                } catch { $ok = $false; Write-Log ('Задача не возвращена: ' + $t.Name + ' - ' + $_.Exception.Message) 'warn' }
            }
        } catch {}
    }
    Add-History -Kind 'registry' -Name 'Откат исправлений реестра' -Result $(if ($ok) { 'ok' } else { 'fail' }) -Ref $Folder
    Write-Log $(if ($ok) { 'Откат выполнен' } else { 'Откат выполнен частично' }) $(if ($ok) { 'ok' } else { 'warn' })
    return $ok
}

# ---------- Интерфейс ----------

function Build-Page_registry {
    $ui = @{ Rows = @{}; Secs = @{} }
    $script:RgUi = $ui
    $ui.ScanBtn = New-Button -Text 'Проверить' -Icon 'search' -OnClick { Start-RegistryScan }
    $ui.FixBtn = New-Button -Text 'Исправить выбранные' -Icon 'check' -Kind Primary -OnClick { Start-RegistryFix }
    $ui.FixBtn.IsEnabled = $false
    $ab = New-ActionBar -Right @($ui.FixBtn)
    $ui.Bar = $ab
    $L = New-PageLayout -Title 'Проверка реестра' -Subtitle 'Только записи, которые вызывают реальные проблемы. Ничего системного не трогаем.' -HeaderRight @($ui.ScanBtn) -ActionBar $ab.Root
    $ui.Found = New-StatCard -Label 'Найдено проблем' -Value '—'
    $ui.Danger = New-StatCard -Label 'Подозрительное' -Value '—'
    $ui.Size = New-StatCard -Label 'Размер реестра' -Value '—'
    [void]$L.Body.Children.Add((New-Grid -Columns 3 -Items @($ui.Found.Root, $ui.Danger.Root, $ui.Size.Root)))
    $ui.Body = New-Stack
    [void]$L.Body.Children.Add($ui.Body)
    [void]$ui.Body.Children.Add((New-Hint -Text 'Это не «чистка реестра» ради цифр - лишние ключи на скорость не влияют. Здесь ищется то, что мешает: вирусные блокировки, автозагрузка и пункты меню удалённых программ, сломанные ассоциации. Перед изменением всё сохраняется, откатить можно на странице «История».' -Kind 'info'))
    return $L.Root
}

function Show-Page_registry {
    param($Arg)
    if (-not $script:RgUi.Loaded) { Start-RegistryScan }
}

function Start-RegistryScan {
    $ui = $script:RgUi
    if ($ui.Running) { return }
    $ui.Loaded = $true
    $ui.Running = $true
    $ui.ScanBtn.IsEnabled = $false; $ui.FixBtn.IsEnabled = $false
    $ui.Body.Children.Clear()
    [void]$ui.Body.Children.Add((New-Placeholder 'Проверяю реестр, автозагрузку и контекстное меню…'))
    Start-BgTask -Name 'Проверка реестра' -Script { Invoke-RegistryScan } -OnDone {
        param($r)
        $ui = $script:RgUi
        $ui.Running = $false
        $ui.ScanBtn.IsEnabled = $true
        Set-ButtonText -Button $ui.ScanBtn -Text 'Проверить снова'
        if ($r) { Set-RegistryResult -R $r } else { $ui.Body.Children.Clear(); [void]$ui.Body.Children.Add((New-Placeholder 'Проверка не завершилась - подробности в журнале.')) }
    } | Out-Null
}

function Set-RegistryResult {
    param($R)
    $ui = $script:RgUi
    $items = @($R.Items)
    $danger = @($items | Where-Object { $_.Cat -eq 'danger' })
    $ui.Found.Value.Text = [string]$items.Count
    $ui.Found.Sub.Text = 'проверка ' + ([datetime]$R.Time).ToString('HH:mm')
    $ui.Danger.Value.Text = [string]$danger.Count
    $ui.Danger.Value.Foreground = Get-Brush $(if ($danger.Count) { 'Bad' } else { 'Ok' })
    $ui.Danger.Sub.Text = if ($danger.Count) { 'следы вирусов или «оптимизаторов»' } else { 'не найдено' }
    $ui.Size.Value.Text = Format-Size $R.Size
    $ui.Size.Value.Foreground = Get-Brush $(if (@($R.Big).Count) { 'Warn' } else { 'Ok' })
    $ui.Size.Sub.Text = if (@($R.Big).Count) { 'раздут: ' + (@($R.Big) -join ', ') } else { 'в норме - сжатие не нужно' }
    $ui.Rows = @{}
    $ui.Body.Children.Clear()
    if (-not $items.Count) {
        [void]$ui.Body.Children.Add((New-Hint -Text 'Проблем не найдено: автозагрузка, контекстное меню, ассоциации и защитные настройки в порядке.' -Kind 'ok'))
        Update-RegistrySelection
        return
    }
    $cats = [ordered]@{
        danger = @('Подозрительное', 'так делают вирусы', 'warn', 'Bad')
        run    = @('Автозагрузка в никуда', 'при входе выскакивает «не удаётся найти»', 'power', 'Accent')
        menu   = @('Контекстное меню и ассоциации', 'медленный правый клик, «Открыть с помощью» в никуда', 'key', 'Accent')
        apps   = @('Программы, которых уже нет', 'висят в списке установленных', 'box', 'Accent')
    }
    foreach ($c in $cats.Keys) {
        $list = @($items | Where-Object { $_.Cat -eq $c })
        if (-not $list.Count) { continue }
        $d = $cats[$c]
        $sec = New-Section -Title ($d[0] + ' · ' + $list.Count) -Right @((New-Text -Text $d[1] -Size 12 -Color 'Muted'))
        if ($c -eq 'danger') { try { $sec.Root.BorderBrush = Get-Brush 'Bad'; $sec.Root.BorderThickness = New-Thickness 3, 1, 1, 1 } catch {} }
        foreach ($it in $list) {
            $chk = New-CheckBox -Checked $it.Checked -Tag $it.Id -OnChange { Update-RegistrySelection }
            $main = New-TitleBlock -Title $it.Title -Sub $it.Detail
            $main.ToolTip = $it.Detail
            $badge = New-Badge $it.Badge $(if ($c -eq 'danger') { 'bad' } else { 'muted' })
            [void]$sec.Body.Children.Add((New-Row -Left $chk -Main $main -Right @($badge) -Padding (16, 8, 16, 8)))
            $ui.Rows[$it.Id] = @{ Check = $chk; Item = $it }
        }
        [void]$ui.Body.Children.Add($sec.Root)
    }
    Update-RegistrySelection
}

function Update-RegistrySelection {
    $ui = $script:RgUi
    $sel = @($ui.Rows.Values | Where-Object { $_.Check.IsChecked })
    $ui.Bar.Text.Text = [string]$sel.Count + ' выбрано · перед изменением каждый ключ сохраняется в .reg'
    $ui.FixBtn.IsEnabled = $sel.Count -gt 0 -and -not $ui.Running
}

function Start-RegistryFix {
    $ui = $script:RgUi
    $sel = @($ui.Rows.Values | Where-Object { $_.Check.IsChecked } | ForEach-Object { $_.Item })
    if (-not $sel.Count) { return }
    $msg = 'Исправить ' + $sel.Count + " записей?`n`n  • " + ((@($sel | Select-Object -First 12) | ForEach-Object { $_.Title }) -join "`n  • ") + $(if ($sel.Count -gt 12) { "`n  • и ещё " + ($sel.Count - 12) } else { '' }) + "`n`nПеред изменением будет создана точка восстановления и копия всех ключей. Откатить можно на странице «История»."
    if (-not (Show-Confirm -Message $msg -Title 'Проверка реестра')) { return }
    $ui.Running = $true
    $ui.FixBtn.IsEnabled = $false; $ui.ScanBtn.IsEnabled = $false
    Start-BgTask -Name 'Исправление реестра' -Vars @{ Sel = $sel } -Script {
        [void](New-RestorePoint -Description 'PotatoPC: исправление реестра')
        Invoke-RegistryFixes -Items $Sel
    } -OnDone {
        $script:RgUi.Running = $false
        if ($script:StUi) { $script:StUi.Loaded = $false }
        if ($script:UnUi) { $script:UnUi.Loaded = $false }
        Start-RegistryScan
    } | Out-Null
}
