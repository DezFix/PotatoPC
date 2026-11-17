# NAME: Отключить автозапуск с флешек и дисков
# DESC: NoDriveTypeAutoRun=0xFF: фшки и диски не запускают программы сами. Защищает от заражения с USB. Заводское значение вернёт откат
# TAGS: 1
# ICON: 💾
# PRESET: potato,office,game
# CHECK: Test-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun' 255

$ErrorActionPreference = "Stop"
try {
    foreach ($p in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer", "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer")) {
        if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        Set-ItemProperty -LiteralPath $p -Name "NoDriveTypeAutoRun" -Value 0xFF -Type DWord -Force
        $v = [int](Get-ItemProperty -LiteralPath $p -Name "NoDriveTypeAutoRun" -ErrorAction Stop).NoDriveTypeAutoRun
        if ($v -ne 0xFF) { throw "NoDriveTypeAutoRun не записался в $p (стало $v)" }
    }
    Write-Output "[OK] Автозапуск с флешек и дисков отключён для всех пользователей. Перезагрузись, чтобы применилось."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
