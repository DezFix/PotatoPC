# Добавление необходимых сборок для работы с графическим интерфейсом
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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
    $msgBoxForm.MinimizeBox = $false # Отключить кнопку свернуть
    $msgBoxForm.MaximizeBox = $false # Отключить кнопку развернуть

    $msgLabel = New-Object System.Windows.Forms.Label
    $msgLabel.Text = $Message
    $msgLabel.Location = New-Object System.Drawing.Point(20, 20)
    $msgLabel.AutoSize = $true
    # ИСПРАВЛЕНО: обернуты математические операции в скобки
    $msgLabel.MaximumSize = New-Object System.Drawing.Size(($msgBoxForm.Width - 40), 0) # Перенос текста
    $msgBoxForm.Controls.Add($msgLabel)

    $buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft # Кнопки справа налево
    $buttonPanel.AutoSize = $true
    $buttonPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right # Привязка к нижнему правому углу
    $msgBoxForm.Controls.Add($buttonPanel)

    $result = ""
    foreach ($text in $ButtonTexts) {
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $text
        $btn.Size = New-Object System.Drawing.Size(90, 30) # Увеличен размер кнопок
        $btn.Add_Click({
            $result = $btn.Text
            $msgBoxForm.Close()
        })
        $buttonPanel.Controls.Add($btn)
    }

    # ИСПРАВЛЕНО: обернуты математические операции в скобки
    $buttonPanel.Location = New-Object System.Drawing.Point(($msgBoxForm.ClientSize.Width - $buttonPanel.Width - 20), ($msgBoxForm.ClientSize.Height - $buttonPanel.Height - 20))

    [void]$msgBoxForm.ShowDialog()
    return $result
}

# URL-адрес JSON-файла с GitHub, содержащего информацию о приложениях
$jsonUrl = 'https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/apps.json'

# Глобальная переменная для хранения данных о приложениях
$script:apps = @()
$script:jsonRaw = $null # Глобальная переменная для хранения сырых данных JSON

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
            # Итерируем по свойствам (ключам) ManualCategories
            foreach ($categoryName in $script:jsonRaw.ManualCategories.PSObject.Properties.Name) {
                $categoryApps = $script:jsonRaw.ManualCategories.$categoryName
                # Проверяем, является ли значение категории массивом приложений
                if ($categoryApps -is [System.Array]) {
                    foreach ($app in $categoryApps) {
                        # Проверяем наличие полей Name и Id для каждого приложения
                        if ($app.Name -and $app.Id) {
                            $script:apps += [PSCustomObject]@{
                                Name = $app.Name
                                Id   = $app.Id
                                Category = $categoryName # Категория сохраняется для фильтрации
                            }
                        }
                    }
                }
            }
        }
        return $true
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Не удалось загрузить apps.json. Проверьте подключение к Интернету или URL-адрес.", "Ошибка загрузки", "OK", "Error")
        return $false
    }
}

# Попытка загрузить JSON-файл при запуске скрипта
if (-not (LoadAppsData $jsonUrl)) {
    exit # Выходим, если не удалось загрузить данные
}

# Создание главной формы графического интерфейса
$form = New-Object System.Windows.Forms.Form
$form.Text = "Wicked Raven Installer" # Заголовок окна
$form.Size = New-Object System.Drawing.Size(700, 750) # Увеличен размер формы для нового расположения элементов
$form.StartPosition = "CenterScreen" # Размещение формы по центру экрана
$form.MinimumSize = New-Object System.Drawing.Size(500, 600) # Минимальный размер окна
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi # Автоматическое масштабирование по DPI

# Создание GroupBox для выбора метода установки
$methodGroupBox = New-Object System.Windows.Forms.GroupBox
$methodGroupBox.Text = "Выберите метод установки:"
$methodGroupBox.Location = New-Object System.Drawing.Point(10, 10)
$methodGroupBox.Size = New-Object System.Drawing.Size(660, 60) # Увеличена ширина GroupBox
$methodGroupBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right # Привязка к верху, левому и правому краю
$form.Controls.Add($methodGroupBox)

# Создание RadioButton для Winget
$radioWinget = New-Object System.Windows.Forms.RadioButton
$radioWinget.Text = "Winget"
$radioWinget.Location = New-Object System.Drawing.Point(15, 25) # Позиция внутри GroupBox
$radioWinget.Checked = [bool]$true # Устанавливаем Winget по умолчанию
$radioWinget.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left # Привязка к верху и левому краю
$methodGroupBox.Controls.Add($radioWinget)

# Создание RadioButton для Chocolatey
$radioChoco = New-Object System.Windows.Forms.RadioButton
$radioChoco.Text = "Chocolatey"
$radioChoco.Location = New-Object System.Drawing.Point(150, 25) # Скорректирована позиция для видимости
$radioChoco.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left # Привязка к верху и левому краю
$methodGroupBox.Controls.Add($radioChoco)


# --- Новая группа для кнопок "Выбрать все" и "Убрать отмеченные" ---
$selectionButtonsGroupBox = New-Object System.Windows.Forms.GroupBox
$selectionButtonsGroupBox.Text = "Выбор приложений"
$selectionButtonsGroupBox.Location = New-Object System.Drawing.Point(10, ($methodGroupBox.Location.Y + $methodGroupBox.Height + 10))
$selectionButtonsGroupBox.Size = New-Object System.Drawing.Size(280, 70) # Достаточно места для двух кнопок
$selectionButtonsGroupBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left # Привязка к верху и левому краю
$form.Controls.Add($selectionButtonsGroupBox)

# Создание кнопки "Выбрать все"
$selectAllBtn = New-Object System.Windows.Forms.Button
$selectAllBtn.Text = "Выбрать все"
$selectAllBtn.Location = New-Object System.Drawing.Point(10, 25) # Позиция внутри selectionButtonsGroupBox
$selectAllBtn.Size = New-Object System.Drawing.Size(100, 30)
$selectAllBtn.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left # Привязка к верху и левому краю
$selectAllBtn.Add_Click({
    for ($i = 0; $i -lt $checkedList.Items.Count; $i++) {
        $checkedList.SetItemChecked($i, [bool]$true) # ИСПРАВЛЕНО: явное приведение к [bool]
    }
})
$selectionButtonsGroupBox.Controls.Add($selectAllBtn)

# Создание кнопки "Убрать отмеченные"
$deselectAllBtn = New-Object System.Windows.Forms.Button
$deselectAllBtn.Text = "Убрать отмеченные"
$deselectAllBtnXLocation = $selectAllBtn.Location.X + $selectAllBtn.Width + 10
$deselectAllBtn.Location = New-Object System.Drawing.Point($deselectAllBtnXLocation, 25) # После кнопки "Выбрать все"
$deselectAllBtn.Size = New-Object System.Drawing.Size(130, 30) # Немного шире для текста
$deselectAllBtn.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left # Привязка к верху и левому краю
$deselectAllBtn.Add_Click({
    for ($i = 0; $i -lt $checkedList.Items.Count; $i++) {
        $checkedList.SetItemChecked($i, [bool]$false) # ИСПРАВЛЕНО: явное приведение к [bool]
    }
})
$selectionButtonsGroupBox.Controls.Add($deselectAllBtn)


# Создание ComboBox для фильтрации по категориям (ПЕРЕМЕЩЕНО ВЫШЕ МЕТКИ)
$categoryComboBox = New-Object System.Windows.Forms.ComboBox
$categoryComboBox.Location = New-Object System.Drawing.Point(10, ($selectionButtonsGroupBox.Location.Y + $selectionButtonsGroupBox.Height + 10)) # Теперь под selectionButtonsGroupBox
$categoryComboBox.Size = New-Object System.Drawing.Size(200, 30)
$categoryComboBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left # Привязка к верху и левому краю
$form.Controls.Add($categoryComboBox)

# Создание метки (Label) для инструкции пользователя (ПЕРЕМЕЩЕНО НИЖЕ ComboBox)
$label = New-Object System.Windows.Forms.Label
$label.Text = "Выберите приложения для установки:"
$label.Location = New-Object System.Drawing.Point(10, ($categoryComboBox.Location.Y + $categoryComboBox.Height + 5)) # Теперь под ComboBox
$label.AutoSize = [bool]$true # Автоматический размер метки по содержимому
$label.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right # Привязка к верху, левому и правому краю
$form.Controls.Add($label) # Добавление метки на форму

# Создание списка с флажками (CheckedListBox) для выбора приложений
$checkedList = New-Object System.Windows.Forms.CheckedListBox
$checkedList.Location = New-Object System.Drawing.Point(10, ($label.Location.Y + $label.Height + 10)) # Смещаем список ниже метки
$checkedList.Size = New-Object System.Drawing.Size(660, 350) # Скорректирован размер списка
$checkedList.CheckOnClick = [bool]$true # Позволяет отмечать/снимать флажок по одному клику
$checkedList.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right # Привязка ко всем краям
$form.Controls.Add($checkedList) # Добавление списка на форму


# Функция для заполнения ComboBox категорий
function PopulateCategoryComboBox {
    param(
        [ref]$ComboBox,
        [array]$AppsData # Используем уже обработанные данные $script:apps
    )
    $ComboBox.Value.Items.Clear()
    $ComboBox.Value.Items.Add("Все")
    
    $foundCategories = @()
    # Собираем уникальные категории из $script:apps
    $AppsData | Select-Object -ExpandProperty Category -Unique | Sort-Object | ForEach-Object {
        if ($_ -and ($_.ToString() -ne "")) { # Проверяем на null и пустую строку
            $ComboBox.Value.Items.Add($_)
            $foundCategories += $_ # Добавляем найденную категорию
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
    $checkedItemsBeforeFilter = @{}
    # Сохраняем состояние отмеченных элементов по их ID
    for ($i = 0; $i -lt $checkedList.Items.Count; $i++) {
        if ($checkedList.GetItemChecked($i)) {
            $appName = $checkedList.Items[$i]
            # Находим приложение в исходном массиве $apps для получения его ID
            $appObj = $script:apps | Where-Object { $_.Name -eq $appName }
            if ($appObj) {
                $checkedItemsBeforeFilter[$appObj.Id] = [bool]$true
            }
        }
    }

    $checkedList.Items.Clear() # Очищаем список перед заполнением

    $filteredApps = @()
    if ($categoryFilter -eq "Все" -or $categoryFilter -eq $null) {
        $filteredApps = $script:apps # Если выбрано "Все" или фильтр не указан, используем все приложения
    } else {
        # Фильтруем приложения по выбранной категории
        $filteredApps = $script:apps | Where-Object { $_.Category -eq $categoryFilter }
    }

    # Теперь просто добавляем отфильтрованные приложения
    foreach ($app in $filteredApps) {
        $checkedList.Items.Add($app.Name) | Out-Null
        # Восстанавливаем состояние отмеченных элементов
        if ($checkedItemsBeforeFilter.ContainsKey($app.Id)) {
            $index = $checkedList.Items.IndexOf($app.Name)
            if ($index -ne -1) {
                $checkedList.SetItemChecked($index, [bool]$true)
            }
        }
    }
}

# Обработчик события изменения выбора в ComboBox категорий
$categoryComboBox.Add_SelectedIndexChanged({
    # Вызываем UpdateCheckedList с текущим выбранным элементом фильтрации
    UpdateCheckedList($categoryComboBox.SelectedItem)
})


# --- Создание единого GroupBox для нижних кнопок (Установить, Выход, Проверка обновлений, Обновить список) ---
$bottomButtonsGroupBox = New-Object System.Windows.Forms.GroupBox
$bottomButtonsGroupBox.Text = "Управление" # Заголовок для GroupBox кнопок
$bottomButtonsGroupBox.Location = New-Object System.Drawing.Point(10, ($checkedList.Location.Y + $checkedList.Height + 10))
# Ширина GroupBox, достаточная для четырех кнопок
# 100 (Уст) + 10 (отст) + 100 (Вых) + 10 (отст) + 150 (Проверка) + 10 (отст) + 120 (Обновить список) + 10 (отст) = 520 + 20 (внутр отст) = 540
$bottomButtonsGroupBox.Size = New-Object System.Drawing.Size(540, 70)
$bottomButtonsGroupBox.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right # Привязка к низу, левому и правому краю
$form.Controls.Add($bottomButtonsGroupBox)

# Создание кнопки "Установить"
$installBtn = New-Object System.Windows.Forms.Button
$installBtn.Text = "Установить"
$installBtn.Location = New-Object System.Drawing.Point(10, 25) # Позиция внутри bottomButtonsGroupBox
$installBtn.Size = New-Object System.Drawing.Size(100, 30) # Размер кнопки
$installBtn.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left # Привязка к низу и левому краю
$bottomButtonsGroupBox.Controls.Add($installBtn) # Добавление кнопки в GroupBox

# Создание кнопки "Выход"
$exitBtn = New-Object System.Windows.Forms.Button
$exitBtn.Text = "Выход"
# Рассчитываем X-координату в отдельной переменной для надежности
$exitBtnXLocation = $installBtn.Location.X + $installBtn.Width + 10
$exitBtn.Location = New-Object System.Drawing.Point($exitBtnXLocation, 25) # После кнопки "Установить"
$exitBtn.Size = New-Object System.Drawing.Size(100, 30) # Размер кнопки
$exitBtn.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left # Привязка к низу и левому краю
# Добавление обработчика события клика для кнопки "Выход"
$exitBtn.Add_Click({
    $menuScriptUrl = 'https://raw.githubusercontent.com/DezFix/PotatoPC/main/menu.ps1'
    try {
        # Загрузка содержимого скрипта
        $scriptContent = Invoke-RestMethod -Uri $menuScriptUrl -UseBasicParsing
        # Закрываем текущую форму перед запуском нового скрипта
        $form.Close()
        # Выполняем загруженный скрипт
        Invoke-Expression $scriptContent
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Не удалось загрузить или запустить menu.ps1. Проверьте подключение к Интернету или URL-адрес.", "Ошибка запуска меню", "OK", "Error")
    }
})
$bottomButtonsGroupBox.Controls.Add($exitBtn) # Добавление кнопки в GroupBox

# Создание кнопки "Проверка обновлений"
$checkUpdatesBtn = New-Object System.Windows.Forms.Button
$checkUpdatesBtn.Text = "Проверка обновлений"
$checkUpdatesBtnXLocation = $exitBtn.Location.X + $exitBtn.Width + 10
$checkUpdatesBtn.Location = New-Object System.Drawing.Point($checkUpdatesBtnXLocation, 25) # После кнопки "Выход"
$checkUpdatesBtn.Size = New-Object System.Drawing.Size(150, 30) # Увеличим ширину для текста
$checkUpdatesBtn.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left # Привязка к низу и левому краю
$checkUpdatesBtn.Add_Click({
    $installMethod = if ($radioWinget.Checked) { "winget" } else { "choco" }

    if ($installMethod -eq "winget") {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            [System.Windows.Forms.MessageBox]::Show("Запуск проверки обновлений через Winget. Откроется окно консоли для отображения прогресса.", "Проверка обновлений", "OK", "Information")
            # Запускаем обновление всех приложений через Winget
            Start-Process "winget" -ArgumentList "upgrade --all --silent" -Wait 
            [System.Windows.Forms.MessageBox]::Show("Проверка и установка обновлений Winget завершена.", "Обновления завершены", "OK", "Information")
        } else {
            [System.Windows.Forms.MessageBox]::Show("Winget не найден. Невозможно проверить обновления.", "Ошибка", "OK", "Error")
        }
    } elseif ($installMethod -eq "choco") {
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            [System.Windows.Forms.MessageBox]::Show("Запуск проверки обновлений через Chocolatey. Откроется окно консоли для отображения прогресса.", "Проверка обновлений", "OK", "Information")
            # Запускаем обновление всех приложений через Chocolatey
            Start-Process "choco" -ArgumentList "upgrade all -y" -Wait 
            [System.Windows.Forms.MessageBox]::Show("Проверка и установка обновлений Chocolatey завершена.", "Обновления завершены", "OK", "Information")
        } else {
            [System.Windows.Forms.MessageBox]::Show("Chocolatey не найден. Невозможно проверить обновления.", "Ошибка", "OK", "Error")
        }
    }
})
$bottomButtonsGroupBox.Controls.Add($checkUpdatesBtn)

# Создание кнопки "Обновить список"
$refreshListBtn = New-Object System.Windows.Forms.Button
$refreshListBtn.Text = "Обновить список"
$refreshListBtnXLocation = $checkUpdatesBtn.Location.X + $checkUpdatesBtn.Width + 10
$refreshListBtn.Location = New-Object System.Drawing.Point($refreshListBtnXLocation, 25) # После кнопки "Проверка обновлений"
$refreshListBtn.Size = New-Object System.Drawing.Size(120, 30) # Размер кнопки
$refreshListBtn.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left # Привязка к низу и левому краю
$refreshListBtn.Add_Click({
    if (LoadAppsData $jsonUrl) { # Перезагружаем данные
        PopulateCategoryComboBox -ComboBox ([ref]$categoryComboBox) -AppsData $script:apps # Обновляем категории
        UpdateCheckedList($categoryComboBox.SelectedItem) # Обновляем список приложений с новым фильтром
        [System.Windows.Forms.MessageBox]::Show("Список приложений успешно обновлен.", "Обновление списка", "OK", "Information")
    }
})
$bottomButtonsGroupBox.Controls.Add($refreshListBtn)


# Обработчик события клика для кнопки "Установить"
$installBtn.Add_Click({
    $selectedItems = @() # Инициализация пустого массива для хранения ID выбранных приложений
    # Перебор всех отмеченных элементов в списке
    foreach ($checkedItem in $checkedList.CheckedItems) {
        # Нахождение соответствующего объекта приложения по имени
        $selectedApp = $script:apps | Where-Object { $_.Name -eq $checkedItem }
        if ($selectedApp) {
            $selectedItems += $selectedApp.Id # Добавление ID выбранного приложения
        }
    }

    # Проверка, выбраны ли какие-либо приложения
    if ($selectedItems.Count -eq 0) {
        # Сообщение, если ничего не выбрано
        [System.Windows.Forms.MessageBox]::Show("Вы не выбрали ни одного приложения для установки.", "Внимание", "OK", "Warning")
    } else {
        # Формирование сообщения с ID выбранных приложений
        $msg = "Будут установлены следующие ID:`n" + ($selectedItems -join "`n")
        # Отображение сообщения пользователю
        [System.Windows.Forms.MessageBox]::Show($msg, "Подтверждение установки", "OK", "Information")

        # --- Здесь добавлена реальная логика установки с выбором метода ---

        # Определяем выбранный метод установки
        $installMethod = if ($radioWinget.Checked) { "winget" } else { "choco" }

        if ($installMethod -eq "winget") {
            # Проверка наличия winget
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                [System.Windows.Forms.MessageBox]::Show("Запуск установки через Winget. Откроется окно консоли для отображения прогресса.", "Установка приложений", "OK", "Information")
                # Пример установки с помощью winget (Windows Package Manager):
                foreach ($id in $selectedItems) {
                    Write-Host "Установка $id с помощью winget..."
                    Start-Process "winget" -ArgumentList "install --id $id --silent" -Wait 
                }
                [System.Windows.Forms.MessageBox]::Show("Процесс установки завершен. Проверьте установленные приложения.", "Готово", "OK", "Information")
            } else {
                # Предложить установить Winget
                $installWingetPrompt = ShowCustomMessageBox -Title "Winget не найден" -Message "Winget не найден в вашей системе. Хотите получить инструкции по его установке?" -ButtonTexts @("Да", "Нет")
                if ($installWingetPrompt -eq "Да") {
                    [System.Windows.Forms.MessageBox]::Show("Для установки Winget откройте Microsoft Store и найдите 'App Installer' или посетите страницу Winget на GitHub для ручной установки.", "Инструкции по установке Winget", "OK", "Information")
                }
            }
        } elseif ($installMethod -eq "choco") {
            # Проверка наличия Chocolatey
            if (Get-Command choco -ErrorAction SilentlyContinue) {
                [System.Windows.Forms.MessageBox]::Show("Запуск установки через Chocolatey. Откроется окно консоли для отображения прогресса.", "Установка приложений", "OK", "Information")
                # Пример установки с помощью Chocolatey:
                foreach ($id in $selectedItems) {
                    Write-Host "Установка $id с помощью choco..."
                    Start-Process "choco" -ArgumentList "install $id -y" -Wait 
                }
                [System.Windows.Forms.MessageBox]::Show("Процесс установки завершен. Проверьте установленные приложения.", "Готово", "OK", "Information")
            } else {
                # Предложить установить Chocolatey
                $installChocoPrompt = ShowCustomMessageBox -Title "Chocolatey не найден" -Message "Chocolatey не найден в вашей системе. Хотите получить инструкции по его установке?" -ButtonTexts @("Да", "Нет")
                if ($installChocoPrompt -eq "Да") {
                    [System.Windows.Forms.MessageBox]::Show("Для установки Chocolatey откройте PowerShell от имени администратора и выполните следующую команду: `n`nSet-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))", "Инструкции по установке Chocolatey", "OK", "Information")
                }
            }
        }
    }
})

# Изначальное заполнение списка при запуске формы
PopulateCategoryComboBox -ComboBox ([ref]$categoryComboBox) -AppsData $script:apps # Изначальное заполнение категорий
UpdateCheckedList($categoryComboBox.SelectedItem) # Изначальное заполнение списка приложений

# Запуск формы графического интерфейса в модальном режиме
[void]$form.ShowDialog()
