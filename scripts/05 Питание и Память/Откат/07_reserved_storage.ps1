# NAME: Откат: Вернуть Reserved Storage
# DESC: Включает зарезервированное хранилище обратно - Windows снова держит место под обновления
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { $out = & dism /Online /Set-ReservedStorageState /State:Enabled 2>&1; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $prev }
    if ($code -ne 0) { throw ("DISM: код " + $code + "; " + (($out | Out-String).Trim())) }
    Write-Output "[OK] Reserved Storage включён."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
