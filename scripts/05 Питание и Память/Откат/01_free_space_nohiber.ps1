# NAME: Откат: Вернуть гибернацию
# DESC: Включает гибернацию и быстрый запуск обратно (файл hiberfil.sys снова займёт место на C:)
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

# powercfg пишет ошибки в stderr; при ErrorActionPreference=Stop перенаправление
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

try {
    $r = Invoke-Powercfg /hibernate on
    if ($r.Code -ne 0) { throw ("powercfg /hibernate on: код " + $r.Code + "; " + $r.Text) }
    Write-Output "[OK] Гибернация включена."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
