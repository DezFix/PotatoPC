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
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
if (-not $Root) {
    if ($PSCommandPath) { $Root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent }
    else { $Root = (Get-Location).Path }
}
$out = Join-Path $Root 'SHA256SUMS'
$files = Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction Stop |
    Where-Object { $_.FullName -notmatch '[\\/]\.git([\\/]|$)' -and $_.Name -ne 'SHA256SUMS' } |
    Sort-Object FullName

$lines = @()
foreach ($f in $files) {
    $rel = $f.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
    $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
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
