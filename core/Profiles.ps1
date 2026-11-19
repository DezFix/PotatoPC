# PotatoPC v7 - файлы пользователей на другом диске.
#
# Профиль (C:\Users\Имя) переносится на другой диск целиком: Windows работает
# с ним как раньше, а при переустановке системы он остаётся на месте. После
# переустановки файлы из старого профиля возвращаются новой учётной записи.
#
# Как устроен перенос:
#   * пользователь не должен быть в системе (файлы профиля заняты);
#   * robocopy /COPY:DATSO копирует всё с правами и владельцами, точки соединения (legacy junctions
#     вроде «Application Data») создаются заново - уже со ссылкой на новое место;
#   * в реестре меняется ProfileList\<SID>\ProfileImagePath; копия ключа ложится
#     в BackupFolder, откат - из «Истории»;
#   * старая папка на C: не удаляется, пока пользователь не проверит новую.
# Все функции, кроме чистых (Select-BestProfileDrive, Get-DriveVerdict,
# ConvertTo-BookmarksHtml, Get-UniquePath), рассчитаны на фоновый поток.

function Get-ProfileStatePath {
    # Состояние переносов относится к компьютеру, а не к папке программы:
    # даже в портативном режиме оно лежит в ProgramData.
    $pd = if ($env:ProgramData) { $env:ProgramData } else { $env:TEMP }
    return (Join-Path $pd 'PotatoPC\profiles.json')
}

function Get-ProfileState {
    $r = @{ Moves = @(); Dismissed = @() }
    try {
        $p = Get-ProfileStatePath
        if (Test-Path -LiteralPath $p) {
            $o = Get-Content -LiteralPath $p -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($o.Moves) { $r.Moves = @($o.Moves) }
            if ($o.Dismissed) { $r.Dismissed = @($o.Dismissed | ForEach-Object { [string]$_ }) }
        }
    } catch {}
    return $r
}

function Save-ProfileState {
    param($State)
    try {
        $p = Get-ProfileStatePath
        $dir = Split-Path $p -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $json = @{ Moves = @($State.Moves); Dismissed = @($State.Dismissed) } | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($p, $json, (New-Object System.Text.UTF8Encoding($true)))
    } catch { Write-Log ('Не сохранилось состояние переносов: ' + $_.Exception.Message) 'warn' }
}

function Add-ProfileMoveRecord {
    param([string]$Sid, [string]$Old, [string]$New)
    $s = Get-ProfileState
    $list = @($s.Moves | Where-Object { [string]$_.Sid -ne $Sid })
    $list += [pscustomobject]@{ Sid = $Sid; Old = $Old; New = $New; Time = (Get-Date).ToString('s') }
    $s.Moves = $list
    Save-ProfileState $s
}

function Get-UniquePath {
    # Свободное имя рядом: «Имя.2» для папок профиля, «файл (со старой Windows).txt» для файлов.
    param([string]$Path, [string]$Suffix = '', [scriptblock]$Exists = { param($p) Test-Path -LiteralPath $p })
    if (-not (& $Exists $Path)) { return $Path }
    $dir = Split-Path $Path -Parent
    $leaf = Split-Path $Path -Leaf
    if ($Suffix) {
        $ext = [System.IO.Path]::GetExtension($leaf)
        $stem = if ($ext) { $leaf.Substring(0, $leaf.Length - $ext.Length) } else { $leaf }
        for ($i = 1; $i -lt 1000; $i++) {
            $tag = if ($i -eq 1) { $Suffix } else { $Suffix.TrimEnd(')') + ' ' + $i + ')' }
            $c = Join-Path $dir ($stem + ' ' + $tag + $ext)
            if (-not (& $Exists $c)) { return $c }
        }
    } else {
        for ($i = 2; $i -lt 1000; $i++) {
            $c = Join-Path $dir ($leaf + '.' + $i)
            if (-not (& $Exists $c)) { return $c }
        }
    }
    throw ('Не нашлось свободного имени для ' + $Path)
}

# ---------- Диски ----------

function Get-DriveVerdict {
    # Чистая функция: подходит ли диск для файлов пользователя и почему.
    param($Drive)
    $v = @{ Suitable = $false; Reason = ''; Note = ''; NoteKind = 'muted' }
    if ($Drive.IsSystem) { $v.Reason = 'Здесь Windows - сотрётся при переустановке'; return $v }
    if ([int]$Drive.DriveType -eq 4) { $v.Reason = 'Сетевые диски для этого не годятся'; return $v }
    if ([int]$Drive.DriveType -eq 2 -or [string]$Drive.BusType -in @('USB', 'SD', 'MMC', '1394')) {
        $v.Reason = 'Флешка или внешний диск: если его отключить, Windows не сможет войти в учётную запись'; return $v
    }
    if ([int]$Drive.DriveType -ne 3) { $v.Reason = 'Этот диск не подходит'; return $v }
    if ([string]$Drive.FileSystem -ne 'NTFS') { $v.Reason = 'Файловая система ' + $(if ($Drive.FileSystem) { $Drive.FileSystem } else { 'неизвестна' }) + ' - нужна NTFS'; return $v }
    $v.Suitable = $true
    if ($Drive.SameDiskAsSystem) {
        $v.Note = 'Тот же физический диск, что и ' + $env:SystemDrive + ' - переустановку переживёт, поломку диска нет'
    } else {
        $v.Note = 'Отдельный диск - файлы уцелеют, даже если сломается диск с Windows'
        $v.NoteKind = 'ok'
    }
    return $v
}

function Select-BestProfileDrive {
    # Чистая функция. Отдельный физический диск лучше раздела на том же,
    # среди равных - где больше места. Запас - 2 ГБ сверх нужного.
    param([object[]]$Drives, [double]$NeedBytes = 0)
    $ok = @($Drives | Where-Object { $_.Suitable -and ([double]$_.Free - $NeedBytes) -ge 2GB })
    if ($ok.Count -eq 0) { return $null }
    $best = $ok | Sort-Object @{ Expression = { [bool]$_.SameDiskAsSystem } }, @{ Expression = { [double]$_.Free }; Descending = $true } | Select-Object -First 1
    return [string]$best.Letter
}

function Get-ProfileDrives {
    # Все диски с буквой (кроме CD) и вердикт для каждого.
    $sys = ($env:SystemDrive).TrimEnd(':').ToUpperInvariant()
    $diskOf = @{}
    $phys = @{}
    try { foreach ($p in @(Get-Partition -ErrorAction Stop)) { if ($p.DriveLetter -and [string]$p.DriveLetter -match '^[A-Za-z]$') { $diskOf[([string]$p.DriveLetter).ToUpperInvariant()] = [int]$p.DiskNumber } } } catch {}
    try { foreach ($d in @(Get-PhysicalDisk -ErrorAction Stop)) { $phys[[string]$d.DeviceId] = $d } } catch {}
    $sysDisk = if ($diskOf.ContainsKey($sys)) { $diskOf[$sys] } else { -1 }
    $list = @()
    foreach ($ld in @(Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue)) {
        $dt = [int]$ld.DriveType
        if ($dt -notin @(2, 3, 4)) { continue }
        $L = ([string]$ld.DeviceID).TrimEnd(':').ToUpperInvariant()
        $d = @{
            Letter = $L; Label = [string]$ld.VolumeName; Size = [double]$ld.Size; Free = [double]$ld.FreeSpace
            FileSystem = [string]$ld.FileSystem; DriveType = $dt; IsSystem = ($L -eq $sys)
            DiskNumber = -1; SameDiskAsSystem = $false; BusType = ''; Media = ''
        }
        if ($diskOf.ContainsKey($L)) {
            $d.DiskNumber = $diskOf[$L]
            $d.SameDiskAsSystem = ($sysDisk -ge 0 -and $d.DiskNumber -eq $sysDisk)
            $pd = $phys[[string]$d.DiskNumber]
            if ($pd) {
                $d.BusType = [string]$pd.BusType
                $d.Media = if ([string]$pd.MediaType -eq 'SSD' -or $d.BusType -eq 'NVMe') { 'SSD' } elseif ([string]$pd.MediaType -eq 'HDD') { 'HDD' } else { '' }
            }
        }
        $v = Get-DriveVerdict $d
        foreach ($k in $v.Keys) { $d[$k] = $v[$k] }
        if (-not $d.Label) { $d.Label = if ($d.IsSystem) { 'Система' } elseif ($dt -eq 4) { 'Сеть' } elseif ($dt -eq 2) { 'Флешка' } else { 'Диск' } }
        $list += $d
    }
    return @($list | Sort-Object { $_.Letter })
}

# ---------- Профили ----------

function Get-ProfileListMap {
    # SID -> развёрнутый путь профиля из реестра (без служебных SYSTEM, LOCAL SERVICE...).
    $map = @{}
    $root = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    foreach ($k in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
        try {
            $raw = (Get-ItemProperty -LiteralPath $k.PSPath -Name 'ProfileImagePath' -ErrorAction Stop).ProfileImagePath
            $map[[string]$k.PSChildName] = [System.Environment]::ExpandEnvironmentVariables([string]$raw)
        } catch {}
    }
    return $map
}

function Get-UserProfileStates {
    # SID -> @{ Path; Loaded; Letter; OnSystem; Exists }. Только для известных профилей.
    $map = Get-ProfileListMap
    $loaded = @{}
    try { foreach ($p in @(Get-CimInstance Win32_UserProfile -ErrorAction Stop)) { $loaded[[string]$p.SID] = [bool]$p.Loaded } } catch {}
    $sys = ($env:SystemDrive).TrimEnd(':').ToUpperInvariant()
    $out = @{}
    foreach ($sid in $map.Keys) {
        $path = $map[$sid]
        $L = ''
        if ($path -match '^([A-Za-z]):') { $L = $Matches[1].ToUpperInvariant() }
        $out[$sid] = @{ Path = $path; Loaded = [bool]$loaded[$sid]; Letter = $L; OnSystem = ($L -eq $sys); Exists = (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue) }
    }
    return $out
}

function Get-FolderBytes {
    # Размер папки. robocopy /L считает быстро и не спотыкается о права и длинные пути.
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return 0.0 }
    $rc = Join-Path $env:WINDIR 'System32\robocopy.exe'
    $nul = Join-Path $env:TEMP ('potatopc-size-' + [guid]::NewGuid().ToString('N'))
    $r = Invoke-ProcessLive -FilePath $rc -Arguments ('"' + $Path.TrimEnd('\') + '" "' + $nul + '" /L /E /XJ /BYTES /NFL /NDL /NJH /NP /R:0 /W:0') -TimeoutSec 1800 -Quiet
    # Итоговая таблица: Каталоги, Файлы, Байты, Время - подписи зависят от языка, порядок нет.
    $rows = @(($r.Output -split "`r?`n") | Where-Object { $_ -match ':\s*\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s*$' })
    if ($rows.Count -ge 3) {
        if ($rows[2] -match ':\s*(\d+)') { return [double]$Matches[1] }
    }
    # Запасной путь: обычный обход (медленнее).
    $sum = 0.0
    try {
        $stack = New-Object System.Collections.Stack
        $stack.Push((New-Object System.IO.DirectoryInfo $Path))
        while ($stack.Count -gt 0) {
            $d = $stack.Pop()
            try {
                foreach ($e in $d.EnumerateFileSystemInfos()) {
                    if (($e.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                    if ($e -is [System.IO.DirectoryInfo]) { $stack.Push($e) } else { $sum += $e.Length }
                }
            } catch {}
        }
    } catch {}
    return $sum
}

function New-UserProfileNow {
    # Создаёт профиль сразу (обычно Windows делает это при первом входе).
    param([string]$Sid, [string]$Name)
    if (-not ('PotatoPC.UserEnv' -as [type])) {
        Add-Type -Namespace 'PotatoPC' -Name 'UserEnv' -MemberDefinition '[DllImport("userenv.dll", CharSet = CharSet.Unicode)] public static extern int CreateProfile(string pszUserSid, string pszUserName, System.Text.StringBuilder pszProfilePath, uint cchProfilePath);'
    }
    $sb = New-Object System.Text.StringBuilder 520
    $hr = [PotatoPC.UserEnv]::CreateProfile($Sid, $Name, $sb, 520)
    # 0x800700B7 - профиль уже есть.
    if ($hr -ne 0 -and $hr -ne -2147024713) { throw ('Windows не создала профиль (код 0x' + ('{0:X8}' -f $hr) + ')') }
    $map = Get-ProfileListMap
    if ($map.ContainsKey($Sid)) { return $map[$Sid] }
    return [string]$sb
}

function Copy-ProfileJunctions {
    # Точки соединения в профиле («Application Data», «Мои документы»...) ведут
    # в сам профиль по полному пути. Создаём их заново - со ссылкой на новое место.
    param([string]$Src, [string]$Dst, [int]$MaxDepth = 6)
    $src = $Src.TrimEnd('\'); $dst = $Dst.TrimEnd('\')
    $cmd = Join-Path $env:WINDIR 'System32\cmd.exe'
    $ic = Join-Path $env:WINDIR 'System32\icacls.exe'
    $at = Join-Path $env:WINDIR 'System32\attrib.exe'
    $n = 0
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue(@((New-Object System.IO.DirectoryInfo $src), 0))
    while ($queue.Count -gt 0) {
        $item = $queue.Dequeue(); $dir = $item[0]; $depth = $item[1]
        $children = @()
        try { $children = @($dir.EnumerateDirectories()) } catch { continue }
        foreach ($c in $children) {
            if (($c.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
                if ($depth + 1 -lt $MaxDepth) { $queue.Enqueue(@($c, ($depth + 1))) }
                continue
            }
            try {
                $target = @((Get-Item -LiteralPath $c.FullName -Force -ErrorAction Stop).Target)[0]
                if (-not $target) { continue }
                if ($target.StartsWith($src + '\', [System.StringComparison]::OrdinalIgnoreCase) -or $target -ieq $src) { $target = $dst + $target.Substring($src.Length) }
                $link = $dst + $c.FullName.Substring($src.Length)
                if ((Test-Path -LiteralPath $link) -or -not (Test-Path -LiteralPath (Split-Path $link -Parent))) { continue }
                # mklink не требует, чтобы цель существовала; icacls /L и attrib /L работают
                # с самой ссылкой, а не с папкой, куда она ведёт.
                $mk = Invoke-ProcessLive -FilePath $cmd -Arguments ('/d /c mklink /J "' + $link + '" "' + $target + '"') -TimeoutSec 30 -Quiet
                if (-not (Test-Path -LiteralPath $link)) { throw $mk.Output.Trim() }
                # Стандартные ссылки закрыты от просмотра (запрет «Все: содержимое папки»),
                # иначе программы резервного копирования ходят по кругу.
                $acl = Invoke-ProcessLive -FilePath $ic -Arguments ('"' + $c.FullName + '" /L') -TimeoutSec 30 -Quiet
                if ($acl.Output -match '\(DENY\)') { [void](Invoke-ProcessLive -FilePath $ic -Arguments ('"' + $link + '" /deny *S-1-1-0:(RD) /L /Q') -TimeoutSec 30 -Quiet) }
                $flags = @()
                if (($c.Attributes -band [System.IO.FileAttributes]::Hidden) -ne 0) { $flags += '+H' }
                if (($c.Attributes -band [System.IO.FileAttributes]::System) -ne 0) { $flags += '+S' }
                if ($flags.Count) { [void](Invoke-ProcessLive -FilePath $at -Arguments (($flags -join ' ') + ' "' + $link + '" /L') -TimeoutSec 30 -Quiet) }
                $n++
            } catch { Write-Log ('Ссылка не создана: ' + $c.FullName + ' - ' + $_.Exception.Message) 'warn' }
        }
    }
    return $n
}

function Set-ProfileRootAcl {
    # Папка профиля: только SYSTEM, администраторы и сам пользователь, без наследования
    # от корня диска (там по умолчанию «Прошедшие проверку» с правом изменения).
    param([string]$Path, [string]$Sid)
    $ic = Join-Path $env:WINDIR 'System32\icacls.exe'
    $a = '"' + $Path + '" /inheritance:r /grant:r *S-1-5-18:(OI)(CI)F *S-1-5-32-544:(OI)(CI)F *' + $Sid + ':(OI)(CI)F /Q'
    $r = Invoke-ProcessLive -FilePath $ic -Arguments $a -TimeoutSec 120 -Quiet
    if ($r.Code -ne 0) { Write-Log ('Права на папку профиля выставлены не полностью: ' + $r.Output.Trim()) 'warn' }
    $r2 = Invoke-ProcessLive -FilePath $ic -Arguments ('"' + $Path + '" /setowner *' + $Sid + ' /Q') -TimeoutSec 120 -Quiet
}

function Remove-FolderSafe {
    # rd /s /q не заходит внутрь точек соединения - в отличие от Remove-Item в PowerShell 5.1.
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $true }
    [void](Invoke-ProcessLive -FilePath (Join-Path $env:WINDIR 'System32\cmd.exe') -Arguments ('/d /c rd /s /q "' + $Path + '"') -TimeoutSec 3600 -Quiet)
    return -not (Test-Path -LiteralPath $Path)
}

function Move-UserProfile {
    <#
      Фон. Переносит профиль пользователя на диск $Drive (буква). Пользователь
      не должен быть в системе. Возвращает @{ Ok; Message; Old; New; Backup }.
    #>
    param([Parameter(Mandatory)][string]$Sid, [Parameter(Mandatory)][string]$Drive)
    $res = @{ Ok = $false; Message = ''; Old = ''; New = ''; Backup = '' }
    $Drive = $Drive.TrimEnd(':', '\').ToUpperInvariant()
    $keyPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\' + $Sid
    try {
        $old = [System.Environment]::ExpandEnvironmentVariables([string](Get-ItemProperty -LiteralPath $keyPath -Name 'ProfileImagePath' -ErrorAction Stop).ProfileImagePath).TrimEnd('\')
    } catch { $res.Message = 'У пользователя ещё нет папки профиля'; return $res }
    $res.Old = $old
    if (-not (Test-Path -LiteralPath $old)) { $res.Message = 'Папка профиля не найдена: ' + $old; return $res }
    if ($old -match '^([A-Za-z]):' -and $Matches[1].ToUpperInvariant() -eq $Drive) { $res.Message = 'Файлы уже на диске ' + $Drive + ':'; return $res }
    try {
        $p = Get-CimInstance Win32_UserProfile -Filter ("SID='" + $Sid + "'") -ErrorAction Stop
        if ($p -and $p.Loaded) { $res.Message = 'Пользователь сейчас в системе - пусть выйдет из учётной записи (Пуск → значок пользователя → Выход)'; return $res }
    } catch {}
    $parent = $Drive + ':\Users'
    $dst = Get-UniquePath -Path (Join-Path $parent (Split-Path $old -Leaf))
    $res.New = $dst

    Set-JobProgress -1 'Считаем, сколько места нужно…'
    $need = Get-FolderBytes $old
    try {
        $ld = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $Drive + ":'") -ErrorAction Stop
        if (([double]$ld.FreeSpace - $need) -lt 1GB) { $res.Message = 'На диске ' + $Drive + ': не хватит места: нужно ' + (Format-Size $need) + ', свободно ' + (Format-Size ([double]$ld.FreeSpace)); return $res }
    } catch {}

    # Копия ключа реестра - для отката из «Истории».
    $bk = Join-Path $BackupFolder ('profile-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    try {
        New-Item -ItemType Directory -Path $bk -Force -ErrorAction Stop | Out-Null
        $native = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\' + $Sid
        $r = Invoke-ProcessLive -FilePath (Join-Path $env:WINDIR 'System32\reg.exe') -Arguments ('export "' + $native + '" "' + (Join-Path $bk 'ProfileList.reg') + '" /y') -TimeoutSec 60 -Quiet
        if ($r.Code -ne 0) { throw 'reg export' }
        $res.Backup = $bk
    } catch { $res.Message = 'Не удалось сохранить копию реестра - перенос отменён'; return $res }

    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Write-Log ('Переносим ' + $old + ' → ' + $dst + ' (' + (Format-Size $need) + ')')
    Set-JobProgress -1 ('Копируем файлы на диск ' + $Drive + ':…')
    $rc = Join-Path $env:WINDIR 'System32\robocopy.exe'
    $rcArgs = '"' + $old + '" "' + $dst + '" /E /COPY:DATSO /DCOPY:DAT /B /XJD /SL /R:1 /W:1 /NP /NFL /NDL /NJH /MT:8 /XD "' + (Join-Path $old 'AppData\Local\Temp') + '"'
    $r = Invoke-ProcessLive -FilePath $rc -Arguments $rcArgs -TimeoutSec 21600 -Quiet
    if ($r.Cancelled -or $r.TimedOut -or $r.Code -lt 0 -or $r.Code -ge 8 -or -not (Test-Path -LiteralPath (Join-Path $dst 'NTUSER.DAT'))) {
        Write-Log ('robocopy: код ' + $r.Code) 'warn'
        foreach ($l in @(($r.Output -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Last 6)) { Write-Log ('   ' + $l.Trim()) 'warn' }
        [void](Remove-FolderSafe $dst)
        $res.Message = if ($r.Cancelled) { 'Перенос остановлен - всё осталось как было' } else { 'Не все файлы скопировались - перенос отменён, всё осталось как было' }
        return $res
    }
    Set-JobProgress -1 'Восстанавливаем ссылки и права…'
    [void](Copy-ProfileJunctions -Src $old -Dst $dst)
    Set-ProfileRootAcl -Path $dst -Sid $Sid
    New-Item -ItemType Directory -Path (Join-Path $dst 'AppData\Local\Temp') -Force -ErrorAction SilentlyContinue | Out-Null

    # Пока копировали, пользователь мог войти - тогда ничего не переключаем.
    try {
        $p = Get-CimInstance Win32_UserProfile -Filter ("SID='" + $Sid + "'") -ErrorAction Stop
        if ($p -and $p.Loaded) { [void](Remove-FolderSafe $dst); $res.Message = 'Пользователь вошёл, пока шло копирование - перенос отменён'; return $res }
    } catch {}
    try {
        Set-ItemProperty -LiteralPath $keyPath -Name 'ProfileImagePath' -Value $dst -Type ExpandString -ErrorAction Stop
    } catch { [void](Remove-FolderSafe $dst); $res.Message = 'Не удалось переключить профиль: ' + $_.Exception.Message; return $res }
    Add-ProfileMoveRecord -Sid $Sid -Old $old -New $dst
    $res.Ok = $true
    $res.Message = 'Файлы перенесены: ' + $dst
    Write-Log ('Профиль перенесён: ' + $dst + '. Старая папка ' + $old + ' пока осталась') 'ok'
    Add-History -Kind 'users' -Name ('Файлы пользователя перенесены на ' + $Drive + ': (' + (Split-Path $old -Leaf) + ')') -Detail ($old + ' → ' + $dst) -Ref $bk
    return $res
}

# ---------- Перенос при перезагрузке (для того, кто сейчас в системе) ----------

function Get-ProfileMoveFolder { $pd = if ($env:ProgramData) { $env:ProgramData } else { $env:TEMP }; return (Join-Path $pd 'PotatoPC\profile-move') }

function Register-ProfileMoveAtBoot {
    # Задача планировщика от SYSTEM при старте Windows: переносит профиль до входа
    # пользователя и удаляет себя. Скрипт самодостаточный - папка программы к
    # перезагрузке может исчезнуть (запуск по ссылке работает из TEMP).
    param([Parameter(Mandatory)][string]$Sid, [Parameter(Mandatory)][string]$Drive)
    $dir = Get-ProfileMoveFolder
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $rid = ($Sid -split '-')[-1]
    $task = 'ProfileMove-' + $rid
    $file = Join-Path $dir ('move-' + $Sid + '.ps1')
    [System.IO.File]::WriteAllText($file, (New-ProfileMoveBootScript -Sid $Sid -Drive $Drive -Dir $dir), (New-Object System.Text.UTF8Encoding($true)))
    $ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $act = New-ScheduledTaskAction -Execute $ps -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $file + '"')
    $trg = New-ScheduledTaskTrigger -AtStartup
    $pri = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 6) -StartWhenAvailable
    Register-ScheduledTask -TaskName $task -TaskPath '\PotatoPC\' -Action $act -Trigger $trg -Principal $pri -Settings $set -Force -ErrorAction Stop | Out-Null
    Write-Log ('Перенос файлов запланирован на следующую перезагрузку (диск ' + $Drive + ':)') 'ok'
    Add-History -Kind 'users' -Name ('Перенос файлов на ' + $Drive + ': запланирован на перезагрузку')
    return $true
}

function New-ProfileMoveBootScript {
    # Текст скрипта для задачи при загрузке: нужные функции целиком + вызов.
    param([string]$Sid, [string]$Drive, [string]$Dir)
    $rid = ($Sid -split '-')[-1]
    $task = 'ProfileMove-' + $rid
    $resFile = Join-Path $Dir ('result-' + $Sid + '.json')
    $dir = $Dir
    $fns = @('Write-Log', 'Set-JobProgress', 'Test-JobCancel', 'Add-History', 'Format-Size', 'Stop-ProcessTree', 'Invoke-ProcessLive',
             'Get-ProfileStatePath', 'Get-ProfileState', 'Save-ProfileState', 'Add-ProfileMoveRecord', 'Get-UniquePath',
             'Get-FolderBytes', 'Copy-ProfileJunctions', 'Set-ProfileRootAcl', 'Remove-FolderSafe', 'Move-UserProfile')
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# PotatoPC: перенос профиля при загрузке Windows. Удаляется сам после запуска.')
    [void]$sb.AppendLine('$ErrorActionPreference = ''Continue''')
    $q = { param($s) "'" + ([string]$s).Replace("'", "''") + "'" }
    [void]$sb.AppendLine('$LogPath = ' + (& $q (Join-Path $dir ('move-' + $rid + '.log'))))
    [void]$sb.AppendLine('$HistoryPath = ' + (& $q $HistoryPath))
    [void]$sb.AppendLine('$BackupFolder = ' + (& $q $BackupFolder))
    [void]$sb.AppendLine('$UiQueue = $null; $Job = $null')
    foreach ($f in $fns) { [void]$sb.AppendLine('function ' + $f + ' {' + (Get-Item ('function:' + $f)).Definition + '}') }
    [void]$sb.AppendLine('Start-Sleep -Seconds 5')
    [void]$sb.AppendLine('$r = Move-UserProfile -Sid ' + (& $q $Sid) + ' -Drive ' + (& $q $Drive))
    [void]$sb.AppendLine('$r.Time = (Get-Date).ToString(''s''); $r.Sid = ' + (& $q $Sid))
    [void]$sb.AppendLine('[System.IO.File]::WriteAllText(' + (& $q $resFile) + ', ($r | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($true)))')
    [void]$sb.AppendLine('try { Unregister-ScheduledTask -TaskName ' + (& $q $task) + ' -TaskPath ''\PotatoPC\'' -Confirm:$false -ErrorAction Stop } catch {}')
    [void]$sb.AppendLine('Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue')
    return $sb.ToString()
}

function Get-PendingProfileMoves {
    # SID, для которых перенос ждёт перезагрузки.
    $out = @{}
    $dir = Get-ProfileMoveFolder
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter 'move-S-*.ps1' -File -ErrorAction SilentlyContinue)) {
        $out[$f.BaseName.Substring(5)] = $f.FullName
    }
    return $out
}

function Unregister-ProfileMoveAtBoot {
    param([string]$Sid)
    $rid = ($Sid -split '-')[-1]
    try { Unregister-ScheduledTask -TaskName ('ProfileMove-' + $rid) -TaskPath '\PotatoPC\' -Confirm:$false -ErrorAction Stop } catch {}
    Remove-Item -LiteralPath (Join-Path (Get-ProfileMoveFolder) ('move-' + $Sid + '.ps1')) -Force -ErrorAction SilentlyContinue
    Write-Log 'Перенос при перезагрузке отменён' 'ok'
}

function Read-ProfileMoveResults {
    # Итоги переносов, сделанных при загрузке, - один раз, потом файл удаляется.
    $out = @()
    foreach ($f in @(Get-ChildItem -LiteralPath (Get-ProfileMoveFolder) -Filter 'result-*.json' -File -ErrorAction SilentlyContinue)) {
        try { $out += (Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json) } catch {}
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
    }
    return $out
}

function Remove-OldProfileCopy {
    # Фон. Удаляет старую копию профиля после переноса. Отказывается удалять то,
    # что сейчас является чьим-то профилем, корень диска и всё вне папки Users.
    param([Parameter(Mandatory)][string]$Path)
    $p = $Path.TrimEnd('\')
    $map = Get-ProfileListMap
    foreach ($v in $map.Values) { if ($v.TrimEnd('\') -ieq $p) { Write-Log ('Это действующий профиль - не удаляем: ' + $p) 'err'; return $false } }
    if ($p -notmatch '^[A-Za-z]:\\Users\\[^\\]+$') { Write-Log ('Не похоже на папку профиля - не удаляем: ' + $p) 'err'; return $false }
    Write-Log ('Удаляем старую копию: ' + $p)
    $ok = Remove-FolderSafe $p
    if ($ok) {
        Write-Log 'Старая копия удалена' 'ok'
        $s = Get-ProfileState
        $s.Moves = @($s.Moves | Where-Object { [string]$_.Old -ine $p })
        Save-ProfileState $s
        Add-History -Kind 'users' -Name ('Удалена старая копия файлов: ' + $p)
    } else { Write-Log ('Удалось удалить не всё: ' + $p) 'warn' }
    return $ok
}

# ---------- После переустановки: старые профили ----------

function Find-OldProfiles {
    # Папки профилей на других дисках, которые не принадлежат ни одной учётке этой Windows.
    $known = @{}
    foreach ($v in (Get-ProfileListMap).Values) { $known[$v.TrimEnd('\').ToLowerInvariant()] = $true }
    $dismissed = @{}
    foreach ($d in (Get-ProfileState).Dismissed) { $dismissed[$d.ToLowerInvariant()] = $true }
    $skip = @('default', 'default user', 'public', 'all users', 'defaultapppool')
    $sys = ($env:SystemDrive).TrimEnd(':').ToUpperInvariant()
    $out = @()
    foreach ($ld in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue)) {
        $L = ([string]$ld.DeviceID).TrimEnd(':').ToUpperInvariant()
        if ($L -eq $sys) { continue }
        $u = $L + ':\Users'
        foreach ($d in @(Get-ChildItem -LiteralPath $u -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($skip -contains $d.Name.ToLowerInvariant()) { continue }
            if (($d.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            $key = $d.FullName.TrimEnd('\').ToLowerInvariant()
            if ($known[$key] -or $dismissed[$key]) { continue }
            $nt = Join-Path $d.FullName 'NTUSER.DAT'
            if (-not (Test-Path -LiteralPath $nt)) { continue }
            $lw = $d.LastWriteTime
            try { $lw = (Get-Item -LiteralPath $nt -Force).LastWriteTime } catch {}
            $out += @{ Name = ($d.Name -replace '\.\d+$', ''); Folder = $d.Name; Path = $d.FullName; Letter = $L; LastWrite = $lw }
        }
    }
    return $out
}

function Hide-OldProfile {
    param([string]$Path)
    $s = Get-ProfileState
    $s.Dismissed = @(@($s.Dismissed) + $Path.TrimEnd('\') | Select-Object -Unique)
    Save-ProfileState $s
}

function Get-ProfileFolderDefs { return @(
    @{ Id = 'Desktop'; Title = 'Рабочий стол'; Rel = 'Desktop' }
    @{ Id = 'Documents'; Title = 'Документы'; Rel = 'Documents' }
    @{ Id = 'Downloads'; Title = 'Загрузки'; Rel = 'Downloads' }
    @{ Id = 'Pictures'; Title = 'Фото'; Rel = 'Pictures' }
    @{ Id = 'Videos'; Title = 'Видео'; Rel = 'Videos' }
    @{ Id = 'Music'; Title = 'Музыка'; Rel = 'Music' }
    @{ Id = 'SavedGames'; Title = 'Сохранения игр'; Rel = 'Saved Games' }
    @{ Id = 'Favorites'; Title = 'Избранное'; Rel = 'Favorites' }
) }

# Браузеры. Chromium шифрует пароли и cookie ключом DPAPI старой Windows -
# их не вернуть. Firefox хранит ключ в своём профиле - у него возвращается всё.
function Get-ProfileBrowserDefs { return @(
    @{ Id = 'chrome'; Title = 'Google Chrome'; Rel = 'AppData\Local\Google\Chrome'; Data = 'User Data'; Kind = 'chromium'; Proc = 'chrome' }
    @{ Id = 'edge'; Title = 'Microsoft Edge'; Rel = 'AppData\Local\Microsoft\Edge'; Data = 'User Data'; Kind = 'chromium'; Proc = 'msedge' }
    @{ Id = 'yandex'; Title = 'Яндекс Браузер'; Rel = 'AppData\Local\Yandex\YandexBrowser'; Data = 'User Data'; Kind = 'chromium'; Proc = 'browser' }
    @{ Id = 'brave'; Title = 'Brave'; Rel = 'AppData\Local\BraveSoftware\Brave-Browser'; Data = 'User Data'; Kind = 'chromium'; Proc = 'brave' }
    @{ Id = 'vivaldi'; Title = 'Vivaldi'; Rel = 'AppData\Local\Vivaldi'; Data = 'User Data'; Kind = 'chromium'; Proc = 'vivaldi' }
    @{ Id = 'opera'; Title = 'Opera'; Rel = 'AppData\Roaming\Opera Software\Opera Stable'; Data = ''; Kind = 'chromium'; Proc = 'opera' }
    @{ Id = 'operagx'; Title = 'Opera GX'; Rel = 'AppData\Roaming\Opera Software\Opera GX Stable'; Data = ''; Kind = 'chromium'; Proc = 'opera' }
    @{ Id = 'firefox'; Title = 'Mozilla Firefox'; Rel = 'AppData\Roaming\Mozilla\Firefox'; Data = ''; Kind = 'firefox'; Proc = 'firefox' }
) }
function Get-BrowserCacheNames { return @('Cache', 'Code Cache', 'GPUCache', 'DawnCache', 'DawnGraphiteCache', 'DawnWebGPUCache', 'GrShaderCache', 'GraphiteDawnCache', 'ShaderCache', 'CacheStorage', 'ScriptCache', 'component_crx_cache', 'extensions_crx_cache', 'cache2', 'startupCache') }

# Папки AppData, которые не переносим: система, временные файлы, папки браузеров (они отдельно).
function Get-AppDataSkip { return @('Microsoft', 'Packages', 'Temp', 'ConnectedDevicesPlatform', 'D3DSCache', 'CrashDumps', 'PlaceholderTileLogoFolder', 'Comms',
    'Publishers', 'VirtualStore', 'ElevatedDiagnostics', 'PeerDistRepub', 'Programs', 'Google', 'Yandex', 'BraveSoftware', 'Vivaldi', 'Mozilla',
    'Opera Software', 'NVIDIA', 'NVIDIA Corporation', 'AMD', 'Intel', 'IsolatedStorage', 'SquirrelTemp', 'pip', 'npm-cache') }
function Get-AppNotes { return @{
    'telegram desktop' = @('ok', 'Входить заново не придётся')
    'discord'          = @('warn', 'Придётся войти заново')
    'viber'            = @('warn', 'Придётся войти заново')
    'whatsapp'         = @('warn', 'Придётся войти заново')
} }

function Read-JsonFast {
    # ConvertFrom-Json в PowerShell 5.1 медленный на больших файлах (закладки бывают по 100 МБ).
    param([string]$Path)
    try {
        Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
        $js = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $js.MaxJsonLength = [int]::MaxValue
        $js.RecursionLimit = 1000
        return $js.DeserializeObject([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8))
    } catch { return $null }
}

function Get-BookmarkCount {
    param($Node)
    if ($null -eq $Node) { return 0 }
    $n = 0
    $stack = New-Object System.Collections.Stack
    $stack.Push($Node)
    while ($stack.Count -gt 0) {
        $x = $stack.Pop()
        if ($x -is [System.Collections.IDictionary]) {
            if ([string]$x['type'] -eq 'url') { $n++ }
            if ($x.ContainsKey('children')) { foreach ($c in @($x['children'])) { $stack.Push($c) } }
            if ($x.ContainsKey('roots')) { foreach ($k in @($x['roots'].Keys)) { $stack.Push($x['roots'][$k]) } }
        }
    }
    return $n
}

function ConvertTo-BookmarksHtml {
    # Чистая функция: дерево закладок Chromium -> файл закладок Netscape,
    # который умеет импортировать любой браузер.
    param($Data, [string]$Title = 'Закладки')
    $enc = { param($s) [System.Net.WebUtility]::HtmlEncode([string]$s) }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!DOCTYPE NETSCAPE-Bookmark-file-1>')
    [void]$sb.AppendLine('<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">')
    [void]$sb.AppendLine('<TITLE>' + (& $enc $Title) + '</TITLE>')
    [void]$sb.AppendLine('<H1>' + (& $enc $Title) + '</H1>')
    [void]$sb.AppendLine('<DL><p>')
    $names = @{ bookmark_bar = 'Панель закладок'; other = 'Другие закладки'; synced = 'Мобильные закладки' }
    $toUnix = {
        param($v)
        try { $d = [double]$v; if ($d -gt 0) { return [string][long](($d / 1000000) - 11644473600) } } catch {}
        return '0'
    }
    $walk = $null
    $walk = {
        param($node, [int]$depth)
        $pad = '    ' * $depth
        foreach ($c in @($node['children'])) {
            if ($c -isnot [System.Collections.IDictionary]) { continue }
            if ([string]$c['type'] -eq 'url') {
                [void]$sb.AppendLine($pad + '<DT><A HREF="' + (& $enc $c['url']) + '" ADD_DATE="' + (& $toUnix $c['date_added']) + '">' + (& $enc $c['name']) + '</A>')
            } else {
                [void]$sb.AppendLine($pad + '<DT><H3 ADD_DATE="' + (& $toUnix $c['date_added']) + '">' + (& $enc $c['name']) + '</H3>')
                [void]$sb.AppendLine($pad + '<DL><p>')
                & $walk $c ($depth + 1)
                [void]$sb.AppendLine($pad + '</DL><p>')
            }
        }
    }
    $roots = $Data['roots']
    if ($roots -is [System.Collections.IDictionary]) {
        foreach ($k in @('bookmark_bar', 'other', 'synced')) {
            $r = $roots[$k]
            if ($r -isnot [System.Collections.IDictionary] -or @($r['children']).Count -eq 0) { continue }
            $nm = if ($names[$k]) { $names[$k] } else { [string]$r['name'] }
            [void]$sb.AppendLine('    <DT><H3>' + (& $enc $nm) + '</H3>')
            [void]$sb.AppendLine('    <DL><p>')
            & $walk $r 2
            [void]$sb.AppendLine('    </DL><p>')
        }
    }
    [void]$sb.AppendLine('</DL><p>')
    return $sb.ToString()
}

function Get-ChromiumProfiles {
    # Профили браузера на базе Chromium: папка, имя, файл закладок, число закладок.
    param([string]$UserData)
    $out = @()
    if (-not (Test-Path -LiteralPath $UserData)) { return $out }
    $names = @{}
    $ls = Join-Path $UserData 'Local State'
    if (Test-Path -LiteralPath $ls) {
        $j = Read-JsonFast $ls
        try { $ic = $j['profile']['info_cache']; foreach ($k in @($ic.Keys)) { $names[$k] = [string]$ic[$k]['name'] } } catch {}
    }
    $dirs = @()
    if (Test-Path -LiteralPath (Join-Path $UserData 'Preferences')) { $dirs += Get-Item -LiteralPath $UserData }
    $dirs += @(Get-ChildItem -LiteralPath $UserData -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'Preferences') })
    foreach ($d in $dirs) {
        $bm = Join-Path $d.FullName 'Bookmarks'
        $count = 0
        if (Test-Path -LiteralPath $bm) { $count = Get-BookmarkCount (Read-JsonFast $bm) }
        $nm = if ($names[$d.Name]) { $names[$d.Name] } elseif ($d.Name -eq 'Default') { 'Основной' } else { $d.Name }
        $out += @{ Dir = $d.FullName; Name = $nm; Bookmarks = $bm; Count = $count }
    }
    return $out
}

function Get-OldProfileItems {
    <#
      Фон. Что можно вернуть из старого профиля: папки, браузеры, данные программ.
      Каждый элемент: @{ Id; Kind (folder|browser|app); Title; Rels; Bytes; CacheBytes;
      Note; NoteKind; Details; Strategy (merge|replace); Proc; Profiles }.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $items = @()
    foreach ($f in (Get-ProfileFolderDefs)) {
        $p = Join-Path $Path $f.Rel
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $b = Get-FolderBytes $p
        if ($b -le 4KB) { continue }
        $items += @{ Id = $f.Id; Kind = 'folder'; Title = $f.Title; Rels = @($f.Rel); Bytes = $b; CacheBytes = 0.0; Note = ''; NoteKind = 'muted'; Details = ''; Strategy = 'merge'; Proc = ''; Profiles = @() }
    }
    foreach ($br in (Get-ProfileBrowserDefs)) {
        $root = Join-Path $Path $br.Rel
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $it = @{ Id = $br.Id; Kind = 'browser'; Title = $br.Title; Rels = @($br.Rel); Bytes = (Get-FolderBytes $root); CacheBytes = 0.0; Note = ''; NoteKind = 'warn'; Details = ''; Strategy = 'replace'; Proc = $br.Proc; Profiles = @() }
        if ($br.Kind -eq 'chromium') {
            $ud = if ($br.Data) { Join-Path $root $br.Data } else { $root }
            $profs = @(Get-ChromiumProfiles $ud)
            $it.Profiles = $profs
            foreach ($pr in $profs) { foreach ($c in (Get-BrowserCacheNames)) { $cp = Join-Path $pr.Dir $c; if (Test-Path -LiteralPath $cp) { $it.CacheBytes += Get-FolderBytes $cp } } }
            $total = 0; foreach ($pr in $profs) { $total += [int]$pr.Count }
            $parts = @()
            if ($profs.Count -gt 1) { $parts += ('профили: ' + (($profs | ForEach-Object { $_.Name }) -join ', ')) }
            $parts += ('закладки: ' + ('{0:N0}' -f $total))
            $parts += 'история, вкладки и расширения вернутся'
            $it.Details = ($parts -join ' · ')
            $it.Note = 'Пароли и входы на сайты не вернутся - Windows шифрует их для старой системы'
        } else {
            $it.Details = 'закладки, история, расширения и пароли'
            $it.Note = 'Вернётся всё, включая пароли'
            $it.NoteKind = 'ok'
        }
        $items += $it
    }
    # Остальные программы: папки верхнего уровня в AppData\Roaming и AppData\Local, одноимённые - вместе.
    $apps = [ordered]@{}
    $skipApp = Get-AppDataSkip
    $notes = Get-AppNotes
    foreach ($base in @('AppData\Roaming', 'AppData\Local')) {
        $bp = Join-Path $Path $base
        foreach ($d in @(Get-ChildItem -LiteralPath $bp -Directory -Force -ErrorAction SilentlyContinue)) {
            if (($d.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            if ($skipApp -contains $d.Name) { continue }
            $k = $d.Name.ToLowerInvariant()
            if (-not $apps.Contains($k)) { $apps[$k] = @{ Title = $d.Name; Rels = @() } }
            $apps[$k].Rels += (Join-Path $base $d.Name)
        }
    }
    foreach ($k in $apps.Keys) {
        $a = $apps[$k]
        $b = 0.0
        foreach ($r in $a.Rels) { $b += Get-FolderBytes (Join-Path $Path $r) }
        if ($b -lt 64KB) { continue }
        $n = $notes[$k]
        $items += @{ Id = 'app:' + $k; Kind = 'app'; Title = $a.Title; Rels = @($a.Rels); Bytes = $b; CacheBytes = 0.0; Note = $(if ($n) { $n[1] } else { '' }); NoteKind = $(if ($n) { $n[0] } else { 'muted' }); Details = ''; Strategy = 'replace'; Proc = ''; Profiles = @() }
    }
    return $items
}

function Move-MergeDirectory {
    # Перемещение с переименованием: на одном диске - мгновенно, сколько бы ни было файлов.
    # Если папка уже есть - сливаем; совпавшие файлы получают пометку «(со старой Windows)».
    param([string]$Src, [string]$Dst, [string[]]$ExcludeNames = @())
    if (-not (Test-Path -LiteralPath $Dst) -and $ExcludeNames.Count -eq 0) {
        $parent = Split-Path $Dst -Parent
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [System.IO.Directory]::Move($Src, $Dst)
        return
    }
    if (-not (Test-Path -LiteralPath $Dst)) { New-Item -ItemType Directory -Path $Dst -Force | Out-Null }
    foreach ($e in @((New-Object System.IO.DirectoryInfo $Src).EnumerateFileSystemInfos())) {
        $t = Join-Path $Dst $e.Name
        if ($e -is [System.IO.DirectoryInfo]) {
            if ($ExcludeNames -contains $e.Name) { continue }
            if (($e.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            try { Move-MergeDirectory -Src $e.FullName -Dst $t -ExcludeNames $ExcludeNames } catch { Write-Log ('Не перенесено: ' + $e.FullName + ' - ' + $_.Exception.Message) 'warn' }
        } else {
            try {
                if (Test-Path -LiteralPath $t) { $t = Get-UniquePath -Path $t -Suffix '(со старой Windows)' }
                [System.IO.File]::Move($e.FullName, $t)
            } catch { Write-Log ('Не перенесено: ' + $e.FullName + ' - ' + $_.Exception.Message) 'warn' }
        }
    }
}

function Restore-OldProfileItems {
    <#
      Фон. Возвращает выбранное из старого профиля $Source пользователю $TargetSid.
      Mode: move | copy. Папки (Документы...) сливаются с текущими, данные программ
      заменяют текущие (текущие сохраняются рядом как «.new-дата»). После - права
      на всё перенесённое выдаются новой учётной записи.
    #>
    param(
        [Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$TargetSid, [string]$TargetName = '',
        [object[]]$Items = @(), [string]$Mode = 'move', [bool]$SkipCache = $true, [bool]$ExportBookmarks = $true
    )
    $res = @{ Ok = $false; Message = ''; Done = 0; Failed = 0; Target = '' }
    $map = Get-ProfileListMap
    $target = $map[$TargetSid]
    if (-not $target -or -not (Test-Path -LiteralPath $target)) {
        Set-JobProgress -1 'Создаём папку профиля…'
        try { $target = New-UserProfileNow -Sid $TargetSid -Name $TargetName } catch { $res.Message = $_.Exception.Message; return $res }
        # Новый профиль сразу кладём на диск со старыми файлами - так перенос мгновенный.
        $srcL = $Source.Substring(0, 1).ToUpperInvariant()
        if ($target -notmatch ('^' + $srcL + ':')) {
            $m = Move-UserProfile -Sid $TargetSid -Drive $srcL
            if ($m.Ok) { $target = $m.New }
        }
    }
    $target = $target.TrimEnd('\')
    $res.Target = $target
    $same = ([System.IO.Path]::GetPathRoot($Source)).ToUpperInvariant() -eq ([System.IO.Path]::GetPathRoot($target)).ToUpperInvariant()
    $rc = Join-Path $env:WINDIR 'System32\robocopy.exe'
    $ic = Join-Path $env:WINDIR 'System32\icacls.exe'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
    $touched = @()
    $i = 0
    # Закладки - отдельным файлом, пока они ещё на старом месте.
    $bmFolder = Join-Path $target 'Documents\Закладки со старой Windows'
    if ($ExportBookmarks) {
        foreach ($it in @($Items | Where-Object { $_.Kind -eq 'browser' })) {
            foreach ($pr in @($it.Profiles)) {
                if (-not $pr.Bookmarks -or -not (Test-Path -LiteralPath $pr.Bookmarks) -or [int]$pr.Count -eq 0) { continue }
                try {
                    if (-not (Test-Path -LiteralPath $bmFolder)) { New-Item -ItemType Directory -Path $bmFolder -Force | Out-Null }
                    $name = ($it.Title + ' - ' + $pr.Name) -replace '[\\/:*?"<>|]', '_'
                    $html = ConvertTo-BookmarksHtml -Data (Read-JsonFast $pr.Bookmarks) -Title ($it.Title + ' - ' + $pr.Name)
                    [System.IO.File]::WriteAllText((Join-Path $bmFolder ($name + '.html')), $html, (New-Object System.Text.UTF8Encoding($true)))
                } catch { Write-Log ('Закладки не сохранены: ' + $it.Title + ' - ' + $_.Exception.Message) 'warn' }
            }
        }
        if (Test-Path -LiteralPath $bmFolder) { $touched += $bmFolder; Write-Log ('Закладки сохранены файлами: ' + $bmFolder) 'ok' }
    }
    foreach ($it in $Items) {
        $i++
        if (Test-JobCancel) { break }
        Set-JobProgress ($i / [Math]::Max(1, $Items.Count)) ('Возвращаем: ' + $it.Title)
        $ex = @(if ($it.Kind -eq 'browser' -and $SkipCache) { Get-BrowserCacheNames })
        foreach ($rel in @($it.Rels)) {
            $src = Join-Path $Source $rel
            $dst = Join-Path $target $rel
            if (-not (Test-Path -LiteralPath $src)) { continue }
            try {
                if ($it.Strategy -eq 'replace' -and (Test-Path -LiteralPath $dst)) {
                    $keep = Get-UniquePath -Path ($dst + '.new-' + $stamp)
                    [System.IO.Directory]::Move($dst, $keep)
                    Write-Log ('Текущие данные «' + $it.Title + '» сохранены рядом: ' + (Split-Path $keep -Leaf))
                }
                if ($Mode -eq 'move' -and $same) {
                    Move-MergeDirectory -Src $src -Dst $dst -ExcludeNames $ex
                } else {
                    $a = '"' + $src + '" "' + $dst + '" /E /COPY:DAT /DCOPY:DAT /XJD /R:1 /W:1 /NP /NFL /NDL /NJH /MT:8'
                    if ($ex.Count) { $a += ' /XD ' + (($ex | ForEach-Object { '"' + $_ + '"' }) -join ' ') }
                    if ($it.Strategy -eq 'merge') { $a += ' /XC /XN /XO' }
                    if ($Mode -eq 'move') { $a += ' /MOVE' }
                    $r = Invoke-ProcessLive -FilePath $rc -Arguments $a -TimeoutSec 21600 -Quiet
                    if ($r.Code -lt 0 -or $r.Code -ge 8) { throw ('robocopy, код ' + $r.Code) }
                }
                $touched += $dst
                $res.Done++
                Write-Log ('Возвращено: ' + $it.Title) 'ok'
            } catch { $res.Failed++; Write-Log ('Не получилось вернуть «' + $it.Title + '»: ' + $_.Exception.Message) 'warn' }
        }
    }
    # Права: перенесённое наследует права нового профиля, владелец - новая учётка.
    Set-JobProgress -1 'Выдаём права новой учётной записи…'
    foreach ($t in ($touched | Select-Object -Unique)) {
        [void](Invoke-ProcessLive -FilePath $ic -Arguments ('"' + $t + '" /reset /T /C /Q') -TimeoutSec 7200 -Quiet)
        [void](Invoke-ProcessLive -FilePath $ic -Arguments ('"' + $t + '" /setowner *' + $TargetSid + ' /T /C /Q') -TimeoutSec 7200 -Quiet)
    }
    Hide-OldProfile -Path $Source
    $res.Ok = ($res.Done -gt 0 -and $res.Failed -eq 0)
    $res.Message = 'Возвращено: ' + $res.Done + $(if ($res.Failed) { ', не получилось: ' + $res.Failed } else { '' })
    Add-History -Kind 'users' -Name ('Возвращены файлы со старой Windows: ' + (Split-Path $Source -Leaf) + ' → ' + $(if ($TargetName) { $TargetName } else { $TargetSid })) -Result $(if ($res.Failed) { 'fail' } else { 'ok' }) -Detail $res.Message
    return $res
}
