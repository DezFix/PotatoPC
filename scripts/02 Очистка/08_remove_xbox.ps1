# NAME: 08 · Отключить службы Xbox (до 5 шт.)
# DESC: Ставит XblAuthManager, XblGameSave, XboxNetApiSvc и др. в Startup=Disabled. НЕ ставить геймерам — сломает Game Pass и Game Bar
# TAGS: 2
# ICON: 🎮
# PRESET: potato, office

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    # Start=4 пишем прямо в реестре: службы Xbox под защитой PPL, и Set-Service/
    # Stop-Service на них отвечают "Access is denied" даже у админа. Молчаливый
    # SilentlyContinue раньше давал "[OK] выключено: 4", когда не выключено было
    # ничего. Теперь пишем в реестр и проверяем результат чтением.
    $list = @("XblAuthManager","XblGameSave","XboxNetApiSvc","XboxGipSvc","xbgm")
    $n = 0; $miss = @(); $fail = @()
    foreach ($s in $list) {
        $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$s"
        if (-not (Test-Path -LiteralPath $k)) { $miss += $s; continue }
        try {
            Set-ItemProperty -LiteralPath $k -Name "Start" -Value 4 -Type DWord -Force -ErrorAction Stop
            $check = [int](Get-ItemProperty -LiteralPath $k -Name "Start" -ErrorAction Stop).Start
            if ($check -ne 4) { throw "Start остался $check" }
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
            $n++
        } catch {
            $fail += $s
            Write-Output ("[!] " + $s + ": " + $_.Exception.Message)
        }
    }
    if ($n -eq 0) {
        Write-Output "[=] Службы Xbox не найдены или защищены - ничего не менял."
        exit 0
    }
    Write-Output ("[OK] Служб Xbox отключено: " + $n)
    if ($miss.Count -gt 0) { Write-Output ("[*] Не установлено (нет на этой системе): " + ($miss -join ", ")) }
    if ($fail.Count -gt 0) { Write-Output ("[!] Не удалось: " + ($fail -join ", ")) }
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
