# NAME: 11 · Мышь без акселерации (точность для игр)
# DESC: Ставит MouseSpeed=0, пороги 0: курсор движется 1:1 с рукой, прицел точнее. На FPS не влияет
# TAGS: 1
# ICON: 🎯
# PRESET: game

$ErrorActionPreference = "Stop"
try {
    $p = "HKCU:\Control Panel\Mouse"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -LiteralPath $p -Name "MouseSpeed" -Value "0" -Type String -Force
    Set-ItemProperty -LiteralPath $p -Name "MouseThreshold1" -Value "0" -Type String -Force
    Set-ItemProperty -LiteralPath $p -Name "MouseThreshold2" -Value "0" -Type String -Force
    Write-Output "[OK] Акселерация выключена. Перезайди чтобы применилось."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
