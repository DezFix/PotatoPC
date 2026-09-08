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
`SHA256 menu.ps1` для main (коммит 258d614, 2026-09-08):
`EFD85EAD06ADD8FA3C9DA3B3451B7282AEA2DA7261B54E6BF056445F4C486CC3`

Замечание про SmartScreen/Defender: ругаться будет на любой запуск
скрипта, скачанного из интернета — это нормально. Исходники открыты: скачай,
прочитай, потом запускай. После сверки хэша bootstrap сам снимает
блокировку (`Unblock-File`) с проверенного архива.

Описание шапки сприптов 
```powershell
﻿# NAME: Название
# DESC: Описание 
# TAGS: 1,2,3,win11 (1-безопасно 2-осторожно 3-опасно win11-то что работает только на windows11)
# ICON: Емодзи брать на сайте https://emojidb.org/
# RECOMMENDED: true (те скрипты что я рекомендую)
```

## Атрибуция
- Иконки интерфейса — [Papirus Icon Theme](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme) (GNU GPL 3.0).
- Логотип-картошка — [Twemoji](https://github.com/twitter/twemoji) potato (U+1F954), графика под CC-BY 4.0 (c) Twitter.
