# Добавление необходимых сборок для работы с графическим интерфейсом
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Проверка на наличие прав администратора
if (-not ([Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
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
            # ИСПРАВЛЕНО: Более надежный способ итерации по свойствам PSCustomObject
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
        [System.Windows.Forms.MessageBox]::Show("Запуск проверки обновлений через Winget. Прогресс будет отображен в текущей консоли.", "Проверка обновлений", "OK", "Information")
        # Установка кодировки для корректного отображения вывода Winget
        $OutputEncoding = [System.Text.Encoding]::UTF8
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        winget upgrade --all --accept-source-agreements --accept-package-agreements 2>&1 | Write-Host
        [System.Windows.Forms.MessageBox]::Show("Проверка и установка обновлений Winget завершена.", "Обновления завершены", "OK", "Information")
    } else {
        $installWingetPrompt = ShowCustomMessageBox -Title "Winget не найден" -Message "Winget не найден в вашей системе. Что вы хотите сделать?" -ButtonTexts @("Открыть Microsoft Store", "Открыть ссылку в браузере", "Отмена")
        if ($installWingetPrompt -eq "Открыть Microsoft Store") {
            [void](Start-Process "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1")
            [System.Windows.Forms.MessageBox]::Show("Открыт Microsoft Store. Пожалуйста, найдите и установите 'App Installer'.", "Установка Winget", "OK", "Information")
        } elseif ($installWingetPrompt -eq "Открыть ссылку в браузере") {
            [void](Start-Process "https://apps.microsoft.com/detail/9nblggh4nns1?hl=ru-RU&gl=UA")
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
            $OutputEncoding = [System.Text.Encoding]::UTF8
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            
            # Пример установки с помощью winget (Windows Package Manager):
            foreach ($app in $selectedItems) {
                Write-Host "Установка $($app.Name) (ID: $($app.Id)) с помощью Winget..." -ForegroundColor Cyan
                # Выполняем команду Winget и перенаправляем stderr в stdout для Write-Host
                $wingetOutput = winget install --id $($app.Id) --accept-source-agreements --accept-package-agreements 2>&1
                Write-Host $wingetOutput

                # Проверяем код выхода Winget для определения результата
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Установка $($app.Name) завершена." -ForegroundColor Green
                } elseif ($LASTEXITCODE -eq -1978335212) {
                    Write-Host "ОШИБКА: Пакет $($app.Name) не найден или не соответствует условиям. Проверьте ID пакета или источники Winget." -ForegroundColor Red
                } elseif ($LASTEXITCODE -eq 1700 -or $LASTEXITCODE -eq -1978335189) {
                    Write-Host "ПРИМЕЧАНИЕ: Winget сообщает, что приложение $($app.Name) уже установлено и находится в актуальном состоянии. Обновления не требуются." -ForegroundColor Yellow
                } else {
                    Write-Host "ОШИБКА при установке $($app.Name) через Winget. Код выхода: " + $LASTEXITCODE -ForegroundColor Red
                }
            }
            [System.Windows.Forms.MessageBox]::Show("Процесс установки Winget завершен. Проверьте установленные приложения.", "Готово", "OK", "Information")
        } else {
            $installWingetPrompt = ShowCustomMessageBox -Title "Winget не найден" -Message "Winget не найден в вашей системе. Что вы хотите сделать?" -ButtonTexts @("Открыть Microsoft Store", "Открыть ссылку в браузere", "Отмена")
            if ($installWingetPrompt -eq "Открыть Microsoft Store") {
                [void](Start-Process "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1")
                [System.Windows.Forms.MessageBox]::Show("Открыт Microsoft Store. Пожалуйста, найдите и установите 'App Installer'.", "Установка Winget", "OK", "Information")
            } elseif ($installWingetPrompt -eq "Открыть ссылку в браузере") {
                [void](Start-Process "https://apps.microsoft.com/detail/9nblggh4nns1?hl=ru-RU&gl=UA")
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
