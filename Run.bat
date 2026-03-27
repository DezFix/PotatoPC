@echo off
:: PotatoPS Launcher Batch Script
:: Запускает PotatoPS через PowerShell

echo ╔═══════════════════════════════════════════════════════════════╗
echo ║                   PotatoPS Launcher                           ║
echo ╚═══════════════════════════════════════════════════════════════╝
echo.

:: Проверяем права администратора
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] Требуется запуск от имени администратора!
    echo.
    echo Перезапуск с правами администратора...
    powershell -Command "Start-Process PowerShell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~f0\"' -Verb RunAs"
    exit /b
)

:: Проверяем версию PowerShell
powershell -Command "$PSVersionTable.PSVersion.Major" | findstr /R "^[5-9]" >nul
if %errorLevel% neq 0 (
    echo [!] Требуется PowerShell 5.1 или выше!
    echo.
    pause
    exit /b
)

:: Запускаем PotatoPS
echo [i] Запуск PotatoPS...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0launcher.ps1" %*

echo.
echo [✓] PotatoPS завершен.
pause
