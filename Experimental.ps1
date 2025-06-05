# Создание точки восстановления
try {
    Checkpoint-Computer -Description "До выполнения Wicked Raven System Clear" -RestorePointType "MODIFY_SETTINGS"
    Write-Host "[+] Точка восстановления создана" -ForegroundColor Green
} catch {
    Write-Host "[-] Не удалось создать точку восстановления: $_" -ForegroundColor Yellow
}

# Функция отображения меню
function Show-Menu {
    Clear-Host
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host "     WICKED RAVEN Experimental     " -ForegroundColor Magenta
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host ""
    Write-Host " 1. Заблокировать рекламу" -ForegroundColor Green
    Write-Host " 2. Восстановить оригинальный hosts" -ForegroundColor Yellow
    Write-Host " 0. Назад" -ForegroundColor Red
    Write-Host ""
}

# Замена Hosts файла для блокировки рекламы
function Block-Ads {
    Write-Host "[*] Блокировка рекламы через обновление hosts..." -ForegroundColor Cyan

    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    $backupDir = "$env:SystemRoot\System32\drivers\etc\hosts_backup"
    $originalHostsBackup = Join-Path $backupDir "original_hosts.bak"

    try {
        if (-not (Test-Path $backupDir)) {
            New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
        }

        if (-not (Test-Path $originalHostsBackup)) {
            Copy-Item -Path $hostsPath -Destination $originalHostsBackup -Force
            Write-Host "[*] Оригинальный hosts сохранен как резервная копия: $originalHostsBackup" -ForegroundColor Yellow
        }

        $timestamp = Get-Date -Format "yyyyMMdd_HHmm"
        $backupPath = Join-Path $backupDir "hosts_$timestamp.bak"
        Copy-Item -Path $hostsPath -Destination $backupPath -Force
        Write-Host "[*] Создана резервная копия: $backupPath" -ForegroundColor Yellow

        $url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
        $newHosts = Invoke-WebRequest -Uri $url -UseBasicParsing

        if ($newHosts.StatusCode -eq 200) {
            $newHosts.Content | Set-Content -Path $hostsPath -Force -Encoding ASCII
            Write-Host "[+] Новый hosts успешно применён." -ForegroundColor Green
        } else {
            Write-Host "[!] Не удалось загрузить файл hosts. Код: $($newHosts.StatusCode)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "[!] Ошибка: $_" -ForegroundColor Red
    }

    Start-Sleep -Seconds 4
}

function Restore-Original {
    Write-Host "[*] Восстановление оригинального hosts..." -ForegroundColor Cyan

    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    $backupDir = "$env:SystemRoot\System32\drivers\etc\hosts_backup"
    $originalHostsBackup = Join-Path $backupDir "original_hosts.bak"

    try {
        if (-not (Test-Path $originalHostsBackup)) {
            Write-Host "[!] Оригинальный hosts не найден. Невозможно восстановить." -ForegroundColor Red
            return
        }

        if (-not (Test-Path $backupDir)) {
            New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
        }
        $timestamp = Get-Date -Format "yyyyMMdd_HHmm"
        $backupPath = Join-Path $backupDir "hosts_$timestamp.bak"
        Copy-Item -Path $hostsPath -Destination $backupPath -Force
        Write-Host "[*] Создана резервная копия текущего hosts: $backupPath" -ForegroundColor Yellow

        Copy-Item -Path $originalHostsBackup -Destination $hostsPath -Force
        Write-Host "[+] Оригинальный hosts успешно восстановлен." -ForegroundColor Green
    }
    catch {
        Write-Host "[!] Ошибка: $_" -ForegroundColor Red
    }

    Start-Sleep -Seconds 4
}

# Основной цикл
$backToMain = $false

while (-not $backToMain) {
    Show-Menu
    $choice = Read-Host "Выберите опцию (0-2):"
    switch ($choice) {
        '1' { Block-Ads }
        '2' { Restore-Original }
        '0' {
            Write-Host "Возврат в главное меню..." -ForegroundColor Green
            Start-Sleep -Seconds 1
            iex (irm "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/menu.ps1")
            $backToMain = $true
        }
        default {
            Write-Host "Неверный ввод. Попробуйте снова." -ForegroundColor Red; Pause 
        }
    }
}
