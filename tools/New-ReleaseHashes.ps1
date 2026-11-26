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
# Хвостовой слеш ломал бы относительные пути: все последующие Substring($Root.Length)
# отрезали бы лишний символ и манифест стал бы нечитаемым.
$Root = ([System.IO.Path]::GetFullPath($Root)).TrimEnd('\','/')
$out = Join-Path $Root 'SHA256SUMS'
$allFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction Stop |
    Where-Object { $_.FullName -notmatch '[\\/]\.git([\\/]|$)' -and $_.Name -ne 'SHA256SUMS' })
# Git decides what goes in. -IncludeUntracked adds untracked files, but never the
# ignored ones (_archive_v6/, data/, portable.txt) - -Force above lists them too.
$tracked = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$gitOk = $false
try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'git'
    # -c -o --exclude-standard: tracked plus untracked, never the ignored ones
    # (_archive_v6, data, portable.txt must stay out of the manifest).
    $psi.Arguments = '-C "' + $Root + '" ls-files -z' + $(if ($IncludeUntracked) { ' -c -o --exclude-standard' } else { '' })
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
# Папки с export-ignore в .gitattributes (tests/, tools/) GitHub не кладёт в
# архив ветки - их нет и в манифесте, иначе запуск по ссылке не найдёт файлы.
$skipDirs = @()
$ga = Join-Path $Root '.gitattributes'
if (Test-Path -LiteralPath $ga) {
    foreach ($l in [System.IO.File]::ReadAllLines($ga)) {
        if ($l -match '^\s*([^#\s]+)/\s+.*\bexport-ignore\b') { $skipDirs += (($Matches[1] -replace '/', '\') + '\') }
    }
}
$files = @($allFiles | Where-Object {
    $rel = $_.FullName.Substring($Root.Length).TrimStart('\', '/')
    $skip = $false
    foreach ($d in $skipDirs) { if ($rel.StartsWith($d, [StringComparison]::OrdinalIgnoreCase)) { $skip = $true } }
    (-not $skip) -and ((-not $gitOk) -or $tracked.Contains($rel))
})
# Ordinal, not Sort-Object: the current culture orders Install-PotatoPC.ps1,
# LICENSE and README.md differently, so every culture re-writes the manifest.
$byPath = @{}
foreach ($f in $files) { $byPath[$f.FullName] = $f }
$keys = [string[]]@($byPath.Keys)
[array]::Sort($keys, [StringComparer]::Ordinal)
$files = @($keys | ForEach-Object { $byPath[$_] })

function Test-RepoManifestTextFile {
    param([string]$Path)
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $name = [System.IO.Path]::GetFileName($Path).ToLowerInvariant()
    return (@('.bat', '.cfg', '.cmd', '.conf', '.cs', '.css', '.csv', '.editorconfig', '.gitattributes', '.gitignore', '.htm', '.html', '.ini', '.js', '.json', '.md', '.ps1', '.psd1', '.psm1', '.toml', '.txt', '.svg', '.xml', '.xaml', '.yaml', '.yml') -contains $ext) -or ($name -match '^(license|notice|copying|readme)$')
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
# LF, а не CRLF: с CRLF `sha256sum -c` в WSL/Linux не проходил из-за \r в конце строки.
[System.IO.File]::WriteAllText($out, (($lines -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
Write-Host ("SHA256SUMS: файлов=" + $lines.Count + " -> " + $out) -ForegroundColor Green

$menu = Join-Path $Root 'menu.ps1'
if (Test-Path $menu) {
    $mh = (Get-FileHash -LiteralPath $menu -Algorithm SHA256).Hash
    Write-Host ('menu.ps1 SHA256: ' + $mh) -ForegroundColor Cyan
    Write-Host 'Вставь хэш в README и Release notes вместе с коммитом/тегом.' -ForegroundColor DarkGray
}
