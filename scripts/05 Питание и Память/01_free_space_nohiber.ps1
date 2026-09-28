# NAME: 01 · Удалить файл гибернации hiberfil.sys (освободить ГБ)
# DESC: Команда powercfg /hibernate off: удаляет hiberfil.sys (~40% RAM). Пропадут гибернация и быстрый запуск
# TAGS: 2
# ICON: 💽
# PRESET: potato

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
    # Если гибернация уже выключена, powercfg вернёт 0 и скрипт рапортовал бы
    # "Место освобождено", хотя диск не изменился.
    $was = (Invoke-Powercfg /a).Text
    $wasOn = ($was -match '(?i)Hibernate\s+The following sleep states are available') -or ($was -match '(?i)Гибернация')
    $r = Invoke-Powercfg /hibernate off
    if ($r.Code -ne 0) { throw ("powercfg /hibernate off: код " + $r.Code + "; " + $r.Text) }
    if (-not $wasOn) {
        Write-Output "[=] Гибернация уже была выключена - освобождать нечего."
        exit 0
    }
    Write-Output "[OK] Файл гибернации удален. Место освобождено."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
