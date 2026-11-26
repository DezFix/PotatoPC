# NAME: Откат: Гостевая запись как была
# DESC: Включает гостя, только если он был включён до твика (по снимку)
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

# Снимки состояния твик кладёт в ProgramData\PotatoPC\backups перед изменением.
# Берём САМЫЙ РАННИЙ: повторный запуск твика снимает уже изменённое состояние.
# После отката снимки этого вида удаляются - следующий цикл начнётся с чистого листа.
$script:SnapDir = Join-Path $env:ProgramData 'PotatoPC\backups'
function Get-FirstSnapshot([string]$Filter) {
    $f = @(Get-ChildItem -LiteralPath $script:SnapDir -Filter $Filter -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -First 1)
    if ($f.Count -eq 0) { return $null }
    try { return (Get-Content -LiteralPath $f[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}
function Clear-Snapshots([string]$Filter) {
    Get-ChildItem -LiteralPath $script:SnapDir -Filter $Filter -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

try {
    $data = Get-FirstSnapshot 'guest-*.json'
    $guest = Get-LocalUser -ErrorAction Stop | Where-Object { $_.SID.Value -like 'S-1-5-21-*-501' } | Select-Object -First 1
    if (-not $guest) { Write-Output "[=] Гостевой записи нет."; exit 0 }
    if ($data -and [bool]$data.Enabled) { Enable-LocalUser -SID ([string]$guest.SID.Value) -ErrorAction Stop; Write-Output "[*] Гость включён, как было." }
    else { Write-Output "[=] Гость был выключен и до твика - оставляю." }
    Clear-Snapshots "guest-*.json"
    Write-Output "[OK] Готово."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
