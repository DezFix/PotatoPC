# NAME: Откат: Анимации, тени и прозрачность
# DESC: Возвращает визуальные эффекты «на усмотрение Windows», прозрачность и перетаскивание окон с содержимым
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    Del-Prop "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting"
    # Маска эффектов: без значения Windows берёт заводскую.
    Del-Prop "HKCU:\Control Panel\Desktop" "UserPreferencesMask"
    Set-ItemProperty -LiteralPath "HKCU:\Control Panel\Desktop" -Name "DragFullWindows" -Value "1" -Type String -Force
    Set-ItemProperty -LiteralPath "HKCU:\Control Panel\Desktop" -Name "FontSmoothing" -Value "2" -Type String -Force
    Set-ItemProperty -LiteralPath "HKCU:\Control Panel\Desktop" -Name "FontSmoothingType" -Value 2 -Type DWord -Force
    $t = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    if (-not (Test-Path -LiteralPath $t)) { New-Item -Path $t -Force | Out-Null }
    Set-ItemProperty -LiteralPath $t -Name "EnableTransparency" -Value 1 -Type DWord -Force
    Write-Output "[OK] Эффекты возвращены. Применится после перезахода."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
