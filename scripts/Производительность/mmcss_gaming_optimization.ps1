# NAME: Оптимизация MMCSS для игр
# DESC: Настраивает планировщик мультимедиа для снижения задержек и повышения приоритета игр
# TAGS: 1
# ICON: 🎮


$systemProfileKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"

# Основные настройки SystemProfile
if (!(Test-Path $systemProfileKey)) { New-Item -Path $systemProfileKey -Force | Out-Null }
Set-ItemProperty -Path $systemProfileKey -Name "NoLazyMode" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $systemProfileKey -Name "AlwaysOn" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $systemProfileKey -Name "NetworkThrottlingIndex" -Value 0xFFFFFFFF -Type DWord -Force
Set-ItemProperty -Path $systemProfileKey -Name "SystemResponsiveness" -Value 10 -Type DWord -Force

# Настройки для игр
$gamesKey = "$systemProfileKey\Tasks\Games"
if (!(Test-Path $gamesKey)) { New-Item -Path $gamesKey -Force | Out-Null }
Set-ItemProperty -Path $gamesKey -Name "Priority" -Value 2 -Type DWord -Force
Set-ItemProperty -Path $gamesKey -Name "Scheduling Category" -Value "High" -Type String -Force
Set-ItemProperty -Path $gamesKey -Name "SFIO Priority" -Value "High" -Type String -Force
Set-ItemProperty -Path $gamesKey -Name "GPU Priority" -Value 8 -Type DWord -Force

Write-Host "MMCSS оптимизирован для игр и низкой задержки"
