function Resolve-PotatoPlan {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$ProfileName,
        [switch]$Full,
        [string[]]$Include = @(),
        [string[]]$Exclude = @(),
        $SystemInfo = $null
    )

    $profileProp = $Config.Profiles.PSObject.Properties[$ProfileName]
    if ($null -eq $profileProp) {
        throw ("Профиль не найден: '$ProfileName'. Доступны: " + ((Get-PotatoPropertyNames $Config.Profiles) -join ', '))
    }
    if ($null -eq $SystemInfo) { $SystemInfo = Get-PotatoSystemInfo }
    $profile = $profileProp.Value

    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($id in @(Get-PotatoObjectProperty $profile 'safe')) {
        if (-not [string]::IsNullOrWhiteSpace([string]$id) -and -not $ids.Contains([string]$id)) { [void]$ids.Add([string]$id) }
    }
    if ($Full) {
        foreach ($id in @(Get-PotatoObjectProperty $profile 'full')) {
            if (-not [string]::IsNullOrWhiteSpace([string]$id) -and -not $ids.Contains([string]$id)) { [void]$ids.Add([string]$id) }
        }
    }
    foreach ($id in @($Include)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$id)) {
            if (-not $Config.TweakMap.ContainsKey([string]$id)) { throw ("Неизвестный твик в -Include: '$id'.") }
            if (-not $ids.Contains([string]$id)) { [void]$ids.Add([string]$id) }
        }
    }
    foreach ($id in @($Exclude)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$id)) { [void]$ids.Remove([string]$id) }
    }

    $items = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[string]

    foreach ($id in $ids) {
        $t = $Config.TweakMap[$id]
        if ($null -eq $t) { throw ("Неизвестный твик: '$id'.") }

        $windows = [string](Get-PotatoObjectProperty $t 'windows')
        if ($windows -eq '11' -and [int]$SystemInfo.Major -lt 11) {
            $warnings.Add("Пропуск '$id': только Windows 11.")
            continue
        }

        $risk = [string](Get-PotatoObjectProperty $t 'risk')
        if ($risk -ne 'safe') {
            $warnings.Add(("Осторожно: '{0}' помечен как {1}." -f $id, $risk))
        }
        if ([bool](Get-PotatoObjectProperty $t 'irreversible')) {
            $warnings.Add(("Необратимо: '{0}'." -f $id))
        }
        if ($SystemInfo.IsLaptop -and $id -in @('high-performance', 'free-space-nohiber')) {
            $warnings.Add(("Ноутбук: '{0}' может ухудшить батарею/сон." -f $id))
        }
        if ($SystemInfo.IsDomain -and $id -in @('security-only', 'stop-spy-services', 'firewall-on')) {
            $warnings.Add(("Домен/GPO: '{0}' может конфликтовать с политикой." -f $id))
        }

        $items.Add([PSCustomObject]@{
            Id              = $id
            Name            = [string](Get-PotatoObjectProperty $t 'name')
            Description     = [string](Get-PotatoObjectProperty $t 'description')
            Category        = [string](Get-PotatoObjectProperty $t 'category')
            Risk            = $risk
            Apply           = [string](Get-PotatoObjectProperty $t 'apply')
            UndoGroup       = [string](Get-PotatoObjectProperty $t 'undoGroup')
            UndoScript      = [string](Get-PotatoObjectProperty $t 'undoScript')
            UndoQuality     = [string](Get-PotatoObjectProperty $t 'undoQuality')
            RequiresAdmin   = [bool](Get-PotatoObjectProperty $t 'requiresAdmin')
            RequiresReboot  = [bool](Get-PotatoObjectProperty $t 'requiresReboot')
            Irreversible    = [bool](Get-PotatoObjectProperty $t 'irreversible')
            TimeoutSec      = [int](Get-PotatoObjectProperty $t 'timeoutSec')
            Windows         = $windows
            Icon            = [string](Get-PotatoObjectProperty $t 'icon')
        })
    }

    return [PSCustomObject]@{
        Profile           = $ProfileName
        ProfileName       = [string](Get-PotatoObjectProperty $profile 'name')
        ProfileDescription = [string](Get-PotatoObjectProperty $profile 'description')
        Full              = [bool]$Full
        Items             = $items.ToArray()
        Warnings          = $warnings.ToArray()
        NeedsReboot       = (@($items | Where-Object { $_.RequiresReboot }).Count -gt 0)
        RiskyCount        = @($items | Where-Object { $_.Risk -ne 'safe' }).Count
        IrreversibleCount = @($items | Where-Object { $_.Irreversible }).Count
        AdminRequired     = (@($items | Where-Object { $_.RequiresAdmin }).Count -gt 0)
        SystemInfo        = $SystemInfo
        Created           = (Get-Date).ToString('s')
    }
}

function Show-PotatoPlan {
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [switch]$NoWarnings
    )

    Write-Host ''
    Write-Host ('PotatoPC v7 — {0}' -f $Plan.ProfileName) -ForegroundColor White
    if ($Plan.ProfileDescription) { Write-Host ('  ' + $Plan.ProfileDescription) -ForegroundColor DarkGray }
    Write-Host ('  Режим: {0}   Действий: {1}   Рискованных: {2}   Необратимых: {3}' -f `
        $(if ($Plan.Full) { 'full' } else { 'safe' }), $Plan.Items.Count, $Plan.RiskyCount, $Plan.IrreversibleCount) -ForegroundColor DarkGray
    Write-Host ''

    $i = 0
    foreach ($item in $Plan.Items) {
        $i++
        $riskLabel = Get-PotatoRiskLabel -Risk $item.Risk
        $riskColor = Get-PotatoRiskColor -Risk $item.Risk
        $flags = @()
        if ($item.RequiresReboot) { $flags += 'reboot' }
        if ($item.Irreversible) { $flags += 'irreversible' }
        $flagText = if ($flags.Count -gt 0) { ' [' + ($flags -join ', ') + ']' } else { '' }
        Write-Host ('  {0,2}. ' -f $i) -NoNewline
        Write-Host ('[{0}]' -f $riskLabel) -ForegroundColor $riskColor -NoNewline
        Write-Host (' {0}' -f $item.Name) -NoNewline
        Write-Host ('{0}' -f $flagText) -ForegroundColor DarkYellow
        Write-Host ('      {0}' -f $item.Id) -ForegroundColor DarkGray
    }

    if (-not $NoWarnings -and $Plan.Warnings.Count -gt 0) {
        Write-Host ''
        foreach ($warning in $Plan.Warnings) { Write-PotatoLog -Message $warning -Level 'Warn' }
    }

    Write-Host ''
    if ($Plan.NeedsReboot) { Write-PotatoLog -Message 'После выполнения потребуется перезагрузка.' -Level 'Warn' }
    if ($Plan.AdminRequired) { Write-PotatoLog -Message 'Часть действий требует прав администратора.' -Level 'Info' }
}

function Show-PotatoCatalog {
    param([Parameter(Mandatory = $true)]$Config)

    Write-Host ''
    Write-Host 'PotatoPC v7 — профили' -ForegroundColor White
    foreach ($profileName in (Get-PotatoPropertyNames $Config.Profiles)) {
        $profile = $Config.Profiles.$profileName
        $safe = @(Get-PotatoObjectProperty $profile 'safe').Count
        $full = @(Get-PotatoObjectProperty $profile 'full').Count
        Write-Host ('  {0,-8} {1}' -f $profileName, [string](Get-PotatoObjectProperty $profile 'name')) -ForegroundColor Cyan
        Write-Host ('           safe: {0}, full: +{1}' -f $safe, $full) -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host 'Действия' -ForegroundColor White
    foreach ($id in (Get-PotatoPropertyNames $Config.Tweaks | Sort-Object)) {
        $t = $Config.Tweaks.$id
        $risk = [string](Get-PotatoObjectProperty $t 'risk')
        Write-Host ('  [{0,-2}] {1,-28} {2}' -f (Get-PotatoRiskLabel -Risk $risk), $id, [string](Get-PotatoObjectProperty $t 'name')) -ForegroundColor (Get-PotatoRiskColor -Risk $risk)
    }
    Write-Host ''
    Write-PotatoLog -Message ('Всего действий: ' + (@(Get-PotatoPropertyNames $Config.Tweaks).Count)) -Level 'Info'
}
