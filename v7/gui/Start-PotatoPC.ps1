param(
    [switch]$Preview,
    [ValidateSet('potato', 'office', 'game')]
    [string]$Profile,
    [switch]$Full
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# --- Admin gate: relaunch the GUI elevated once ---
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $Preview) {
    $arg = '-STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $PSCommandPath
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arg
    exit
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$script:Root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $script:Root 'PotatoPC.psd1') -Force

$script:Config = Import-PotatoConfig
$script:CurrentPlan = $null
$script:CurrentProfile = $null
$script:Running = $false
$script:Stopping = $false
$script:CurrentProcess = $null
$script:CanApply = $isAdmin
$script:RunIsDryRun = $false
$script:BrushCache = @{}
$global:PotatoCrashLog = Join-Path $env:TEMP 'PotatoPC\gui-crash.log'
try { New-Item -ItemType Directory -Path (Split-Path $global:PotatoCrashLog -Parent) -Force | Out-Null } catch {}
try {
    [AppDomain]::CurrentDomain.add_UnhandledException({
        param($sender, $eventArgs)
        try {
            Add-Content -LiteralPath $global:PotatoCrashLog -Value ("UNHANDLED: " + $eventArgs.ExceptionObject.ToString()) -Encoding UTF8
        } catch {}
    })
} catch {}

function Brush {
    param([string]$Hex)
    if (-not $script:BrushCache.ContainsKey($Hex)) {
        $script:BrushCache[$Hex] = (New-Object System.Windows.Media.BrushConverter).ConvertFrom($Hex)
    }
    return $script:BrushCache[$Hex]
}

$xamlPath = Join-Path $PSScriptRoot 'MainWindow.xaml'
[xml]$xaml = Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$titleText     = $window.FindName('TitleText')
$titleBar      = $window.FindName('TitleBar')
$titleDragArea = $window.FindName('TitleDragArea')
$minBtn        = $window.FindName('MinBtn')
$maxBtn        = $window.FindName('MaxBtn')
$closeBtn      = $window.FindName('CloseBtn')
$headerLogo    = $window.FindName('HeaderLogo')
$titleLogo     = $window.FindName('TitleLogo')
$potatoIcon    = $window.FindName('PotatoIcon')
$officeIcon    = $window.FindName('OfficeIcon')
$gameIcon      = $window.FindName('GameIcon')
$systemText    = $window.FindName('SystemText')
$systemSubText = $window.FindName('SystemSubText')
$potatoBtn     = $window.FindName('PotatoBtn')
$officeBtn     = $window.FindName('OfficeBtn')
$gameBtn       = $window.FindName('GameBtn')
$safeRadio     = $window.FindName('SafeRadio')
$fullRadio     = $window.FindName('FullRadio')
$planList      = $window.FindName('PlanList')
$planCountText = $window.FindName('PlanCountText')
$summaryText   = $window.FindName('SummaryText')
$warningsText  = $window.FindName('WarningsText')
$warnIcon      = $window.FindName('WarnIcon')
$logBox        = $window.FindName('LogBox')
$applyBtn      = $window.FindName('ApplyBtn')
$applyIcon     = $window.FindName('ApplyIcon')
$checkBtn      = $window.FindName('CheckBtn')
$checkIcon     = $window.FindName('CheckIcon')
$stopBtn       = $window.FindName('StopBtn')
$stopIcon      = $window.FindName('StopIcon')
$undoBtn       = $window.FindName('UndoBtn')
$undoIcon      = $window.FindName('UndoIcon')
$statusText    = $window.FindName('StatusText')
$statusDot     = $window.FindName('StatusDot')

$profileButtons = @($potatoBtn, $officeBtn, $gameBtn)

function Set-UiIcon {
    param($Image, [string]$File)
    if ($null -eq $Image) { return }
    $path = Join-Path $PSScriptRoot ('icons\' + $File)
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try { $Image.Source = [System.Windows.Media.Imaging.BitmapImage]::new([Uri]$path) } catch {}
    }
}

$iconPath = Join-Path $PSScriptRoot 'icons\potato.png'
if (Test-Path -LiteralPath $iconPath -PathType Leaf) {
    try { $window.Icon = [System.Windows.Media.Imaging.BitmapImage]::new([Uri]$iconPath) } catch {}
}
Set-UiIcon $headerLogo 'potato.png'
Set-UiIcon $titleLogo 'potato.png'
Set-UiIcon $potatoIcon 'potato.png'
Set-UiIcon $officeIcon 'office.png'
Set-UiIcon $gameIcon 'games.png'
Set-UiIcon $applyIcon 'play.png'
Set-UiIcon $checkIcon 'check.png'
Set-UiIcon $stopIcon 'power.png'
Set-UiIcon $undoIcon 'undo.png'
Set-UiIcon $warnIcon 'warn.png'

function Add-Log {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    if ($logBox.Dispatcher.CheckAccess()) {
        $logBox.AppendText($Text + "`r`n") | Out-Null
        $logBox.ScrollToEnd()
    } else {
        $logBox.Dispatcher.Invoke([System.Action]{
            $logBox.AppendText($Text + "`r`n") | Out-Null
            $logBox.ScrollToEnd()
        }) | Out-Null
    }
}

function Set-Status {
    param([string]$Text, [string]$Color = '#8f93a8')
    if ($statusText.Dispatcher.CheckAccess()) {
        $statusText.Text = $Text
        $statusText.Foreground = Brush $Color
        if ($statusDot) { $statusDot.Fill = Brush $Color }
    } else {
        $statusText.Dispatcher.Invoke([System.Action]{
            $statusText.Text = $Text
            $statusText.Foreground = Brush $Color
            if ($statusDot) { $statusDot.Fill = Brush $Color }
        }) | Out-Null
    }
}

function Set-Busy {
    param([bool]$Busy)
    $applyBtn.IsEnabled = (-not $Busy -and $null -ne $script:CurrentPlan)
    $checkBtn.IsEnabled = (-not $Busy -and $null -ne $script:CurrentPlan)
    $stopBtn.IsEnabled = $Busy
    $undoBtn.IsEnabled = (-not $Busy -and $script:CanApply)
    foreach ($button in $profileButtons) { $button.IsEnabled = -not $Busy }
    $safeRadio.IsEnabled = -not $Busy
    $fullRadio.IsEnabled = -not $Busy
}

$script:StdoutTask = $null
$script:StderrTask = $null
$script:ProcessTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:ProcessTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$script:ProcessTimer.Add_Tick({
    try {
    $proc = $script:CurrentProcess
    if ($null -eq $proc) { $script:ProcessTimer.Stop(); return }

    $exited = $false
    try { $exited = $proc.HasExited } catch { $exited = $true }
    if (-not $exited) { return }

    $outText = ''
    $errText = ''
    try { if ($script:StdoutTask) { $outText = [string]$script:StdoutTask.Result } } catch {}
    try { if ($script:StderrTask) { $errText = [string]$script:StderrTask.Result } } catch {}
    foreach ($line in ($outText -split "`r?`n")) { if (-not [string]::IsNullOrWhiteSpace($line)) { Add-Log $line.TrimEnd() } }
    foreach ($line in ($errText -split "`r?`n")) { if (-not [string]::IsNullOrWhiteSpace($line)) { Add-Log $line.TrimEnd() } }

    $script:ProcessTimer.Stop()
    $code = -1
    try { $code = [int]$proc.ExitCode } catch {}
    $script:Running = $false
    $script:CurrentProcess = $null
    Set-Busy $false
    Add-Log ('--- завершено, код ' + $code + ' ---')

    if ($script:Stopping) {
        $script:Stopping = $false
        Set-Status 'Остановлено пользователем' '#e06c75'
        try { $proc.Dispose() } catch {}
        return
    }

    if ($code -eq 0) {
        Set-Status $(if ($script:RunIsDryRun) { 'Проверка пройдена — изменения не вносились' } else { 'Готово' }) '#3ecf8e'
    } else {
        Set-Status $(if ($script:RunIsDryRun) { 'Проверка нашла ошибки — смотри журнал' } else { 'Завершено с ошибками — смотри журнал' }) '#e06c75'
    }

    if ($script:RunIsDryRun) {
        if ($code -ne 0) {
            [System.Windows.MessageBox]::Show('Проверка нашла ошибки. Подробности в журнале. Изменения не вносились.', 'PotatoPC', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        }
        try { $proc.Dispose() } catch {}
        return
    }

    if ($script:CurrentPlan -and $script:CurrentPlan.NeedsReboot) {
        $answer = [System.Windows.MessageBox]::Show(
            'Изменения применены. Перезагрузить компьютер сейчас?',
            'PotatoPC',
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question)
        if ($answer -eq [System.Windows.MessageBoxResult]::Yes) { Restart-Computer -Force }
    } elseif ($code -ne 0) {
        [System.Windows.MessageBox]::Show('Часть действий завершилась с ошибкой. Подробности в журнале.', 'PotatoPC', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
    }

    try { $proc.Dispose() } catch {}
    } catch {
        try {
            $msg = "TIMER: " + $_.Exception.ToString() + "`r`n" + $_.ScriptStackTrace
            Add-Content -LiteralPath $global:PotatoCrashLog -Value $msg -Encoding UTF8
        } catch {}
        try { $script:ProcessTimer.Stop() } catch {}
        try { $script:Running = $false; $script:CurrentProcess = $null; Set-Busy $false } catch {}
        try { Set-Status 'Ошибка обработки — смотри gui-crash.log' '#e06c75' } catch {}
    }
})

function Select-ProfileButton {
    param($Selected)
    $Selected = @($Selected) | Select-Object -First 1
    foreach ($button in $profileButtons) {
        $button.Background = Brush '#171a26'
        $button.BorderBrush = Brush '#2a2e42'
    }
    if ($Selected) {
        $Selected.Background = Brush '#1f2a3d'
        $Selected.BorderBrush = Brush '#14b8a6'
    }
}

function Confirm-Plan {
    param($Plan)
    $message = "Профиль: $($Plan.ProfileName)`nДействий: $($Plan.Items.Count)`nРискованных: $($Plan.RiskyCount)`nНеобратимых: $($Plan.IrreversibleCount)`n"
    if ($Plan.NeedsReboot) { $message += "`nПосле работы потребуется перезагрузка." }
    if ($Plan.IrreversibleCount -gt 0) {
        $message += "`n`nВНИМАНИЕ: есть необратимые действия. Их нельзя откатить."
    }
    $message += "`n`nСначала будет создана точка восстановления — это может занять до минуты."
    $message += "`n`nПрименить этот план?"
    $answer = [System.Windows.MessageBox]::Show(
        $message,
        'PotatoPC — подтверждение',
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning)
    return ($answer -eq [System.Windows.MessageBoxResult]::Yes)
}

function Show-Plan {
    param([string]$Profile)
    try {
        $full = [bool]$fullRadio.IsChecked
        $plan = Resolve-PotatoPlan -Config $script:Config -ProfileName $Profile -Full:$full
        $script:CurrentPlan = $plan
        $script:CurrentProfile = $Profile

        $planList.Items.Clear()
        foreach ($item in @($plan.Items)) {
            $name = $item.Name -replace '^\d+\s*·\s*', ''
            $flags = @()
            if ($item.RequiresReboot) { $flags += 'перезагрузка' }
            if ($item.Irreversible) { $flags += 'необратимо' }
            $suffix = if ($flags.Count -gt 0) { '  [' + ($flags -join ', ') + ']' } else { '' }

            $riskColor = switch ($item.Risk) {
                'safe' { '#3ecf8e' }
                'caution' { '#f0c040' }
                'advanced' { '#e06c75' }
                default { '#8f93a8' }
            }
            $row = New-Object System.Windows.Controls.StackPanel
            $row.Orientation = 'Horizontal'
            $dot = New-Object System.Windows.Controls.TextBlock
            $dot.Text = '●'
            $dot.FontSize = 9
            $dot.Margin = [System.Windows.Thickness]::new(0, 2, 8, 0)
            $dot.Foreground = Brush $riskColor
            $text = New-Object System.Windows.Controls.TextBlock
            $text.Text = $name + $suffix
            $text.Foreground = Brush '#dcdcf0'
            $text.TextWrapping = 'Wrap'
            $row.Children.Add($dot) | Out-Null
            $row.Children.Add($text) | Out-Null

            $listItem = New-Object System.Windows.Controls.ListBoxItem
            $listItem.Content = $row
            $listItem.ToolTip = $item.Description
            [void]$planList.Items.Add($listItem)
        }
        if ($planList.Items.Count -gt 0) { $planList.ScrollIntoView($planList.Items[0]) }

        $rebootText = if ($plan.NeedsReboot) { 'да' } else { 'нет' }
        $summaryText.Text = "Профиль: $($plan.ProfileName)`nДействий: $($plan.Items.Count)`nРискованных: $($plan.RiskyCount)`nНеобратимых: $($plan.IrreversibleCount)`nПерезагрузка: $rebootText"
        $warningsText.Text = if ($plan.Warnings.Count -gt 0) { ($plan.Warnings -join "`n") } else { 'Предупреждений нет.' }
        if ($planCountText) { $planCountText.Text = [string]$plan.Items.Count }

        $selectedButton = $profileButtons | Where-Object { $_.Tag -eq $Profile } | Select-Object -First 1
        Select-ProfileButton $selectedButton

        $applyBtn.IsEnabled = $true
        $checkBtn.IsEnabled = $true
        if ($script:CanApply) {
            Set-Status ("План готов: $($plan.Items.Count) действий. Проверь и нажми «Применить».") '#3ecf8e'
        } else {
            Set-Status 'План готов. Режим просмотра: для применения запусти от администратора.' '#d4a017'
        }
    } catch {
        Add-Log ('ОШИБКА ПЛАНА: ' + $_.Exception.Message)
        Add-Log ([string]$_.ScriptStackTrace)
        Set-Status 'Ошибка построения плана' '#e06c75'
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'PotatoPC', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
    }
}

function Start-Cli {
    param([string]$Arguments, [bool]$IsDryRun = $false)
    $script:RunIsDryRun = $IsDryRun
    Set-Status $(if ($IsDryRun) { 'Проверяю план… ничего не меняется' } else { 'Выполняется… не закрывай окно' }) '#f0c040'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
    $psi.Arguments = $Arguments
    $psi.WorkingDirectory = $script:Root
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    if ($script:Running) { return }

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    $script:CurrentProcess = $proc
    $script:Running = $true
    $script:Stopping = $false
    Set-Busy $true
    try {
        $proc.Start() | Out-Null
        $script:StdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $script:StderrTask = $proc.StandardError.ReadToEndAsync()
        $script:ProcessTimer.Start()
    } catch {
        $script:Running = $false
        $script:CurrentProcess = $null
        Set-Busy $false
        Add-Log ('Не удалось запустить процесс: ' + $_.Exception.Message)
        Set-Status 'Ошибка запуска — смотри журнал' '#e06c75'
        try { $proc.Dispose() } catch {}
    }
}

function Start-Elevated {
    $profileArg = if ($script:CurrentProfile) { ' -Profile ' + $script:CurrentProfile } else { '' }
    $fullArg = if ($fullRadio.IsChecked) { ' -Full' } else { '' }
    $arg = '-STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"{1}{2}' -f $PSCommandPath, $profileArg, $fullArg
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arg
        $window.Close()
    } catch {
        [System.Windows.MessageBox]::Show('Не удалось перезапустить от администратора. Запусти PotatoPC.cmd вручную.', 'PotatoPC', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
    }
}

function Start-Apply {
    if (-not $script:CanApply) {
        $answer = [System.Windows.MessageBox]::Show(
            'Для применения нужны права администратора. Перезапустить программу от администратора?',
            'PotatoPC',
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question)
        if ($answer -eq [System.Windows.MessageBoxResult]::Yes) { Start-Elevated }
        return
    }
    if ($null -eq $script:CurrentPlan) { return }
    if (-not (Confirm-Plan $script:CurrentPlan)) { return }

    $profile = $script:CurrentPlan.Profile
    $full = [bool]$script:CurrentPlan.Full
    $cli = Join-Path $script:Root 'PotatoPC.ps1'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $cli + '"'), '-Profile', $profile)
    if ($full) { $argList += '-Full' }
    $argList += @('-Yes', '-AllowIrreversible', '-NoReboot')

    Add-Log ''
    Add-Log ('=== ЗАПУСК: ' + $profile + $(if ($full) { ' (full)' } else { ' (safe)' }) + ' ===')
    Start-Cli -Arguments ($argList -join ' ') -IsDryRun $false
}

function Start-Check {
    if ($null -eq $script:CurrentPlan) { return }
    $profile = $script:CurrentPlan.Profile
    $full = [bool]$script:CurrentPlan.Full
    $cli = Join-Path $script:Root 'PotatoPC.ps1'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $cli + '"'), '-Profile', $profile)
    if ($full) { $argList += '-Full' }
    $argList += '-DryRun'

    Add-Log ''
    Add-Log '=== ПРОВЕРКА (dry-run, без изменений) ==='
    Start-Cli -Arguments ($argList -join ' ') -IsDryRun $true
}

function Start-Undo {
    if (-not $script:CanApply) {
        [System.Windows.MessageBox]::Show('Для отката нужны права администратора. Закрой окно и запусти PotatoPC.cmd.', 'PotatoPC', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        return
    }
    try { $session = Get-PotatoSession } catch {
        [System.Windows.MessageBox]::Show('Сессий пока нет — откатывать нечего.', 'PotatoPC', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        return
    }
    $actions = @($session.Actions)
    $message = "Откатить сессию $($session.Id)?`nПрофиль: $($session.Profile)`nСтатус: $($session.Status)`nДействий: $($actions.Count)"
    $answer = [System.Windows.MessageBox]::Show($message, 'PotatoPC — откат', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }

    $cli = Join-Path $script:Root 'PotatoPC.ps1'
    $argText = '-NoProfile -ExecutionPolicy Bypass -File "' + $cli + '" -Undo -Session ' + $session.Id + ' -Yes'
    Add-Log ''
    Add-Log ('=== ОТКАТ: ' + $session.Id + ' ===')
    Start-Cli -Arguments $argText -IsDryRun $false
}

function Stop-Apply {
    if (-not $script:Running -or $null -eq $script:CurrentProcess) { return }
    $answer = [System.Windows.MessageBox]::Show(
        'Остановить выполнение? Часть изменений может остаться применённой.',
        'PotatoPC — остановка',
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning)
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
    $script:Stopping = $true
    Set-Status 'Остановка...' '#e06c75'
    try { & taskkill.exe /PID $script:CurrentProcess.Id /T /F 2>$null | Out-Null } catch {}
}

$potatoBtn.Add_Click({ Show-Plan -Profile 'potato' })
$officeBtn.Add_Click({ Show-Plan -Profile 'office' })
$gameBtn.Add_Click({ Show-Plan -Profile 'game' })
$safeRadio.Add_Checked({ if ($script:CurrentProfile) { Show-Plan -Profile $script:CurrentProfile } })
$fullRadio.Add_Checked({ if ($script:CurrentProfile) { Show-Plan -Profile $script:CurrentProfile } })
$applyBtn.Add_Click({ Start-Apply })
$checkBtn.Add_Click({ Start-Check })
$stopBtn.Add_Click({ Stop-Apply })
$undoBtn.Add_Click({ Start-Undo })

$titleDragArea.Add_MouseLeftButtonDown({
    param($sender, $eventArgs)
    if ($eventArgs.ButtonState -eq [System.Windows.Input.MouseButtonState]::Pressed) {
        try { $window.DragMove() } catch {}
    }
})
$minBtn.Add_Click({ $window.WindowState = 'Minimized' })
$maxBtn.Add_Click({
    if ($window.WindowState -eq 'Maximized') { $window.WindowState = 'Normal' }
    else { $window.WindowState = 'Maximized' }
})
$closeBtn.Add_Click({ $window.Close() })

$window.Dispatcher.add_UnhandledException({
    param($sender, $eventArgs)
    try {
        Add-Log ('UI ERROR: ' + $eventArgs.Exception.Message)
        Set-Status 'Ошибка интерфейса — смотри журнал' '#e06c75'
        $eventArgs.Handled = $true
    } catch {}
})

$window.Add_Closing({
    param($sender, $eventArgs)
    if ($script:Running) {
        [System.Windows.MessageBox]::Show('Идёт работа. Дождись завершения или нажми «Остановить».', 'PotatoPC', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        $eventArgs.Cancel = $true
    }
})

$window.Add_Loaded({
    $system = Get-PotatoSystemInfo
    if ($systemText) { $systemText.Text = ($system.OS -replace '^Microsoft\s+', '') }
    if ($systemSubText) {
        $device = if ($system.IsLaptop) { 'ноутбук' } else { 'ПК' }
        $systemSubText.Text = "build $($system.Build) · $($system.RamGB) ГБ · $device"
    }
    Add-Log 'PotatoPC v7'
    Add-Log ("Система: " + $system.OS + " (build " + $system.Build + "), RAM " + $system.RamGB + " ГБ" + $(if ($system.IsLaptop) { ', ноутбук' } else { '' }))
    Add-Log 'Выбери профиль сверху — покажу план. Ничего не изменится без кнопки «Применить».'
    [void]$planList.Items.Add('Выбери профиль сверху — здесь появится план.')
    $warningsText.Text = 'Пока нет предупреждений.'
    $planCountText.Text = '0'
    if ($Full) { $fullRadio.IsChecked = $true }
    if ($script:CanApply) {
        Set-Status 'Выбери профиль'
    } else {
        Add-Log 'Режим просмотра: программа запущена без прав администратора. При нажатии «Применить» предложит перезапуск.'
        Set-Status 'Режим просмотра: нажми «Применить» — предложу перезапуск от администратора.' '#d4a017'
    }
    Set-Busy $false
    if ($Profile) { Show-Plan -Profile $Profile }
})

$window.ShowDialog() | Out-Null
