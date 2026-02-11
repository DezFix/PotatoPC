# Ссылки на твои файлы на GitHub
$JsonUrl = "https://raw.githubusercontent.com/DezFix/PotatoPC/main/apps.json"
$MainMenuUrl = "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/menu.ps1"

# Прямая ссылка на пакет WinGet (v1.12.470)
$WinGetBundleUrl = "https://github.com/microsoft/winget-cli/releases/download/v1.12.470/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"

# --- Вспомогательные функции стиля ---

function Write-FrameHeader {
    param([string]$Text)
    $Width = 71
    $Padding = [math]::Max(0, [int](($Width - $Text.Length) / 2))
    $LeftPad = " " * $Padding
    $RightPad = " " * ($Width - $Text.Length - $Padding)
    
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║$LeftPad$Text$RightPad║" -ForegroundColor Yellow
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
}

function Write-InvalidInput {
    Write-Host "`n[!] Неверный ввод, попробуйте снова." -ForegroundColor Red
    Start-Sleep -Seconds 1
}

# --- Функция установки WinGet ---

function Ensure-WinGet {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Clear-Host
        Write-FrameHeader "УСТАНОВКА WINGET"
        Write-Host "[!] WinGet не обнаружен в системе." -ForegroundColor Red
        Write-Host "[*] Попытка автоматической загрузки и установки..." -ForegroundColor Cyan
        
        $tempPath = "$env:TEMP\WinGet.msixbundle"
        
        try {
            # Скачивание пакета
            Write-Host "[>] Загрузка пакета с GitHub..." -ForegroundColor Gray
            Invoke-WebRequest -Uri $WinGetBundleUrl -OutFile $tempPath -ErrorAction Stop
            
            # Установка пакета
            Write-Host "[>] Установка пакета в систему..." -ForegroundColor Gray
            Add-AppxPackage -Path $tempPath -ErrorAction Stop
            
            Write-Host "[+] WinGet успешно установлен!" -ForegroundColor Green
            Remove-Item $tempPath -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        catch {
            # Если автоматика не сработала
            Write-Host "`n[!] ОШИБКА АВТОМАТИЧЕСКОЙ УСТАНОВКИ" -ForegroundColor Red
            Write-Host "------------------------------------------------------------" -ForegroundColor Yellow
            Write-Host " Пожалуйста, установите WinGet вручную по ссылке ниже:" -ForegroundColor White
            Write-Host " https://github.com/microsoft/winget-cli/releases/tag/v1.12.470" -ForegroundColor Cyan
            Write-Host "------------------------------------------------------------" -ForegroundColor Yellow
            Write-Host "`nНажмите любую клавишу, чтобы выйти..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            exit
        }
    }
}

function Get-AppData {
    try { return Invoke-RestMethod -Uri $JsonUrl }
    catch { Write-Host "[!] Ошибка загрузки JSON конфигурации" -ForegroundColor Red; return $null }
}

# --- Основные меню ---

function Show-Main {
    Ensure-WinGet
    $Data = Get-AppData
    if (-not $Data) { Pause; return }

    while ($true) {
        Clear-Host
        Write-FrameHeader "WICKED RAVEN SYSTEM TOOLKIT : SOFTWARE"
        
        Write-Host " 1. " -ForegroundColor Green -NoNewline
        Write-Host "Установка пресета (набора программ)"
        
        Write-Host " 2. " -ForegroundColor Green -NoNewline
        Write-Host "Установка программ по категориям"
        
        Write-Host " 3. " -ForegroundColor Green -NoNewline
        Write-Host "Обновление установленного ПО"
        
        Write-Host ""
        Write-Host " 0. " -ForegroundColor Red -NoNewline
        Write-Host "Возврат в системный Toolkit"
        Write-Host ""
        
        $choice = Read-Host "Выберите опцию"

        switch ($choice) {
            "1" { Menu-Presets $Data }
            "2" { Menu-Categories $Data }
            "3" { Menu-UpdateCenter }
            "0" {
                Write-Host "`nВозврат в главное меню..." -ForegroundColor Green
                Start-Sleep -Seconds 1
                iex (irm $MainMenuUrl)
                return 
            }
            Default { Write-InvalidInput }
        }
    }
}

function Menu-Presets {
    param($Data)
    while ($true) {
        Clear-Host
        Write-FrameHeader "ВЫБОР ПРЕСЕТА"
        
        if (-not $Data.Presets) {
            Write-Host "[!] В JSON не найден раздел 'Presets'." -ForegroundColor Red
            Pause; return
        }

        $presetNames = $Data.Presets.PSObject.Properties.Name
        for ($i=0; $i -lt $presetNames.Count; $i++) {
            Write-Host " $($i+1). " -ForegroundColor Green -NoNewline
            Write-Host "$($presetNames[$i])"
        }
        
        Write-Host ""
        Write-Host " 0. " -ForegroundColor Red -NoNewline
        Write-Host "Назад"
        Write-Host ""

        $pChoice = Read-Host "Выберите номер пресета"
        if ($pChoice -eq "0") { return }
        
        if ($pChoice -match '^\d+$' -and [int]$pChoice -gt 0 -and [int]$pChoice -le $presetNames.Count) {
            $selected = $presetNames[[int]$pChoice - 1]
            Write-Host "`n[>] Установка набора: $selected..." -ForegroundColor Cyan
            foreach ($id in $Data.Presets.$selected) {
                Write-Host " - Установка $id" -ForegroundColor Gray
                winget install --id $id --silent --accept-package-agreements --accept-source-agreements
            }
            Write-Host "[+] Готово!" -ForegroundColor Green
            Pause
        } else { Write-InvalidInput }
    }
}

function Menu-Categories {
    param($Data)
    while ($true) {
        Clear-Host
        Write-FrameHeader "КАТЕГОРИИ ПРОГРАММ"
        
        $catNames = $Data.ManualCategories.PSObject.Properties.Name
        for ($i=0; $i -lt $catNames.Count; $i++) {
            $num = ($i + 1).ToString().PadRight(2)
            Write-Host " $num. " -ForegroundColor Green -NoNewline
            Write-Host "$($catNames[$i])"
        }
        
        Write-Host ""
        Write-Host " 0. " -ForegroundColor Red -NoNewline
        Write-Host "Назад"
        Write-Host ""

        $cChoice = Read-Host "Выберите категорию"
        if ($cChoice -eq "0") { return }

        if ($cChoice -match '^\d+$' -and [int]$cChoice -gt 0 -and [int]$cChoice -le $catNames.Count) {
            $selectedCat = $catNames[[int]$cChoice - 1]
            Menu-AppList $Data.ManualCategories.$selectedCat $selectedCat
        } else { Write-InvalidInput }
    }
}

function Menu-AppList {
    param($AppList, $CatName)
    while ($true) {
        Clear-Host
        Write-FrameHeader "КАТЕГОРИЯ: $CatName"
        
        for ($i=0; $i -lt $AppList.Count; $i++) {
            $num = ($i + 1).ToString().PadRight(2)
            Write-Host " $num. " -ForegroundColor Green -NoNewline
            Write-Host "$($AppList[$i].Name.PadRight(25))" -NoNewline
            Write-Host " - $($AppList[$i].Description)" -ForegroundColor Gray
        }
        
        Write-Host ""
        Write-Host " 0. " -ForegroundColor Red -NoNewline
        Write-Host "Назад к списку категорий"
        Write-Host ""

        $input = Read-Host "Введите номера через запятую"
        if ($input -eq "0") { return }

        try {
            foreach ($idx in $input.Split(',')) {
                $app = $AppList[[int]$idx.Trim() - 1]
                if ($app) {
                    Write-Host "`n[>] Установка $($app.Name)..." -ForegroundColor Cyan
                    winget install --id $app.Id --silent --accept-package-agreements
                }
            }
            Write-Host "`n[+] Готово." -ForegroundColor Green
            Pause
        } catch { Write-InvalidInput }
    }
}

function Menu-UpdateCenter {
    while ($true) {
        Clear-Host
        Write-FrameHeader "ЦЕНТР ОБНОВЛЕНИЙ"
        Write-Host "[*] Сканирование системы... " -ForegroundColor Gray
        
        $rawUpdates = winget upgrade | Select-String -Pattern '^\S+' | Select-Object -Skip 2
        
        if (-not $rawUpdates) {
            Write-Host "[+] Все программы в актуальном состоянии." -ForegroundColor Green
            Pause; return
        }

        $upgradeList = @()
        for ($i=0; $i -lt $rawUpdates.Count; $i++) {
            $line = $rawUpdates[$i].ToString()
            $parts = $line -split '\s{2,}'
            if ($parts.Count -ge 2) {
                $upgradeList += [PSCustomObject]@{ Name = $parts[0]; ID = $parts[1] }
                $num = ($i + 1).ToString().PadRight(2)
                Write-Host " $num. " -ForegroundColor Green -NoNewline
                Write-Host "$($parts[0].PadRight(25)) (Доступно: $($parts[3]))"
            }
        }

        Write-Host ""
        Write-Host " A. " -ForegroundColor Yellow -NoNewline
        Write-Host "ОБНОВИТЬ ВСЁ"
        Write-Host " 0. " -ForegroundColor Red -NoNewline
        Write-Host "Назад"
        Write-Host ""

        $uChoice = Read-Host "Выберите номер или 'A'"
        
        if ($uChoice -eq "A" -or $uChoice -eq "a" -or $uChoice -eq "ф") {
            winget upgrade --all --silent --accept-package-agreements
            Pause; return
        } elseif ($uChoice -eq "0") {
            return
        } elseif ($uChoice -match '^\d+$' -and $upgradeList[[int]$uChoice - 1]) {
            $target = $upgradeList[[int]$uChoice - 1]
            winget upgrade --id $target.ID --silent --accept-package-agreements
            Pause
        } else { Write-InvalidInput }
    }
}

# Запуск
Show-Main
