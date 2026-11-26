# NAME: Откат: Вернуть службы Xbox
# DESC: Возвращает службы Xbox в режим «Вручную» (заводской) - заработают Game Pass и сохранения в облаке
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    # Start=3 пишем в реестр: XboxGipSvc/xbgm под защитой PPL, Set-Service отказывает.
    $n = 0
    foreach ($s in @("XblAuthManager","XblGameSave","XboxNetApiSvc","XboxGipSvc","xbgm")) {
        $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$s"
        if (-not (Test-Path -LiteralPath $k)) { continue }
        try { Set-ItemProperty -LiteralPath $k -Name "Start" -Value 3 -Type DWord -Force -ErrorAction Stop; $n++ }
        catch { Write-Output ("[!] " + $s + ": " + $_.Exception.Message) }
    }
    Write-Output ("[*] Служб в режиме «Вручную»: " + $n)
    Write-Output "[OK] Службы Xbox возвращены."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
