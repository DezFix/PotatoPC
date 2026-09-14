# PotatoPC

## Установка

### 1. Быстро (для своих)
```powershell
irm "https://kutt.to/potatopc" | iex
```
Шортлинк ведёт на `menu.ps1` в main-ветке. Удобно, но код выполняется сразу
без проверки, а шортлинк непрозрачен. Вариант чуть честнее (та же ветка,
но виден конечный URL):
```powershell
irm https://raw.githubusercontent.com/DezFix/PotatoPC/main/menu.ps1 | iex
```

### 2. Безопасно (со сверкой SHA256)
```powershell
Invoke-WebRequest https://raw.githubusercontent.com/DezFix/PotatoPC/main/Install-PotatoPC.ps1 -OutFile Install-PotatoPC.ps1
# Аудит без запуска: скачать архив, показать хэш, проверить файлы
.\Install-PotatoPC.ps1 -VerifyOnly
# Запуск со сверкой хэша релиза (хэш — на странице Releases)
.\Install-PotatoPC.ps1 -ExpectedHash '<SHA256>'
```
Несовпадение хэша = архив удаляется, запуск блокируется. Актуальный
`SHA256 menu.ps1` (v6 по умолчанию, 2026-09-14):
`8593417013087F236EC8BD27BD72312126016276816ABABB64BC794E2E1FA1D4`

Замечание про SmartScreen/Defender: ругаться будет на любой запуск
скрипта, скачанного из интернета — это нормально. Исходники открыты: скачай,
прочитай, потом запускай. После сверки хэша bootstrap сам снимает
блокировку (`Unblock-File`) с проверенного архива.

### 3. Интерфейс v6 (по умолчанию)
```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File menu.ps1
```
Дашборд, закреплённые панели действий, кастомный хром.
Черновик дизайна: `mockup/v6-preview.ps1` (только картинка, не запускать).

Описание шапки сприптов 
```powershell
﻿# NAME: Название
# DESC: Описание 
# TAGS: 1,2,3,win11 (1-безопасно 2-осторожно 3-опасно win11-то что работает только на windows11)
# ICON: Емодзи брать на сайте https://emojidb.org/
# PRESET: potato,office,game (в какие пресеты входит: potato-слабый ПК, office-работа, game-игры)
```

Нумерация скриптов: файлы лежат как `scripts/02 Очистка/04_remove_bloat.ps1`,
номер раздела + номер файла (`02 04`) виден и в интерфейсе. Порядок в разделе —
по номеру файла. Поиск скрывает разделы без совпадений; зависший скрипт
(3 попытки по 120 секунд) скипается, очередь идёт дальше.

## Атрибуция
- Иконки интерфейса — [Papirus Icon Theme](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme) (GNU GPL 3.0).
- Логотип-картошка — [Twemoji](https://github.com/twitter/twemoji) potato (U+1F954), графика под CC-BY 4.0 (c) Twitter.
