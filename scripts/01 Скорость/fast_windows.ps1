# NAME: Быстрые окна
# DESC: Убирает тени и анимацию. Меню летает на слабом ПК
# TAGS: 1
# ICON: 🚀
# PRESET: potato, office, game
# RECOMMENDED: true

$ErrorActionPreference = "Stop"
try {
    Write-Output "[*] Выключаю лишние эффекты..."

    $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -Path $p -Name "VisualFXSetting" -Value 2 -Force

    # Все выкл, кроме сглаживания шрифтов (иначе текст лесенкой)
    $d = "HKCU:\Control Panel\Desktop"
    Set-ItemProperty -Path $d -Name "UserPreferencesMask" -Value ([byte[]](0x90,0x12,0x01,0x80,0x10,0x00,0x00,0x00)) -Force
    Set-ItemProperty -Path $d -Name "DragFullWindows" -Value 0 -Force
    Set-ItemProperty -Path $d -Name "FontSmoothing" -Value 2 -Force
    Set-ItemProperty -Path $d -Name "FontSmoothingType" -Value 2 -Force

    $t = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    if (Test-Path $t) { Set-ItemProperty -Path $t -Name "EnableTransparency" -Value 0 -Force }

    Write-Output "[OK] Эффекты выключены. Шрифты четкие. Применится после перезахода."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
