$script:ScanCheckboxes = @{}
$script:ProtectLastScan = $null
$script:ScanRunning = $false
$script:ScanHandle = $null
$script:ScanControl = $null
$script:ScanOperationId = ''
$script:QuarantineRunning = $false
$script:QuarantineControl = $null
$script:QuarantineOperationId = ''
$script:YaraEngineZipSha256 = '352396C8A3D9B31B157A4820ABD3B9347FC934A2314CDDA8A4F566A5570163E4'
$script:YaraEngineExeSha256 = '1C45EB279D820ABA81FD41C22384428EBE44037CF5793BE4B52A9D3B3DF62B33'
$script:YaraRulesManifestSha256 = '6854EA681543805EF8EEB4D10BE98AD9C40021894EAC4709CE64148C10D016B4'
$script:YaraRuleHashes = @{
    'MALW_Arkei.yar' = '3EBAE7B8D1EFD69FFBB7D3D3B7C285ED827F7226F0A3B6E009D7A35A57DA4206'
    'MALW_AZORULT.yar' = 'E86E0A5B6A71BD0F8F9BA404B93DDE97EBD41B64A5F6B6194E5690CC3D363670'
    'MALW_CAP_HookExKeylogger.yar' = '962D7904342AC4D9DF103C3A3F2B3EA06F167035EB9BFC1B7AADB49B1F37A42D'
    'MALW_Eicar.yar' = '1BA3175CEBE28FC5D4D25C1CAF604BEDA152766DB268A3F159E4BF61C2EDDF54'
    'MALW_Fareit.yar' = '6A8CDC84CB8E9B6EFF4DC850ED607DB879F7061A5BB0ABC88F56D367D07EB145'
    'MALW_hancitor.yar' = '4D99A2992A41CC0BFA5152EB8E0A4E0BF8B09B1094B2C57587CA8D1E030C6794'
    'MALW_Install11.yar' = 'C968DAC993842B2AD9EAB3CD107948E0478193585CB2BD172B8EEC782C286DF7'
    'MALW_kirbi_mimikatz.yar' = '7C92DD473551746E87D3E7536EDE7191B8AFDDAC8D35468D05D9659CBF440CDE'
    'MALW_Monero_Miner_installer.yar' = 'DBA740CD77BAC8B40986BC0111CE74D0993C1F5DE5F9FA0EFD1F296F1C90FD8E'
    'MALW_MSILStealer.yar' = '587AAFF8E7B4D969CC04DAC2F66BE0D44B208A528BAECA8719C6939478A233D3'
    'MALW_Pony.yar' = 'EF83DD8260BBEE0301FB065B751F6C6136EA55BED40DBC57D422C9F988651E44'
    'MALW_Stealer.yar' = '7889E2BE33FE6CC13F33DFF8C9FD7CADB631A0C0AA47DCAFB1BC480A8B2CC950'
    'MALW_Tinba.yar' = '0B472CDCB0388F6AC3A9017D3977785D8397422B7EC2EB585917839128CBAA12'
    'MALW_Upatre.yar' = '2D2B11B76BE97A17EBBE86049E40C9BFD3F80C16AE68E1ECDED9277021D822CE'
    'MALW_viotto_keylogger.yar' = 'A6CAD250175C25656057F7AFA56DF219B7D5EB2F73958B9AC3A649C5496BB1A7'
    'MALW_XMRIG_Miner.yar' = 'B4435B8A807DB961088209B5E12EFBD708BFF64BC9DB6E1349CF85A2E8A7E65C'
    'MALW_Zeus.yar' = '3B844477C7DBB97418EDC4B5485DF2D0E0F9E1119F73F99188EA6E36D4354CFF'
    'RANSOM_Cerber.yar' = '93E1DC32941AFD6B7FEBEFC4283FDB951B0CD1E354F2CBBC0AF6E8FD5A99C8EE'
    'RANSOM_Locky.yar' = 'EAF00A1660FA88B2D332CAEBAD9A41110131B5FC8C232315B63421FA409EC580'
    'RANSOM_Stampado.yar' = '60B41F887DC916B53E08C6D037492361F0125575C4CFE9C5D07D95CB000B4BAB'
    'RANSOM_TeslaCrypt.yar' = '45A89521A98F29E88C950C4A179320D72DBC5EC0BE0573D56DF6C97B16F59996'
    'RAT_Asyncrat.yar' = '7FFCA8D68A1DD22AC9C9CA157EC3DE87B770597718F9CFBF88E22CD61F6A6E3B'
    'RAT_DarkComet.yar' = '4A593CB64EBAD7AC03D8967C4242E278F159A3C74B4B4D111B90A67FBAD1CAAB'
    'RAT_Nanocore.yar' = 'D284CFC4F391711BDE33C861045B3F3C6632F95513D71EAFC34D0F88045E6F3A'
    'RAT_Njrat.yar' = '58F2E83F91DF433050C5363E18A23EF1B713F3FFB7D2DFF55612795AB86D2F96'
    'RAT_Orcus.yar' = '3E994EFB4935F645B6EC3A6DD9441F14C8B763B45AC2C2C78A7F244A77D0503A'
    'RAT_PoisonIvy.yar' = 'ADEB9350D6165B581E3A8F5F93CFC470DC50D9D950598589D0A5DEFCFA8D6D8D'
}

function Test-OperationCancelled {
    param($Control)
    if ($null -eq $Control) { return $false }
    try { if ([bool]$Control.Abort) { return $true } } catch {}
    try { if ([bool]$Control.CancelRequested) { return $true } } catch {}
    return $false
}

function Assert-OperationActive {
    param($Control, [string]$Message = 'STOPPED_BY_USER')
    if (Test-OperationCancelled $Control) { throw $Message }
}

function New-OperationControl {
    param([string]$Kind = 'operation')
    return [hashtable]::Synchronized(@{
        Abort = $false
        CancelRequested = $false
        ChildPid = 0
        Kind = $Kind
        OperationId = [Guid]::NewGuid().ToString('N')
        StartedUtc = [DateTime]::UtcNow
    })
}

function Stop-Operation {
    param($Control)
    if ($null -eq $Control) { return $false }
    try { $Control.CancelRequested = $true } catch {}
    try { $Control.Abort = $true } catch {}
    $childPid = 0
    try { $childPid = [int]$Control.ChildPid } catch {}
    if ($childPid -gt 4) {
        $stopTree = Get-Command Stop-ProcessTree -ErrorAction SilentlyContinue
        if ($stopTree) {
            try { & $stopTree -TargetPid $childPid } catch {}
        } else {
            try { Stop-Process -Id $childPid -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
    try { $Control.ChildPid = 0 } catch {}
    return $true
}

function ConvertTo-ProtectPath {
    param([string]$Path, [switch]$AllowMissing)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $raw = $Path.Trim()
    if ($raw -match '[\x00-\x1f]' -or $raw -match '^[\\/]{2}' -or $raw -match '^\?') { return $null }
    if ($raw -notmatch '^[A-Za-z]:[\\/]' -or $raw.Substring(2).Contains(':')) { return $null }
    $segments = @($raw -split '[\\/]')
    $lastSegment = $segments.Count - 1
    for ($i = 1; $i -lt $segments.Count; $i++) {
        $segment = [string]$segments[$i]
        if ([string]::IsNullOrEmpty($segment)) {
            if ($i -ne $lastSegment) { return $null }
            continue
        }
        if ($segment -eq '.' -or $segment -eq '..' -or $segment.EndsWith('.') -or $segment.EndsWith(' ') -or $segment -match '[*?<>|]') { return $null }
        if ($segment -match '^(?i:CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|COM[1-9]|LPT[1-9])(?:\..*)?$') { return $null }
    }
    try { $full = [System.IO.Path]::GetFullPath(($raw -replace '/', '\')) } catch { return $null }
    if (-not [System.IO.Path]::IsPathRooted($full)) { return $null }
    $pathRoot = [System.IO.Path]::GetPathRoot($full)
    if ($pathRoot -notmatch '^[A-Za-z]:\\$') { return $null }
    $probe = $full
    while (-not [string]::IsNullOrEmpty($probe)) {
        $item = $null
        try { $item = Get-Item -LiteralPath $probe -Force -ErrorAction Stop } catch {}
        if ($null -ne $item -and (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) { return $null }
        $parent = $null
        try { $parent = [System.IO.Path]::GetDirectoryName($probe) } catch {}
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $probe) { break }
        $probe = $parent
    }
    $exists = $false
    try { $exists = [bool](Test-Path -LiteralPath $full -ErrorAction SilentlyContinue) } catch {}
    if (-not $exists -and -not $AllowMissing) { return $null }
    if ($full.Length -gt 3) { $full = $full.TrimEnd('\') }
    return $full
}

function Test-ProtectPath {
    param([string]$Path, [switch]$AllowMissing, [switch]$Directory, [switch]$Leaf)
    if ($Directory -and $Leaf) { return $false }
    $full = ConvertTo-ProtectPath -Path $Path -AllowMissing:$AllowMissing
    if ($null -eq $full) { return $false }
    $item = $null
    try { $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop } catch {}
    if ($null -eq $item) { return [bool]$AllowMissing }
    try { if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false } } catch { return $false }
    if ($Directory -and -not $item.PSIsContainer) { return $false }
    if ($Leaf -and $item.PSIsContainer) { return $false }
    return $true
}

function Get-ProtectFileInfo {
    param([string]$Path)
    $full = ConvertTo-ProtectPath -Path $Path
    if ($null -eq $full) { return $null }
    $item = $null
    try { $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop } catch { return $null }
    if ($null -eq $item -or $item.PSIsContainer) { return $null }
    try { if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $null } } catch { return $null }
    return $item
}

function Get-ProtectDirectoryInfo {
    param([string]$Path)
    $full = ConvertTo-ProtectPath -Path $Path
    if ($null -eq $full) { return $null }
    $item = $null
    try { $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop } catch { return $null }
    if ($null -eq $item -or -not $item.PSIsContainer) { return $null }
    try { if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $null } } catch { return $null }
    return $item
}

function Test-ProtectPathWithin {
    param([string]$Path, [string]$Root)
    $candidate = ConvertTo-ProtectPath -Path $Path -AllowMissing
    $base = ConvertTo-ProtectPath -Path $Root -AllowMissing
    if ($null -eq $candidate -or $null -eq $base) { return $false }
    if ($candidate.Equals($base, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    $prefix = $base
    if ($prefix.Length -gt 3) { $prefix = $prefix.TrimEnd('\') }
    if (-not $prefix.EndsWith('\')) { $prefix += '\' }
    return $candidate.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-ProtectRestoreTarget {
    param([string]$OriginalPath, [string]$ScanRoot)
    $original = ConvertTo-ProtectPath -Path $OriginalPath -AllowMissing
    $scan = ConvertTo-ProtectPath -Path $ScanRoot -AllowMissing
    if ($null -eq $original -or $null -eq $scan) { return $false }
    $roots = @(
        $env:TEMP,
        (Join-Path $env:USERPROFILE 'Downloads'),
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp')
    )
    foreach ($candidate in $roots) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) { continue }
        $root = ConvertTo-ProtectPath -Path ([string]$candidate) -AllowMissing
        if ($null -eq $root) { continue }
        if ((Test-ProtectPathWithin -Path $original -Root $root) -and (Test-ProtectPathWithin -Path $scan -Root $root)) { return $true }
    }
    return $false
}

function Set-ProtectDirectoryAcl {
    param([string]$Path)
    $full = ConvertTo-ProtectPath -Path $Path -AllowMissing
    if ($null -eq $full) { return $false }
    $item = $null
    try { $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop } catch { return $false }
    if ($null -eq $item -or -not $item.PSIsContainer) { return $false }
    try {
        $acl = New-Object System.Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)
        $systemSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
        $adminSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
        $inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        $none = [System.Security.AccessControl.PropagationFlags]::None
        $allow = [System.Security.AccessControl.AccessControlType]::Allow
        $rights = [System.Security.AccessControl.FileSystemRights]::FullControl
        $acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($systemSid, $rights, $inherit, $none, $allow)))
        $acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($adminSid, $rights, $inherit, $none, $allow)))
        $acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($systemSid, $rights, [System.Security.AccessControl.InheritanceFlags]::None, $none, $allow)))
        $acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($adminSid, $rights, [System.Security.AccessControl.InheritanceFlags]::None, $none, $allow)))
        $acl.SetOwner($adminSid)
        Set-Acl -LiteralPath $full -AclObject $acl
        return $true
    } catch { return $false }
}

function Set-ProtectFileAcl {
    param([string]$Path)
    $full = ConvertTo-ProtectPath -Path $Path
    if ($null -eq $full) { return $false }
    try {
        $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
        if ($item.PSIsContainer) { return $false }
        $acl = New-Object System.Security.AccessControl.FileSecurity
        $systemSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
        $adminSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
        $none = [System.Security.AccessControl.InheritanceFlags]::None
        $prop = [System.Security.AccessControl.PropagationFlags]::None
        $allow = [System.Security.AccessControl.AccessControlType]::Allow
        $rights = [System.Security.AccessControl.FileSystemRights]::FullControl
        $acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($systemSid, $rights, $none, $prop, $allow)))
        $acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($adminSid, $rights, $none, $prop, $allow)))
        $acl.SetOwner($adminSid)
        Set-Acl -LiteralPath $full -AclObject $acl
        return $true
    } catch { return $false }
}

function Set-ProtectFileAclFromSddl {
    param([string]$Path, [string]$Sddl)
    if ([string]::IsNullOrWhiteSpace($Sddl) -or $Sddl.Length -gt 8192 -or -not $Sddl.StartsWith('O:', [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    try {
        $full = ConvertTo-ProtectPath -Path $Path
        if ($null -eq $full) { return $false }
        $acl = New-Object System.Security.AccessControl.FileSecurity
        $acl.SetSecurityDescriptorSddlForm($Sddl)
        Set-Acl -LiteralPath $full -AclObject $acl
        return $true
    } catch { return $false }
}

function Get-ProtectQuarantineRoot {
    $base = ''
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramData)) { $base = Join-Path $env:ProgramData 'PotatoPC\quarantine' }
    else { $base = Join-Path ([string]$script:WorkFolder) 'quarantine' }
    $root = ConvertTo-ProtectPath -Path $base -AllowMissing
    if ($null -eq $root) { return '' }
    $item = $null
    try { $item = Get-Item -LiteralPath $root -Force -ErrorAction Stop } catch {}
    if ($null -ne $item -and -not $item.PSIsContainer) { return '' }
    if ($null -ne $item -and -not (Set-ProtectDirectoryAcl -Path $root)) { return '' }
    return $root
}

function Get-ProtectQuarantineManifestPath {
    param([string]$Path)
    $root = Get-ProtectQuarantineRoot
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($root)) { return '' }
    $full = ConvertTo-ProtectPath -Path $Path -AllowMissing
    if ($null -eq $full) { return '' }
    $item = $null
    try { $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop } catch {}
    if ($null -ne $item -and $item.PSIsContainer) { $full = Join-Path $full 'manifest.json' }
    elseif ($null -eq $item -and [System.IO.Path]::GetExtension($full) -eq '') { $full = Join-Path $full 'manifest.json' }
    $full = ConvertTo-ProtectPath -Path $full -AllowMissing
    if ($null -eq $full -or -not (Test-ProtectPathWithin -Path $full -Root $root)) { return '' }
    return $full
}

function Get-ProtectFileFingerprint {
    param([string]$Path)
    $item = Get-ProtectFileInfo -Path $Path
    if ($null -eq $item) { return $null }
    $hash = $null
    try { $hash = [string](Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256 -ErrorAction Stop).Hash } catch { return $null }
    if ($hash -notmatch '^[0-9A-Fa-f]{64}$') { return $null }
    return [pscustomobject]@{ Path = [string]$item.FullName; Size = [long]$item.Length; Hash = $hash.ToUpperInvariant() }
}

function Get-TextSha256 {
    param([string]$Text)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes([string]$Text)))).Replace('-', '') }
        finally { $sha.Dispose() }
    } catch { return '' }
}

function Test-ProtectSha256 {
    param([string]$Path, [string]$Expected)
    if ([string]::IsNullOrWhiteSpace($Expected)) { return $false }
    try {
        $item = Get-ProtectFileInfo -Path $Path
        if ($null -eq $item) { return $false }
        $actual = [string](Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
        return [bool]($actual.Equals($Expected, [System.StringComparison]::OrdinalIgnoreCase))
    } catch { return $false }
}

function Test-ProtectFingerprint {
    param($Expected, [string]$Path)
    if ($null -eq $Expected) { return $false }
    $actual = Get-ProtectFileFingerprint -Path $Path
    if ($null -eq $actual) { return $false }
    try { $expectedHash = ([string]$Expected.Hash).ToUpperInvariant(); $expectedSize = [long]$Expected.Size } catch { return $false }
    if ($expectedHash -notmatch '^[0-9A-F]{64}$') { return $false }
    return [bool]($actual.Hash -eq $expectedHash -and $actual.Size -eq $expectedSize)
}

function Write-ProtectTextAtomic {
    param([string]$Path, [string]$Text)
    $full = ConvertTo-ProtectPath -Path $Path -AllowMissing
    if ($null -eq $full) { throw 'Небезопасный путь' }
    $parent = [System.IO.Path]::GetDirectoryName($full)
    if (-not (Test-ProtectPath -Path $parent -Directory)) { throw 'Нет безопасной папки' }
    $tmp = Join-Path $parent ('.protect-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $enc = New-Object System.Text.UTF8Encoding $false
    try {
        [System.IO.File]::WriteAllText($tmp, $Text, $enc)
        if (Test-Path -LiteralPath $full -ErrorAction SilentlyContinue) {
            try { [System.IO.File]::Replace($tmp, $full, $null, $true) }
            catch { Move-Item -LiteralPath $tmp -Destination $full -Force -ErrorAction Stop }
        } else { [System.IO.File]::Move($tmp, $full) }
        return $full
    } finally { if (Test-Path -LiteralPath $tmp -ErrorAction SilentlyContinue) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } }
}

function Write-ProtectJsonAtomic {
    param([string]$Path, $Value)
    $json = [string]($Value | ConvertTo-Json -Depth 10 -ErrorAction Stop)
    return Write-ProtectTextAtomic -Path $Path -Text $json
}

function Read-ProtectJsonFile {
    param([string]$Path)
    $full = ConvertTo-ProtectPath -Path $Path
    if ($null -eq $full) { return $null }
    try {
        $text = [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        return ($text | ConvertFrom-Json -ErrorAction Stop)
    } catch { return $null }
}

function New-ProtectQuarantineDirectory {
    $work = ConvertTo-ProtectPath -Path ([string]$script:WorkFolder) -AllowMissing
    if ($null -eq $work) { return '' }
    $workItem = Get-ProtectDirectoryInfo -Path $work
    if ($null -eq $workItem) {
        try { New-Item -ItemType Directory -Path $work -Force -ErrorAction Stop | Out-Null } catch { return '' }
        $workItem = Get-ProtectDirectoryInfo -Path $work
    }
    if ($null -eq $workItem) { return '' }
    $root = Get-ProtectQuarantineRoot
    if ([string]::IsNullOrWhiteSpace($root)) { return '' }
    $rootItem = Get-ProtectDirectoryInfo -Path $root
    if ($null -eq $rootItem) {
        try { New-Item -ItemType Directory -Path $root -Force -ErrorAction Stop | Out-Null } catch { return '' }
    }
    if (-not (Test-ProtectPath -Path $root -Directory)) { return '' }
    $rootParent = Split-Path $root -Parent
    if ($env:ProgramData -and $rootParent.StartsWith(([System.IO.Path]::GetFullPath($env:ProgramData).TrimEnd('\') + '\'), [System.StringComparison]::OrdinalIgnoreCase)) {
        if (-not (Set-ProtectDirectoryAcl -Path $rootParent)) { return '' }
    }
    if (-not (Set-ProtectDirectoryAcl -Path $root)) { return '' }
    $name = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + ([Guid]::NewGuid().ToString('N').Substring(0, 8))
    $batch = Join-Path $root $name
    try { New-Item -ItemType Directory -Path $batch -ErrorAction Stop | Out-Null } catch { return '' }
    $item = Get-ProtectDirectoryInfo -Path $batch
    if ($null -eq $item) { return '' }
    return [string]$item.FullName
}

function Save-QuarantineManifest {
    param([string]$ManifestPath, $Manifest)
    return Write-ProtectJsonAtomic -Path $ManifestPath -Value $Manifest
}

function ConvertFrom-ProtectYaraManifest {
    param([string]$Content)
    $names = New-Object System.Collections.ArrayList
    $valid = $true
    $error = ''
    if ($null -eq $Content) {
        $valid = $false
        $error = 'Пустой манифест'
    } else {
        if ($Content.Length -gt 1048576) { $valid = $false; $error = 'Манифест слишком большой' }
        foreach ($lineValue in @($Content -split "`r?`n")) {
            if (-not $valid) { break }
            $line = ([string]$lineValue).Trim()
            if ($line.Length -gt 0 -and [int][char]$line[0] -eq 0xfeff) { $line = $line.Substring(1) }
            if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
            if ($line -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.yar$') { $valid = $false; $error = 'Недопустимое имя: ' + $line; break }
            if ($line -match '^(?i:CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|COM[1-9]|LPT[1-9])(?:\..*)?$') { $valid = $false; $error = 'Зарещённое имя: ' + $line; break }
            if ($names -contains $line) { $valid = $false; $error = 'Повтор: ' + $line; break }
            [void]$names.Add($line)
            if ($names.Count -gt 4096) { $valid = $false; $error = 'Слишком много правил'; break }
        }
        if ($names.Count -eq 0 -and $valid) { $valid = $false; $error = 'В манифесте нет правил' }
    }
    $arr = @()
    foreach ($name in $names) { $arr += [string]$name }
    return [pscustomobject]@{ Valid = [bool]$valid; Names = $arr; Error = $error }
}

function Read-ProtectYaraManifest {
    param([string]$Path)
    try {
        $full = ConvertTo-ProtectPath -Path $Path
        if ($null -eq $full) { return $null }
        $text = [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
        $parsed = ConvertFrom-ProtectYaraManifest -Content $text
        if (-not $parsed.Valid) { return $null }
        return $parsed
    } catch { return $null }
}

function Get-YaraToolsDir {
    $base = ''
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramData)) { $base = Join-Path $env:ProgramData 'PotatoPC\tools' }
    else { $base = Join-Path ([string]$script:WorkFolder) 'tools' }
    $dir = ConvertTo-ProtectPath -Path $base -AllowMissing
    if ($null -eq $dir) { return '' }
    $item = $null
    try { $item = Get-Item -LiteralPath $dir -Force -ErrorAction Stop } catch {}
    if ($null -ne $item -and -not $item.PSIsContainer) { return '' }
    return $dir
}

function Get-YaraRulesDir {
    $base = ''
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramData)) { $base = Join-Path $env:ProgramData 'PotatoPC\protect-rules' }
    else { $base = Join-Path ([string]$script:WorkFolder) 'protect-rules' }
    $dir = ConvertTo-ProtectPath -Path $base -AllowMissing
    if ($null -eq $dir) { return '' }
    $item = $null
    try { $item = Get-Item -LiteralPath $dir -Force -ErrorAction Stop } catch {}
    if ($null -ne $item -and -not $item.PSIsContainer) { return '' }
    return $dir
}

function Get-YaraRulesManifestPath {
    $dir = Get-YaraRulesDir
    if ([string]::IsNullOrWhiteSpace($dir)) { return '' }
    return ConvertTo-ProtectPath -Path (Join-Path $dir 'rules.txt') -AllowMissing
}

function Test-YaraRuleSet {
    param([string]$RulesDir)
    try {
        $rd = ConvertTo-ProtectPath -Path $RulesDir
        $manifestPath = Join-Path $rd 'rules.txt'
        $manifestItem = Get-ProtectFileInfo -Path $manifestPath
        if ($null -eq $manifestItem) { return $false }
        $manifest = Read-ProtectYaraManifest -Path $manifestPath
        if ($null -eq $manifest) { return $false }
        $normalized = ((@($manifest.Names) -join "`n") + "`n")
        if ((Get-TextSha256 -Text $normalized) -ne [string]$script:YaraRulesManifestSha256) { return $false }
        $hashes = $script:YaraRuleHashes
        if ($null -eq $hashes -or $hashes.Count -eq 0) { return $false }
        $names = @($manifest.Names)
        if ($names.Count -ne $hashes.Count) { return $false }
        foreach ($name in $names) {
            if (-not $hashes.ContainsKey([string]$name)) { return $false }
            $file = Get-ProtectFileInfo -Path (Join-Path $rd ([string]$name))
            if ($null -eq $file -or -not (Test-ProtectSha256 -Path $file.FullName -Expected ([string]$hashes[[string]$name]))) { return $false }
            if (-not (Set-ProtectFileAcl -Path $file.FullName)) { return $false }
        }
        return $true
    } catch { return $false }
}

function Get-YaraVersion {
    param([string]$Exe, [int]$TimeoutSec = 3)
    $item = Get-ProtectFileInfo -Path $Exe
    if ($null -eq $item) { return '' }
    if (-not (Test-ProtectSha256 -Path $item.FullName -Expected $script:YaraEngineExeSha256)) { return '' }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $item.FullName
    $psi.Arguments = '--version'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = $null
    try {
        $p = [System.Diagnostics.Process]::Start($psi)
        if ($null -eq $p) { return '' }
        $outTask = $null
        $errTask = $null
        try { $outTask = $p.StandardOutput.ReadToEndAsync() } catch {}
        try { $errTask = $p.StandardError.ReadToEndAsync() } catch {}
        $ms = [Math]::Max(500, [Math]::Min(30000, $TimeoutSec * 1000))
        if (-not $p.WaitForExit($ms)) {
            try { $p.Kill() } catch {}
            try { $null = $p.WaitForExit(2000) } catch {}
            return ''
        }
        $text = ''
        try { if ($outTask -and $outTask.Wait(2000)) { $text = [string]$outTask.Result } } catch {}
        if ([string]::IsNullOrWhiteSpace($text)) { try { if ($errTask -and $errTask.Wait(1000)) { $text = [string]$errTask.Result } } catch {} }
        foreach ($line in @($text -split "`r?`n")) {
            if ($line -match '(?i)yara\s+v?([0-9]+(?:\.[0-9]+){1,3})') { return $Matches[1] }
            if ($line -match '(?i)v?([0-9]+\.[0-9]+(?:\.[0-9]+){0,2})') { return $Matches[1] }
        }
        return ''
    } catch { return '' }
    finally { if ($p) { try { $p.Dispose() } catch {} } }
}

function Get-YaraStatus {
    $st = @{ Exe = ''; Version = ''; RulesCount = 0; RulesExpectedCount = 0; RulesReady = $false; ManifestValid = $false; ManifestPath = ''; RulesError = ''; VersionError = '' }
    try {
        $tools = Get-YaraToolsDir
        if (-not [string]::IsNullOrWhiteSpace($tools)) {
            $exeItem = Get-ProtectFileInfo -Path (Join-Path $tools 'yara64.exe')
            if ($null -ne $exeItem) {
                if (Test-ProtectSha256 -Path $exeItem.FullName -Expected $script:YaraEngineExeSha256) {
                    $st.Exe = [string]$exeItem.FullName
                    $st.Version = Get-YaraVersion -Exe $st.Exe -TimeoutSec 3
                    if ([string]::IsNullOrWhiteSpace($st.Version)) { $st.VersionError = 'Не удалось получить версию' }
                } else { $st.VersionError = 'Хэш движка не совпадает' }
            }
        }
        $rd = Get-YaraRulesDir
        if (-not [string]::IsNullOrWhiteSpace($rd)) {
            $mp = Get-YaraRulesManifestPath
            $st.ManifestPath = [string]$mp
            $manifest = Read-ProtectYaraManifest -Path $mp
            $files = @()
            try { $files = @(Get-ChildItem -LiteralPath $rd -Filter '*.yar' -File -Force -ErrorAction SilentlyContinue) } catch {}
            $validFiles = @()
            foreach ($file in $files) {
                $fi = Get-ProtectFileInfo -Path $file.FullName
                if ($null -ne $fi -and [long]$fi.Length -gt 0) { $validFiles += $fi }
            }
            $st.RulesCount = $validFiles.Count
            if ($null -ne $manifest) {
                $st.ManifestValid = $true
                $st.RulesExpectedCount = @($manifest.Names).Count
                if (Test-YaraRuleSet -RulesDir $rd) {
                    $st.RulesReady = $true
                    $st.RulesCount = $st.RulesExpectedCount
                } else { $st.RulesError = 'Хэш или набор правил не прошёл проверку' }
            } else { $st.RulesError = 'Манифест правил отсутствует или неверен' }
        }
    } catch { $st.RulesError = 'Статус YARA недоступен' }
    return $st
}

function Ensure-YaraRules {
    param([string]$RulesDir, [hashtable]$Control = $null)
    $base = [string]$script:ProtectRulesBaseUrl
    $manifestUrl = [string]$script:ProtectRulesManifestUrl
    if ([string]::IsNullOrWhiteSpace($base)) { $base = 'https://raw.githubusercontent.com/Yara-Rules/rules/0f93570194a80d2f2032869055808b0ddcdfb360/malware' }
    if ([string]::IsNullOrWhiteSpace($manifestUrl)) { $manifestUrl = 'https://raw.githubusercontent.com/DezFix/PotatoPC/b5b26c3/protect/rules.txt' }
    try {
        Assert-OperationActive -Control $Control
        $rd = ConvertTo-ProtectPath -Path $RulesDir -AllowMissing
        if ($null -eq $rd) { return '' }
        $di = Get-ProtectDirectoryInfo -Path $rd
        if ($null -eq $di) {
            try { New-Item -ItemType Directory -Path $rd -Force -ErrorAction Stop | Out-Null } catch { return '' }
            $di = Get-ProtectDirectoryInfo -Path $rd
        }
        if ($null -eq $di) { return '' }
        if (-not (Set-ProtectDirectoryAcl -Path $rd)) { return '' }
        $manifestPath = Join-Path $rd 'rules.txt'
        $manifestItem = $null
        try { $manifestItem = Get-Item -LiteralPath $manifestPath -Force -ErrorAction Stop } catch {}
        if ($null -ne $manifestItem -and ($manifestItem.PSIsContainer -or (($manifestItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0))) { return '' }
        if ($null -ne $manifestItem -and -not (Set-ProtectFileAcl -Path $manifestItem.FullName)) { return '' }
        $remote = $null
        try {
            Assert-OperationActive -Control $Control
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
             $response = Invoke-WebRequest -Uri $manifestUrl -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
            $content = $response.Content
            if ($content -is [byte[]]) { $content = [System.Text.Encoding]::UTF8.GetString($content) }
             $remote = ConvertFrom-ProtectYaraManifest -Content ([string]$content)
             if ($remote.Valid) {
                 $normalized = ((@($remote.Names) -join "`n") + "`n")
                 if ((Get-TextSha256 -Text $normalized) -ne [string]$script:YaraRulesManifestSha256) { $remote.Valid = $false; $remote.Error = 'Хэш списка правил не совпадает' }
             }
             if (-not $remote.Valid) { Write-Log ('[!] Манифест правил отклонён: ' + $remote.Error) -Color 'Yellow' }
        } catch {
            if (Test-OperationCancelled $Control) { throw 'STOPPED_BY_USER' }
            Write-Log ('[!] Манифест правил не скачался, проверяю кэш: ' + $_.Exception.Message) -Color 'Yellow'
        }
        if ($null -ne $remote -and $remote.Valid) {
            $names = @($remote.Names)
            try { [void](Write-ProtectTextAtomic -Path $manifestPath -Text (($names -join "`n") + "`n")) } catch { return '' }
        } else {
             $local = Read-ProtectYaraManifest -Path $manifestPath
             if ($null -eq $local) { return '' }
             $localNormalized = ((@($local.Names) -join "`n") + "`n")
             if ((Get-TextSha256 -Text $localNormalized) -ne [string]$script:YaraRulesManifestSha256) { return '' }
             $names = @($local.Names)
        }
        if ($names.Count -eq 0) { return '' }
        $failed = 0
        foreach ($name in $names) {
            Assert-OperationActive -Control $Control
             $destination = Join-Path $rd $name
             $expectedHash = ''
             try { if ($script:YaraRuleHashes -and $script:YaraRuleHashes.ContainsKey([string]$name)) { $expectedHash = [string]$script:YaraRuleHashes[[string]$name] } } catch {}
             if ($expectedHash -notmatch '^[0-9A-F]{64}$') { $failed++; continue }
             $item = $null
            try { $item = Get-Item -LiteralPath $destination -Force -ErrorAction Stop } catch {}
            $usable = $false
            if ($null -ne $item) {
                $reparse = $false
                try { $reparse = (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) } catch {}
                if ($reparse) { $failed++; Write-Log ('  Небезопасная ссылка правила: ' + $name) -Color 'Yellow'; continue }
                try { $usable = (-not $item.PSIsContainer -and [long]$item.Length -gt 0 -and (Test-ProtectSha256 -Path $item.FullName -Expected $expectedHash)) } catch {}
                if (-not $usable) {
                    try { Remove-Item -LiteralPath $destination -Force -ErrorAction Stop } catch { $failed++; continue }
                }
            }
            if ($usable) {
                if (-not (Set-ProtectFileAcl -Path $item.FullName)) { $failed++ }
                continue
            }
            $tmp = Join-Path $rd ('.rule-' + [Guid]::NewGuid().ToString('N') + '.tmp')
            try {
                Assert-OperationActive -Control $Control
                 Invoke-WebRequest -Uri ($base.TrimEnd('/') + '/' + [System.Uri]::EscapeDataString([string]$name)) -OutFile $tmp -UseBasicParsing -TimeoutSec 45 -ErrorAction Stop
                 $downloaded = Get-ProtectFileInfo -Path $tmp
                 if ($null -eq $downloaded -or [long]$downloaded.Length -le 0) { throw 'Пустое правило' }
                 if (-not (Test-ProtectSha256 -Path $tmp -Expected $expectedHash)) { throw 'Хэш правила не совпадает' }
                if (Test-Path -LiteralPath $destination -ErrorAction SilentlyContinue) {
                    $old = $null
                    try { $old = Get-Item -LiteralPath $destination -Force -ErrorAction Stop } catch {}
                    if ($null -eq $old -or $old.PSIsContainer -or (($old.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'Путь назначения занят' }
                    Remove-Item -LiteralPath $destination -Force -ErrorAction Stop
                }
                Move-Item -LiteralPath $tmp -Destination $destination -ErrorAction Stop
                if (-not (Set-ProtectFileAcl -Path $destination)) { throw 'Не удалось защитить файл правила' }
            } catch {
                if (Test-OperationCancelled $Control) { throw 'STOPPED_BY_USER' }
                $failed++
                Write-Log ('  Правило не скачалось: ' + $name) -Color 'Yellow'
            } finally { if (Test-Path -LiteralPath $tmp -ErrorAction SilentlyContinue) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } }
        }
        $missing = 0
        foreach ($name in $names) {
            $item = Get-ProtectFileInfo -Path (Join-Path $rd $name)
            if ($null -eq $item -or [long]$item.Length -le 0) { $missing++ }
        }
        if ($failed -gt 0 -or $missing -gt 0) {
            Write-Log ('[!] Набор YARA неполный: отсутствует ' + $missing + ', ошибок ' + $failed) -Color 'Yellow'
            return ''
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $rd -Filter '*.yar' -File -Force -ErrorAction SilentlyContinue)) {
            if ($names -notcontains $file.Name) {
                try { if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue } } catch {}
            }
        }
        if (-not (Test-YaraRuleSet -RulesDir $rd)) { return '' }
        Write-Log ('Правила YARA готовы: ' + $names.Count) -Color 'Green'
        return $rd
    } catch {
        if (Test-OperationCancelled $Control) { throw }
        Write-Log ('[!] Набор YARA не готов: ' + $_.Exception.Message) -Color 'Yellow'
        return ''
    }
}

function Ensure-YaraEngine {
    param([string]$ToolsDir, [hashtable]$Control = $null)
    $engineUrl = 'https://github.com/VirusTotal/yara/releases/download/v4.5.5/yara-4.5.5-2368-win64.zip'
    $zip = $null
    $tmp = $null
    try {
        Assert-OperationActive -Control $Control
        $tools = ConvertTo-ProtectPath -Path $ToolsDir -AllowMissing
        if ($null -eq $tools) { return '' }
        $ti = Get-ProtectDirectoryInfo -Path $tools
        if ($null -eq $ti) {
            try { New-Item -ItemType Directory -Path $tools -Force -ErrorAction Stop | Out-Null } catch { return '' }
        }
        if (-not (Test-ProtectPath -Path $tools -Directory)) { return '' }
        if (-not (Set-ProtectDirectoryAcl -Path $tools)) { return '' }
        $exe = Join-Path $tools 'yara64.exe'
        $existing = Get-ProtectFileInfo -Path $exe
        if ($null -ne $existing -and [long]$existing.Length -gt 0) {
            if (Test-ProtectSha256 -Path $existing.FullName -Expected $script:YaraEngineExeSha256) {
                if (Set-ProtectFileAcl -Path $existing.FullName) { return $exe }
                return ''
            }
            try { Remove-Item -LiteralPath $exe -Force -ErrorAction Stop } catch { return '' }
        }
        Assert-OperationActive -Control $Control
        Write-Log 'Качаю движок YARA (разово, ~5 МБ)...'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $zip = Join-Path $tools ('.yara-' + [Guid]::NewGuid().ToString('N') + '.zip')
        $tmp = Join-Path $tools ('.yara-unpack-' + [Guid]::NewGuid().ToString('N'))
        Invoke-WebRequest -Uri $engineUrl -OutFile $zip -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
        if (-not (Test-ProtectPath -Path $zip -Leaf)) { throw 'Архив YARA не скачан' }
        if (-not (Test-ProtectSha256 -Path $zip -Expected $script:YaraEngineZipSha256)) { throw 'Хэш архива YARA не совпадает' }
        try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop } catch {}
        $archive = $null
        try {
            $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
            foreach ($entry in $archive.Entries) {
                $entryName = ([string]$entry.FullName).Replace('/', '\')
                if ([System.IO.Path]::IsPathRooted($entryName) -or $entryName -match '(^|\\)\.\.(\\|$)' -or $entryName -match '(^|\\)\.(\\|$)' -or $entryName.Contains(':')) { throw 'Небезопасный путь в архиве YARA' }
            }
        } finally { if ($archive) { $archive.Dispose() } }
        Expand-Archive -Path $zip -DestinationPath $tmp -Force -ErrorAction Stop
        $found = $null
        foreach ($file in @(Get-ChildItem -LiteralPath $tmp -Filter 'yara64.exe' -File -Recurse -Force -ErrorAction SilentlyContinue)) {
            $fi = Get-ProtectFileInfo -Path $file.FullName
            if ($null -ne $fi) { $found = $fi; break }
        }
        if ($null -eq $found) { throw 'yara64.exe нет в архиве' }
        Move-Item -LiteralPath $found.FullName -Destination $exe -ErrorAction Stop
        if (-not (Set-ProtectFileAcl -Path $exe)) { throw 'Не удалось защитить файл движка YARA' }
        if (-not (Test-ProtectSha256 -Path $exe -Expected $script:YaraEngineExeSha256)) { Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue; throw 'Хэш движка YARA не совпадает' }
        $result = Get-ProtectFileInfo -Path $exe
        if ($null -eq $result -or [long]$result.Length -le 0) { throw 'Движок не проверен' }
        Write-Log 'Движок готов.' -Color 'Green'
        return $exe
    } catch {
        if (Test-OperationCancelled $Control) { throw }
        Write-Log ('Не вышло скачать движок: ' + $_.Exception.Message) -Color 'Red'
        return ''
    } finally {
        if ($tmp -and (Test-Path -LiteralPath $tmp -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        if ($zip -and (Test-Path -LiteralPath $zip -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }
    }
}

function Combine-YaraRules {
    param([string]$RulesDir, [string]$OutFile, [hashtable]$Control = $null)
    try {
        Assert-OperationActive -Control $Control
        $rd = ConvertTo-ProtectPath -Path $RulesDir
        $rdItem = Get-ProtectDirectoryInfo -Path $rd
        if ($null -eq $rdItem) { return '' }
        $manifestPath = Join-Path $rd 'rules.txt'
        $names = @()
        $manifestItem = $null
        try { $manifestItem = Get-Item -LiteralPath $manifestPath -Force -ErrorAction Stop } catch {}
        if ($null -ne $manifestItem) {
            if ($manifestItem.PSIsContainer -or (($manifestItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) { return '' }
            $manifest = Read-ProtectYaraManifest -Path $manifestPath
            if ($null -eq $manifest) { return '' }
            $names = @($manifest.Names)
        } else {
            $files = @(Get-ChildItem -LiteralPath $rd -Filter '*.yar' -File -Force -ErrorAction Stop)
            $names = @($files | ForEach-Object { [string]$_.Name })
        }
        if ($names.Count -eq 0) { return '' }
        $out = ConvertTo-ProtectPath -Path $OutFile -AllowMissing
        if ($null -eq $out) { return '' }
        $outParent = [System.IO.Path]::GetDirectoryName($out)
        if (-not (Test-ProtectPath -Path $outParent -Directory)) { return '' }
        $outItem = $null
        try { $outItem = Get-Item -LiteralPath $out -Force -ErrorAction Stop } catch {}
        if ($null -ne $outItem -and ($outItem.PSIsContainer -or (($outItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0))) { return '' }
        $prefix = $rd.TrimEnd('\')
        if (-not $prefix.EndsWith('\')) { $prefix += '\' }
        $builder = New-Object System.Text.StringBuilder
        $decoder = New-Object System.Text.UTF8Encoding($false, $true)
        foreach ($name in $names) {
            Assert-OperationActive -Control $Control
            if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.yar$') { return '' }
            $source = Join-Path $rd $name
            $sourceFull = ConvertTo-ProtectPath -Path $source
            if ($null -eq $sourceFull -or -not $sourceFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return '' }
            $item = Get-ProtectFileInfo -Path $sourceFull
            if ($null -eq $item -or [long]$item.Length -le 0) { return '' }
            try {
                $text = $decoder.GetString([System.IO.File]::ReadAllBytes($sourceFull))
                if ([string]::IsNullOrWhiteSpace($text)) { return '' }
                [void]$builder.AppendLine()
                [void]$builder.Append($text)
                [void]$builder.AppendLine()
            } catch { return '' }
        }
        if ($builder.Length -le 0) { return '' }
        $tmp = Join-Path $outParent ('.combined-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        try {
            [System.IO.File]::WriteAllText($tmp, $builder.ToString(), (New-Object System.Text.UTF8Encoding($false)))
            if (Test-Path -LiteralPath $out -ErrorAction SilentlyContinue) {
                try { [System.IO.File]::Replace($tmp, $out, $null, $true) }
                catch { Move-Item -LiteralPath $tmp -Destination $out -Force -ErrorAction Stop }
            } else { [System.IO.File]::Move($tmp, $out) }
            if (-not (Set-ProtectFileAcl -Path $out)) { return '' }
            return $out
        } finally { if (Test-Path -LiteralPath $tmp -ErrorAction SilentlyContinue) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } }
    } catch {
        if (Test-OperationCancelled $Control) { throw }
        return ''
    }
}

function Invoke-YaraEntry {
    param([string]$Exe, [string]$Rules, [string]$Target, [hashtable]$Control, [int]$TimeoutSec = 180, [string]$OperationId = '')
    $exeItem = Get-ProtectFileInfo -Path $Exe
    $rulesItem = Get-ProtectFileInfo -Path $Rules
    $targetFull = ConvertTo-ProtectPath -Path $Target
    if ($null -eq $targetFull) { throw 'Недопустимый путь YARA' }
    $targetItem = $null
    try { $targetItem = Get-Item -LiteralPath $targetFull -Force -ErrorAction Stop } catch { throw 'Недопустимый путь YARA' }
    if ($null -eq $exeItem -or $null -eq $rulesItem -or $null -eq $targetItem) { throw 'Недопустимый объект YARA' }
    try {
        if (($targetItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Недопустимая ссылка YARA' }
    } catch { throw }
    if ($OperationId -and $Control -and $Control.OperationId -and ([string]$Control.OperationId -ne $OperationId)) { throw 'STOPPED_BY_USER' }
    Assert-OperationActive -Control $Control
    if (-not (Test-ProtectSha256 -Path $exeItem.FullName -Expected $script:YaraEngineExeSha256)) { throw 'Хэш движка YARA изменился' }
    function Quote-ProcessArgument([string]$Value) {
        $text = $Value
        if ($text.Length -gt 3) { $text = $text.TrimEnd('\') }
        return '"' + $text.Replace('"', '\"') + '"'
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exeItem.FullName
    $psi.Arguments = '-N -w -r ' + (Quote-ProcessArgument $rulesItem.FullName) + ' ' + (Quote-ProcessArgument $targetItem.FullName)
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = $null
    try { $p = [System.Diagnostics.Process]::Start($psi) } catch { throw ('Не запустился сканер: ' + $_.Exception.Message) }
    if ($null -eq $p) { throw 'Не запустился сканер' }
    try {
        if ($Control) { try { $Control.ChildPid = $p.Id } catch {} }
        $outTask = $null
        $errTask = $null
        try { $outTask = $p.StandardOutput.ReadToEndAsync() } catch {}
        try { $errTask = $p.StandardError.ReadToEndAsync() } catch {}
        $timeoutMs = [Math]::Max(1000, [Math]::Min(2147483, $TimeoutSec * 1000))
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $exited = $false
        while (-not $exited) {
            Assert-OperationActive -Control $Control
            $exited = $p.WaitForExit(250)
            if (-not $exited -and $watch.Elapsed.TotalMilliseconds -ge $timeoutMs) {
                try { $p.Kill() } catch {}
                try { $null = $p.WaitForExit(3000) } catch {}
                return @{ TimedOut = $true; ExitCode = -1; Lines = @(); Error = '' }
            }
        }
        Assert-OperationActive -Control $Control
        $stdout = ''
        $stderr = ''
        try { if ($outTask -and $outTask.Wait(3000)) { $stdout = [string]$outTask.Result } } catch {}
        try { if ($errTask -and $errTask.Wait(3000)) { $stderr = [string]$errTask.Result } } catch {}
        return @{ TimedOut = $false; ExitCode = [int]$p.ExitCode; Lines = @($stdout -split "`r?`n" | Where-Object { $_ -match '\S' }); Error = $stderr.Trim() }
    } finally {
        if ($Control) { try { $Control.ChildPid = 0 } catch {} }
        try { if (-not $p.HasExited) { $p.Kill(); $null = $p.WaitForExit(3000) } } catch {}
        try { $p.Dispose() } catch {}
    }
}

function Update-ScanCount {
    $selected = 0
    $total = 0
    try {
        $total = @($script:ScanCheckboxes.Values).Count
        $selected = @($script:ScanCheckboxes.Values | Where-Object { $_ -and $_.Box -and $_.Box.IsChecked }).Count
    } catch {}
    try { if ($scanCountText) { $scanCountText.Text = "Выбрано: $selected из $total" } } catch {}
    try { Update-HeaderCount } catch {}
}

function Get-ProtectDefenderStatus {
    $result = @{ Ok = $false; Active = $false; Mode = ''; SigAge = $null; SigUpdated = ''; SigVersion = ''; RealTime = $false; Error = '' }
    $raw = $null
    try { $raw = Get-MpComputerStatus -ErrorAction Stop } catch {}
    if ($null -ne $raw) {
        $result.Ok = $true
        try { $result.Mode = [string]$raw.AMRunningMode } catch {}
        try { if ($null -ne $raw.AntivirusSignatureAge) { $result.SigAge = [int]$raw.AntivirusSignatureAge } } catch {}
        try { if ($raw.AntivirusSignatureLastUpdated) { $result.SigUpdated = [string]$raw.AntivirusSignatureLastUpdated } } catch {}
        try { if ($raw.AntivirusSignatureVersion) { $result.SigVersion = [string]$raw.AntivirusSignatureVersion } } catch {}
        $antivirus = $true
        $realtime = $true
        try { if ($null -ne $raw.AntivirusEnabled) { $antivirus = [bool]$raw.AntivirusEnabled } } catch {}
        try { if ($null -ne $raw.RealTimeProtectionEnabled) { $realtime = [bool]$raw.RealTimeProtectionEnabled } } catch {}
        $result.RealTime = $realtime
        $result.Active = [bool]($antivirus -and $realtime -and $result.Mode -and $result.Mode -notmatch '(?i)disabled|offline|passive')
    } else {
        try {
            $legacy = Get-DefenderStatus
            if ($legacy -and $legacy.Ok) {
                $result.Ok = $true
                $result.Mode = [string]$legacy.Mode
                if ($null -ne $legacy.SigAge) { $result.SigAge = [int]$legacy.SigAge }
                $result.Active = [bool](-not [string]::IsNullOrWhiteSpace($result.Mode) -and $result.Mode -notmatch '(?i)disabled|offline|passive')
            } else { $result.Error = 'Defender недоступен' }
        } catch { $result.Error = 'Defender недоступен' }
    }
    if ($result.Ok -and $null -eq $result.SigAge -and -not [string]::IsNullOrWhiteSpace($result.SigUpdated)) {
        try { $result.SigAge = [int]((Get-Date) - [datetime]$result.SigUpdated).TotalDays; if ($result.SigAge -lt 0) { $result.SigAge = 0 } } catch {}
    }
    return $result
}

function Get-ProtectQuarantineSummary {
    $result = @{ Batches = 0; Files = 0; Restorable = 0; Root = ''; Known = $false; Error = '' }
    $root = Get-ProtectQuarantineRoot
    if ([string]::IsNullOrWhiteSpace($root)) { $result.Error = 'Карантин недоступен'; return $result }
    $result.Root = $root
    try {
        $rootItem = $null
        try { $rootItem = Get-Item -LiteralPath $root -Force -ErrorAction Stop } catch {}
        if ($null -eq $rootItem) { $result.Known = $true; return $result }
        if (-not $rootItem.PSIsContainer) { $result.Error = 'Путь карантина повреждён'; return $result }
        $result.Known = $true
        foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction Stop)) {
            $manifestPath = Join-Path $dir.FullName 'manifest.json'
            if (-not (Test-ProtectPath -Path $manifestPath -Leaf)) { $result.Known = $false; $result.Error = 'Повреждённый карантин'; continue }
            $manifest = Read-QuarantineManifest -ManifestPath $manifestPath
            if ($null -eq $manifest) { $result.Known = $false; $result.Error = 'Недействительный манифест карантина'; continue }
            $result.Batches++
            foreach ($item in @($manifest.Items)) {
                $result.Files++
                if ([string]$item.State -eq 'QUARANTINED' -and (Test-ProtectPath -Path ([string]$item.QuarantinePath) -Leaf)) { $result.Restorable++ }
            }
        }
    } catch { $result.Known = $false; $result.Error = 'Ошибка чтения карантина: ' + $_.Exception.Message }
    return $result
}

function Build-ProtectPanel {
    if ($null -eq $protectPanel) { [Console]::WriteLine('PotatoPC: этот файл — часть приложения. Запускай menu.ps1'); return }
    $protectPanel.Children.Clear()
    $script:ScanCheckboxes = @{}
    $st = Get-YaraStatus
    $ds = $null
    try { $ds = Get-ProtectDefenderStatus } catch {}
    $fwOff = 0
    try { $fwOff = @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { -not $_.Enabled }).Count } catch {}
    $quarantine = Get-ProtectQuarantineSummary
    $defenderValue = 'недоступен'
    $defenderGood = $false
    if ($ds -and $ds.Ok) {
        $mode = if ([string]::IsNullOrWhiteSpace([string]$ds.Mode)) { 'режим неизвестен' } else { [string]$ds.Mode }
        $signature = if ($null -ne $ds.SigAge) { "подпись $([int]$ds.SigAge) дн." } else { 'подпись неизвестна' }
        $defenderValue = "$mode, $signature"
        $defenderGood = [bool]($ds.Active -and $null -ne $ds.SigAge -and [int]$ds.SigAge -le 7)
    }
    $yaraValue = if ($st.Exe -and $st.Version) { "есть ($($st.Version))" } elseif ($st.Exe) { 'есть, версия недоступна' } else { 'скачается при проверке' }
    $rulesValue = if ($st.RulesReady) { "$($st.RulesCount) файлов" } elseif ($st.ManifestValid -and $st.RulesExpectedCount -gt 0) { "$($st.RulesCount) из $($st.RulesExpectedCount), неполно" } else { 'нет полного набора' }
    if (-not $quarantine.Known) { $quarantineValue = 'неизвестно'; $quarantineGood = $false }
    elseif ($quarantine.Files -gt 0) { $quarantineValue = "$($quarantine.Files) файлов, восстановить: $($quarantine.Restorable)"; $quarantineGood = $false }
    else { $quarantineValue = 'пусто'; $quarantineGood = $true }
    $protectPanel.Children.Add((New-CategoryHeader -Title 'Состояние')) | Out-Null
    $rows = @(
        @{ L = 'Defender'; V = $defenderValue; Good = $defenderGood },
        @{ L = 'Движок YARA'; V = $yaraValue; Good = [bool]$st.Exe },
        @{ L = 'Правила'; V = $rulesValue; Good = [bool]$st.RulesReady },
        @{ L = 'Карантин'; V = $quarantineValue; Good = $quarantineGood },
        @{ L = 'Брандмауэр'; V = $(if ($fwOff -eq 0) { 'включён везде' } else { "выключен: $fwOff" }); Good = ($fwOff -eq 0) }
    )
    foreach ($row in $rows) {
        $card = New-Card
        $grid = [System.Windows.Controls.Grid]::new()
        $left = [System.Windows.Controls.ColumnDefinition]::new(); $left.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $right = [System.Windows.Controls.ColumnDefinition]::new(); $right.Width = [System.Windows.GridLength]::new([System.Windows.GridUnitType]::Auto)
        $grid.ColumnDefinitions.Add($left); $grid.ColumnDefinitions.Add($right)
        $label = [System.Windows.Controls.TextBlock]::new(); $label.Text = [string]$row.L; $label.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom('#8a8aa5'); $label.FontSize = 12; $label.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($label, 0); $grid.Children.Add($label) | Out-Null
        $value = [System.Windows.Controls.TextBlock]::new(); $value.Text = [string]$row.V; $value.FontSize = 12; $value.FontWeight = 'SemiBold'; $value.VerticalAlignment = 'Center'; $value.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom($(if ($row.Good) { '#2ecc71' } else { '#f0c040' }))
        [System.Windows.Controls.Grid]::SetColumn($value, 1); $grid.Children.Add($value) | Out-Null
        $card.Child = $grid; $protectPanel.Children.Add($card) | Out-Null
    }
    try { if ($protectStatusText) { $protectStatusText.Text = 'Defender: ' + $defenderValue } } catch {}
    try { if ($restoreQuarantineBtn) { $restoreQuarantineBtn.IsEnabled = ($quarantine.Restorable -gt 0) } } catch {}
    $protectPanel.Children.Add((New-CategoryHeader -Title 'Находки')) | Out-Null
    $script:ScanResultsBox = [System.Windows.Controls.StackPanel]::new()
    $protectPanel.Children.Add($script:ScanResultsBox) | Out-Null
    if ($null -ne $script:ProtectLastScan) {
        Render-ScanHits -Items @($script:ProtectLastScan.Items) -Complete ([bool]$script:ProtectLastScan.Complete) -Errors ([int]$script:ProtectLastScan.Errors) -TimedOut ([int]$script:ProtectLastScan.TimedOut) -Cancelled ([bool]$script:ProtectLastScan.Cancelled) -FailureMessage ([string]$script:ProtectLastScan.FailureMessage)
    } else {
        $hint = [System.Windows.Controls.TextBlock]::new(); $hint.Text = 'Пока пусто — нажми «Проверить».'; $hint.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom('#8a8ab0'); $hint.FontSize = 12; $hint.TextAlignment = 'Center'; $hint.Margin = [System.Windows.Thickness]::new(0, 20, 0, 20)
        $script:ScanResultsBox.Children.Add($hint) | Out-Null
        Update-ScanCount
    }
}

function Render-ScanHits {
    param($Items, [bool]$Complete = $true, [int]$Errors = 0, [int]$TimedOut = 0, [bool]$Cancelled = $false, [string]$FailureMessage = '')
    if ($null -eq $protectPanel -or $null -eq $script:ScanResultsBox) { return }
    $list = @()
    foreach ($rawHit in @($Items)) {
        if ($null -eq $rawHit) { continue }
        if ($rawHit -is [System.Collections.IDictionary]) {
            $rule = [string]$rawHit['Rule']; $file = [string]$rawHit['File']
        } else {
            $rule = [string]$rawHit.Rule; $file = [string]$rawHit.File
        }
        if (-not [string]::IsNullOrWhiteSpace($rule) -or -not [string]::IsNullOrWhiteSpace($file)) { $list += [pscustomobject]@{ Rule = $rule; File = $file } }
    }
    $script:ProtectLastScan = @{ Items = @($list); Complete = $Complete; Errors = $Errors; TimedOut = $TimedOut; Cancelled = $Cancelled; FailureMessage = $FailureMessage }
    $script:ScanRunning = $false; $script:ScanHandle = $null
    try { if ($script:ScanBtnText) { $scanBtn.Content = $script:ScanBtnText }; $scanBtn.Style = $window.FindResource('BtnPrimary') } catch {}
    try { if ($protectStatusText) { $protectStatusText.Text = if ($list.Count -gt 0) { ("Проверка: находок — " + $list.Count) } elseif ($Cancelled) { 'Проверка остановлена' } elseif (-not $Complete) { 'Проверка завершилась с ошибками' } else { 'Проверка завершена: находок нет' } } } catch {}
    $script:ScanResultsBox.Children.Clear(); $script:ScanCheckboxes = @{}
    if ($Cancelled) {
        $text = [System.Windows.Controls.TextBlock]::new(); $text.Text = 'Проверка остановлена пользователем.'; $text.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom('#f0c040'); $text.FontSize = 12; $text.TextAlignment = 'Center'; $text.TextWrapping = 'Wrap'; $text.Margin = [System.Windows.Thickness]::new(0, 20, 0, 20); $script:ScanResultsBox.Children.Add($text) | Out-Null
    } elseif (-not $Complete) {
        $message = if (-not [string]::IsNullOrWhiteSpace($FailureMessage)) { $FailureMessage } else { ("Проверка завершилась с ошибками: " + $Errors) }
        $text = [System.Windows.Controls.TextBlock]::new(); $text.Text = $message; $text.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom('#f0c040'); $text.FontSize = 12; $text.TextAlignment = 'Center'; $text.TextWrapping = 'Wrap'; $text.Margin = [System.Windows.Thickness]::new(0, 20, 0, 20); $script:ScanResultsBox.Children.Add($text) | Out-Null
    } elseif ($list.Count -eq 0) {
        $text = [System.Windows.Controls.TextBlock]::new(); $text.Text = 'Чисто — ничего не найдено.'; $text.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom('#2ecc71'); $text.FontSize = 12; $text.TextAlignment = 'Center'; $text.Margin = [System.Windows.Thickness]::new(0, 20, 0, 20); $script:ScanResultsBox.Children.Add($text) | Out-Null
    }
    $index = 0
    foreach ($hit in $list) {
        $key = "h$index"; $index++
        $card = New-Card; $grid = [System.Windows.Controls.Grid]::new()
        $checkColumn = [System.Windows.Controls.ColumnDefinition]::new(); $checkColumn.Width = [System.Windows.GridLength]::new(28)
        $textColumn = [System.Windows.Controls.ColumnDefinition]::new(); $textColumn.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $grid.ColumnDefinitions.Add($checkColumn); $grid.ColumnDefinitions.Add($textColumn)
        $check = [System.Windows.Controls.CheckBox]::new(); $check.VerticalAlignment = 'Center'; $check.Tag = $key; $check.Add_Checked({ Update-ScanCount }); $check.Add_Unchecked({ Update-ScanCount }); [System.Windows.Controls.Grid]::SetColumn($check, 0); $grid.Children.Add($check) | Out-Null
        $stack = [System.Windows.Controls.StackPanel]::new(); $stack.VerticalAlignment = 'Center'
        $rule = [System.Windows.Controls.TextBlock]::new(); $rule.Text = [string]$hit.Rule; $rule.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom('#f87171'); $rule.FontSize = 12; $rule.FontWeight = 'SemiBold'
        $file = [System.Windows.Controls.TextBlock]::new(); $file.Text = [string]$hit.File; $file.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom('#9898c8'); $file.FontSize = 10; $file.TextTrimming = 'CharacterEllipsis'
        $stack.Children.Add($rule) | Out-Null; $stack.Children.Add($file) | Out-Null; [System.Windows.Controls.Grid]::SetColumn($stack, 1); $grid.Children.Add($stack) | Out-Null
        $card.Child = $grid; $script:ScanResultsBox.Children.Add($card) | Out-Null
        $script:ScanCheckboxes[$key] = @{ Box = $check; Rule = [string]$hit.Rule; File = [string]$hit.File }
    }
    Update-ScanCount
}

function Get-ProtectScanTargets {
    $output = New-Object System.Collections.ArrayList
    $candidates = New-Object System.Collections.ArrayList
    if ($env:TEMP) { [void]$candidates.Add([string]$env:TEMP) }
    if ($env:USERPROFILE) { [void]$candidates.Add((Join-Path $env:USERPROFILE 'Downloads')); [void]$candidates.Add((Join-Path $env:USERPROFILE 'Desktop')) }
    if ($env:APPDATA) { [void]$candidates.Add((Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup')) }
    if ($env:ProgramData) { [void]$candidates.Add((Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp')) }
    $work = ConvertTo-ProtectPath -Path ([string]$script:WorkFolder) -AllowMissing
    foreach ($candidate in $candidates) {
        $item = Get-ProtectDirectoryInfo -Path $candidate
        if ($null -eq $item) { continue }
        if ($work -and (Test-ProtectPathWithin -Path $item.FullName -Root $work)) { continue }
        if (@($output) -notcontains $item.FullName) { [void]$output.Add([string]$item.FullName) }
    }
    $result = @()
    foreach ($item in $output) { $result += [string]$item }
    return $result
}

function Start-YaraScan {
    if ($script:QuarantineRunning) { Write-Log 'Карантин выполняется' -Color 'Yellow'; return }
    if ($script:ScanRunning) {
        try { Stop-Operation -Control $script:ScanControl } catch {}
        try { if ($script:ScanHandle -and $script:ScanHandle.Stop) { & $script:ScanHandle.Stop } } catch {}
        Write-Log 'Остановка запрошена...' -Color 'Yellow'
        return
    }
    $rulesDir = Get-YaraRulesDir
    $toolsDir = Get-YaraToolsDir
    $workFolder = ConvertTo-ProtectPath -Path ([string]$script:WorkFolder) -AllowMissing
    $targets = @(Get-ProtectScanTargets)
    if ([string]::IsNullOrWhiteSpace($rulesDir) -or [string]::IsNullOrWhiteSpace($toolsDir) -or [string]::IsNullOrWhiteSpace($workFolder) -or $targets.Count -eq 0) { $message = 'Нет безопасных папок или компонентов для проверки'; Write-Log $message -Color 'Yellow'; Render-ScanHits -Items @() -Complete $false -FailureMessage $message; return }
    $buttonText = ''
    $buttonSaved = $false
    try { $buttonText = [string]$scanBtn.Content; $script:ScanBtnText = $buttonText; $buttonSaved = $true } catch {}
    $control = New-OperationControl -Kind 'yara-scan'
    $operationId = [string]$control.OperationId
    $script:ScanControl = $control; $script:ScanOperationId = $operationId; $script:ScanRunning = $true
    try { $scanBtn.Content = '⏹ Стоп'; $scanBtn.Style = $window.FindResource('BtnDanger') } catch {}
    $script:ScanHandle = [pscustomobject]@{ Stop = { Stop-Operation -Control $control }.GetNewClosure() }
    Write-Log '══ Проверка YARA запущена ══'; Set-Progress; try { if ($protectStatusText) { $protectStatusText.Text = 'Проверка запускается…' } } catch {}
    try {
        Start-Background -ScriptBlock {
            $hits = @(); $seen = @{}; $errors = 0; $timedOut = 0; $published = $false; $failure = ''
            try {
                Assert-OperationActive -Control $Control
                $rulesDir = Ensure-YaraRules -RulesDir $rulesDir -Control $Control
                if ([string]::IsNullOrWhiteSpace($rulesDir)) { throw 'Нет полного набора правил' }
                $exe = Ensure-YaraEngine -ToolsDir $toolsDir -Control $Control
                if ([string]::IsNullOrWhiteSpace($exe)) { throw 'Нет движка YARA' }
                $combined = Combine-YaraRules -RulesDir $rulesDir -OutFile (Join-Path $toolsDir 'potato.yar') -Control $Control
                if ([string]::IsNullOrWhiteSpace($combined)) { throw 'Не удалось объединить правила' }
                $total = @($targets).Count; $targetIndex = 0; $skipNames = @('opencode', 'PotatoPC')
                foreach ($targetRoot in @($targets)) {
                    Assert-OperationActive -Control $Control; $targetIndex++; Write-Log ('── ' + $targetRoot)
                    $entries = @(); try { $entries = @(Get-ChildItem -LiteralPath $targetRoot -Force -ErrorAction SilentlyContinue) } catch { $errors++ }
                    $entryIndex = 0; $entryTotal = [Math]::Max(1, $entries.Count)
                    foreach ($entry in $entries) {
                        Assert-OperationActive -Control $Control; $entryIndex++
                        if ($workFolder -and (Test-ProtectPathWithin -Path $entry.FullName -Root $workFolder)) { continue }
                        if ($skipNames -contains $entry.Name) { continue }
                        $isReparse = $false; try { $isReparse = (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) } catch {}
                        if ($isReparse) { Write-Log ('  Пропущена ссылка: ' + $entry.Name) -Color 'Yellow'; continue }
                        if (-not $entry.PSIsContainer) { try { if ([long]$entry.Length -gt 200MB) { Write-Log ('  Большой файл пропущен: ' + $entry.Name) -Color 'Yellow'; continue } } catch {} }
                        Set-Progress (([double]($targetIndex - 1) + [double]$entryIndex / [double]$entryTotal) / [double]([Math]::Max(1, $total)))
                        try {
                            $result = Invoke-YaraEntry -Exe $exe -Rules $combined -Target $entry.FullName -Control $Control -TimeoutSec 180 -OperationId $Control.OperationId
                            if ($result.TimedOut) { $timedOut++; Write-Log ('  Долго — пропускаю: ' + $entry.Name) -Color 'Yellow'; continue }
                            if ($result.ExitCode -ne 0) { $errors++; if ($result.Error) { Write-Log ('  Сканер: ' + $result.Error) -Color 'Yellow' } }
                            foreach ($line in @($result.Lines)) {
                                if ($line -notmatch '^([A-Za-z_][A-Za-z0-9_]*)\s+(.+)$') { continue }
                                $rule = $Matches[1].Trim(); $reported = $Matches[2].Trim(); $hitPath = $null
                                try { $hitPath = [System.IO.Path]::GetFullPath($reported) } catch { continue }
                                $prefix = $targetRoot.TrimEnd('\'); if (-not $prefix.EndsWith('\')) { $prefix += '\' }
                                if (-not ($hitPath.Equals($targetRoot, [System.StringComparison]::OrdinalIgnoreCase) -or $hitPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase))) { continue }
                                $hitItem = Get-ProtectFileInfo -Path $hitPath
                                if ($null -eq $hitItem) { continue }
                                $key = $rule.ToUpperInvariant() + '|' + $hitItem.FullName.ToUpperInvariant(); if ($seen.ContainsKey($key)) { continue }
                                $seen[$key] = $true; $hits += @{ Rule = $rule; File = [string]$hitItem.FullName }; Write-Log ('  ✗ {0}: {1}' -f $rule, (Split-Path -Leaf $hitItem.FullName)) -Color 'Red'
                            }
                        } catch { if (Test-OperationCancelled $Control) { throw }; $errors++; Write-Log ('  Не вышло проверить: ' + $_.Exception.Message) -Color 'Yellow' }
                    }
                }
                Assert-OperationActive -Control $Control
                Set-BgResult -Key 'scanHits' -Value @{ Items = $hits; Complete = ($errors -eq 0 -and $timedOut -eq 0); Errors = $errors; TimedOut = $timedOut; Cancelled = $false; FailureMessage = '' }
                $published = $true
                if ($hits.Count -eq 0) { Write-Log 'Чисто.' -Color 'Green' } else { Write-Log ('Находок: ' + $hits.Count + ' — выбери и отправь в карантин') -Color 'Yellow' }
                Write-Log '══════════════════════════════════════'
            } catch { $failure = $_.Exception.Message; if (Test-OperationCancelled $Control) { Write-Log '⏹ Остановлено пользователем' -Color 'Yellow' } else { Write-Log ('✗ Проверка упала: ' + $failure) -Color 'Red' } }
            finally {
                Clear-Progress
                if (-not $published) { Set-BgResult -Key 'scanHits' -Value @{ Items = @(); Complete = $false; Errors = 1; TimedOut = 0; Cancelled = (Test-OperationCancelled $Control); FailureMessage = $failure } }
            }
        } -Variables @{ rulesDir = $rulesDir; toolsDir = $toolsDir; workFolder = $workFolder; targets = $targets; Control = $control; YaraRuleHashes = $script:YaraRuleHashes }
    } catch {
        $script:ScanRunning = $false; $script:ScanHandle = $null
        try { if ($buttonSaved) { $scanBtn.Content = $buttonText }; $scanBtn.Style = $window.FindResource('BtnPrimary') } catch {}
        $failureMessage = 'Проверка не запустилась: ' + $_.Exception.Message
        Write-Log ('✗ ' + $failureMessage) -Color 'Red'
        Render-ScanHits -Items @() -Complete $false -FailureMessage $failureMessage
    }
}

function Reset-ScanButton {
    if ($script:ScanRunning) { try { Stop-Operation -Control $script:ScanControl } catch {}; return }
    try { if ($script:ScanBtnText) { $scanBtn.Content = $script:ScanBtnText } } catch {}
    try { $scanBtn.Style = $window.FindResource('BtnPrimary') } catch {}
    $script:ScanRunning = $false; $script:ScanHandle = $null
}

function Read-QuarantineManifest {
    param([string]$ManifestPath)
    $path = Get-ProtectQuarantineManifestPath -Path $ManifestPath
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    $root = Get-ProtectQuarantineRoot; $folder = [System.IO.Path]::GetDirectoryName($path)
    if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-ProtectPathWithin -Path $path -Root $root)) { return $null }
    if (-not (Set-ProtectDirectoryAcl -Path $folder) -or -not (Set-ProtectFileAcl -Path $path)) { return $null }
    $doc = Read-ProtectJsonFile -Path $path
    if ($null -eq $doc) { return $null }
    try { if (-not $doc.PSObject.Properties['Version'] -or [string]$doc.Version -ne '1' -or -not $doc.PSObject.Properties['Items']) { return $null } } catch { return $null }
    $items = New-Object System.Collections.ArrayList; $originals = @{}; $quarantined = @{}; $index = 0
    foreach ($raw in @($doc.Items)) {
        if ($null -eq $raw) { return $null }
        try {
            $original = ConvertTo-ProtectPath -Path ([string]$raw.OriginalPath) -AllowMissing
            $quarantine = ConvertTo-ProtectPath -Path ([string]$raw.QuarantinePath) -AllowMissing
            $hash = ([string]$raw.Hash).ToUpperInvariant(); $sizeText = ([string]$raw.Size).Trim(); $state = ([string]$raw.State).ToUpperInvariant()
            $rule = ''; $scanRoot = ''; $created = ''; $restored = ''; $aclSddl = ''; $algorithm = 'SHA256'
            if ($raw.PSObject.Properties['HashAlgorithm']) { $algorithm = [string]$raw.HashAlgorithm }
            if ($algorithm -ne 'SHA256') { return $null }
            if ($raw.PSObject.Properties['Rule']) { $rule = [string]$raw.Rule }
            if ($raw.PSObject.Properties['ScanRoot']) { $scanRoot = [string]$raw.ScanRoot }
            if ($raw.PSObject.Properties['CreatedUtc']) { $created = [string]$raw.CreatedUtc }
             if ($raw.PSObject.Properties['RestoredUtc']) { $restored = [string]$raw.RestoredUtc }
             if ($raw.PSObject.Properties['AclSddl']) { $aclSddl = [string]$raw.AclSddl }
        } catch { return $null }
        if ($null -eq $original -or $null -eq $quarantine -or $hash -notmatch '^[0-9A-F]{64}$' -or $sizeText -notmatch '^\d+$') { return $null }
        try { $size = [long]$sizeText } catch { return $null }
         if ($state -notin @('PENDING', 'QUARANTINED', 'RESTORED', 'FAILED', 'INTEGRITYFAILED', 'RESTORE_FAILED')) { return $null }
         if (-not [string]::IsNullOrWhiteSpace($aclSddl) -and ($aclSddl.Length -gt 8192 -or -not $aclSddl.StartsWith('O:', [System.StringComparison]::OrdinalIgnoreCase))) { return $null }
        if (Test-ProtectPathWithin -Path $original -Root $root) { return $null }
        if (-not (Test-ProtectPathWithin -Path $quarantine -Root $folder) -or -not (Test-ProtectPathWithin -Path $quarantine -Root $root) -or -not ([System.IO.Path]::GetDirectoryName($quarantine).Equals($folder, [System.StringComparison]::OrdinalIgnoreCase))) { return $null }
        if ([string]::IsNullOrWhiteSpace($scanRoot)) { return $null }
        if (-not (Test-ProtectRestoreTarget -OriginalPath $original -ScanRoot $scanRoot)) { return $null }
        $qItem = Get-ProtectFileInfo -Path $quarantine
         if ($null -ne $qItem) {
             if (-not (Set-ProtectFileAcl -Path $quarantine)) { return $null }
             if (-not (Test-ProtectFingerprint -Expected @{ Hash = $hash; Size = $size } -Path $quarantine)) { return $null }
         } elseif ($state -eq 'QUARANTINED') { return $null }
        $originalKey = $original.ToUpperInvariant(); $quarantineKey = $quarantine.ToUpperInvariant()
        if ($originals.ContainsKey($originalKey) -or $quarantined.ContainsKey($quarantineKey)) { return $null }
        $originals[$originalKey] = $true; $quarantined[$quarantineKey] = $true
        [void]$items.Add([pscustomobject]@{ Index = $index; OriginalPath = $original; QuarantinePath = $quarantine; HashAlgorithm = $algorithm; Hash = $hash; Size = $size; Rule = $rule; State = $state; ScanRoot = $scanRoot; CreatedUtc = $created; RestoredUtc = $restored; AclSddl = $aclSddl })
        $index++
    }
    $out = @(); foreach ($item in $items) { $out += $item }
    return [pscustomobject]@{ Path = $path; Version = 1; CreatedUtc = [string]$doc.CreatedUtc; Items = $out }
}

function Start-Quarantine {
    if ($script:ScanRunning) { Write-Log 'Дождись окончания проверки' -Color 'Yellow'; return }
    if ($script:QuarantineRunning) { Write-Log 'Карантин уже выполняется' -Color 'Yellow'; return }
    $selected = @()
    try { $selected = @($script:ScanCheckboxes.GetEnumerator() | Where-Object { $_.Value -and $_.Value.Box -and $_.Value.Box.IsChecked }) } catch {}
    if ($selected.Count -eq 0) { Write-Log '⚠ Ничего не выбрано' -Color 'Yellow'; return }
    $answer = [System.Windows.MessageBox]::Show(
        "Переместить выбранные файлы в защищённый карантин PotatoPC?`nОригиналы и SHA-256 будут записаны в manifest.json. Восстановление доступно отдельной кнопкой.",
        "Карантин PotatoPC",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning)
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
    $control = New-OperationControl -Kind 'quarantine'; $operationId = [string]$control.OperationId
    $script:QuarantineControl = $control; $script:QuarantineOperationId = $operationId; $script:QuarantineRunning = $true
    $buttonEnabled = $true
    try { $buttonEnabled = [bool]$quarantineBtn.IsEnabled; $quarantineBtn.IsEnabled = $false } catch {}
    $success = @{}; $manifestPath = ''
    try {
        $batch = New-ProtectQuarantineDirectory
        if ([string]::IsNullOrWhiteSpace($batch)) { throw 'Не удалось создать безопасный карантин' }
        $manifestPath = Join-Path $batch 'manifest.json'
        $manifest = [pscustomobject]@{ Version = 1; CreatedUtc = [DateTime]::UtcNow.ToString('o'); Items = @() }
        [void](Save-QuarantineManifest -ManifestPath $manifestPath -Manifest $manifest)
        $entries = New-Object System.Collections.ArrayList; $number = 0; $quarantined = 0; $failed = 0
        foreach ($pair in $selected) {
            if (Test-OperationCancelled $control) { break }
            $source = [string]$pair.Value.File; $rule = [string]$pair.Value.Rule
            $source = ConvertTo-ProtectPath -Path $source; $sourceItem = Get-ProtectFileInfo -Path $source; $qroot = Get-ProtectQuarantineRoot
            if ($null -eq $sourceItem -or $null -eq $qroot -or (Test-ProtectPathWithin -Path $source -Root $qroot)) { $failed++; continue }
            $key = $source.ToUpperInvariant(); if ($success.ContainsKey($key)) { continue }
            $fingerprint = Get-ProtectFileFingerprint -Path $source
            if ($null -eq $fingerprint) { $failed++; continue }
            $sourceAcl = $null
            try { $sourceAcl = Get-Acl -LiteralPath $source -ErrorAction Stop } catch { $failed++; continue }
            $aclSddl = [string]$sourceAcl.Sddl
            if ([string]::IsNullOrWhiteSpace($aclSddl) -or -not $aclSddl.StartsWith('O:', [System.StringComparison]::OrdinalIgnoreCase)) { $failed++; continue }
            $scanRoot = ''; $parent = [System.IO.Path]::GetDirectoryName($source)
            foreach ($target in @(Get-ProtectScanTargets)) { if (Test-ProtectPathWithin -Path $source -Root $target) { $scanRoot = [string]$target; break } }
            if (-not $scanRoot -and (Get-ProtectDirectoryInfo -Path $parent)) { $scanRoot = [string]$parent }
            $number++; $destination = ConvertTo-ProtectPath -Path (Join-Path $batch ('{0:D6}.quarantined' -f $number)) -AllowMissing
            if ($null -eq $destination -or -not (Test-ProtectPathWithin -Path $destination -Root $batch)) { $failed++; continue }
            $entry = [ordered]@{ Index = $number; OriginalPath = $source; QuarantinePath = $destination; HashAlgorithm = 'SHA256'; Hash = $fingerprint.Hash; Size = $fingerprint.Size; Rule = $rule; State = 'Pending'; ScanRoot = $scanRoot; CreatedUtc = [DateTime]::UtcNow.ToString('o'); RestoredUtc = ''; AclSddl = $aclSddl }
            [void]$entries.Add($entry); $manifest.Items = @($entries)
            try { [void](Save-QuarantineManifest -ManifestPath $manifestPath -Manifest $manifest) } catch { [void]$entries.Remove($entry); $manifest.Items = @($entries); $failed++; continue }
            $moved = $false
            try {
                Assert-OperationActive -Control $control
                $before = Get-ProtectFileFingerprint -Path $source
                if ($null -eq $before -or $before.Hash -ne $fingerprint.Hash -or $before.Size -ne $fingerprint.Size) { throw 'Файл изменился до перемещения' }
                if (Test-ProtectPath -Path $destination -Leaf) { throw 'Файл назначения уже существует' }
                 Move-Item -LiteralPath $source -Destination $destination -ErrorAction Stop; $moved = $true
                 if (-not (Set-ProtectFileAcl -Path $destination)) { throw 'Не удалось защитить файл в карантине' }
                 $after = Get-ProtectFileFingerprint -Path $destination
                if ($null -eq $after -or $after.Hash -ne $fingerprint.Hash -or $after.Size -ne $fingerprint.Size) { throw 'Нарушена целостность после перемещения' }
                $entry['State'] = 'Quarantined'; $manifest.Items = @($entries); [void](Save-QuarantineManifest -ManifestPath $manifestPath -Manifest $manifest)
                $success[$key] = $true; $quarantined++; Write-Log ('  В карантине: ' + (Split-Path -Leaf $source)) -Color 'Green'
            } catch {
                $entry['State'] = 'IntegrityFailed'
                $rollbackErrors = @()
                if ($moved) {
                    try {
                        $current = Get-ProtectFileFingerprint -Path $destination
                        if ($null -ne $current -and $current.Hash -eq $fingerprint.Hash -and $current.Size -eq $fingerprint.Size -and -not (Test-ProtectPath -Path $source -Leaf)) {
                            Move-Item -LiteralPath $destination -Destination $source -ErrorAction Stop
                            $aclRestored = Set-ProtectFileAclFromSddl -Path $source -Sddl $aclSddl
                            if (-not $aclRestored) { $rollbackErrors += 'исходный ACL не восстановлен' }
                            $entry['State'] = if ($aclRestored) { 'Failed' } else { 'IntegrityFailed' }
                        } else { $rollbackErrors += 'файл не соответствует ожидаемому хэшу' }
                    } catch { $rollbackErrors += ('откат карантина: ' + $_.Exception.Message) }
                }
                try { $manifest.Items = @($entries); [void](Save-QuarantineManifest -ManifestPath $manifestPath -Manifest $manifest) } catch { $rollbackErrors += ('манифест не сохранён: ' + $_.Exception.Message) }
                if ($rollbackErrors.Count -gt 0) { Write-Log ('  ✗ Откат карантина неполный: ' + ($rollbackErrors -join '; ')) -Color 'Red' }
                $failed++; Write-Log ('  ✗ Не вышло безопасно поместить в карантин: ' + $source) -Color 'Red'
            }
        }
        try {
            $remaining = @()
            foreach ($pair in $script:ScanCheckboxes.GetEnumerator()) {
                $file = ConvertTo-ProtectPath -Path ([string]$pair.Value.File) -AllowMissing
                if ($file -and -not $success.ContainsKey($file.ToUpperInvariant()) -and (Test-ProtectPath -Path $file -Leaf)) { $remaining += @{ Rule = [string]$pair.Value.Rule; File = $file } }
            }
            Render-ScanHits -Items $remaining
        } catch {}
        $message = 'Карантин: ' + $quarantined + ' файлов. Манифест: ' + $manifestPath
        if ($failed -gt 0) { $message += '. Ошибок: ' + $failed }
        Write-Log $message -Color $(if ($failed -eq 0) { 'Green' } else { 'Yellow' })
    } catch { if (Test-OperationCancelled $control) { Write-Log '⏹ Карантин остановлен пользователем' -Color 'Yellow' } else { Write-Log ('✗ Карантин не выполнен: ' + $_.Exception.Message) -Color 'Red' } }
    finally { try { $quarantineBtn.IsEnabled = $buttonEnabled } catch {}; if ($script:QuarantineOperationId -eq $operationId) { $script:QuarantineRunning = $false; $script:QuarantineControl = $null } }
}

function Restore-QuarantineFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][Alias('Manifest', 'Path')][string]$ManifestPath,
        [Parameter(Position = 1)][Alias('ItemIndex')][int]$Index = 0,
        [Alias('TargetPath')][string]$DestinationPath = '',
        [hashtable]$Control = $null
    )
    $restored = $false
    try {
        Assert-OperationActive -Control $Control
        $manifest = Read-QuarantineManifest -ManifestPath $ManifestPath
        if ($null -eq $manifest) { throw 'Манифест карантина недействителен' }
        $items = @($manifest.Items); if ($Index -lt 0 -or $Index -ge $items.Count) { throw 'Индекс карантина не найден' }
        $item = $items[$Index]; if ($item.State -eq 'RESTORED') { return $false }
         if ([string]::IsNullOrWhiteSpace([string]$item.AclSddl)) { throw 'Для старой записи карантина не сохранён исходный ACL; восстановление заблокировано' }
        $original = ConvertTo-ProtectPath -Path ([string]$item.OriginalPath) -AllowMissing; $quarantine = ConvertTo-ProtectPath -Path ([string]$item.QuarantinePath)
        $qroot = Get-ProtectQuarantineRoot; $folder = [System.IO.Path]::GetDirectoryName([string]$manifest.Path)
        if ($null -eq $original -or $null -eq $quarantine -or [string]::IsNullOrWhiteSpace($qroot) -or -not (Test-ProtectPathWithin -Path $quarantine -Root $folder) -or (Test-ProtectPathWithin -Path $original -Root $qroot) -or -not (Test-ProtectRestoreTarget -OriginalPath $original -ScanRoot ([string]$item.ScanRoot))) { throw 'Небезопасный путь карантина' }
        if ($DestinationPath) { $requested = ConvertTo-ProtectPath -Path $DestinationPath -AllowMissing; if ($null -eq $requested -or -not $requested.Equals($original, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Путь восстановления должен совпадать с манифестом' } }
        $parent = [System.IO.Path]::GetDirectoryName($original); if (-not (Test-ProtectPath -Path $parent -Directory)) { throw 'Родительская папка недоступна' }
        if (Test-ProtectPath -Path $original -Leaf) { throw 'Файл уже существует, замена запрещена' }
        if (-not (Test-ProtectFingerprint -Expected $item -Path $quarantine)) { throw 'Hash или размер карантина не совпадает' }
        Assert-OperationActive -Control $Control
        if (-not (Test-ProtectFingerprint -Expected $item -Path $quarantine)) { throw 'Hash или размер изменился перед восстановлением' }
        Move-Item -LiteralPath $quarantine -Destination $original -ErrorAction Stop
        try {
            if (-not (Set-ProtectFileAclFromSddl -Path $original -Sddl ([string]$item.AclSddl))) { throw 'Не удалось восстановить исходный ACL файла' }
            if (-not (Test-ProtectFingerprint -Expected $item -Path $original)) { throw 'Нарушена целостность после восстановления' }
            $item.State = 'Restored'; $item.RestoredUtc = [DateTime]::UtcNow.ToString('o'); $manifest.Items = $items; [void](Save-QuarantineManifest -ManifestPath $manifest.Path -Manifest $manifest)
            $restored = $true; Write-Log ('  Восстановлено: ' + $original) -Color 'Green'
        } catch {
            $rollbackErrors = @()
            if ((Test-ProtectPath -Path $original -Leaf) -and -not (Test-ProtectPath -Path $quarantine -Leaf)) {
                try { Move-Item -LiteralPath $original -Destination $quarantine -ErrorAction Stop } catch { $rollbackErrors += ('возврат в карантин: ' + $_.Exception.Message) }
                if (-not (Test-ProtectPath -Path $quarantine -Leaf) -or -not (Set-ProtectFileAcl -Path $quarantine)) { $rollbackErrors += 'ACL карантина не восстановлен' }
            }
            if ($rollbackErrors.Count -gt 0 -and (Test-ProtectPath -Path $quarantine -Leaf)) {
                $item.State = 'RESTORE_FAILED'
                $item.RestoredUtc = [DateTime]::UtcNow.ToString('o')
                $manifest.Items = $items
                try { [void](Save-QuarantineManifest -ManifestPath $manifest.Path -Manifest $manifest) } catch { $rollbackErrors += ('манифест не сохранён: ' + $_.Exception.Message) }
            }
            if (-not (Test-ProtectPath -Path $quarantine -Leaf) -and (Test-ProtectPath -Path $original -Leaf)) {
                $item.State = 'RESTORE_FAILED'
                $item.RestoredUtc = [DateTime]::UtcNow.ToString('o')
                $manifest.Items = $items
                try { [void](Save-QuarantineManifest -ManifestPath $manifest.Path -Manifest $manifest) } catch { $rollbackErrors += ('манифест не сохранён: ' + $_.Exception.Message) }
            }
            if ($rollbackErrors.Count -gt 0) { Write-Log ('  ✗ Откат восстановления неполный: ' + ($rollbackErrors -join '; ')) -Color 'Red' }
            throw
        }
    } catch { if (Test-OperationCancelled $Control) { Write-Log '⏹ Восстановление остановлено пользователем' -Color 'Yellow' } else { Write-Log ('  ✗ Восстановление не выполнено: ' + $_.Exception.Message) -Color 'Red' } }
    return $restored
}

function Restore-QuarantinedFiles {
    [CmdletBinding()]
    param([Alias('Path', 'QuarantineRoot', 'Manifest')][string]$ManifestPath = '', [int[]]$Index = @(), [switch]$All, [hashtable]$Control = $null)
    $manifests = @()
    try {
        if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
            $root = Get-ProtectQuarantineRoot; if ([string]::IsNullOrWhiteSpace($root)) { throw 'Карантин недоступен' }
            $dirs = @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction Stop)
            foreach ($dir in $dirs) { $candidate = Join-Path $dir.FullName 'manifest.json'; if (Test-ProtectPath -Path $candidate -Leaf) { $manifests += $candidate } }
        } else {
            $requested = ConvertTo-ProtectPath -Path $ManifestPath -AllowMissing; if ($null -eq $requested) { throw 'Небезопасный путь манифеста' }
            $item = $null; try { $item = Get-Item -LiteralPath $requested -Force -ErrorAction Stop } catch {}
            $isDirectory = ($null -ne $item -and $item.PSIsContainer) -or ($null -eq $item -and [System.IO.Path]::GetExtension($requested) -eq '')
            if ($isDirectory) {
                if (-not (Test-ProtectPath -Path $requested -Directory)) { throw 'Небезопасный путь каталога' }
                $root = Get-ProtectQuarantineRoot
                if ($root -and $requested.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) {
                    foreach ($dir in @(Get-ChildItem -LiteralPath $requested -Directory -Force -ErrorAction Stop)) { $candidate = Join-Path $dir.FullName 'manifest.json'; if (Test-ProtectPath -Path $candidate -Leaf) { $manifests += $candidate } }
                } else {
                    $candidate = Join-Path $requested 'manifest.json'
                    if (Test-ProtectPath -Path $candidate -Leaf) { $manifests += $candidate }
                }
            } else {
                $resolved = Get-ProtectQuarantineManifestPath -Path $requested; if ([string]::IsNullOrWhiteSpace($resolved)) { throw 'Небезопасный путь манифеста' }; $manifests += $resolved
            }
        }
    } catch { Write-Log ('  ✗ Не найдены манифесты карантина: ' + $_.Exception.Message) -Color 'Red'; return 0 }
    $count = 0
    foreach ($manifestFile in @($manifests)) {
        if (Test-OperationCancelled $Control) { break }
        $manifest = Read-QuarantineManifest -ManifestPath $manifestFile; if ($null -eq $manifest) { continue }
        $items = @($manifest.Items); $indices = if ($Index.Count -gt 0) { @($Index) } else { @(0..([Math]::Max(0, $items.Count - 1))) }
        if ($items.Count -eq 0) { $indices = @() }
        foreach ($i in $indices) { if (Test-OperationCancelled $Control) { break }; if (Restore-QuarantineFile -ManifestPath $manifestFile -Index ([int]$i) -Control $Control) { $count++ } }
    }
    Write-Log ('Восстановлено файлов: ' + $count) -Color $(if ($count -gt 0) { 'Green' } else { 'Yellow' })
    return [int]$count
}
