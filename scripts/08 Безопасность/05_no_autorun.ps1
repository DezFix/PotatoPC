# NAME: Отключить автозапуск с фшек и дисков
# DESC: NoDriveTypeAutoRun=0xFF: фшки и диски не запускают программы сами. Защищает от заражения с USB. Заводское значение вернёт откат
# TAGS: 1
# ICON: 💾
# PRESET: potato,office,game

$ErrorActionPreference = "Stop"
try {
    $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -LiteralPath $p -Name "NoDriveTypeAutoRun" -Value 0xFF -Type DWord -Force
    $v = [int](Get-ItemProperty -LiteralPath $p -Name "NoDriveTypeAutoRun" -ErrorAction Stop).NoDriveTypeAutoRun
    if ($v -ne 0xFF) { throw "NoDriveTypeAutoRun не записался (стало $v)" }
    Write-Output "[OK] Автозапуск отключён. Перезагрузись, чтобы применилось."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
