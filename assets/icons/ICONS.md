# Иконки интерфейса — Papirus Icon Theme (GNU GPL 3.0)

Файлы в этой папке (`svg/` — исходники, `*.png` — растр 48px для WPF)
взяты из проекта **Papirus Icon Theme**:

- Upstream: https://github.com/PapirusDevelopmentTeam/papirus-icon-theme
- License: **GNU General Public License v3.0** (копия: `LICENSE.GPL-3.0.txt`)
- Соответствие лицензии: исходники SVG сохранены в `svg/` (preferred form
  для модификаций), PNG сгенерированы локально (`svg_manifest.txt` — откуда
  взят каждый файл).

Использованные иконки (слот PotatoPC <- upstream):

actions/admin_gear <- configure | actions/calendar <- calendar-go-today
actions/copy <- edit-copy | actions/doc_new <- document-new
actions/go_up <- go-up | actions/location <- mark-location
actions/nav_startup <- system-run | actions/play <- media-playback-start
actions/power <- system-shutdown | actions/refresh <- view-refresh
actions/restore <- document-revert | actions/save <- document-save | actions/go_down <- go-down
actions/search <- edit-find | actions/select_all <- edit-select-all
actions/undo <- edit-undo
apps/logo <- Twemoji potato (1f954), CC-BY 4.0 (c) Twitter, https://github.com/twitter/twemoji (см. ниже) | apps/nav_modules <- applications-development
apps/nav_diag <- applications-science | apps/nav_updates <- system-software-update
apps/nav_users <- system-users | apps/office <- applications-office
apps/games <- preferences-desktop-gaming | apps/monitor <- utilities-system-monitor
apps/terminal <- utilities-terminal | apps/tools <- applications-engineering
devices/computer <- computer | devices/display <- computer
devices/drive <- drive-harddisk | devices/mic <- audio-input-microphone
devices/mouse <- input-mouse | devices/nav_sys <- computer-laptop
devices/network <- network-wired | devices/keyboard <- input-keyboard
mimetypes/doc_generic <- text-x-generic | mimetypes/nav_apps <- system-software-install
mimetypes/robot <- avatar-default | mimetypes/script_default <- text-x-script
places/folder_open <- folder-blue-open | places/trash <- user-trash
status/err <- dialog-error | status/info <- dialog-information
status/night <- weather-clear-night | status/password <- emblem-encrypted-locked
status/privacy <- changes-prevent | status/warn <- dialog-warning

## Исключение: логотип-картошка
`apps/logo.svg/png` — не Papirus, а Twemoji potato (U+1F954) от Twitter:
https://github.com/twitter/twemoji/blob/master/assets/svg/1f954.svg
Графика Twemoji под CC-BY 4.0 (код — MIT): https://creativecommons.org/licenses/by/4.0/
Упоминание есть в корневом README. CC-BY 4.0 односторонне совместима с GPL-3.0.
