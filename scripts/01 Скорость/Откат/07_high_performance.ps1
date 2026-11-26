# NAME: Откат: Схема питания «Сбалансированная»
# DESC: Включает заводскую схему «Сбалансированная» и удаляет копию «Высокой производительности», если её создавал PotatoPC
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
    $r = Invoke-Powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e
    if ($r.Code -ne 0) { throw ("powercfg /setactive: код " + $r.Code + "; " + $r.Text) }
    # Копию схемы твик создаёт через -duplicatescheme, когда встроенная скрыта.
    # Удаляем только копии (не встроенные GUID) с именем «Высокая производительность».
    $builtIn = @('381b4222-f694-41f0-9685-ff5bb260df2e', '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c', 'a1841308-3541-4fab-bc81-f71556f20b4a')
    foreach ($line in (Invoke-Powercfg /list).Text -split "`n") {
        if ($line -notmatch '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s+\((.+)\)') { continue }
        $g = $Matches[1]; $title = $Matches[2]
        if ($builtIn -contains $g.ToLowerInvariant()) { continue }
        if ($title -notmatch '(?i)(Высокая производительность|High performance)') { continue }
        if ((Invoke-Powercfg /delete $g).Code -eq 0) { Write-Output ("[*] Удалена копия схемы: " + $title) }
    }
    Write-Output "[OK] Включена схема «Сбалансированная»."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
