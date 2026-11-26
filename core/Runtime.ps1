# PotatoPC v7 - журнал, фоновые задачи, история действий.
#
# Модель потоков:
#   * окно живёт в UI-потоке; всё долгое (CIM, сканы, скрипты, winget) уходит
#     в фоновый ранспейс через Start-BgTask;
#   * фон пишет в журнал через общую очередь $UiQueue; таймер UI-потока раз в
#     150 мс выгребает очередь в окно журнала и проверяет завершённые задачи;
#   * результат задачи (последний объект, который вернул скрипт) передаётся в
#     -OnDone, который выполняется уже в UI-потоке и может трогать контролы.

$script:UiQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
$script:BgJobs  = New-Object System.Collections.ArrayList
$script:BgIss   = $null

function Write-Log {
    # Level: info | ok | warn | err | head
    param([Parameter(Position = 0)][string]$Text, [Parameter(Position = 1)][string]$Level = 'info')
    $stamp = (Get-Date).ToString('HH:mm:ss')
    $mark = switch ($Level) { 'ok' { '[OK]' } 'warn' { '[!]' } 'err' { '[X]' } 'head' { '==' } default { '   ' } }
    $line = "$stamp $mark $Text"
    try { $UiQueue.Enqueue(@{ Text = $line; Level = $Level; Raw = $Text }) } catch {}
    try {
        if ($LogPath) { [System.IO.File]::AppendAllText($LogPath, $line + "`r`n", [System.Text.Encoding]::UTF8) }
    } catch {
        try { Start-Sleep -Milliseconds 20; [System.IO.File]::AppendAllText($LogPath, $line + "`r`n", [System.Text.Encoding]::UTF8) } catch {}
    }
}

function Set-JobProgress {
    # Вызывается из фона: прогресс 0..1 (или -1 = неопределённый) и подпись.
    param([double]$Value = -1, [string]$Status = '')
    try { if ($Job) { $Job.Progress = $Value; if ($Status) { $Job.Status = $Status } } } catch {}
}

function Test-JobCancel {
    try { if ($Job -and $Job.Cancel) { return $true } } catch {}
    return $false
}

function Add-History {
    # Журнал действий для страницы «История», отчёта мастера и статуса «Применено».
    param([string]$Kind, [string]$Name, [string]$Result = 'ok', [string]$Detail = '', [string]$Ref = '')
    try {
        $rec = [ordered]@{
            Time = (Get-Date).ToString('s'); Kind = $Kind; Name = $Name
            Result = $Result; Detail = $Detail; Ref = $Ref; Pc = $env:COMPUTERNAME
        }
        $json = ($rec | ConvertTo-Json -Compress)
        [System.IO.File]::AppendAllText($HistoryPath, $json + "`n", [System.Text.Encoding]::UTF8)
    } catch {}
}

function Get-History {
    param([int]$Last = 500, [int]$Days = 0)
    $out = @()
    try {
        if (-not (Test-Path -LiteralPath $HistoryPath)) { return @() }
        $lines = [System.IO.File]::ReadAllLines($HistoryPath, [System.Text.Encoding]::UTF8)
        $start = [Math]::Max(0, $lines.Count - $Last)
        $cut = if ($Days -gt 0) { (Get-Date).AddDays(-$Days) } else { [DateTime]::MinValue }
        for ($i = $lines.Count - 1; $i -ge $start; $i--) {
            if ([string]::IsNullOrWhiteSpace($lines[$i])) { continue }
            try {
                $o = $lines[$i] | ConvertFrom-Json -ErrorAction Stop
                if ($Days -gt 0) { try { if ([datetime]$o.Time -lt $cut) { continue } } catch {} }
                $out += $o
            } catch {}
        }
    } catch {}
    return $out
}

function Get-AppFunctionNames {
    # Все функции, загруженные из файлов приложения (core/, pages/).
    $root = [string]$AppRoot
    return @(Get-ChildItem function: | Where-Object {
        try { $_.ScriptBlock.File -and $_.ScriptBlock.File.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase) } catch { $false }
    })
}

function Get-BgInitialState {
    if ($script:BgIss) { return $script:BgIss }
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    try { $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass } catch {}
    foreach ($f in (Get-AppFunctionNames)) {
        $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $f.Name, $f.Definition))
    }
    $script:BgIss = $iss
    return $iss
}

function Start-BgTask {
    <#
      Запускает $Script в фоновом ранспейсе.
      -Vars    : переменные для скрипта (имя -> значение)
      -OnDone  : scriptblock { param($Result, $Err, $Job) } в UI-потоке
      -Context : любой объект, вернётся в $Job.Context
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Script,
        [hashtable]$Vars = @{},
        [scriptblock]$OnDone = $null,
        $Context = $null,
        [switch]$Silent
    )
    $job = [hashtable]::Synchronized(@{ Name = $Name; Cancel = $false; Progress = -1.0; Status = ''; Context = $Context; Started = Get-Date; Silent = [bool]$Silent; ChildPid = 0 })
    try {
        $rs = [runspacefactory]::CreateRunspace((Get-BgInitialState))
        $rs.ApartmentState = 'STA'
        $rs.ThreadOptions = 'ReuseThread'
        $rs.Open()
        foreach ($n in $script:ConfigVarNames) {
            $v = Get-Variable -Name $n -Scope Script -ErrorAction SilentlyContinue
            if ($v) { $rs.SessionStateProxy.SetVariable($n, $v.Value) }
        }
        $rs.SessionStateProxy.SetVariable('UiQueue', $script:UiQueue)
        $rs.SessionStateProxy.SetVariable('Job', $job)
        $rs.SessionStateProxy.SetVariable('ErrorActionPreference', 'Continue')
        foreach ($k in $Vars.Keys) { $rs.SessionStateProxy.SetVariable($k, $Vars[$k]) }
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        # CleanGuard держит состояние в переменных скрипта - подключаем его заново в каждом потоке.
        $prefix = if ($CleanGuardPath -and (Test-Path -LiteralPath $CleanGuardPath)) { '. ''' + $CleanGuardPath.Replace("'", "''") + "'`n" } else { '' }
        [void]$ps.AddScript($prefix + $Script.ToString())
        $handle = $ps.BeginInvoke()
        [void]$script:BgJobs.Add(@{ PS = $ps; RS = $rs; Handle = $handle; OnDone = $OnDone; Job = $job })
        if (-not $Silent) { Update-BusyIndicator }
    } catch {
        Write-Log ("Не удалось запустить задачу «" + $Name + "»: " + $_.Exception.Message) 'err'
        if ($OnDone) { try { & $OnDone $null $_ $job } catch {} }
    }
    return $job
}

function Stop-BgTask {
    param($Job)
    if (-not $Job) { return }
    $Job.Cancel = $true
    try { if ('PotatoBench' -as [type]) { [PotatoBench]::Cancel = $true } } catch {}
    try { if ('PotatoNet' -as [type]) { [PotatoNet]::Cancel = $true } } catch {}
    try { if ('PotatoDisk' -as [type]) { [PotatoDisk]::Cancel = $true } } catch {}
    try { if ($Job.ChildPid -gt 0) { Stop-ProcessTree -TargetPid $Job.ChildPid } } catch {}
}

function Get-RunningTasks {
    return @($script:BgJobs | ForEach-Object { $_.Job } | Where-Object { -not $_.Silent })
}

function Invoke-BgPoll {
    # UI-поток: журнал + завершённые задачи.
    $n = 0
    $item = $null
    while ($n -lt 400 -and $script:UiQueue.TryDequeue([ref]$item)) {
        $n++
        try { Add-LogLine $item } catch {}
    }
    if ($script:BgJobs.Count -eq 0) { return }
    $done = @($script:BgJobs | Where-Object { $_.Handle.IsCompleted })
    foreach ($j in $done) {
        $script:BgJobs.Remove($j)
        $result = $null; $err = $null
        try {
            $out = $j.PS.EndInvoke($j.Handle)
            if ($out -and $out.Count -gt 0) { $result = $out[$out.Count - 1] }
            if ($j.PS.Streams.Error.Count -gt 0 -and $null -eq $result) { $err = $j.PS.Streams.Error[0] }
            foreach ($e in @($j.PS.Streams.Error | Select-Object -First 3)) {
                Write-Log ("[" + $j.Job.Name + "] " + $e.ToString()) 'warn'
            }
        } catch { $err = $_ }
        try { $j.PS.Dispose() } catch {}
        try { $j.RS.Dispose() } catch {}
        if ($j.OnDone) {
            try { & $j.OnDone $result $err $j.Job }
            catch { Write-Log ("Ошибка после задачи «" + $j.Job.Name + "»: " + $_.Exception.Message) 'err' }
        }
    }
    Update-BusyIndicator
}

function Stop-ProcessTree {
    param([int]$TargetPid)
    if ($TargetPid -le 0) { return }
    try {
        $kids = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$TargetPid" -ErrorAction SilentlyContinue)
        foreach ($k in $kids) { Stop-ProcessTree -TargetPid ([int]$k.ProcessId) }
    } catch {}
    try { Stop-Process -Id $TargetPid -Force -ErrorAction SilentlyContinue } catch {}
}

function Invoke-ProcessLive {
    <#
      Запускает внешнюю программу, построчно передаёт её вывод в журнал.
      Encoding: utf8 | oem | unicode. Возвращает @{ Code; Output; TimedOut; Cancelled }.
    #>
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$Arguments = '',
        [int]$TimeoutSec = 600,
        [string]$Encoding = 'oem',
        [switch]$Quiet,
        [string]$Prefix = '   '
    )
    $res = @{ Code = -1; Output = ''; TimedOut = $false; Cancelled = $false }
    $enc = switch ($Encoding) {
        'utf8'    { New-Object System.Text.UTF8Encoding($false) }
        'unicode' { [System.Text.Encoding]::Unicode }
        default {
            # Консольные утилиты пишут в OEM-кодировке СИСТЕМЫ (язык для программ, не поддерживающих Юникод),
            # а она может не совпадать с региональным форматом пользователя (en-US -> 437 вместо 866).
            $cp = 0
            try { $cp = [int](Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' -Name OEMCP -ErrorAction Stop).OEMCP } catch {}
            if ($cp -le 0) { try { $cp = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage } catch {} }
            try { [System.Text.Encoding]::GetEncoding($cp) } catch { [System.Text.Encoding]::Default }
        }
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $enc
    $psi.StandardErrorEncoding = $enc
    $psi.CreateNoWindow = $true
    $sb = New-Object System.Text.StringBuilder
    $p = $null
    try {
        $p = [System.Diagnostics.Process]::Start($psi)
        try { if ($Job) { $Job.ChildPid = $p.Id } } catch {}
        $errTask = $p.StandardError.ReadToEndAsync()
        $deadline = (Get-Date).AddSeconds([Math]::Max(5, $TimeoutSec))
        $lineTask = $p.StandardOutput.ReadLineAsync()
        while ($true) {
            if ($lineTask.Wait(250)) {
                $line = $lineTask.Result
                if ($null -eq $line) { break }
                # sfc/DISM рисуют прогресс через \r - оставляем последнюю часть строки.
                $clean = ($line -split "`r")[-1].Replace([string][char]0, '').TrimEnd()
                if ($clean.Trim()) {
                    [void]$sb.AppendLine($clean)
                    if (-not $Quiet) { Write-Log ($Prefix + $clean.Trim()) }
                }
                $lineTask = $p.StandardOutput.ReadLineAsync()
                continue
            }
            if (Test-JobCancel) { $res.Cancelled = $true; Stop-ProcessTree -TargetPid $p.Id; break }
            if ((Get-Date) -gt $deadline) { $res.TimedOut = $true; Stop-ProcessTree -TargetPid $p.Id; break }
        }
        if (-not $res.TimedOut -and -not $res.Cancelled) { [void]$p.WaitForExit(15000) }
        try { if ($errTask.Wait(3000)) {
            $e = [string]$errTask.Result
            foreach ($l in ($e -split "`r?`n")) { if ($l.Trim()) { [void]$sb.AppendLine($l); if (-not $Quiet) { Write-Log ($Prefix + $l.Trim()) 'warn' } } }
        } } catch {}
        try { if ($p.HasExited) { $res.Code = $p.ExitCode } } catch {}
    } catch {
        [void]$sb.AppendLine($_.Exception.Message)
        if (-not $Quiet) { Write-Log ("Не удалось запустить " + $FilePath + ": " + $_.Exception.Message) 'err' }
    } finally {
        try { if ($Job) { $Job.ChildPid = 0 } } catch {}
        if ($p) { try { $p.Dispose() } catch {} }
    }
    $res.Output = $sb.ToString()
    return $res
}

function Format-Size {
    param([double]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N1} ТБ' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N1} ГБ' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} МБ' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} КБ' -f ($Bytes / 1KB)) }
    if ($Bytes -le 0) { return '0' }
    return ('{0:N0} Б' -f $Bytes)
}

function Format-Duration {
    param([double]$Seconds)
    if ($Seconds -lt 0) { return '—' }
    $t = [TimeSpan]::FromSeconds($Seconds)
    if ($t.TotalDays -ge 1) { return ('{0} д {1} ч' -f [int][Math]::Floor($t.TotalDays), $t.Hours) }
    if ($t.TotalHours -ge 1) { return ('{0} ч {1} мин' -f [int][Math]::Floor($t.TotalHours), $t.Minutes) }
    if ($t.TotalMinutes -ge 1) { return ('{0}:{1:D2}' -f [int][Math]::Floor($t.TotalMinutes), $t.Seconds) }
    return ('{0:N1} с' -f $Seconds)
}

function New-RestorePoint {
    # Фон. Точка восстановления перед изменениями. Windows по умолчанию даёт
    # одну точку в сутки - снимаем это ограничение для наших вызовов.
    param([string]$Description = 'PotatoPC')
    try {
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        try { Set-ItemProperty -LiteralPath $key -Name 'SystemRestorePointCreationFrequency' -Value 0 -Type DWord -Force -ErrorAction Stop } catch {}
        Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Log 'Точка восстановления создана' 'ok'
        Add-History -Kind 'restore' -Name ('Точка восстановления: ' + $Description)
        return $true
    } catch {
        $m = $_.Exception.Message
        if ($m -match '(?i)disabled|отключ|1058|0x80042306') {
            Write-Log 'Защита системы выключена - точку восстановления не создать. Включить её можно на странице «История».' 'warn'
        } else {
            Write-Log ('Точка восстановления не создана: ' + $m) 'warn'
        }
        return $false
    }
}
