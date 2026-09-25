<#
.SYNOPSIS
    PotatoPC: генерация SHA256SUMS для релиза (запускает мейнтейнер).
.DESCRIPTION
    Обходит файлы репозитория (кроме .git и самого SHA256SUMS),
    пишет SHA256SUMS в корень и печатает хэш menu.ps1 для README/Release notes.
    После каждого изменения файлов перед тегом — перезапустить.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/New-ReleaseHashes.ps1
#>
[CmdletBinding()]
param(
    [string]$Root = '',
    [switch]$IncludeUntracked
)

$ErrorActionPreference = 'Stop'
if (-not $Root) {
    if ($PSCommandPath) { $Root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent }
    else { $Root = (Get-Location).Path }
}
$out = Join-Path $Root 'SHA256SUMS'
$allFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction Stop |
    Where-Object { $_.FullName -notmatch '[\\/]\.git([\\/]|$)' -and $_.Name -ne 'SHA256SUMS' })
if ($IncludeUntracked) {
    $files = @($allFiles)
} else {
    $tracked = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $gitOk = $false
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'git'
        $psi.Arguments = '-C "' + $Root + '" ls-files -z'
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        try { $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
        $proc = [System.Diagnostics.Process]::Start($psi)
        if ($proc) {
            $raw = $proc.StandardOutput.ReadToEnd()
            [void]$proc.WaitForExit()
            if ($proc.ExitCode -eq 0) {
                foreach ($rel in @($raw -split "`0")) {
                    if (-not [string]::IsNullOrWhiteSpace($rel)) { [void]$tracked.Add(($rel -replace '/', '\')) }
                }
                $gitOk = $tracked.Count -gt 0
            }
            $proc.Dispose()
        }
    } catch {}
    if ($gitOk) {
        $files = @($allFiles | Where-Object {
            $rel = $_.FullName.Substring($Root.Length).TrimStart('\', '/')
            $tracked.Contains($rel)
        })
    } else { $files = @($allFiles) }
}
$files = @($files | Sort-Object FullName)

function Test-RepoManifestTextFile {
    param([string]$Path)
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $name = [System.IO.Path]::GetFileName($Path).ToLowerInvariant()
    return (@('.bat', '.cfg', '.cmd', '.conf', '.css', '.csv', '.editorconfig', '.gitattributes', '.gitignore', '.htm', '.html', '.ini', '.js', '.json', '.md', '.ps1', '.psd1', '.toml', '.txt', '.xml', '.xaml', '.yaml', '.yml', '.yar', '.yara') -contains $ext) -or ($name -match '^(license|notice|copying|readme)$')
}

function Get-RepoManifestHash {
    param([string]$Path)
    if (Test-RepoManifestTextFile -Path $Path) {
        $text = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($Path))
        $text = $text.Replace("`r`n", "`n").Replace("`r", "`n")
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') } finally { $sha.Dispose() }
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}

$lines = @()
foreach ($f in $files) {
    $rel = $f.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
    $h = Get-RepoManifestHash -Path $f.FullName
    $lines += ("$h  $rel")
}
[System.IO.File]::WriteAllLines($out, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host ("SHA256SUMS: файлов=" + $lines.Count + " -> " + $out) -ForegroundColor Green

$menu = Join-Path $Root 'menu.ps1'
if (Test-Path $menu) {
    $mh = (Get-FileHash -LiteralPath $menu -Algorithm SHA256).Hash
    Write-Host ('menu.ps1 SHA256: ' + $mh) -ForegroundColor Cyan
    Write-Host 'Вставь хэш в README и Release notes вместе с коммитом/тегом.' -ForegroundColor DarkGray
}
