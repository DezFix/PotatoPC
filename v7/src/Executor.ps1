function Get-PotatoLogPath {
    param([string]$SessionId)
    $base = if (Test-PotatoAdmin -and $env:ProgramData) {
        Join-Path $env:ProgramData 'PotatoPC\logs'
    } else {
        Join-Path $env:TEMP 'PotatoPC\logs'
    }
    if (-not (Test-Path -LiteralPath $base)) {
        New-Item -ItemType Directory -Path $base -Force | Out-Null
    }
    return (Join-Path $base ('session-' + $SessionId + '.log'))
}

function Stop-PotatoProcessTree {
    param([int]$ProcessId)
    try {
        & taskkill.exe /PID $ProcessId /T /F 2>$null | Out-Null
        return
    } catch {}
    try { Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue } catch {}
}

function Invoke-PotatoAction {
    param(
        [Parameter(Mandatory = $true)]$Item,
        [Parameter(Mandatory = $true)]$Config
    )

    $path = Resolve-PotatoPath -Path $Item.Apply -Root $Config.Root
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [PSCustomObject]@{ Ok = $false; ExitCode = -1; TimedOut = $false; Output = ''; Error = ('Нет файла: ' + $path); DurationSec = 0; RebootRequired = $false }
    }

    $timeout = [int]$Item.TimeoutSec
    if ($timeout -le 0) { $timeout = 300 }

    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $path + '"'
    $psi.WorkingDirectory = Split-Path $path -Parent
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $started = Get-Date
    $proc = $null
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit($timeout * 1000)) {
            Stop-PotatoProcessTree -ProcessId $proc.Id
            $duration = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
            return [PSCustomObject]@{ Ok = $false; ExitCode = -1; TimedOut = $true; Output = ''; Error = ('Таймаут ' + $timeout + 'с'); DurationSec = $duration; RebootRequired = $false }
        }
        $output = ''
        $errorText = ''
        try { $output = [string]$outTask.Result } catch {}
        try { $errorText = [string]$errTask.Result } catch {}
        $code = 0
        try { $code = [int]$proc.ExitCode } catch {}
        $duration = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        $ok = ($code -eq 0 -or $code -eq 3010)
        return [PSCustomObject]@{
            Ok             = $ok
            ExitCode       = $code
            TimedOut       = $false
            Output         = $output
            Error          = $errorText
            DurationSec    = $duration
            RebootRequired = ($code -eq 3010)
        }
    } catch {
        $duration = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        return [PSCustomObject]@{ Ok = $false; ExitCode = -1; TimedOut = $false; Output = ''; Error = [string]$_; DurationSec = $duration; RebootRequired = $false }
    } finally {
        if ($proc) { try { $proc.Dispose() } catch {} }
    }
}

function New-PotatoRestorePoint {
    param([string]$Description = 'PotatoPC v7')
    try {
        $drive = if ($env:SystemDrive) { $env:SystemDrive + '\' } else { 'C:\' }
        try { Enable-ComputerRestore -Drive $drive -ErrorAction SilentlyContinue } catch {}
        Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-PotatoLog -Message 'Точка восстановления создана.' -Level 'Ok'
        return $true
    } catch {
        Write-PotatoLog -Message ('Точка восстановления не создана: ' + $_.Exception.Message) -Level 'Warn'
        return $false
    }
}

function Invoke-PotatoPlan {
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)]$Config,
        [switch]$Yes,
        [switch]$NoRestorePoint,
        [switch]$NoReboot,
        [switch]$Reboot,
        [switch]$StopOnError,
        [switch]$AllowIrreversible,
        [switch]$DryRun
    )

    $systemInfo = $Plan.SystemInfo
    if (-not $DryRun -and -not $systemInfo.IsAdmin) {
        throw 'Нужны права администратора. Запусти PowerShell от имени администратора.'
    }

    Show-PotatoPlan -Plan $Plan

    $session = New-PotatoSession -Plan $Plan
    $script:PotatoLogPath = Get-PotatoLogPath -SessionId $session.Id
    Write-PotatoLog -Message ('Лог: ' + $script:PotatoLogPath) -Level 'Info'

    if ($DryRun) {
        Write-PotatoLog -Message 'Dry-run: ничего не изменено.' -Level 'Ok'
        $session.Status = 'dry-run'
        Save-PotatoSession -Session $session | Out-Null
        return $session
    }

    if ($Yes -and $Plan.IrreversibleCount -gt 0 -and -not $AllowIrreversible) {
        throw ('В плане есть необратимые действия (' + $Plan.IrreversibleCount + '). Для unattended-запуска добавь -AllowIrreversible.')
    }

    if (-not $Yes) {
        $answer = Read-Host 'Применить план? [y/N]'
        if ($answer -notmatch '^(y|yes|д|да)$') {
            Write-PotatoLog -Message 'Отменено пользователем.' -Level 'Warn'
            $session.Status = 'cancelled'
            Save-PotatoSession -Session $session | Out-Null
            return $session
        }
    }

    if (-not $NoRestorePoint) {
        New-PotatoRestorePoint -Description ('PotatoPC v7 — ' + $Plan.Profile) | Out-Null
    }

    $session.Status = 'running'
    Save-PotatoSession -Session $session | Out-Null

    $failures = New-Object System.Collections.Generic.List[string]
    $rebootFromAction = $false
    $index = 0
    $oldSafe = $env:POTATOPC_CLEAN_SAFE
    $oldRisky = $env:POTATOPC_ALLOW_RISKY_CLEAN
    $env:POTATOPC_CLEAN_SAFE = if ($Plan.Full) { '0' } else { '1' }
    $env:POTATOPC_ALLOW_RISKY_CLEAN = if ($Plan.Full) { '1' } else { '0' }
    try {
    foreach ($item in @($Plan.Items)) {
        $index++
        Write-PotatoLog -Message ('[{0}/{1}] {2}' -f $index, $Plan.Items.Count, $item.Name) -Level 'Step'
        $result = Invoke-PotatoAction -Item $item -Config $Config

        if (-not [string]::IsNullOrWhiteSpace($result.Output)) {
            foreach ($line in ($result.Output -split "`r?`n")) {
                if (-not [string]::IsNullOrWhiteSpace($line)) { Write-PotatoLog -Message ('    ' + $line.TrimEnd()) -Level 'Info' }
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($result.Error)) {
            foreach ($line in ($result.Error -split "`r?`n")) {
                if (-not [string]::IsNullOrWhiteSpace($line)) { Write-PotatoLog -Message ('    ' + $line.TrimEnd()) -Level 'Error' }
            }
        }

        if ($result.Ok) {
            Write-PotatoLog -Message ('OK: {0} ({1}с)' -f $item.Id, $result.DurationSec) -Level 'Ok'
        } else {
            Write-PotatoLog -Message ('FAIL: {0} (код {1}, {2}с)' -f $item.Id, $result.ExitCode, $result.DurationSec) -Level 'Error'
            $failures.Add([string]$item.Id)
        }
        if ($result.RebootRequired) { $rebootFromAction = $true }

        $session.Actions.Add([PSCustomObject]@{
            Id             = $item.Id
            Name           = $item.Name
            Ok             = [bool]$result.Ok
            ExitCode       = [int]$result.ExitCode
            TimedOut       = [bool]$result.TimedOut
            DurationSec    = [double]$result.DurationSec
            RebootRequired = [bool]$result.RebootRequired
            Output         = if ($result.Output.Length -gt 8000) { $result.Output.Substring(0, 8000) } else { $result.Output }
            Error          = if ($result.Error.Length -gt 8000) { $result.Error.Substring(0, 8000) } else { $result.Error }
        })
        Save-PotatoSession -Session $session | Out-Null

        if ($StopOnError -and -not $result.Ok) {
            Write-PotatoLog -Message 'Остановка по -StopOnError.' -Level 'Warn'
            break
        }
    }
    } finally {
        $env:POTATOPC_CLEAN_SAFE = $oldSafe
        $env:POTATOPC_ALLOW_RISKY_CLEAN = $oldRisky
    }

    $session.Status = if ($failures.Count -eq 0) { 'completed' } else { 'completed-with-errors' }
    $session.Finished = (Get-Date).ToString('s')
    $sessionPath = Save-PotatoSession -Session $session

    Write-Host ''
    Write-PotatoLog -Message ('Готово. Успешно: {0}, ошибок: {1}.' -f ($session.Actions.Count - $failures.Count), $failures.Count) -Level $(if ($failures.Count -eq 0) { 'Ok' } else { 'Warn' })
    if ($failures.Count -gt 0) {
        Write-PotatoLog -Message ('Ошибки: ' + ($failures -join ', ')) -Level 'Error'
    }
    Write-PotatoLog -Message ('Сессия: ' + $sessionPath) -Level 'Info'
    Write-PotatoLog -Message ('Лог: ' + $script:PotatoLogPath) -Level 'Info'

    $needsReboot = $Plan.NeedsReboot -or $rebootFromAction
    if ($needsReboot) { Write-PotatoLog -Message 'Требуется перезагрузка.' -Level 'Warn' }

    if ($needsReboot -and -not $NoReboot) {
        $doReboot = [bool]$Reboot
        if (-not $Yes -or -not $Reboot) {
            $answer = Read-Host 'Перезагрузить сейчас? [y/N]'
            $doReboot = ($answer -match '^(y|yes|д|да)$')
        }
        if ($doReboot) {
            Write-PotatoLog -Message 'Перезагрузка...' -Level 'Warn'
            Restart-Computer -Force
        }
    }

    return $session
}

function Invoke-PotatoUndo {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [switch]$Yes
    )

    if (-not (Test-PotatoAdmin)) { throw 'Нужны права администратора.' }
    Show-PotatoSession -Session $Session

    $items = @($Session.Plan.Items)
    if ($items.Count -eq 0) {
        Write-PotatoLog -Message 'В сессии нет плана для отката.' -Level 'Warn'
        return
    }

    $undoScripts = New-Object System.Collections.Generic.List[string]
    $irreversible = New-Object System.Collections.Generic.List[string]
    foreach ($item in $items) {
        if ($item.Irreversible) { $irreversible.Add([string]$item.Id) }
        $undo = [string]$item.UndoScript
        if (-not [string]::IsNullOrWhiteSpace($undo) -and -not $undoScripts.Contains($undo)) {
            $undoScripts.Add($undo)
        }
    }
    $undoArray = $undoScripts.ToArray()
    [array]::Reverse($undoArray)

    if ($undoArray.Count -eq 0) {
        Write-PotatoLog -Message 'У этой сессии нет скриптов отката.' -Level 'Warn'
        return
    }

    Write-Host ''
    Write-Host 'Откат выполнит:' -ForegroundColor White
    foreach ($script in $undoArray) { Write-Host ('  ' + $script) -ForegroundColor Cyan }
    if ($irreversible.Count -gt 0) {
        Write-PotatoLog -Message ('Необратимые действия: ' + ($irreversible -join ', ')) -Level 'Warn'
    }

    if (-not $Yes) {
        $answer = Read-Host 'Выполнить откат? [y/N]'
        if ($answer -notmatch '^(y|yes|д|да)$') {
            Write-PotatoLog -Message 'Откат отменён.' -Level 'Warn'
            return
        }
    }

    $config = Import-PotatoConfig
    $script:PotatoLogPath = Get-PotatoLogPath -SessionId ($Session.Id + '-undo')
    $failed = 0
    foreach ($script in $undoArray) {
        $leaf = Split-Path $script -Leaf
        Write-PotatoLog -Message ('Откат: ' + $leaf) -Level 'Step'
        $fake = [PSCustomObject]@{ Id = ('undo-' + $leaf); Name = $leaf; Apply = $script; TimeoutSec = 1800 }
        $result = Invoke-PotatoAction -Item $fake -Config $config
        if (-not [string]::IsNullOrWhiteSpace($result.Output)) {
            foreach ($line in ($result.Output -split "`r?`n")) {
                if (-not [string]::IsNullOrWhiteSpace($line)) { Write-PotatoLog -Message ('    ' + $line.TrimEnd()) -Level 'Info' }
            }
        }
        if (-not $result.Ok) {
            $failed++
            Write-PotatoLog -Message ('Ошибка отката: ' + $leaf + ' (код ' + $result.ExitCode + ')') -Level 'Error'
        }
    }

    $Session.Status = if ($failed -eq 0) { 'undone' } else { 'undone-with-errors' }
    $Session.Finished = (Get-Date).ToString('s')
    Save-PotatoSession -Session $Session | Out-Null
    Write-PotatoLog -Message ('Откат завершён. Ошибок: ' + $failed) -Level $(if ($failed -eq 0) { 'Ok' } else { 'Warn' })
}
