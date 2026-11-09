# NAME: 07 · Схема питания «Высокая производительность»
# DESC: Включает план powercfg 8c5e7fda…: без экономии CPU. На ноутбуке быстрее съест батарею
# TAGS: 1
# ICON: 🔌
# PRESET: game

# powercfg /setactive и /duplicatescheme пишут в HKLM — без прав админа скрипт
# падал на первой же команде, а откат 07_undo_speed права требовал.
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    # powercfg пишет ошибки в stderr, а при $ErrorActionPreference='Stop' перенаправление
    # 2>&1 по нативной команде даёт terminating error - до $LASTEXITCODE управление не
    # доходит. Из-за этого весь аварийный путь (создание своей схемы) был мёртвым кодом:
    # на ноутбуке без плана «Высокая производительность» скрипт падал сразу.
    function Invoke-Powercfg {
        param([Parameter(ValueFromRemainingArguments = $true)][string[]]$PcArgs)
        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $raw = & powercfg @PcArgs 2>&1
            return [PSCustomObject]@{ Code = $LASTEXITCODE; Text = (($raw | Out-String).Trim()) }
        } finally { $ErrorActionPreference = $prev }
    }

    $guid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
    $r = Invoke-Powercfg /setactive $guid
    $activeGuid = $guid
    if ($r.Code -ne 0) {
        # Плана «Высокая производительность» нет (часто на ноутбуках).
        # Раньше здесь дублировался тот же отсутствующий GUID, то есть
        # запасной путь был мёртвым. Теперь дублируем текущую схему и
        # выставляем процессору 100% — это и есть суть плана.
        $current = Invoke-Powercfg /getactivescheme
        if ($current.Code -ne 0) { throw ("powercfg /getactivescheme: код " + $current.Code + "; " + $current.Text) }
        $currentMatch = [regex]::Match($current.Text, '(?i)([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')
        if (-not $currentMatch.Success) { throw ("powercfg /getactivescheme не вернул GUID: " + $current.Text) }
        $dup = Invoke-Powercfg -duplicatescheme $currentMatch.Groups[1].Value
        if ($dup.Code -ne 0) { throw ("powercfg -duplicatescheme: код " + $dup.Code + "; " + $dup.Text) }
        $dupMatches = [regex]::Matches($dup.Text, '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
        if ($dupMatches.Count -eq 0) { throw ("powercfg -duplicatescheme не вернул GUID: " + $dup.Text) }
        $activeGuid = $dupMatches[$dupMatches.Count - 1].Value
        foreach ($sub in @('SUB_PROCESSOR:PROCTHROTTLEMIN', 'SUB_PROCESSOR:PROCTHROTTLEMAX')) {
            $parts = $sub.Split(':')
            $null = Invoke-Powercfg /setacvalueindex $activeGuid $parts[0] $parts[1] 100
            $null = Invoke-Powercfg /setdcvalueindex $activeGuid $parts[0] $parts[1] 100
        }
        $r = Invoke-Powercfg /setactive $activeGuid
        if ($r.Code -ne 0) { throw ("powercfg /setactive: код " + $r.Code + "; " + $r.Text) }
    }
    $verify = Invoke-Powercfg /getactivescheme
    if ($verify.Code -ne 0 -or $verify.Text -notmatch [regex]::Escape($activeGuid)) {
        throw ("Не удалось подтвердить активную схему: код " + $verify.Code + "; " + $verify.Text)
    }
    Write-Output "[OK] План 'Высокая производительность' включен."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
