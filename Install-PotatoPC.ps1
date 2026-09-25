<#
.SYNOPSIS
    PotatoPC: безопасный запуск с проверкой SHA256 (альтернатива irm|iex).
.DESCRIPTION
    Скачивает ZIP репозитория, сверяет SHA256 архива с ожидаемым
    (хэш публикуется на странице Releases), проверяет пофайловые хэши
    SHA256SUMS внутри архива и только потом запускает menu.ps1 с диска.
    Несовпадение хэша = архив удаляется, запуск блокируется.
.EXAMPLE
    # 1. Аудит без запуска: скачать, показать хэш, проверить файлы
    Invoke-WebRequest https://raw.githubusercontent.com/DezFix/PotatoPC/main/Install-PotatoPC.ps1 -OutFile Install-PotatoPC.ps1
    .\Install-PotatoPC.ps1 -VerifyOnly
.EXAMPLE
    # 2. Запуск со сверкой хэша релиза
    .\Install-PotatoPC.ps1 -ExpectedHash '<SHA256 со страницы Releases>'
#>
[CmdletBinding()]
param(
    [string]$Repo = 'DezFix/PotatoPC',
    [string]$Ref = 'main',
    [string]$ZipUrl = '',
    [string]$ExpectedHash = '',
    [switch]$VerifyOnly,
    [switch]$Force,
    [string]$Dest = (Join-Path $env:ProgramData 'PotatoPC\install')
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Resolve-ExtractedPath {
    param([string]$Root, [string]$Relative)
    if ([string]::IsNullOrWhiteSpace($Root) -or [string]::IsNullOrWhiteSpace($Relative)) { return $null }
    $rel = $Relative.Trim() -replace '/', '\'
    if ($rel -match '[\x00]' -or [System.IO.Path]::IsPathRooted($rel)) { return $null }
    $parts = @($rel -split '\\')
    foreach ($part in $parts) {
        if ($part -eq '.' -or $part -eq '..' -or $part -match '^[A-Za-z]:') { return $null }
    }
    try {
        $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\','/')
        $full = [System.IO.Path]::GetFullPath((Join-Path $rootFull $rel))
        $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
        if (-not $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $null }
        return $full
    } catch { return $null }
}

function Test-ZipHashes {
    param([string]$ExtractRoot)
    $root = $null
    try { $root = [System.IO.Path]::GetFullPath($ExtractRoot).TrimEnd('\','/') } catch { return $false }
    try {
        $rootItem = Get-Item -LiteralPath $root -Force -ErrorAction Stop
        if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        $ancestor = $root
        while (-not [string]::IsNullOrEmpty($ancestor)) {
            $ancestorItem = $null
            try { $ancestorItem = Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop } catch {}
            if ($null -ne $ancestorItem -and (($ancestorItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) { return $false }
            $parent = [System.IO.Path]::GetDirectoryName($ancestor)
            if ([string]::IsNullOrEmpty($parent) -or $parent -eq $ancestor) { break }
            $ancestor = $parent
        }
        $sumItem = Get-Item -LiteralPath (Join-Path $root 'SHA256SUMS') -Force -ErrorAction Stop
        if (($sumItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    } catch { return $false }
    $sums = Join-Path $root 'SHA256SUMS'
    if (-not (Test-Path -LiteralPath $sums -PathType Leaf)) {
        Write-Host '[!] SHA256SUMS отсутствует — проверка не пройдена.' -ForegroundColor Red
        return $false
    }
    $ok = 0
    $bad = New-Object System.Collections.ArrayList
    $missing = New-Object System.Collections.ArrayList
    $seen = @{}
    try { $lines = [System.IO.File]::ReadAllLines($sums) } catch {
        Write-Host ('[!] SHA256SUMS не читается: ' + $_.Exception.Message) -ForegroundColor Red
        return $false
    }
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $m = [regex]::Match($line, '^\s*([0-9a-fA-F]{64})\s+\*?(.+?)\s*$')
        if (-not $m.Success) { [void]$bad.Add('Некорректная строка манифеста'); continue }
        $rel = $m.Groups[2].Value.Trim()
        $key = $rel.ToUpperInvariant()
        if ($seen.ContainsKey($key)) { [void]$bad.Add('Повтор в манифесте: ' + $rel); continue }
        $seen[$key] = $true
        $full = Resolve-ExtractedPath -Root $root -Relative $rel
        if ($null -eq $full) { [void]$bad.Add('Недопустимый путь: ' + $rel); continue }
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { [void]$missing.Add($rel); continue }
        try {
            $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { [void]$bad.Add('Reparse path: ' + $rel); continue }
            $actual = (Get-FileHash -LiteralPath $full -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($actual -eq $m.Groups[1].Value.ToUpperInvariant()) { $ok++ } else { [void]$bad.Add('Хэш: ' + $rel) }
        } catch { [void]$bad.Add('Ошибка чтения: ' + $rel) }
    }
    if ($seen.Count -eq 0) { [void]$bad.Add('Пустой манифест') }
    try {
        foreach ($entry in @(Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction Stop)) {
            if (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { [void]$bad.Add('Reparse path: ' + $entry.FullName) }
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction Stop)) {
            if ($file.Name -ieq 'SHA256SUMS') { continue }
            $rel = $file.FullName.Substring($root.Length).TrimStart('\','/')
            if ($seen.ContainsKey($rel.ToUpperInvariant())) { continue }
            if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { [void]$bad.Add('Reparse path: ' + $rel); continue }
            [void]$bad.Add('Файл отсутствует в манифесте: ' + $rel)
        }
    } catch { [void]$bad.Add('Ошибка обхода архива: ' + $_.Exception.Message) }
    Write-Host ("[i] Пофайлово: OK=$ok, битых=$($bad.Count), отсутствует=$($missing.Count)")
    foreach ($b in $bad)     { Write-Host ('[!] ' + $b) -ForegroundColor Red }
    foreach ($m in $missing) { Write-Host ('[!] Нет файла: ' + $m) -ForegroundColor Yellow }
    return ($bad.Count -eq 0 -and $missing.Count -eq 0)
}

function Assert-InstallDestination {
    param([string]$Path)
    try {
        $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\','/')
        if ($full.Length -le 3) { throw 'Корень диска нельзя использовать как Dest.' }
        $forbidden = @(
            [System.IO.Path]::GetFullPath($env:SystemRoot).TrimEnd('\','/'),
            [System.IO.Path]::GetFullPath($env:ProgramFiles).TrimEnd('\','/'),
            [System.IO.Path]::GetFullPath(${env:ProgramFiles(x86)}).TrimEnd('\','/'),
            [System.IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\','/'),
            [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\','/')
        ) | Where-Object { $_ }
        foreach ($root in $forbidden) {
            if ($full.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Указана системная папка: ' + $full }
        }
        $tempRoot = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\','/')
        if ($full.Equals($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($tempRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Dest не должен находиться в пользовательском TEMP: ' + $full }
        $programDataRoot = [System.IO.Path]::GetFullPath($env:ProgramData).TrimEnd('\','/')
        if (-not ($full.Equals($programDataRoot, [System.StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($programDataRoot + '\', [System.StringComparison]::OrdinalIgnoreCase))) { throw 'Dest должен находиться в ProgramData: ' + $full }
        $probe = $full
        while (-not [string]::IsNullOrEmpty($probe)) {
            $existing = $null
            try { $existing = Get-Item -LiteralPath $probe -Force -ErrorAction Stop } catch {}
            if ($null -ne $existing -and (($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'Dest содержит reparse-компонент: ' + $probe }
            $parent = [System.IO.Path]::GetDirectoryName($probe)
            if ([string]::IsNullOrEmpty($parent) -or $parent -eq $probe) { break }
            $probe = $parent
        }
        return $full
    } catch { throw 'Недопустимый Dest: ' + $_.Exception.Message }
}

function Set-InstallDirectoryAcl {
    param([string]$Path)
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not $item.PSIsContainer) { return $false }
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
        Set-Acl -LiteralPath $Path -AclObject $acl
        return $true
    } catch { return $false }
}

function Set-InstallFileAcl {
    param([string]$Path)
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
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
        Set-Acl -LiteralPath $Path -AclObject $acl
        return $true
    } catch { return $false }
}

function Set-InstallTreeAcl {
    param([string]$Path)
    try {
        if (-not (Set-InstallDirectoryAcl -Path $Path)) { return $false }
        foreach ($entry in @(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction Stop)) {
            if (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
            if ($entry.PSIsContainer) { if (-not (Set-InstallDirectoryAcl -Path $entry.FullName)) { return $false } }
            elseif (-not (Set-InstallFileAcl -Path $entry.FullName)) { return $false }
        }
        return $true
    } catch { return $false }
}

if (-not $ZipUrl) { $ZipUrl = "https://github.com/$Repo/archive/refs/heads/$Ref.zip" }
$Dest = Assert-InstallDestination -Path $Dest
if (-not (Test-Path $Dest)) { New-Item -ItemType Directory -Path $Dest -Force | Out-Null }
if (-not (Set-InstallDirectoryAcl -Path $Dest)) { throw 'Не удалось защитить каталог установки.' }
$programDataRoot = [System.IO.Path]::GetFullPath($env:ProgramData).TrimEnd('\','/')
if ($Dest.StartsWith($programDataRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    $installParent = Split-Path $Dest -Parent
    if (-not (Set-InstallDirectoryAcl -Path $installParent)) { throw 'Не удалось защитить родительский каталог установки.' }
}
$zipPath = Join-Path $Dest 'potatopc-dl.zip'
$stagePath = Join-Path $Dest ('stage-' + [Guid]::NewGuid().ToString('N'))
if (Test-Path $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
if (-not (Test-Path $stagePath)) { New-Item -ItemType Directory -Path $stagePath -Force | Out-Null }
if (-not (Set-InstallDirectoryAcl -Path $stagePath)) { throw 'Не удалось защилить staging-каталог.' }

Write-Host ("[*] Скачиваю: " + $ZipUrl)
Invoke-WebRequest -Uri $ZipUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 120
$actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
Write-Host ('[*] SHA256 архива: ' + $actualHash)

if ($ExpectedHash) {
    $exp = ($ExpectedHash -replace '[^0-9a-fA-F]', '').ToUpperInvariant()
    if ($exp -notmatch '^[0-9A-F]{64}$') { throw 'ExpectedHash должен содержать ровно 64 hex-символа.' }
    if ($exp -ne $actualHash) {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        throw ("ХЭШ НЕ СОВПАЛ. Ожидался: $exp. Архив удалён, запуск заблокирован.")
    }
    Write-Host '[+] Хэш архива совпал.' -ForegroundColor Green
    Unblock-File -LiteralPath $zipPath -ErrorAction SilentlyContinue
}
elseif (-not $Force -and -not $VerifyOnly) {
    Write-Host '[!] Хэш не сверен (нет -ExpectedHash). Выполнять код без проверки опасно.' -ForegroundColor Yellow
    $ans = Read-Host 'Продолжить без проверки? [y/N]'
    if ($ans -ne 'y' -and $ans -ne 'Y') { Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue; throw 'Отменено пользователем.' }
}

try {
    Expand-Archive -LiteralPath $zipPath -DestinationPath $stagePath -Force -ErrorAction Stop
} catch {
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $stagePath)
}
$repoDir = Get-ChildItem -LiteralPath $stagePath -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName 'menu.ps1') } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $repoDir -and (Test-Path (Join-Path $stagePath 'menu.ps1') -PathType Leaf)) {
    $repoDir = Get-Item -LiteralPath $stagePath
}
if (-not $repoDir) { throw 'menu.ps1 не найден в архиве.' }

if (-not (Set-InstallTreeAcl -Path $repoDir.FullName)) { throw 'Не удалось защитить распакованный репозиторий.' }
if (-not (Test-ZipHashes -ExtractRoot $repoDir.FullName)) {
    throw 'Пофайловая сверка НЕ пройдена. Запуск заблокирован.'
}
Write-Host '[+] Пофайловая сверка пройдена.' -ForegroundColor Green
try {
    Get-ChildItem -LiteralPath $repoDir.FullName -Filter '*.ps1' -Recurse -File -Force -ErrorAction Stop | Unblock-File -ErrorAction Stop
} catch { throw ('Не удалось снять блокировку файлов: ' + $_.Exception.Message) }
if (-not (Test-ZipHashes -ExtractRoot $repoDir.FullName)) { throw 'Повторная сверка перед запуском не пройдена.' }

if ($VerifyOnly) {
    Write-Host ('[i] VerifyOnly: запуск пропущен. Архив распакован: ' + $repoDir.FullName) -ForegroundColor Cyan
    return
}

$menu = Join-Path $repoDir.FullName 'menu.ps1'
Write-Host ('[*] Запуск: ' + $menu)
& powershell -STA -NoProfile -ExecutionPolicy Bypass -File "$menu"
