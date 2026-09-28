# NAME: 02 · Включить гибернацию (сон с сохранением окон)
# DESC: Команды powercfg /hibernate on + пункт в меню выключения. Съест гигабайты на C: (hiberfil.sys). Противоположность кнопки выше
# TAGS: 2
# ICON: 💤

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
    $r = Invoke-Powercfg /hibernate on
    if ($r.Code -ne 0) { throw ("powercfg /hibernate on: код " + $r.Code + "; " + $r.Text) }
    $r = Invoke-Powercfg /h /type full
    if ($r.Code -ne 0) { throw ("powercfg /h /type full: код " + $r.Code + "; " + $r.Text) }
    $m = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings"
    if (-not (Test-Path $m)) { New-Item -Path $m -Force | Out-Null }
    New-ItemProperty -LiteralPath $m -Name "ShowHibernateOption" -Value 1 -PropertyType DWORD -Force | Out-Null
    if ([int](Get-ItemProperty -LiteralPath $m -Name "ShowHibernateOption" -ErrorAction Stop).ShowHibernateOption -ne 1) {
        throw "Пункт гибернации в меню не записался"
    }
    # Explorer читает FlyoutMenuSettings только при старте - без перезагрузки
    # в меню выключения пункта не будет, хотя гибернация уже включена.
    Write-Output "[OK] Гибернация включена. Пункт в меню выключения появится после перезагрузки."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
