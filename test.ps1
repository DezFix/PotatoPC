<#
.SYNOPSIS
    Безопасная очистка реестра Windows от мусора и "хвостов".
#>

Write-Host "=== Создание резервных копий реестра ===" -ForegroundColor Cyan
$backupDir = "$env:SystemDrive\RegistryBackup"
if (!(Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$HKLMbackup = "$backupDir\HKLM_SOFTWARE_$timestamp.reg"
$HKCUbackup = "$backupDir\HKCU_SOFTWARE_$timestamp.reg"

reg export HKLM\SOFTWARE $HKLMbackup /y | Out-Null
reg export HKCU\SOFTWARE $HKCUbackup /y | Out-Null
Write-Host "Бэкапы сохранены в: $backupDir" -ForegroundColor Green

# ---------------------------------------
Write-Host "`n=== Очистка автозагрузки ===" -ForegroundColor Cyan
$runPaths = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
)
foreach ($path in $runPaths) {
    if (Test-Path $path) {
        Get-ItemProperty $path | ForEach-Object {
            foreach ($prop in $_.PSObject.Properties) {
                $value = $prop.Value
                if ($value -and (Test-Path $value -ErrorAction SilentlyContinue)) { continue }
                Write-Host "🗑 Удаляю из автозагрузки: $($prop.Name) → $value" -ForegroundColor Yellow
                Remove-ItemProperty -Path $path -Name $prop.Name -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# ---------------------------------------
Write-Host "`n=== Очистка следов старого ПО ===" -ForegroundColor Cyan
$uninstallPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

foreach ($path in $uninstallPaths) {
    if (Test-Path $path) {
        Get-ChildItem $path | ForEach-Object {
            try {
                $item = Get-ItemProperty $_.PsPath -ErrorAction Stop
                if (-not $item.DisplayName -and -not $item.UninstallString) {
                    Write-Host "🗑 Удаляю пустой ключ: $($_.PsChildName)" -ForegroundColor Yellow
                    Remove-Item $_.PsPath -Recurse -Force -ErrorAction SilentlyContinue
                } elseif ($item.UninstallString -and -not (Test-Path $item.UninstallString.Split('"')[1] -ErrorAction SilentlyContinue)) {
                    Write-Host "🗑 Удаляю устаревший Uninstall: $($item.DisplayName)" -ForegroundColor Yellow
                    Remove-Item $_.PsPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            } catch {}
        }
    }
}

# ---------------------------------------
Write-Host "`n=== Поиск и удаление битых/пустых ключей в Software ===" -ForegroundColor Cyan
$softwarePaths = @("HKCU:\Software", "HKLM:\Software")
foreach ($root in $softwarePaths) {
    Get-ChildItem -Path $root -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $props = (Get-ItemProperty $_.PsPath -ErrorAction SilentlyContinue).PSObject.Properties
            if (-not $props -or $props.Count -eq 0) {
                Write-Host "🗑 Удаляю пустой ключ: $($_.PsPath)" -ForegroundColor Yellow
                Remove-Item $_.PsPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}

# ---------------------------------------
Write-Host "`n=== Очистка ссылок на несуществующие файлы ===" -ForegroundColor Cyan
$registryPaths = @(
    "HKCU:\Software",
    "HKLM:\Software"
)
foreach ($root in $registryPaths) {
    Get-ChildItem -Path $root -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $item = Get-ItemProperty $_.PsPath -ErrorAction SilentlyContinue
            foreach ($prop in $item.PSObject.Properties) {
                $val = $prop.Value
                if ($val -is [string] -and ($val -match "^[A-Z]:\\") -and (-not (Test-Path $val -ErrorAction SilentlyContinue))) {
                    Write-Host "🗑 Удаляю битую ссылку: $($prop.Name) → $val" -ForegroundColor Yellow
                    Remove-ItemProperty -Path $_.PsPath -Name $prop.Name -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {}
    }
}

Write-Host "`n✅ Очистка завершена! Реестр оптимизирован." -ForegroundColor Green
Write-Host "Резервные копии находятся в $backupDir" -ForegroundColor DarkCyan
