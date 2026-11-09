# Архитектура PotatoPC v7

## Цели

1. Один движок, несколько интерфейсов: CLI сейчас, GUI потом.
2. Профили описываются данными, а не кодом.
3. Безопасность по умолчанию: safe-профиль, dry-run, точка восстановления,
   сессия, откат.
4. Модульность: новое действие — это запись в `tweaks.json` и, при
   необходимости, новый `.ps1`/функция.
5. Старое не ломаем: проверенные действия переиспользуются, пока не будут
   переписаны в функции.

## Слои

```
CLI / GUI (gui\Start-PotatoPC.ps1, WPF)
   |
PotatoPC.Core (PowerShell module)
   |-- Config.ps1      загрузка и валидация JSON
   |-- Plan.ps1        профиль -> план действий
   |-- Session.ps1     сессия, лог, JSON
   |-- Executor.ps1    запуск, таймауты, откат
   |-- Common.ps1      пути, логи, система, риск
   |
config/*.json          профили, действия, приложения
actions/*.ps1          проверенные действия
cleaner/*              движок и правила очистки
```

## Данные

### Профиль

```json
{
  "potato": {
    "name": "Potato — суперслабый ПК",
    "description": "...",
    "safe": ["fast-login", "fast-windows"],
    "full": ["remove-bloat", "pagefile"]
  }
}
```

`safe` — то, что можно применять по умолчанию. `full` — дополнительные
осторожные пункты; включаются только с `-Full`.

### Действие

```json
{
  "fast-windows": {
    "name": "...",
    "description": "...",
    "category": "speed",
    "risk": "safe",
    "apply": "actions/01 Скорость/03_fast_windows.ps1",
    "undoGroup": "speed",
    "undoScript": "actions/09 Откат/07_undo_speed.ps1",
    "undoQuality": "full",
    "requiresAdmin": false,
    "requiresReboot": false,
    "irreversible": false,
    "timeoutSec": 300,
    "windows": "any"
  }
}
```

`risk`: `safe` / `caution` / `advanced`.
`undoQuality`: `full` / `partial` / `manual` / `none`.
`windows`: `any` / `11`.

### План

`Resolve-PotatoPlan` берёт профиль, добавляет `full` при `-Full`, применяет
`-Include`/`-Exclude`, отбрасывает Win11-only действия на Win10 и возвращает:

```
Profile, Full, Items[], Warnings[], NeedsReboot, RiskyCount,
IrreversibleCount, AdminRequired, SystemInfo, Created
```

### Сессия

Сохраняется в `%ProgramData%\PotatoPC\sessions\<id>.json`
(без админа — в `%TEMP%`). Содержит план, систему, результат каждого действия,
статус и время. Лог — `%ProgramData%\PotatoPC\logs\session-<id>.log`.

## Поток выполнения

```
CLI
 -> Import-PotatoConfig
 -> Resolve-PotatoPlan
 -> Show-PotatoPlan
 -> [DryRun] стоп
 -> confirm
 -> restore point
 -> session
 -> for each action:
      Invoke-PotatoAction (powershell -File, таймаут, stdout/stderr)
      session.Actions.Add(...)
      Save-PotatoSession
 -> summary
 -> reboot prompt
```

## GUI

`gui\Start-PotatoPC.ps1` — тонкая WPF-обёртка:

- строит план через `Resolve-PotatoPlan`;
- запускает `PotatoPC.ps1` отдельным процессом;
- читает stdout/stderr через `ReadToEndAsync`;
- обновляет интерфейс из `DispatcherTimer`, без событий процесса
  (`OutputDataReceived`/`Exited`), чтобы падение фонового потока не убивало окно;
- кнопка «Проверить» запускает `-DryRun` и показывает полный вывод.

Все ошибки интерфейса пишутся в `%TEMP%\PotatoPC\gui-crash.log`.

## Безопасность

- Абсолютные пути и `..` запрещены: `Resolve-PotatoPath`.
- `safe`-список не содержит `risk != safe`; это проверяет тест.
- `clean-junk` в safe-режиме пропускает игры/шейдеры и `Confirm`-кэши.
- `-Yes` не перезагружает ПК; для перезагрузки нужно отдельное подтверждение
  или `-Reboot`.
- `-Yes` с необратимыми действиями требует `-AllowIrreversible`.
- Перед первым изменением создаётся точка восстановления (если включена).
- Все действия логируются; ошибка одного действия не отменяет остальные, но
  попадает в итог и в сессию.
- Таймауты: DISM 30 мин, winget 60 мин, remove-bloat 20 мин, clean-junk 10 мин.

## Откат

Старые откаты групповые: `undo_speed` откатывает весь раздел «Скорость».
Сессия группирует действия по `undoGroup` и запускает каждый скрипт отката
один раз в обратном порядке. Это честно помечено в `undoQuality`:

- `full` — откат раздела;
- `partial` — часть изменений не вернуть (например, remove-bloat);
- `manual` — откат вручную (firewall);
- `none` — необратимо (clean-junk, winsxs).

Следующий шаг — переписать действия в функции `Apply/Undo/Test`, чтобы откат
был по одному пункту, а не по разделу.

## Как добавить действие

1. Положить `.ps1` в `actions/<раздел>/`.
2. Добавить запись в `config/tweaks.json` (или сгенерировать заново
   `tools/Import-LegacyTweaks.ps1`).
3. Указать `risk`, `apply`, `undoScript`/`undoGroup`, `timeoutSec`, `windows`.
4. Добавить id в `safe` или `full` нужного профиля.
5. Запустить тесты: `Invoke-Pester .\v7\tests`.

## Миграция со старой версии

- Старый код остаётся в корне и в ветке `backup/pre-rewrite-*`.
- `v7/actions` — копия проверенных действий. Логика не переписана, чтобы не
  тащить регрессии.
- `tweaks.json` сгенерирован из старых заголовков `NAME/DESC/TAGS/PRESET`.
- Старые модули (`modules/*.ps1`) не подключены к v7. GUI будет новым,
  тонким слоем над ядром.

## Дальше

1. GUI: три кнопки, safe/full, сводка, прогресс, лог, откат.
2. `-Config` для импорта/экспорта настроек.
3. `-Audit` (только чтение) и `-Sysprep` (default user).
4. Хэши действий и подпись релиза.
5. CI: Pester, AST, JSON, SHA256.
