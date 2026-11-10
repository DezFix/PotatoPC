# NAME: 07 · Освободить место под Reserved Storage
# DESC: DISM /Set-ReservedStorageState /State:Disabled: освобождает несколько ГБ на C:. Обновления и компоненты Windows работают как обычно
# TAGS: 2
# ICON: 🧱
# PRESET: potato

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    # DISM пишет ошибки в stderr; при $ErrorActionPreference='Stop' перенаправление
    # 2>&1 обрывает скрипт до проверки $LASTEXITCODE.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $out = & dism /Online /Set-ReservedStorageState /State:Disabled 2>&1
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prev }
    $text = ($out | Out-String)
    Write-Output ($text -replace "`r", "`n")
    if ($code -ne 0) { throw ("DISM: код " + $code + "; " + $text.Trim()) }
    Write-Output "[OK] Reserved Storage выключен. Место на C: освобождено."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
