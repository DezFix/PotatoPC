# Плагины PotatoPC

PotatoPC собирается из плагинов двух видов:

1. **Твики** — отдельные `.ps1` в `scripts\<NN Раздел>\`. Появляются на странице «Твики».
2. **Вкладки** — `.ps1` в `pages\`. Появляются в боковом меню.

Положите файл в папку и нажмите «Обновить» на странице «Твики» (для вкладок — перезапустите программу).

## Твик

`scripts\06 Мои\01_no_bluetooth.ps1`:

```powershell
# NAME: Отключить службы Bluetooth
# DESC: Если Bluetooth не нужен - минус две службы в фоне. Есть откат в разделе «Откат»
# TAGS: 2
# ICON: plug
# PRESET: potato
# CHECK: (Get-Service bthserv -ErrorAction Stop).StartType -eq 'Disabled'
# TIMEOUT: 120

#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
try {
    Set-Service bthserv -StartupType Disabled
    Stop-Service bthserv -Force -ErrorAction SilentlyContinue
    Write-Output '[OK] Bluetooth отключён'
    exit 0
} catch {
    Write-Output ('[X] Ошибка: ' + $_)
    exit 1
}
```

| Поле | Обязательно | Что значит |
|---|---|---|
| `NAME` | да | Название в списке |
| `DESC` | да | Одна строка: что делает и чем может помешать |
| `TAGS` | да | `1` — безопасно, `2` — осторожно, `3` — рискованно. Добавьте `win11`, если твик только для Windows 11 |
| `ICON` | нет | Имя значка: `bolt`, `broom`, `shield`, `eye`, `mem`, `disk`, `power`, `plug`, `lock`… Без него берётся значок раздела |
| `PRESET` | нет | В какие пресеты входит: `potato`, `office`, `game` (через запятую) |
| `CHECK` | нет | Выражение PowerShell: `$true`, если твик уже применён. Помощник: `Test-Reg 'HKCU:\Путь' 'Имя' значение` |
| `UNDO` | нет | Путь к своему скрипту отката относительно `scripts\` |
| `UNDOFOR` | для откатов | Номер раздела, который откатывает скрипт (`01`). Такой скрипт попадает в «Откатить раздел» и на страницу «История» |
| `TIMEOUT` | нет | Сколько секунд ждать, по умолчанию 300 |

Правила:

* Скрипт запускается отдельным процессом `powershell.exe` от администратора. Результат — код выхода: `0` успех, иначе ошибка.
* Всё, что скрипт пишет через `Write-Output`, видно в журнале внизу окна.
* Сохраняйте файл в **UTF-8 с BOM**, иначе Windows PowerShell 5.1 испортит кириллицу.
* Делайте скрипт повторяемым: второй запуск не должен ломать то, что сделал первый.
* Прежде чем менять настройку, сохраните старое значение в `$env:ProgramData\PotatoPC\backups` — так откат вернёт именно то, что было.
* Файлы, которых нет в `SHA256SUMS`, помечаются как «Сторонний плагин». Перед запуском приложение перечисляет их отдельно.

## Вкладка

`pages\85_hello.ps1`:

```powershell
# PAGE: hello
# TITLE: Привет
# ICON: info
# ORDER: 85

function Build-Page_hello {
    $L = New-PageLayout -Title 'Привет' -Subtitle 'Моя вкладка'
    $btn = New-Button -Text 'Посчитать процессы' -Kind Primary -OnClick {
        Start-BgTask -Name 'Процессы' -Script { @(Get-Process).Count } -OnDone {
            param($n) Show-Info ('Процессов: ' + $n)
        } | Out-Null
    }
    [void]$L.Body.Children.Add($btn)
    return $L.Root
}

# Необязательно: вызывается при каждом открытии вкладки.
function Show-Page_hello { param($Arg) }
```

* `ORDER` задаёт место в меню. У встроенных вкладок порядок 10…90.
* `# NAV: footer` ставит пункт в нижнюю часть меню.
* Долгую работу выносите в `Start-BgTask`, иначе окно зависнет. `-OnDone` выполняется в окне, и в нём можно менять элементы.
* Конструктор интерфейса — `core\Ui.ps1`:
  * блоки: `New-Card`, `New-Section`, `New-Row`, `New-Button`, `New-CheckBox`, `New-Toggle`, `New-Badge`, `New-StatCard`, `New-Meter`, `New-Hint`;
  * диалоги: `Show-Confirm`, `Show-Info`, `Show-FormDialog`.
* Журнал: `Write-Log 'текст' 'ok'` (уровни `info`, `ok`, `warn`, `err`). История действий: `Add-History -Kind 'my' -Name 'что сделано'`.
* Состояние страницы храните в `$script:`-переменной: обработчики кнопок видят только её.
