# 🥔 PotatoPS - Системный менеджер Windows

[![GitHub](https://img.shields.io/badge/GitHub-DezFix/PotatoPC-blue?style=for-the-badge&logo=github)](https://github.com/DezFix/PotatoPC)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue?style=for-the-badge&logo=powershell)](https://github.com/PowerShell/PowerShell)

**PotatoPS** — универсальный менеджер настройки Windows с GUI интерфейсом.

---

## 🚀 Запуск

### Онлайн (рекомендуется):
```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/DezFix/PotatoPC/main/install.ps1")))
```

### Локально:
```powershell
.\launcher.ps1          # Консольная версия
.\launcher-gui.ps1      # GUI версия (как в Win11Debloat)
```

> ⚠️ **Требуется:** PowerShell 5.1+, права администратора

---

## 📦 Модули

| Модуль | Описание |
|--------|----------|
| 📦 **Установка ПО** | 88+ программ через winget, пресеты |
| 🧹 **Очистка** | Телеметрия, службы, temp, bloatware |
| 🔍 **Диагностика** | SFC, DISM, CHKDSK, RAM, сеть |
| 🤖 **Удаление AI** | Copilot, Recall, AI пакеты |
| 🗑️ **Деблотер** | 20+ твиков реестра и интерфейса |

---

## 🎨 GUI Интерфейс

Для запуска графической версии (как в Win11Debloat):
```powershell
.\launcher-gui.ps1
```

![PotatoPS GUI](https://via.placeholder.com/800x600/1A1A1A/6366F1?text=PotatoPS+GUI+Preview)

---

## 📋 Требования

- Windows 10/11 x64
- PowerShell 5.1+
- Права администратора
- winget (для установки ПО)

---

## ⚠️ Предупреждение

Используйте на свой страх и риск! Создайте точку восстановления перед применением оптимизаций.

---

## 📄 Лицензия

MIT License — см. файл [LICENSE](LICENSE)

---

## 🙏 Благодарности

Проект создан на основе:
- [PotatoPC](https://github.com/DezFix/PotatoPC)
- [RemoveWindowsAI](https://github.com/zoicware/RemoveWindowsAI)
- [Win11Debloat](https://github.com/Raphire/Win11Debloat)
