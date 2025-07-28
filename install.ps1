# Добавление необходимых сборок для работы с графическим интерфейсом
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Проверка на наличие прав администратора
if (-not ([Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    [System.Windows.Forms.MessageBox]::Show("Этот скрипт должен быть запущен от имени администратора. Пожалуйста, перезапустите PowerShell с правами администратора и повторите попытку.", "Недостаточно прав", "OK", "Error")
    exit
}

# Функция для отображения пользовательского диалогового окна с кнопками "Да" и "Нет"
function ShowCustomMessageBox {
    param(
        [string]$Title,
        [string]$Message,
        [string[]]$ButtonTexts # Например, @("Да", "Нет")
    )

    $msgBoxForm = New-Object System.Windows.Forms.Form
    $msgBoxForm.Text = $Title
    $msgBoxForm.Size = New-Object System.Drawing.Size(450, 200) # Увеличен размер для лучшей читаемости
    $msgBoxForm.StartPosition = "CenterScreen"
    $msgBoxForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog # Фиксированный размер окна
    $msgBoxForm.MinimizeBox = [bool]$false # Отключить кнопку свернуть
    $msgBoxForm.MaximizeBox = [bool]$false # Отключить кнопку развернуть

    $msgLabel = New-Object System.Windows.Forms.Label
    $msgLabel.Text = $Message
    $msgLabel.Location = New-Object System.Drawing.Point(20, 20)
    $msgLabel.AutoSize = [bool]$true
    $msgLabel.MaximumSize = New-Object System.Drawing.Size(($msgBoxForm.Width - 40), 0) # Перенос текста
    $msgBoxForm.Controls.Add($msgLabel)

    $buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft # Кнопки справа налево
    $buttonPanel.AutoSize = [bool]$true
    $buttonPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right # Привязка к нижнему правому углу
    $msgBoxForm.Controls.Add($buttonPanel)

    $result = ""
    foreach ($text in $ButtonTexts) {
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $text
        $btn.Size = New-Object System.Drawing.Size(90, 30) # Увеличен размер кнопок
        [void]$btn.Add_Click({
            $result = $btn.Text
            $msgBoxForm.Close()
        })
        [void]$buttonPanel.Controls.Add($btn)
    }

    $buttonPanel.Location = New-Object System.Drawing.Point(($msgBoxForm.ClientSize.Width - $buttonPanel.Width - 20), ($msgBoxForm.ClientSize.Height - $buttonPanel.Height - 20))

    [void]$msgBoxForm.ShowDialog()
    return $result
}

# URL-адрес JSON-файла с GitHub, содержащего информацию о приложениях
$jsonUrl = 'https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/apps.json'

# Глобальная переменная для хранения данных о приложениях
$script:apps = @()
$script:jsonRaw = $null # Глобальная переменная для хранения сырых данных JSON
# Глобальная переменная для хранения ID всех отмеченных приложений
$script:globalCheckedAppIds = New-Object System.Collections.Generic.HashSet[string]

# Функция для загрузки и парсинга данных о приложениях
function LoadAppsData {
    param(
        [string]$Url
    )
    try {
        $script:jsonRaw = Invoke-RestMethod -Uri $Url -UseBasicParsing # Сохраняем в глобальную переменную
        $script:apps = @() # Очищаем глобальный массив перед заполнением
        
        # Проверяем, существует ли ManualCategories и является ли он объектом (или хэш-таблицей в PowerShell)
        if ($script:jsonRaw.ManualCategories -is [System.Management.Automation.PSCustomObject] -or $script:jsonRaw.ManualCategories -is [System.Collections.Hashtable]) {
            # Более надежный способ итерации по свойствам PSCustomObject
            $script:jsonRaw.ManualCategories.PSObject.Properties | ForEach-Object {
                $categoryName = $_.Name
                $categoryApps = $_.Value
                
                # Проверяем, является ли значение категории массивом приложений
                if ($categoryApps -is [System.Array]) {
                    foreach ($app in $categoryApps) {
                        # Проверяем наличие полей Name, Id и Description для каждого приложения
                        if ($app.Name -and $app.Id -and $app.Description) {
                            $newApp = [PSCustomObject]@{
                                Name = $app.Name
                                Id   = $app.Id
                                Description = $app.Description
                                Category = $categoryName # Категория сохраняется для фильтрации
                                # Добавляем флаг, если описание содержит "Установка требует --source msstore"
                                RequiresMsStoreSource = $app.Description -like "*Установка требует --source msstore*"
                            }
                            # Явно добавляем метод ToString, который будет использоваться CheckedListBox
                            Add-Member -InputObject $newApp -MemberType ScriptMethod -Name ToString -Value { return "$($this.Name)" } -Force
                            $script:apps += $newApp
                        }
                    }
                }
            }
        }
        return [bool]$true
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Не удалось загрузить apps.json. Проверьте подключение к Интернету или URL-адрес. Ошибка: $($_.Exception.Message)", "Ошибка загрузки", "OK", "Error")
        return [bool]$false
    }
}

# Функция для проверки, установлено ли приложение в системе (через записи деинсталлятора и AppX)
function Check-ApplicationInstalled {
    param(
        [string]$AppNamePartial # Часть имени имени для поиска
    )
    # Отладка: Выводим информацию о проверке
    Write-Host "Отладка: Проверка, установлено ли приложение с частичным именем '$AppNamePartial'..." -ForegroundColor DarkYellow

    # Check traditional uninstall entries
    $uninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($path in $uninstallPaths) {
        if (Test-Path $path) {
            $foundUninstall = Get-ItemProperty "$path\*" -ErrorAction SilentlyContinue | Where-Object {
                $_.DisplayName -like "*$AppNamePartial*" -and $_.UninstallString
            }
            if ($foundUninstall) {
                Write-Host "Отладка: Найдено в реестре: $($foundUninstall.DisplayName)" -ForegroundColor DarkGreen
                return $true
            }
        }
    }

    # Check for AppX packages (Microsoft Store apps)
    try {
        $foundAppX = Get-AppxPackage -Name "*$AppNamePartial*" -ErrorAction SilentlyContinue
        if ($foundAppX) {
            Write-Host "Отладка: Найдено как AppX пакет: $($foundAppX.Name)" -ForegroundColor DarkGreen
            return $true
        }
    } catch {
        # Используем Write-Warning, чтобы не прерывать выполнение, но сообщить об ошибке
        Write-Warning "Отладка: Не удалось проверить наличие AppX пакетов. Ошибка: $($_.Exception.Message)"
    }
    Write-Host "Отладка: Приложение с частичным именем '$AppNamePartial' не найдено." -ForegroundColor DarkRed
    return $false
}

# Функция для получения версии Winget
function Get-WingetVersion {
    try {
        # Capture all output, including potential header lines
        $rawOutput = winget --version 2>&1 | Out-String
        
        # Look for a line that contains "vX.Y.Z" pattern
        if ($rawOutput -match 'v(\d+\.\d+\.\d+)') {
            $versionString = $matches[1]
            return [version]$versionString
        }
    } catch {
        # Убрано Write-Warning, так как это отладочный вывод
    }
    return $null
}

# Функция для отображения окна выбора обновлений Winget
function ShowUpgradeWindow {
    # Установка кодировки для корректного отображения вывода Winget
    try {
        $OutputEncoding = [System.Text.Encoding]::UTF8
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    } catch {
        Write-Warning "Не удалось установить OutputEncoding для консоли: $($_.Exception.Message)"
    }

    [System.Windows.Forms.MessageBox]::Show("Получение списка доступных обновлений через Winget. Пожалуйста, подождите...", "Проверка обновлений", "OK", "Information")
    Write-Host "Получение списка доступных обновлений через Winget..." -ForegroundColor Cyan

    $parsedPackages = @()
    $wingetRawOutput = ""

    # 1. Попытка получить JSON-вывод
    try {
        $wingetRawOutput = (winget upgrade --output json --accept-source-agreements --accept-package-agreements 2>&1 | Out-String)
        $jsonStart = $wingetRawOutput.IndexOf('{')
        $jsonEnd = $wingetRawOutput.LastIndexOf('}')
        
        if ($jsonStart -ne -1 -and $jsonEnd -ne -1 -and $jsonEnd -gt $jsonStart) {
            $wingetOutputJson = $wingetRawOutput.Substring($jsonStart, $jsonEnd - $jsonStart + 1)
            $jsonResult = $wingetOutputJson | ConvertFrom-Json -ErrorAction SilentlyContinue
            
            if ($jsonResult -and $jsonResult.UpgradePackages -and $jsonResult.UpgradePackages.Count -gt 0) {
                foreach ($pkg in $jsonResult.UpgradePackages) {
                    $parsedPackages += [PSCustomObject]@{
                        Name             = $pkg.Package.PackageIdentifier # Use PackageIdentifier from JSON
                        Id               = $pkg.Package.PackageIdentifier
                        CurrentVersion   = $pkg.Version
                        AvailableVersion = $pkg.AvailableVersion
                        Source           = $pkg.Source
                        Description      = "Текущая версия: $($pkg.Version)`nДоступная версия: $($pkg.AvailableVersion)`nИсточник: $($pkg.Source)"
                    }
                }
            } else {
                # Fallback to text parsing if JSON is empty or malformed
                $wingetRawOutput = (winget upgrade --accept-source-agreements --accept-package-agreements 2>&1 | Out-String)
                # Text parsing logic
                $upgradeLines = $wingetRawOutput -split "`r?`n" | Where-Object { $_ -match '^\s*\S' -and ($_ -notmatch '^Name\s+Id\s+Version') -and ($_ -notmatch '^-{3,}') }
                foreach ($line in $upgradeLines) {
                    if ($line -match '^(?<Name>.+?)\s+(?<Id>[^\s]+)\s+(?<CurrentVersion>[^\s]+)\s+(?<AvailableVersion>[^\s]+)\s*(?<Source>.*)$') {
                        $parsedPackages += [PSCustomObject]@{
                            Name             = $matches['Name'].Trim()
                            Id               = $matches['Id'].Trim()
                            CurrentVersion   = $matches['CurrentVersion'].Trim()
                            AvailableVersion = $matches['AvailableVersion'].Trim()
                            Source           = $matches['Source'].Trim()
                            Description      = "Текущая версия: $($matches['CurrentVersion'])`nДоступная версия: $($matches['AvailableVersion'])`nИсточник: $($matches['Source'])"
                        }
                    }
                }
            }
        } else {
            # Fallback to text parsing if JSON structure is not found
            $wingetRawOutput = (winget upgrade --accept-source-agreements --accept-package-agreements 2>&1 | Out-String)
            # Text parsing logic
            $upgradeLines = $wingetRawOutput -split "`r?`n" | Where-Object { $_ -match '^\s*\S' -and ($_ -notmatch '^Name\s+Id\s+Version') -and ($_ -notmatch '^-{3,}') }
            foreach ($line in $upgradeLines) {
                if ($line -match '^(?<Name>.+?)\s+(?<Id>[^\s]+)\s+(?<CurrentVersion>[^\s]+)\s+(?<AvailableVersion>[^\s]+)\s*(?<Source>.*)$') {
                    $parsedPackages += [PSCustomObject]@{
                        Name             = $matches['Name'].Trim()
                        Id               = $matches['Id'].Trim()
                        CurrentVersion   = $matches['CurrentVersion'].Trim()
                        AvailableVersion = $matches['AvailableVersion'].Trim()
                        Source           = $matches['Source'].Trim()
                        Description      = "Текущая версия: $($matches['CurrentVersion'])`nДоступная версия: $($matches['AvailableVersion'])`nИсточник: $($matches['Source'])"
                    }
                }
            }
        }
    } catch {
        # Fallback to text parsing if JSON command fails
        $wingetRawOutput = (winget upgrade --accept-source-agreements --accept-package-agreements 2>&1 | Out-String)
        # Text parsing logic
        $upgradeLines = $wingetRawOutput -split "`r?`n" | Where-Object { $_ -match '^\s*\S' -and ($_ -notmatch '^Name\s+Id\s+Version') -and ($_ -notmatch '^-{3,}') }
        foreach ($line in $upgradeLines) {
            if ($line -match '^(?<Name>.+?)\s+(?<Id>[^\s]+)\s+(?<CurrentVersion>[^\s]+)\s+(?<AvailableVersion>[^\s]+)\s*(?<Source>.*)$') {
                $parsedPackages += [PSCustomObject]@{
                    Name             = $matches['Name'].Trim()
                    Id               = $matches['Id'].Trim()
                    CurrentVersion   = $matches['CurrentVersion'].Trim()
                    AvailableVersion = $matches['AvailableVersion'].Trim()
                    Source           = $matches['Source'].Trim()
                    Description      = "Текущая версия: $($matches['CurrentVersion'])`nДоступная версия: $($matches['AvailableVersion'])`nИсточник: $($matches['Source'])"
                }
            }
        }
    }

    if ($parsedPackages.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Нет доступных обновлений через Winget.", "Обновления", "OK", "Information")
        return
    }

    # Создание нового окна
    $upgradeForm = New-Object System.Windows.Forms.Form
    $upgradeForm.Text = "Доступные обновления"
    $upgradeForm.Size = New-Object System.Drawing.Size(600, 500)
    $upgradeForm.StartPosition = "CenterScreen"
    $upgradeForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $upgradeForm.MinimizeBox = [bool]$false
    $upgradeForm.MaximizeBox = [bool]$false

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Выберите приложения для обновления:"
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(10, 10)
    $upgradeForm.Controls.Add($label)

    # ComboBox для сортировки
    $sortComboBox = New-Object System.Windows.Forms.ComboBox
    $sortComboBox.Location = New-Object System.Drawing.Point(380, 10) # Размещаем справа от метки
    $sortComboBox.Size = New-Object System.Drawing.Size(190, 30)
    $sortComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList # Только выбор из списка
    $sortComboBox.Items.AddRange(@(
        "По имени (А-Я)",
        "По имени (Я-А)",
        "По ID (А-Я)",
        "По ID (Я-А)",
        "По версии (по возрастанию)",
        "По версии (по убыванию)"
    ))
    $sortComboBox.SelectedIndex = 0 # Выбираем сортировку по умолчанию (по имени А-Я)
    $upgradeForm.Controls.Add($sortComboBox)

    # CheckedListBox для выбора приложений
    $list = New-Object System.Windows.Forms.CheckedListBox
    $list.Location = New-Object System.Drawing.Point(10, ($label.Location.Y + $label.Height + 5)) # Смещаем список ниже метки
    $list.Size = New-Object System.Drawing.Size(560, 350) 
    $list.CheckOnClick = $true
    
    # Функция для обновления списка CheckedListBox с учетом сортировки
    $script:UpdateUpgradeCheckedList = {
        param($packages, $checkedItems = $null) # $packages - это всегда полный список из $parsedPackages
        $list.Items.Clear()
        
        # Сохраняем текущие отмеченные ID
        $currentCheckedIds = New-Object System.Collections.Generic.HashSet[string]
        if ($checkedItems -ne $null) {
            foreach ($item in $checkedItems) {
                [void]$currentCheckedIds.Add($item.Id)
            }
        }

        # Применяем сортировку
        $selectedSort = $sortComboBox.SelectedItem # Получаем текущий выбранный вариант сортировки
        $sortedPackages = @()
        switch ($selectedSort) {
            "По имени (А-Я)" { $sortedPackages = $packages | Sort-Object Name }
            "По имени (Я-А)" { $sortedPackages = $packages | Sort-Object Name -Descending }
            "По ID (А-Я)" { $sortedPackages = $packages | Sort-Object Id }
            "По ID (Я-А)" { $sortedPackages = $packages | Sort-Object Id -Descending }
            "По версии (по возрастанию)" {
                $sortedPackages = $packages | Sort-Object {
                    try {
                        [version]$_.AvailableVersion
                    } catch {
                        # If conversion fails, assign a very high version to push it to the end
                        [version]'9999.9999.9999.9999'
                    }
                }
            }
            "По версии (по убыванию)" {
                $sortedPackages = $packages | Sort-Object {
                    try {
                        [version]$_.AvailableVersion
                    } catch {
                        # If conversion fails, assign a very low version to push it to the end
                        [version]'0.0.0.0'
                    }
                } -Descending
            }
        }

        foreach ($pkg in $sortedPackages) {
            # Добавляем метод ToString для корректного отображения в CheckedListBox
            Add-Member -InputObject $pkg -MemberType ScriptMethod -Name ToString -Value { return "$($this.Name) (v$($this.CurrentVersion) -> v$($this.AvailableVersion))" } -Force
            [void]$list.Items.Add($pkg)
            
            # Восстанавливаем состояние отмеченного элемента
            if ($currentCheckedIds.Contains($pkg.Id)) {
                $index = $list.Items.IndexOf($pkg) 
                if ($index -ne -1) {
                    $list.SetItemChecked($index, [bool]$true)
                }
            }
        }
    }

    # Обработчик изменения выбора в ComboBox сортировки
    [void]$sortComboBox.Add_SelectedIndexChanged({
        $currentCheckedItems = @($list.CheckedItems) # Сохраняем текущий выбор
        $script:UpdateUpgradeCheckedList.Invoke($parsedPackages, $currentCheckedItems)
    })

    # Изначальная сортировка и заполнение списка
    $script:UpdateUpgradeCheckedList.Invoke($parsedPackages, @()) 

    $upgradeForm.Controls.Add($list)

    # Добавление кнопок "Выбрать все" и "Убрать отмеченные"
    $selectAllUpdatesBtn = New-Object System.Windows.Forms.Button
    $selectAllUpdatesBtn.Text = "Выбрать все"
    $selectAllUpdatesBtn.Location = New-Object System.Drawing.Point(10, 410)
    $selectAllUpdatesBtn.Size = New-Object System.Drawing.Size(100, 30)
    [void]$selectAllUpdatesBtn.Add_Click({
        for ($i = 0; $i -lt $list.Items.Count; $i++) {
            $list.SetItemChecked($i, [bool]$true)
        }
    })
    $upgradeForm.Controls.Add($selectAllUpdatesBtn)

    $deselectAllUpdatesBtn = New-Object System.Windows.Forms.Button
    $deselectAllUpdatesBtn.Text = "Убрать отмеченные"
    $deselectAllUpdatesBtn.Location = New-Object System.Drawing.Point(($selectAllUpdatesBtn.Location.X + $selectAllUpdatesBtn.Width + 10), 410)
    $deselectAllUpdatesBtn.Size = New-Object System.Drawing.Size(130, 30)
    [void]$deselectAllUpdatesBtn.Add_Click({
        for ($i = 0; $i -lt $list.Items.Count; $i++) {
            $list.SetItemChecked($i, [bool]$false)
        }
    })
    $upgradeForm.Controls.Add($deselectAllUpdatesBtn)


    # Add ToolTip for updatable list
    $updateToolTip = New-Object System.Windows.Forms.ToolTip
    $updateToolTip.AutoPopDelay = 5000
    $updateToolTip.InitialDelay = 500
    $updateToolTip.ReshowDelay = 500
    $updateToolTip.ShowAlways = [bool]$true

    [void]$list.Add_MouseMove({
        param($sender, $e)
        $index = $list.IndexFromPoint($e.Location)
        if ($index -ne -1) {
            $appObj = $list.Items[$index]
            if ($appObj -is [PSCustomObject] -and $appObj.Description) {
                $updateToolTip.SetToolTip($list, $appObj.Description)
            } else {
                $updateToolTip.SetToolTip($list, "")
            }
        } else {
            $updateToolTip.SetToolTip($list, "")
        }
    })

    $upgradeButton = New-Object System.Windows.Forms.Button
    $upgradeButton.Text = "Обновить выбранные"
    $upgradeButton.Location = New-Object System.Drawing.Point(($deselectAllUpdatesBtn.Location.X + $deselectAllUpdatesBtn.Width + 10), 410)
    $upgradeButton.Size = New-Object System.Drawing.Size(150, 30)
    $upgradeButton.Add_Click({
        $selected = @($list.CheckedItems)
        if ($selected.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Вы не выбрали ни одного пакета.", "Внимание", "OK", "Warning")
            return
        }

        [System.Windows.Forms.MessageBox]::Show("Запуск обновления выбранных приложений. Прогресс будет отображен в текущей консоли.", "Обновление", "OK", "Information")
        foreach ($pkg in $selected) {
            Write-Host "`nОбновление $($pkg.Name) ($($pkg.Id)) до версии $($pkg.AvailableVersion)" -ForegroundColor Cyan
            winget upgrade --id $($pkg.Id) --accept-source-agreements --accept-package-agreements 2>&1 | Write-Host
        }

        [System.Windows.Forms.MessageBox]::Show("Обновление завершено.", "Готово", "OK", "Information")
        $upgradeForm.Close()
    })
    $upgradeForm.Controls.Add($upgradeButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Отмена"
    $cancelButton.Location = New-Object System.Drawing.Point(($upgradeButton.Location.X + $upgradeButton.Width + 10), 410)
    $cancelButton.Size = New-Object System.Drawing.Size(100, 30)
    $cancelButton.Add_Click({ $upgradeForm.Close() })
    $upgradeForm.Controls.Add($cancelButton)

    [void]$upgradeForm.ShowDialog()
}


# Попытка загрузить JSON-файл при запуске скрипта
if (-not (LoadAppsData $jsonUrl)) {
    exit # Выходим, если не удалось загрузить данные
}

# Создание главной формы графического интерфейса
$form = New-Object System.Windows.Forms.Form
$form.Text = "Wicked Raven Installer" # Заголовок окна
$form.Size = New-Object System.Drawing.Size(700, 620) # Уменьшена высота формы
$form.StartPosition = "CenterScreen" # Размещение формы по центру экрана
$form.MinimumSize = New-Object System.Drawing.Size(500, 550) # Скорректирован минимальный размер окна
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi # Автоматическое масштабирование по DPI

# --- Группа для кнопок "Выбрать все" и "Убрать отмеченные" ---
$selectionButtonsGroupBox = New-Object System.Windows.Forms.GroupBox
$selectionButtonsGroupBox.Text = "Выбор приложений"
$selectionButtonsGroupBox.Location = New-Object System.Drawing.Point(10, 10) # Перемещено вверх
$selectionButtonsGroupBox.Size = New-Object System.Drawing.Size(280, 70) # Достаточно места для двух кнопок
$selectionButtonsGroupBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left # Привязка к верху и левому краю
[void]$form.Controls.Add($selectionButtonsGroupBox)

# Создание кнопки "Выбрать все"
$selectAllBtn = New-Object System.Windows.Forms.Button
$selectAllBtn.Text = "Выбрать все"
$selectAllBtn.Location = New-Object System.Drawing.Point(10, 25) # Позиция внутри selectionButtonsGroupBox
$selectAllBtn.Size = New-Object System.Drawing.Size(100, 30)
$selectAllBtn.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left # Привязка к верху и левому краю
[void]$selectAllBtn.Add_Click({
    # Обновляем глобальный список отмеченных ID при выборе всех
    for ($i = 0; $i -lt $checkedList.Items.Count; $i++) {
        $appObj = $checkedList.Items[$i] # Получаем объект приложения
        if ($appObj) {
            [void]$script:globalCheckedAppIds.Add($appObj.Id)
        }
        $checkedList.SetItemChecked($i, [bool]$true)
    }
})
[void]$selectionButtonsGroupBox.Controls.Add($selectAllBtn)

# Создание кнопки "Убрать отмеченные"
$deselectAllBtn = New-Object System.Windows.Forms.Button
$deselectAllBtn.Text = "Убрать отмеченные"
$deselectAllBtnXLocation = $selectAllBtn.Location.X + $selectAllBtn.Width + 10
$deselectAllBtn.Location = New-Object System.Drawing.Point($deselectAllBtnXLocation, 25) # После кнопки "Выбрать все"
$deselectAllBtn.Size = New-Object System.Drawing.Size(130, 30) # Немного шире для текста
$deselectAllBtn.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left # Привязка к верху и левому краю
[void]$deselectAllBtn.Add_Click({
    # Очищаем глобальный список отмеченных ID при снятии всех
    for ($i = 0; $i -lt $checkedList.Items.Count; $i++) {
        $appObj = $checkedList.Items[$i] # Получаем объект приложения
        if ($appObj) {
            [void]$script:globalCheckedAppIds.Remove($appObj.Id)
        }
        $checkedList.SetItemChecked($i, [bool]$false)
    }
})
[void]$selectionButtonsGroupBox.Controls.Add($deselectAllBtn)


# Создание ComboBox для фильтрации по категориям
$categoryComboBox = New-Object System.Windows.Forms.ComboBox
$categoryComboBox.Location = New-Object System.Drawing.Point(10, ($selectionButtonsGroupBox.Location.Y + $selectionButtonsGroupBox.Height + 10)) # Теперь под selectionButtonsGroupBox
$categoryComboBox.Size = New-Object System.Drawing.Size(200, 30)
$categoryComboBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left # Привязка к верху и левому краю
[void]$form.Controls.Add($categoryComboBox)

# Создание метки (Label) для инструкции пользователя
$label = New-Object System.Windows.Forms.Label
$label.Text = "Выберите приложения для установки:"
$label.Location = New-Object System.Drawing.Point(10, ($categoryComboBox.Location.Y + $categoryComboBox.Height + 5)) # Теперь под ComboBox
$label.AutoSize = [bool]$true # Автоматический размер метки по содержимому
$label.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right # Привязка к верху, левому и правому краю
[void]$form.Controls.Add($label)

# Создание списка с флажками (CheckedListBox) для выбора приложений
$checkedList = New-Object System.Windows.Forms.CheckedListBox
$checkedList.Location = New-Object System.Drawing.Point(10, ($label.Location.Y + $label.Height + 10)) # Смещаем список ниже метки
$checkedList.Size = New-Object System.Drawing.Size(660, 350) # Скорректирован размер списка
$checkedList.CheckOnClick = [bool]$true # Позволяет отмечать/снимать флажок по одному клику
$checkedList.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right # Привязка ко всем краям
[void]$form.Controls.Add($checkedList)

# Создание ToolTip для отображения описания
$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 5000 # Время отображения подсказки (5 секунд)
$toolTip.InitialDelay = 500 # Задержка перед появлением подсказки (0.5 секунды)
$toolTip.ReshowDelay = 500 # Задержка перед повторным появлением подсказки (0.5 секунды)
$toolTip.ShowAlways = [bool]$true # Всегда показывать подсказку

# Обработчик события MouseMove для CheckedListBox для отображения подсказок
[void]$checkedList.Add_MouseMove({
    param($sender, $e)
    $index = $checkedList.IndexFromPoint($e.Location)
    if ($index -ne -1) {
        $appObj = $checkedList.Items[$index]
        if ($appObj -is [PSCustomObject] -and $appObj.Description) {
            $toolTip.SetToolTip($checkedList, $appObj.Description)
        } else {
            $toolTip.SetToolTip($checkedList, "") # Очистить подсказку, если нет описания
        }
    } else {
        $toolTip.SetToolTip($checkedList, "") # Очистить подсказку, если курсор не на элементе
    }
})

# Обработчик события ItemCheck для обновления глобального состояния
[void]$checkedList.Add_ItemCheck({
    param($sender, $e)
    $appObj = $checkedList.Items[$e.Index] # Теперь $appObj - это PSCustomObject напрямую
    if ($appObj) {
        if ($e.NewValue -eq [System.Windows.Forms.CheckState]::Checked) {
            [void]$script:globalCheckedAppIds.Add($appObj.Id)
        } else {
            [void]$script:globalCheckedAppIds.Remove($appObj.Id)
        }
    }
})


# Функция для заполнения ComboBox категорий
function PopulateCategoryComboBox {
    param(
        [ref]$ComboBox,
        [array]$AppsData # Используем уже обработанные данные $script:apps
    )
    [void]$ComboBox.Value.Items.Clear()
    [void]$ComboBox.Value.Items.Add("Все")
    
    $foundCategories = @()
    # Собираем уникальные категории из $script:apps
    $AppsData | Select-Object -ExpandProperty Category -Unique | Sort-Object | ForEach-Object {
        if ($_ -and ($_.ToString() -ne "")) { # Проверяем на null и пустую строку
            [void]$ComboBox.Value.Items.Add($_)
            $foundCategories += $_
        }
    }
    $ComboBox.Value.SelectedIndex = 0 # Сбрасываем выбор на "Все"

    # Диагностика: если не найдено категорий (кроме "Все")
    if ($foundCategories.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Не удалось загрузить категории из JSON-файла. Возможно, файл пуст или имеет неверную структуру 'ManualCategories'.", "Предупреждение: Категории не найдены", "OK", "Warning")
    }
}

# Функция для обновления списка приложений с учетом фильтрации по категориям
function UpdateCheckedList ($categoryFilter) {
    [void]$checkedList.Items.Clear() # Очищаем список перед заполнением

    $filteredApps = @()
    if ($categoryFilter -eq "Все" -or $categoryFilter -eq $null) {
        $filteredApps = $script:apps # Если выбрано "Все" или фильтр не указан, используем все приложения
    } else {
        # Фильтруем приложения по выбранной категории
        $filteredApps = $script:apps | Where-Object { $_.Category -eq $categoryFilter }
    }

    # Теперь просто добавляем отфильтрованные приложения (объекты)
    foreach ($app in $filteredApps) {
        [void]$checkedList.Items.Add($app) # Добавляем объект напрямую
        # Восстанавливаем состояние отмеченных элементов из глобального списка
        if ($script:globalCheckedAppIds.Contains($app.Id)) {
            # При поиске индекса CheckedListBox будет использовать метод ToString() объекта
            $index = $checkedList.Items.IndexOf($app) 
            if ($index -ne -1) {
                $checkedList.SetItemChecked($index, [bool]$true)
            }
        }
    }
}

# Обработчик события изменения выбора в ComboBox категорий
[void]$categoryComboBox.Add_SelectedIndexChanged({
    # Вызываем UpdateCheckedList с текущим выбранным элементом фильтрации
    UpdateCheckedList($categoryComboBox.SelectedItem)
})


# --- Создание единого GroupBox для нижних кнопок (Установить, Выход, Проверка обновлений, Обновить список) ---
$bottomButtonsGroupBox = New-Object System.Windows.Forms.GroupBox
$bottomButtonsGroupBox.Text = "Управление" # Заголовок для GroupBox кнопок
$bottomButtonsGroupBox.Location = New-Object System.Drawing.Point(10, ($checkedList.Location.Y + $checkedList.Height + 10))
# Ширина GroupBox, достаточная для трех кнопок (Установить, Выход, Проверка обновлений, Обновить список)
$bottomButtonsGroupBox.Size = New-Object System.Drawing.Size(540, 70) 
$bottomButtonsGroupBox.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right # Привязка к низу, левому и правому краю
[void]$form.Controls.Add($bottomButtonsGroupBox)

# Создание кнопки "Установить"
$installBtn = New-Object System.Windows.Forms.Button
$installBtn.Text = "Установить"
$installBtn.Location = New-Object System.Drawing.Point(10, 25) # Позиция внутри bottomButtonsGroupBox
$installBtn.Size = New-Object System.Drawing.Size(100, 30) # Размер кнопки
$installBtn.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left # Привязка к низу и левому краю
[void]$bottomButtonsGroupBox.Controls.Add($installBtn)

# Создание кнопки "Выход"
$exitBtn = New-Object System.Windows.Forms.Button
$exitBtn.Text = "Выход"
# Рассчитываем X-координату в отдельной переменной для надежности
$exitBtnXLocation = $installBtn.Location.X + $installBtn.Width + 10
$exitBtn.Location = New-Object System.Drawing.Point($exitBtnXLocation, 25) # После кнопки "Установить"
$exitBtn.Size = New-Object System.Drawing.Size(100, 30) # Размер кнопки
$exitBtn.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left # Привязка к низу и левому краю
# Добавление обработчика события клика для кнопки "Выход"
[void]$exitBtn.Add_Click({
    $menuScriptUrl = 'https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/menu.ps1'
    # Отладка: Сообщение о попытке загрузки и запуска меню
    Write-Host "Отладка: Попытка загрузить и запустить скрипт меню: $menuScriptUrl" -ForegroundColor Yellow
    try {
        # Загрузка содержимого скрипта
        $scriptContent = Invoke-RestMethod -Uri $menuScriptUrl -UseBasicParsing
        # Отладка: Сообщение об успешной загрузке
        Write-Host "Отладка: Скрипт меню успешно загружен. Попытка выполнения..." -ForegroundColor Green
        # Закрываем текущую форму перед запуском нового скрипта
        $form.Close()
        # Выполняем загруженный скрипт
        Invoke-Expression $scriptContent
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Не удалось загрузить или запустить menu.ps1. Проверьте подключение к Интернету или URL-адрес. Ошибка: $($_.Exception.Message)", "Ошибка запуска меню", "OK", "Error")
        # Отладка: Сообщение об ошибке при запуске меню
        Write-Host "Отладка: Ошибка при запуске скрипта меню: $($_.Exception.Message)" -ForegroundColor Red
    }
})
[void]$bottomButtonsGroupBox.Controls.Add($exitBtn)

# Создание кнопки "Проверка обновлений"
$checkUpdatesBtn = New-Object System.Windows.Forms.Button
$checkUpdatesBtn.Text = "Проверка обновлений"
$checkUpdatesBtnXLocation = $exitBtn.Location.X + $exitBtn.Width + 10
$checkUpdatesBtn.Location = New-Object System.Drawing.Point($checkUpdatesBtnXLocation, 25) # После кнопки "Выход"
$checkUpdatesBtn.Size = New-Object System.Drawing.Size(150, 30) # Увеличим ширину для текста
$checkUpdatesBtn.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left # Привязка к низу и левому краю
[void]$checkUpdatesBtn.Add_Click({
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        ShowUpgradeWindow # Вызываем функцию для выбора обновлений в GUI
    } else {
        # Изменено: Удалена опция "Открыть Microsoft Store", оставлена только ссылка в браузере
        $installWingetPrompt = ShowCustomMessageBox -Title "Winget не найден" -Message "Winget не найден в вашей системе. Что вы хотите сделать?" -ButtonTexts @("Открыть ссылку в браузере", "Отмена")
        if ($installWingetPrompt -eq "Открыть ссылку в браузере") {
            # Отладка: Выводим ссылку, которую пытаемся открыть
            Write-Host "Отладка: Попытка открыть ссылку в браузере: https://apps.microsoft.com/detail/9nblggh4nns1?hl=ru-RU&gl=UA" -ForegroundColor Yellow
            try {
                # Используем Start-Process с -Verb Open для надежного открытия URL
                [void](Start-Process "https://apps.microsoft.com/detail/9nblggh4nns1?hl=ru-RU&gl=UA" -Verb Open)
                # Отладка: Сообщение об успешном запуске процесса
                Write-Host "Отладка: Процесс Start-Process для ссылки должен быть запущен." -ForegroundColor Green
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Ошибка при открытии ссылки в браузере: $($_.Exception.Message)", "Ошибка", "OK", "Error")
                # Отладка: Сообщение об ошибке при открытии ссылки
                Write-Host "Отладка: Ошибка при открытии ссылки в браузере: $($_.Exception.Message)" -ForegroundColor Red
            }
            [System.Windows.Forms.MessageBox]::Show("Открыта страница Winget в браузере. Пожалуйста, следуйте инструкциям для ручной установки.", "Установка Winget", "OK", "Information")
        }
    }
})
[void]$bottomButtonsGroupBox.Controls.Add($checkUpdatesBtn)

# Создание кнопки "Обновить список"
$refreshListBtn = New-Object System.Windows.Forms.Button
$refreshListBtn.Text = "Обновить список"
$refreshListBtnXLocation = $checkUpdatesBtn.Location.X + $checkUpdatesBtn.Width + 10
$refreshListBtn.Location = New-Object System.Drawing.Point($refreshListBtnXLocation, 25) # После кнопки "Проверка обновлений"
$refreshListBtn.Size = New-Object System.Drawing.Size(120, 30) # Размер кнопки
$refreshListBtn.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left # Привязка к низу и левому краю
[void]$refreshListBtn.Add_Click({
    [System.Windows.Forms.MessageBox]::Show("Обновление списка доступных приложений из JSON-файла. Установка приложений НЕ будет производиться.", "Обновление списка", "OK", "Information")
    if (LoadAppsData $jsonUrl) { # Перезагружаем данные
        PopulateCategoryComboBox -ComboBox ([ref]$categoryComboBox) -AppsData $script:apps # Обновляем категории
        UpdateCheckedList($categoryComboBox.SelectedItem) # Обновляем список приложений с новым фильтром
        [System.Windows.Forms.MessageBox]::Show("Список приложений успешно обновлен.", "Обновление списка", "OK", "Information")
    }
})
[void]$bottomButtonsGroupBox.Controls.Add($refreshListBtn)


# Обработчик события клика для кнопки "Установить"
[void]$installBtn.Add_Click({
    $selectedItems = @() # Инициализация пустого массива для хранения ID выбранных приложений
    # Перебор всех отмеченных элементов в глобальном списке отмеченных ID
    foreach ($checkedAppObject in $checkedList.CheckedItems) { # Теперь итерируем по объектам напрямую
        $selectedItems += [PSCustomObject]@{
            Name = $checkedAppObject.Name
            Id   = $checkedAppObject.Id
            RequiresMsStoreSource = $checkedAppObject.RequiresMsStoreSource # Получаем флаг
        }
    }

    # Проверка, выбраны ли какие-либо приложения
    if ($selectedItems.Count -eq 0) {
        # Сообщение, если ничего не выбрано
        [System.Windows.Forms.MessageBox]::Show("Вы не выбрали ни одного приложения для установки.", "Внимание", "OK", "Warning")
    } else {
        # Формирование сообщения с ID выбранных приложений
        $msg = "Будут установлены следующие ID:`n" + ($selectedItems.Id -join "`n")
        # Отображение сообщения пользователю
        [System.Windows.Forms.MessageBox]::Show($msg, "Подтверждение установки", "OK", "Information")

        # Проверка наличия winget
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            [System.Windows.Forms.MessageBox]::Show("Запуск установки через Winget. Прогресс будет отображен в текущей консоли.", "Установка приложений", "OK", "Information")
            # Установка кодировки для корректного отображения вывода Winget
            try {
                $OutputEncoding = [System.Text.Encoding]::UTF8
                [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 
            } catch {
                Write-Warning "Не удалось установить OutputEncoding для консоли: $($_.Exception.Message)"
            }
            
            # Пример установки с помощью winget (Windows Package Manager):
            foreach ($app in $selectedItems) {
                Write-Host "--- Установка $($app.Name) (ID: $($app.Id)) ---" -ForegroundColor Yellow
                
                # Проверка фактического наличия приложения на ПК
                if (Check-ApplicationInstalled -AppNamePartial $app.Name) {
                    Write-Host "Приложение '$($app.Name)' уже обнаружено. Пропускаем установку." -ForegroundColor Yellow
                } else {
                    Write-Host "Запуск установки '$($app.Name)'..." -ForegroundColor Green
                    
                    $sourceFlag = if ($app.RequiresMsStoreSource) { "--source msstore" } else { "" }
                    $wingetCommand = "winget install --id $($app.Id) $sourceFlag --accept-source-agreements --accept-package-agreements"
                    
                    $wingetOutput = Invoke-Expression "$wingetCommand 2>&1"
                    Write-Host $wingetOutput

                    # Проверяем код выхода Winget для определения результата
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "Установка $($app.Name) завершена успешно." -ForegroundColor Green
                    } elseif ($LASTEXITCODE -eq -1978335212) {
                        Write-Host "ОШИБКА: Пакет $($app.Id) не найден в источниках Winget или не соответствует условиям." -ForegroundColor Red
                    } elseif ($LASTEXITCODE -eq 1700 -or $LASTEXITCODE -eq -1978335189) {
                        Write-Host "ПРИМЕЧАНИЕ: Winget сообщает, что пакет для '$($app.Id)' уже установлен и находится в актуальном состоянии. Обновления не требуются." -ForegroundColor Yellow
                    } else {
                        Write-Host "ОШИБКА при установке $($app.Id) через Winget. Код выхода: " + $LASTEXITCODE -ForegroundColor Red
                    }
                }
                Write-Host "--- Завершено $($app.Name) ---`n" -ForegroundColor Yellow
            }
            [System.Windows.Forms.MessageBox]::Show("Процесс установки Winget завершен. Проверьте установленные приложения.", "Готово", "OK", "Information")
        } else {
            $installWingetPrompt = ShowCustomMessageBox -Title "Winget не найден" -Message "Winget не найден в вашей системе. Что вы хотите сделать?" -ButtonTexts @("Открыть ссылку в браузере", "Отмена")
            if ($installWingetPrompt -eq "Открыть ссылку в браузере") {
                # Отладка: Выводим ссылку, которую пытаемся открыть
                Write-Host "Отладка: Попытка открыть ссылку в браузере: https://apps.microsoft.com/detail/9nblggh4nns1?hl=ru-RU&gl=UA" -ForegroundColor Yellow
                try {
                    [void](Start-Process "https://apps.microsoft.com/detail/9nblggh4nns1?hl=ru-RU&gl=UA" -Verb Open)
                    # Отладка: Сообщение об успешном запуске процесса
                    Write-Host "Отладка: Процесс Start-Process для ссылки должен быть запущен." -ForegroundColor Green
                } catch {
                    [System.Windows.Forms.MessageBox]::Show("Ошибка при открытии ссылки в браузере: $($_.Exception.Message)", "Ошибка", "OK", "Error")
                    # Отладка: Сообщение об ошибке при открытии ссылки
                    Write-Host "Отладка: Ошибка при открытии ссылки в браузере: $($_.Exception.Message)" -ForegroundColor Red
                }
                [System.Windows.Forms.MessageBox]::Show("Открыта страница Winget в браузере. Пожалуйста, следуйте инструкциям для ручной установки.", "Установка Winget", "OK", "Information")
            }
        }
    }
})

# Изначальное заполнение списка при запуске формы
PopulateCategoryComboBox -ComboBox ([ref]$categoryComboBox) -AppsData $script:apps # Изначальное заполнение категорий
UpdateCheckedList($categoryComboBox.SelectedItem) # Изначальное заполнение списка приложений

# Запуск формы графического интерфейса в модальном режиме
[void]$form.ShowDialog()
