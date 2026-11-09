function Get-PotatoSessionDir {
    $base = if (Test-PotatoAdmin -and $env:ProgramData) {
        Join-Path $env:ProgramData 'PotatoPC\sessions'
    } else {
        Join-Path $env:TEMP 'PotatoPC\sessions'
    }
    if (-not (Test-Path -LiteralPath $base)) {
        New-Item -ItemType Directory -Path $base -Force | Out-Null
    }
    return $base
}

function New-PotatoSession {
    param(
        [Parameter(Mandatory = $true)]$Plan
    )
    $id = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + (Get-Random -Minimum 100 -Maximum 999)
    return [PSCustomObject]@{
        Id       = $id
        Started  = (Get-Date).ToString('s')
        Finished = $null
        Profile  = $Plan.Profile
        Full     = $Plan.Full
        Status   = 'planned'
        System   = $Plan.SystemInfo
        Plan     = $Plan
        Actions  = (New-Object System.Collections.Generic.List[object])
    }
}

function Save-PotatoSession {
    param([Parameter(Mandatory = $true)]$Session)
    $dir = Get-PotatoSessionDir
    $path = Join-Path $dir ($Session.Id + '.json')
    $json = $Session | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

function Get-PotatoSession {
    param([string]$Id)
    $dir = Get-PotatoSessionDir
    if ([string]::IsNullOrWhiteSpace($Id)) {
        $latest = @(Get-ChildItem -LiteralPath $dir -File -Filter '*.json' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1)
        if ($latest.Count -eq 0) { throw 'Сессий пока нет.' }
        $path = $latest[0].FullName
    } else {
        $path = Join-Path $dir ($Id + '.json')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw ("Сессия не найдена: '$Id'.") }
    }
    return (Read-PotatoJson -Path $path)
}

function Show-PotatoSession {
    param([Parameter(Mandatory = $true)]$Session)
    Write-Host ''
    Write-Host ('Сессия ' + $Session.Id) -ForegroundColor White
    Write-Host ('  Профиль: {0}   Статус: {1}' -f $Session.Profile, $Session.Status) -ForegroundColor DarkGray
    Write-Host ('  Начало: {0}   Конец: {1}' -f $Session.Started, $(if ($Session.Finished) { $Session.Finished } else { '—' })) -ForegroundColor DarkGray
    if ($Session.Actions) {
        foreach ($action in @($Session.Actions)) {
            $mark = if ($action.Ok) { 'OK' } else { 'FAIL' }
            $color = if ($action.Ok) { 'Green' } else { 'Red' }
            Write-Host ('  [{0}] {1}' -f $mark, $action.Name) -ForegroundColor $color
        }
    }
    Write-Host ''
}
