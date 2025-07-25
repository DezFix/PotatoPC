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
    $msgLabel.MaximumSize = New-Object System.Drawing.Size($msgBoxForm.Width - 40, 0) # Перенос текста
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

    # Корректировка позиции панели кнопок после добавления кнопок
    $buttonPanel.Location = New-Object System.Drawing.Point($msgBoxForm.ClientSize.Width - $buttonPanel.Width - 20, $msgBoxForm.ClientSize.Height - $buttonPanel.Height - 20)

    [void]$msgBoxForm.ShowDialog()
    return $result
}

# URL-адрес JSON-файла с GitHub, содержащего информацию о приложениях
$jsonUrl = 'https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/apps.json'

# Попытка загрузить JSON-файл
try {
    $jsonRaw = Invoke-RestMethod -Uri $jsonUrl -UseBasicParsing
} catch {
    # Отображение сообщения об ошибке, если загрузка не удалась
    [System.Windows.Forms.MessageBox]::Show("Не удалось загрузить apps.json. Проверьте подключение к Интернету или URL-адрес.", "Ошибка загрузки", "OK", "Error")
    exit
}

# Парсинг данных о приложениях из секции ManualCategories JSON-файла
$apps = @() # Инициализация пустого массива для хранения данных о приложений
# Правильная итерация по массиву категорий внутри ManualCategories
foreach ($categoryObject in $jsonRaw.ManualCategories) {
    $categoryName = $categoryObject.Name # Получаем имя категории
    foreach ($app in $categoryObject.Apps) {
        # Проверка наличия полей Name и Id для каждого приложения
        if ($app.Name -and $app.Id) {
            # Добавление приложения в массив в виде пользовательского объекта, включая категорию
            $apps += [PSCustomObject]@{
                Name = $app.Name
                Id   = $app.Id
                Category = $categoryName
            }
        }
    }
}

# Создание главной формы графического интерфейса
$form = New-Object System.Windows.Forms.Form
$form.Text = "Wicked Raven Installer" # Заголовок окна
$form.Size = New-Object System.Drawing.Size(700, 750) # Увеличен размер формы для нового расположения элементов
$form.StartPosition = "CenterScreen" # Размещение формы по центру экрана

# Создание GroupBox для выбора метода установки
$methodGroupBox = New-Object System.Windows.Forms.GroupBox
$methodGroupBox.Text = "Выберите метод установки:"
$methodGroupBox.Location = New-Object System.Drawing.Point(10, 10)
$methodGroupBox.Size = New-Object System.Drawing.Size(660, 60) # Увеличена ширина GroupBox
$form.Controls.Add($methodGroupBox)

# Создание RadioButton для Winget
$radioWinget = New-Object System.Windows.Forms.RadioButton
$radioWinget.Text = "Winget"
$radioWinget.Location = New-Object System.Drawing.Point(15, 25) # Позиция внутри GroupBox
$radioWinget.Checked = $true # Устанавливаем Winget по умолчанию
$methodGroupBox.Controls.Add($radioWinget)

# Создание RadioButton для Chocolatey
$radioChoco = New-Object System.Windows.Forms.RadioButton
$radioChoco.Text = "Chocolatey"
$radioChoco.Location = New-Object System.Drawing.Point(150, 25) # Скорректирована позиция для видимости
$methodGroupBox.Controls.Add($radioChoco)


# --- Новая группа для кнопок "Выбрать все" и "Убрать отмеченные" ---
$selectionButtonsGroupBox = New-Object System.Windows.Forms.GroupBox
$selectionButtonsGroupBox.Text = "Выбор приложений"
$selectionButtonsGroupBox.Location = New-Object System.Drawing.Point(10, ($methodGroupBox.Location.Y + $methodGroupBox.Height + 10))
$selectionButtonsGroupBox.Size = New-Object System.Drawing.Size(280, 70) # Достаточно места для двух кнопок
$form.Controls.Add($selectionButtonsGroupBox)

# Создание кнопки "Выбрать все"
$selectAllBtn = New-Object System.Windows.Forms.Button
$selectAllBtn.Text = "Выбрать все"
$selectAllBtn.Location = New-Object System.Drawing.Point(10, 25) # Позиция внутри selectionButtonsGroupBox
$selectAllBtn.Size = New-Object System.Drawing.Size(100, 30)
$selectAllBtn.Add_Click({
    for ($i = 0; $i -lt $checkedList.Items.Count; $i++) {
        $checkedList.SetItemChecked($i, $true)
    }
})
$selectionButtonsGroupBox.Controls.Add($selectAllBtn)

# Создание кнопки "Убрать отмеченные"
$deselectAllBtn = New-Object System.Windows.Forms.Button
$deselectAllBtn.Text = "Убрать отмеченные"
$deselectAllBtnXLocation = $selectAllBtn.Location.X + $selectAllBtn.Width + 10
$deselectAllBtn.Location = New-Object System.Drawing.Point($deselectAllBtnXLocation, 25) # После кнопки "Выбрать все"
$deselectAllBtn.Size = New-Object System.Drawing.Size(130, 30) # Немного шире для текста
$deselectAllBtn.Add_Click({
    for ($i = 0; $i -lt $checkedList.Items.Count; $i++) {
        $checkedList.SetItemChecked($i, $false)
    }
})
$selectionButtonsGroupBox.Controls.Add($deselectAllBtn)


# Создание метки (Label) для инструкции пользователя
$label = New-Object System.Windows.Forms.Label
$label.Text = "Выберите приложения для установки:"
$label.Location = New-Object System.Drawing.Point(10, ($selectionButtonsGroupBox.Location.Y + $selectionButtonsGroupBox.Height + 10))
$label.AutoSize = $true # Автоматический размер метки по содержимому
$form.Controls.Add($label) # Добавление метки на форму

# --- УДАЛЕН ComboBox для сортировки ---

# Создание ComboBox для фильтрации по категориям
$categoryComboBox = New-Object System.Windows.Forms.ComboBox
$categoryComboBox.Location = New-Object System.Drawing.Point(10, ($label.Location.Y + $label.Height + 5)) # Теперь под меткой
$categoryComboBox.Size = New-Object System.Drawing.Size(200, 30)
$categoryComboBox.Items.Add("Все") # Опция для отображения всех категорий
# Заполняем ComboBox категориями из JSON
$jsonRaw.ManualCategories | ForEach-Object { $categoryComboBox.Items.Add($_.Name) }
$categoryComboBox.SelectedIndex = 0 # По умолчанию выбрано "Все"
$form.Controls.Add($categoryComboBox)


# Создание списка с флажками (CheckedListBox) для выбора приложений
$checkedList = New-Object System.Windows.Forms.CheckedListBox
$checkedList.Location = New-Object System.Drawing.Point(10, ($categoryComboBox.Location.Y + $categoryComboBox.Height + 10)) # Смещаем список ниже ComboBox категории
$checkedList.Size = New-Object System.Drawing.Size(660, 350) # Скорректирован размер списка
$checkedList.CheckOnClick = $true # Позволяет отмечать/снимать флажок по одному клику
$form.Controls.Add($checkedList) # Добавление списка на форму


# Функция для обновления списка приложений с учетом только фильтрации
function UpdateCheckedList ($categoryFilter) { # УДАЛЕН параметр $sortOption
    $checkedItemsBeforeFilter = @{}
    # Сохраняем состояние отмеченных элементов по их ID
    for ($i = 0; $i -lt $checkedList.Items.Count; $i++) {
        if ($checkedList.GetItemChecked($i)) {
            $appName = $checkedList.Items[$i]
            # Находим приложение в исходном массиве $apps для получения его ID
            $appObj = $apps | Where-Object { $_.Name -eq $appName }
            if ($appObj) {
                $checkedItemsBeforeFilter[$appObj.Id] = $true
            }
        }
    }

    $checkedList.Items.Clear() # Очищаем список перед заполнением

    $filteredApps = @()
    if ($categoryFilter -eq "Все" -or $categoryFilter -eq $null) {
        $filteredApps = $apps # Если выбрано "Все" или фильтр не указан, используем все приложения
    } else {
        # Фильтруем приложения по выбранной категории
        $filteredApps = $apps | Where-Object { $_.Category -eq $categoryFilter }
    }

    # Теперь просто добавляем отфильтрованные приложения без сортировки
    foreach ($app in $filteredApps) {
        $checkedList.Items.Add($app.Name) | Out-Null
        # Восстанавливаем состояние отмеченных элементов
        if ($checkedItemsBeforeFilter.ContainsKey($app.Id)) {
            $index = $checkedList.Items.IndexOf($app.Name)
            if ($index -ne -1) {
                $checkedList.SetItemChecked($index, $true)
            }
        }
    }
}

# --- УДАЛЕН обработчик события изменения выбора в ComboBox сортировки ---

# Обработчик события изменения выбора в ComboBox категорий
$categoryComboBox.Add_SelectedIndexChanged({
    # Вызываем UpdateCheckedList с текущим выбранным элементом фильтрации
    UpdateCheckedList($categoryComboBox.SelectedItem)
})

# Изначальное заполнение списка при запуске формы
UpdateCheckedList($categoryComboBox.SelectedItem)


# --- Создание единого GroupBox для нижних кнопок (Установить, Выход, Проверка обновлений) ---
$bottomButtonsGroupBox = New-Object System.Windows.Forms.GroupBox
$bottomButtonsGroupBox.Text = "Управление" # Заголовок для GroupBox кнопок
$bottomButtonsGroupBox.Location = New-Object System.Drawing.Point(10, ($checkedList.Location.Y + $checkedList.Height + 10))
# Ширина GroupBox, достаточная для трех кнопок
# 100 (Уст) + 10 (отст) + 100 (Вых) + 10 (отст) + 150 (Обновить) + 10 (отст) = 380 + 20 (внутр отст) = 400
$bottomButtonsGroupBox.Size = New-Object System.Drawing.Size(420, 70)
$form.Controls.Add($bottomButtonsGroupBox)

# Создание кнопки "Установить"
$installBtn = New-Object System.Windows.Forms.Button
$installBtn.Text = "Установить"
$installBtn.Location = New-Object System.Drawing.Point(10, 25) # Позиция внутри bottomButtonsGroupBox
$installBtn.Size = New-Object System.Drawing.Size(100, 30) # Размер кнопки
$bottomButtonsGroupBox.Controls.Add($installBtn) # Добавление кнопки в GroupBox

# Создание кнопки "Выход"
$exitBtn = New-Object System.Windows.Forms.Button
$exitBtn.Text = "Выход"
# Рассчитываем X-координату в отдельной переменной для надежности
$exitBtnXLocation = $installBtn.Location.X + $installBtn.Width + 10
$exitBtn.Location = New-Object System.Drawing.Point($exitBtnXLocation, 25) # После кнопки "Установить"
$exitBtn.Size = New-Object System.Drawing.Size(100, 30) # Размер кнопки
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
$checkUpdatesBtn.Add_Click({
    $installMethod = if ($radioWinget.Checked) { "winget" } else { "choco" }

    if ($installMethod -eq "winget") {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            [System.Windows.Forms.MessageBox]::Show("Запуск проверки обновлений через Winget. Это может занять некоторое время.", "Проверка обновлений", "OK", "Information")
            # Запускаем обновление всех приложений через Winget
            Start-Process "winget" -ArgumentList "upgrade --all --silent" -Wait -NoNewWindow
            [System.Windows.Forms.MessageBox]::Show("Проверка и установка обновлений Winget завершена.", "Обновления завершены", "OK", "Information")
        } else {
            [System.Windows.Forms.MessageBox]::Show("Winget не найден. Невозможно проверить обновления.", "Ошибка", "OK", "Error")
        }
    } elseif ($installMethod -eq "choco") {
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            [System.Windows.Forms.MessageBox]::Show("Запуск проверки обновлений через Chocolatey. Это может занять некоторое время.", "Проверка обновлений", "OK", "Information")
            # Запускаем обновление всех приложений через Chocolatey
            Start-Process "choco" -ArgumentList "upgrade all -y" -Wait -NoNewWindow
            [System.Windows.Forms.MessageBox]::Show("Проверка и установка обновлений Chocolatey завершена.", "Обновления завершены", "OK", "Information")
        } else {
            [System.Windows.Forms.MessageBox]::Show("Chocolatey не найден. Невозможно проверить обновления.", "Ошибка", "OK", "Error")
        }
    }
})
$bottomButtonsGroupBox.Controls.Add($checkUpdatesBtn)


# Заполнение списка приложений в GUI
foreach ($app in $apps) {
    $checkedList.Items.Add($app.Name) | Out-Null # Добавление имени приложения в список
}

# Обработчик события клика для кнопки "Установить"
$installBtn.Add_Click({
    $selectedItems = @() # Инициализация пустого массива для хранения ID выбранных приложений
    # Перебор всех отмеченных элементов в списке
    foreach ($checkedItem in $checkedList.CheckedItems) {
        # Нахождение соответствующего объекта приложения по имени
        $selectedApp = $apps | Where-Object { $_.Name -eq $checkedItem }
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
                # Пример установки с помощью winget (Windows Package Manager):
                foreach ($id in $selectedItems) {
                    Write-Host "Установка $id с помощью winget..."
                    Start-Process "winget" -ArgumentList "install --id $id --silent" -Wait -NoNewWindow
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
                # Пример установки с помощью Chocolatey:
                foreach ($id in $selectedItems) {
                    Write-Host "Установка $id с помощью choco..."
                    Start-Process "choco" -ArgumentList "install $id -y" -Wait -NoNewWindow
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

# Запуск формы графического интерфейса в модальном режиме
[void]$form.ShowDialog()
