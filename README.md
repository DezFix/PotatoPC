# 🥔 PotatoPS - Системный менеджер Windows

[![GitHub](https://img.shields.io/badge/GitHub-DezFix/PotatoPC-blue?style=for-the-badge&logo=github)](https://github.com/DezFix/PotatoPC)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue?style=for-the-badge&logo=powershell)](https://github.com/PowerShell/PowerShell)

**PotatoPS** — универсальный менеджер настройки Windows. Установка ПО, оптимизация, удаление AI и деблотинг в одном приложении.

---

## 🚀 Запуск

### Онлайн (через GitHub):
```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/DezFix/PotatoPC/main/install.ps1")))
```

### Локально:
```powershell
cd PotatoPC
.\launcher.ps1
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

## 📋 Требования

- Windows 10/11 x64
- PowerShell 5.1+
- Права администратора
- winget (для установки ПО)

---

## 📁 Структура

```
PotatoPC/
├── install.ps1              # Онлайн-загрузчик
├── launcher.ps1             # Главный загрузчик
├── test.ps1                 # Тест проверки
├── Config/
│   ├── apps.json            # Каталог программ
│   └── settings.json        # Настройки
└── Modules/
    ├── SoftwareInstaller/
    ├── SystemClear/
    ├── Diagnostics/
    ├── RemoveAI/
    └── Debloat/
```

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
