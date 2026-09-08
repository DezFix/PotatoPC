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
    [string]$Dest = (Join-Path $env:TEMP 'PotatoPC')
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Test-ZipHashes {
    param([string]$ExtractRoot)
    $sums = Join-Path $ExtractRoot 'SHA256SUMS'
    if (-not (Test-Path $sums)) {
        Write-Host '[i] SHA256SUMS нет в архиве — пофайловая сверка пропущена.' -ForegroundColor DarkGray
        return $true
    }
    $ok = 0; $bad = @(); $missing = @()
    foreach ($line in [System.IO.File]::ReadAllLines($sums)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $m = [regex]::Match($line, '^\s*([0-9a-fA-F]{64})\s+\*?(.+?)\s*$')
        if (-not $m.Success) { continue }
        $rel = $m.Groups[2].Value -replace '/', [System.IO.Path]::DirectorySeparatorChar
        $full = Join-Path $ExtractRoot $rel
        if (-not (Test-Path $full -PathType Leaf)) { $missing += $rel; continue }
        $actual = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
        if ($actual -eq $m.Groups[1].Value.ToUpperInvariant()) { $ok++ } else { $bad += $rel }
    }
    Write-Host ("[i] Пофайлово: OK=$ok, битых=$($bad.Count), отсутствует=$($missing.Count)")
    foreach ($b in $bad)     { Write-Host ("[!] Хэш не совпал: " + $b) -ForegroundColor Red }
    foreach ($m in $missing) { Write-Host ("[!] Нет файла: " + $m) -ForegroundColor Yellow }
    return ($bad.Count -eq 0 -and $missing.Count -eq 0)
}

if (-not $ZipUrl) { $ZipUrl = "https://github.com/$Repo/archive/refs/heads/$Ref.zip" }
if (-not (Test-Path $Dest)) { New-Item -ItemType Directory -Path $Dest -Force | Out-Null }
$zipPath = Join-Path $Dest 'potatopc-dl.zip'
if (Test-Path $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

Write-Host ("[*] Скачиваю: " + $ZipUrl)
Invoke-WebRequest -Uri $ZipUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 120
$actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
Write-Host ('[*] SHA256 архива: ' + $actualHash)

if ($ExpectedHash) {
    $exp = ($ExpectedHash -replace '[^0-9a-fA-F]', '').ToUpperInvariant()
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

# Чистим старые распаковки и разворачиваем свежий архив
Get-ChildItem -LiteralPath $Dest -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'PotatoPC-*' -or $_.Name -like '*-main' } | ForEach-Object {
        try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop } catch {}
    }
try {
    Expand-Archive -LiteralPath $zipPath -DestinationPath $Dest -Force -ErrorAction Stop
} catch {
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $Dest)
}
$repoDir = Get-ChildItem -LiteralPath $Dest -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName 'menu.ps1') } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $repoDir -and (Test-Path (Join-Path $Dest 'menu.ps1') -PathType Leaf)) {
    $repoDir = Get-Item -LiteralPath $Dest
}
if (-not $repoDir) { throw 'menu.ps1 не найден в архиве.' }

if (-not (Test-ZipHashes -ExtractRoot $repoDir.FullName)) {
    throw 'Пофайловая сверка НЕ пройдена. Запуск заблокирован.'
}
Write-Host '[+] Пофайловая сверка пройдена.' -ForegroundColor Green

if ($VerifyOnly) {
    Write-Host ('[i] VerifyOnly: запуск пропущен. Распаковано: ' + $repoDir.FullName) -ForegroundColor Cyan
    return
}

$menu = Join-Path $repoDir.FullName 'menu.ps1'
Write-Host ('[*] Запуск: ' + $menu)
& powershell -NoProfile -ExecutionPolicy Bypass -File "$menu"
