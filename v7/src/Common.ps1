$script:PotatoRoot = Split-Path -Parent $PSScriptRoot
$script:PotatoLogPath = $null

function Get-PotatoRoot {
    return $script:PotatoRoot
}

function Write-PotatoLog {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Ok', 'Warn', 'Error', 'Step')]
        [string]$Level = 'Info'
    )
    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    $color = switch ($Level) {
        'Ok'    { 'Green' }
        'Warn'  { 'Yellow' }
        'Error' { 'Red' }
        'Step'  { 'Cyan' }
        default { 'Gray' }
    }
    $tag = switch ($Level) {
        'Ok'    { '[+]' }
        'Warn'  { '[!]' }
        'Error' { '[x]' }
        'Step'  { '[*]' }
        default { '[ ]' }
    }
    Write-Host ("{0} {1}" -f $tag, $Message) -ForegroundColor $color
    if ($script:PotatoLogPath) {
        try {
            $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level.ToUpperInvariant(), $Message
            Add-Content -LiteralPath $script:PotatoLogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
        } catch {}
    }
}

function Test-PotatoAdmin {
    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-PotatoSystemInfo {
    $info = [ordered]@{
        ComputerName = $env:COMPUTERNAME
        User         = $env:USERNAME
        OS           = ''
        Build        = 0
        Major        = 10
        IsLaptop     = $false
        IsDomain     = $false
        RamGB        = 0
        IsAdmin      = (Test-PotatoAdmin)
        PSVersion    = $PSVersionTable.PSVersion.ToString()
    }
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $info.OS = [string]$os.Caption
        $info.Build = [int]$os.BuildNumber
        $info.Major = if ($info.Build -ge 22000) { 11 } else { 10 }
        $info.IsDomain = [bool]$cs.PartOfDomain
        $info.RamGB = [math]::Round(([double]$cs.TotalPhysicalMemory / 1GB), 1)
        try { $info.IsLaptop = ([int]$cs.PCSystemType -eq 2) } catch {}
        if (-not $info.IsLaptop) {
            try {
                $battery = @(Get-CimInstance Win32_Battery -ErrorAction Stop)
                $info.IsLaptop = ($battery.Count -gt 0)
            } catch {}
        }
    } catch {}
    return [PSCustomObject]$info
}

function Resolve-PotatoPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Root = (Get-PotatoRoot)
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Пустой путь.' }
    if ([System.IO.Path]::IsPathRooted($Path)) { throw ('Абсолютный путь запрещён: ' + $Path) }
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $full = [System.IO.Path]::GetFullPath((Join-Path $rootFull $Path))
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ('Путь выходит за пределы приложения: ' + $Path)
    }
    return $full
}

function Read-PotatoJson {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ('Файл не найден: ' + $Path)
    }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw ('Пустой JSON: ' + $Path)
    }
    return ($raw | ConvertFrom-Json)
}

function Get-PotatoPropertyNames {
    param($Object)
    if ($null -eq $Object) { return @() }
    return @($Object.PSObject.Properties.Name)
}

function Get-PotatoObjectProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Get-PotatoRiskLabel {
    param([string]$Risk)
    switch ($Risk) {
        'safe'     { return 'OK' }
        'caution'  { return '!' }
        'advanced' { return '!!' }
        default    { return '?' }
    }
}

function Get-PotatoRiskColor {
    param([string]$Risk)
    switch ($Risk) {
        'safe'     { return 'Green' }
        'caution'  { return 'Yellow' }
        'advanced' { return 'Red' }
        default    { return 'Gray' }
    }
}
