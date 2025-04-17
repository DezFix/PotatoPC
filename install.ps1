function Show-InstallMenu {
    Clear-Host
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host "     WICKED RAVEN INSTALL SYSTEM    " -ForegroundColor Magenta
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " 1. Установить по пресетам"
    Write-Host " 2. Ручная установка приложений"
    Write-Host " 3. Обновить установленные пакеты"
    Write-Host " 0. Назад"
    Write-Host ""
}

function Check-Choco {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "[!] Chocolatey не найден." -ForegroundColor Yellow
        $install = Read-Host "Установить Chocolatey? (y/n)"
        if ($install -eq 'y') {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
        } else {
            Write-Host "[-] Chocolatey не будет установлен." -ForegroundColor DarkYellow
            return $false
        }
    }
    return $true
}

function Show-PresetMenu {
    Clear-Host
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host "         УСТАНОВКА ПО ПРЕСЕТАМ      " -ForegroundColor Magenta
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " 1. Стандартный набор"
    Write-Host " 2. Геймерский набор"
    Write-Host " 3. Все вместе"
    Write-Host " 0. Назад"
    Write-Host ""
}

function Ask-OpenOfficeInstall {
    $global:installOnlyoffice = $false
    $answer = Read-Host "[?] Установить Onlyoffice? (y/n)"
    if ($answer -eq 'y') {
        $global:installOnlyoffice = $true
    } else {
        Write-Host "[-] Onlyoffice пропущен." -ForegroundColor DarkYellow
    }
}

function Show-LicenseAgreement($apps) {
    Write-Host "Вы собираетесь установить следующие приложения:" -ForegroundColor Cyan
    foreach ($app in $apps) {
        Write-Host "- $app" -ForegroundColor White
    }
    $confirm = Read-Host "Продолжить установку? (y/n)"
    if ($confirm -ne 'y') {
        Write-Host "[-] Установка отменена." -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Install-StandardPreset {
    $apps = @("SumatraPDF", "7-Zip", "AnyDesk")
    if (-not (Show-LicenseAgreement $apps)) { return }
    Ask-OpenOfficeInstall
    Write-Host "[+] Установка стандартного набора программ..." -ForegroundColor Yellow
    choco install -y sumatrapdf 7zip anydesk
    if ($global:installOnlyoffice) {
        choco install -y onlyoffice
    }
    Pause
}

function Install-GamerPreset {
    $apps = @("Steam", "Discord")
    if (-not (Show-LicenseAgreement $apps)) { return }
    Write-Host "[+] Установка геймерского набора..." -ForegroundColor Yellow
    choco install -y steam discord
    Pause
}

function Install-AllPresets {
    Install-StandardPreset
    Install-GamerPreset
}

function Show-ManualInstallList {
    Clear-Host
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host "         РУЧНАЯ УСТАНОВКА           " -ForegroundColor Magenta
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host ""

    $categories = @{
        "Браузеры" = @(
            @{Name='Opera'; Id='opera'},
            @{Name='Google Chrome'; Id='googlechrome'},
            @{Name='Mozilla Firefox'; Id='firefox'}
        )
        "Инструменты" = @(
            @{Name='SumatraPDF'; Id='sumatrapdf'},
            @{Name='7-Zip'; Id='7zip'},
            @{Name='AnyDesk'; Id='anydesk'},
            @{Name='BCUninstaller'; Id='bulk-crap-uninstaller'},
            @{Name='NAPS2'; Id='naps2'},
            @{Name='Warp'; Id='warp'}
        )
        "Связь" = @(
            @{Name='Telegram'; Id='telegram'},
            @{Name='Viber'; Id='viber'},
            @{Name='Microsoft Teams'; Id='msteams'},
            @{Name='Zoom'; Id='zoom'}
        )
        "Игры и Связь" = @(
            @{Name='Steam'; Id='steam'},
            @{Name='Discord'; Id='discord'}
        )
        "Офис" = @(
            @{Name='Onlyoffice'; Id='onlyoffice'}
        )
    }

    $allApps = @()
    $index = 1
    foreach ($category in $categories.Keys) {
        Write-Host "--- $category ---" -ForegroundColor Cyan
        foreach ($app in $categories[$category]) {
            $app.Index = $index
            $allApps += $app
            Write-Host "$index. $($app.Name)"
            $index++
        }
    }

    Write-Host ""
    $choice = Read-Host "Введите номера через запятую, что установить (0 для выхода)"

    if ($choice -eq '0') { return }

    $indexes = $choice -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[0-9]+$' }
    foreach ($i in $indexes) {
        $num = [int]$i - 1
        if ($num -ge 0 -and $num -lt $allApps.Count) {
            choco install -y $($allApps[$num].Id)
        } else {
            Write-Host "[!] Неверный выбор: $($i)" -ForegroundColor Red
        }
    }
    Pause
}

function Update-AllChoco {
    Write-Host "[+] Проверка на доступные обновления..." -ForegroundColor Yellow
    $updates = choco outdated | Select-String -Pattern '^\S+' | ForEach-Object { $_.Line.Split(' ')[0] } | Where-Object { $_ -ne "Outdated" -and $_ -ne "Package" }
    if ($updates.Count -eq 0) {
        Write-Host "Все пакеты уже обновлены." -ForegroundColor Green
        Pause
        return
    }
    Write-Host "Можно обновить следующие пакеты:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $updates.Count; $i++) {
        Write-Host "$($i+1). $($updates[$i])"
    }
    $selection = Read-Host "Введите номера через запятую для обновления или нажмите Enter для обновления всех (0 для отмены)"

    if ($selection -eq '0') {
        Write-Host "Обновление отменено." -ForegroundColor DarkYellow
        Pause
        return
    } elseif ([string]::IsNullOrWhiteSpace($selection)) {
        choco upgrade all -y
    } else {
        $selectedIndexes = $selection -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[0-9]+$' }
        foreach ($index in $selectedIndexes) {
            $i = [int]$index - 1
            if ($i -ge 0 -and $i -lt $updates.Count) {
                choco upgrade $($updates[$i]) -y
            } else {
                Write-Host "[!] Неверный выбор: $index" -ForegroundColor Red
            }
        }
    }
    Pause
}

$backToMain = $false

while (-not $backToMain) {
    Show-InstallMenu
    $choice = Read-Host "Выберите опцию (0-3)"
    switch ($choice) {
        '1' {
            if (Check-Choco) {
                $presetBack = $false
                while (-not $presetBack) {
                    Show-PresetMenu
                    $presetChoice = Read-Host "Выберите пресет (0-3)"
                    switch ($presetChoice) {
                        '1' { Install-StandardPreset }
                        '2' { Install-GamerPreset }
                        '3' { Install-AllPresets }
                        '0' { $presetBack = $true }
                        default { Write-Host "Неверный ввод. Попробуйте снова." -ForegroundColor Red; Pause }
                    }
                }
            }
        }
        '2' {
            if (Check-Choco) {
                Show-ManualInstallList
            }
        }
        '3' {
            if (Check-Choco) {
                Update-AllChoco
            }
        }
        '0' {
            Write-Host "Возврат в главное меню..." -ForegroundColor Green
            Start-Sleep -Seconds 1
            try {
                $menuScript = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/menu.ps1" -UseBasicParsing
                Invoke-Expression $menuScript.Content
            } catch {
                Write-Host "[!] Не удалось загрузить меню. Проверьте подключение к интернету." -ForegroundColor Red
            }
            $backToMain = $true
        }
        default {
            Write-Host "Неверный ввод. Попробуйте снова." -ForegroundColor Red
            Pause
        }
    }
}
