# NAME: Включить тёмную тему
# DESC: Активирует тёмную тему для приложений и системы
# TAGS: 1
# ICON: 🌙

Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0 -Type DWord -Force
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0 -Type DWord -Force
Write-Host "Тёмная тема включена"
