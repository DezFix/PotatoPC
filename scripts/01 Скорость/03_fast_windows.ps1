# NAME: 03 · Интерфейс на максимум: без анимаций и теней
# DESC: Режим «Наилучшее быстродействие» + без прозрачности (реестр VisualEffects). Заметно на слабых ПК
# TAGS: 1
# ICON: 🚀
# PRESET: potato, office, game

$ErrorActionPreference = "Stop"
try {
    Write-Output "[*] Выключаю лишние эффекты..."

    $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -LiteralPath $p -Name "VisualFXSetting" -Value 2 -Force

    # Все выкл, кроме сглаживания шрифтов (иначе текст лесенкой).
    # Байт 2 в маске должен быть 0x03, а не 0x01: с 0x01 это не документированная
    # комбинация "наилучшее быстродействие", о которой говорит заголовок.
    $d = "HKCU:\Control Panel\Desktop"
    if (-not (Test-Path $d)) { New-Item -Path $d -Force | Out-Null }
    Set-ItemProperty -LiteralPath $d -Name "UserPreferencesMask" -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -Force
    Set-ItemProperty -LiteralPath $d -Name "DragFullWindows" -Value 0 -Force
    Set-ItemProperty -LiteralPath $d -Name "FontSmoothing" -Value 2 -Force
    Set-ItemProperty -LiteralPath $d -Name "FontSmoothingType" -Value 2 -Force

    $t = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    # Раньше стояло "если ключ есть" - на машине без него прозрачность просто
    # не отключалась, молча и при "✓ Готово".
    if (-not (Test-Path $t)) { New-Item -Path $t -Force | Out-Null }
    Set-ItemProperty -LiteralPath $t -Name "EnableTransparency" -Value 0 -Force

    Write-Output "[OK] Эффекты выключены. Шрифты четкие. Применится после перезахода."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
