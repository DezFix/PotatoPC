# NAME: 07 · Схема питания «Высокая производительность»
# DESC: Включает план powercfg 8c5e7fda…: без экономии CPU. На ноутбуке быстрее съест батарею
# TAGS: 1
# ICON: 🔌
# PRESET: potato, game

$ErrorActionPreference = "Stop"
try {
    $guid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
    $out = & powercfg /setactive $guid 2>&1
    $code = $LASTEXITCODE
    $activeGuid = $guid
    if ($code -ne 0) {
        # Запасной вариант: своя схема от текущей
        $dupOut = & powercfg -duplicatescheme $guid 2>&1
        $dupCode = $LASTEXITCODE
        $dupText = ($dupOut | Out-String)
        if ($dupCode -ne 0) { throw ("powercfg -duplicatescheme: код " + $dupCode + "; " + $dupText.Trim()) }
        $dupMatches = [regex]::Matches($dupText, '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
        if ($dupMatches.Count -eq 0) { throw ("powercfg -duplicatescheme не вернул GUID: " + $dupText.Trim()) }
        $activeGuid = $dupMatches[$dupMatches.Count - 1].Value
        $out = & powercfg /setactive $activeGuid 2>&1
        $code = $LASTEXITCODE
        if ($code -ne 0) { throw ("powercfg /setactive: код " + $code + "; " + (($out | Out-String).Trim())) }
    }
    $verifyOut = & powercfg /getactivescheme 2>&1
    $verifyCode = $LASTEXITCODE
    $verifyText = ($verifyOut | Out-String)
    if ($verifyCode -ne 0 -or $verifyText -notmatch [regex]::Escape($activeGuid)) { throw ("Не удалось подтвердить активную схему: код " + $verifyCode + "; " + $verifyText.Trim()) }
    Write-Output "[OK] План 'Высокая производительность' включен."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
