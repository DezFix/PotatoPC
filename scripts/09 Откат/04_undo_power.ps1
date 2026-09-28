# NAME: 04 · Откат «Питания»: гибернация и подкачка как было
# DESC: Включает hibernate on + пункт в меню выключения, возвращает быстрый запуск, pagefile в Auto (если он был) и выключает Storage Sense. Откат четырёх кнопок раздела «Питание и Память»
# TAGS: 1
# ICON: ↩️

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    # powercfg пишет ошибки в stderr; при $ErrorActionPreference='Stop' перенаправление
    # 2>&1 обрывает скрипт до проверки $LASTEXITCODE.
    function Invoke-Powercfg {
        param([Parameter(ValueFromRemainingArguments = $true)][string[]]$PcArgs)
        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $raw = & powercfg @PcArgs 2>&1
            return [PSCustomObject]@{ Code = $LASTEXITCODE; Text = (($raw | Out-String).Trim()) }
        } finally { $ErrorActionPreference = $prev }
    }

    Write-Output "[*] Возвращаю гибернацию..."
    $r = Invoke-Powercfg /hibernate on
    if ($r.Code -ne 0) { throw ("powercfg /hibernate on: код " + $r.Code + "; " + $r.Text) }
    # Пункт в меню выключения и быстрый запуск скрипт 02_hibernation.ps1 включал,
    # а 01_free_space_nohiber.ps1 вместе с гибернацией гасил - откат молчал обоих.
    $m = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings"
    if (Test-Path -LiteralPath $m) {
        try { Remove-ItemProperty -LiteralPath $m -Name "ShowHibernateOption" -Force -ErrorAction Stop } catch {}
    }
    $hboot = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
    $hb = Get-ItemProperty -LiteralPath $hboot -Name "HiberbootEnabled" -ErrorAction SilentlyContinue
    if ($null -ne $hb) {
        try { Set-ItemProperty -LiteralPath $hboot -Name "HiberbootEnabled" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue } catch {}
    }

    Write-Output "[*] Файл подкачки..."
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    # Возвращаем автоуправление только если оно и было. У пользователя с
    # ручным pagefile (AutomaticManagedPagefile = false) безусловое $true
    # уничтожало его настройку безвозвратно.
    if (-not [bool]$cs.AutomaticManagedPagefile) {
        Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true } -ErrorAction Stop
        foreach ($pf in @(Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq 'C:\pagefile.sys' })) {
            try { Remove-CimInstance -InputObject $pf -ErrorAction SilentlyContinue } catch {}
        }
        $after = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        if (-not [bool]$after.AutomaticManagedPagefile) { throw "Автоматическое управление pagefile не восстановлено" }
        Write-Output "[*] Pagefile: фиксированный размер возвращён под управление системы."
    } else {
        Write-Output "[=] Pagefile уже под управлением системы - не трогаю."
    }

    Write-Output "[*] Выключаю автоочистку..."
    $sp = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
    if (Test-Path -LiteralPath $sp) {
        foreach ($n in @("01","04","256")) {
            try { Remove-ItemProperty -LiteralPath $sp -Name $n -Force -ErrorAction Stop } catch {}
        }
    }

    Write-Output "[OK] Готово. Нужна перезагрузка, чтобы меню выключения и быстрый запуск вернулись."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
