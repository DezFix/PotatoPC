# NAME: Откат: UAC как был
# DESC: Возвращает UAC в состояние до твика по снимку. Без снимка оставляет включённым
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
    $data = Get-FirstSnapshot 'uac-*.json'
    if (-not $data) { Write-Output "[=] Снимка нет - UAC оставляю включённым."; exit 0 }
    Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value ([int]$data.EnableLUA) -Type DWord -Force
    Clear-Snapshots "uac-*.json"
    Write-Output "[OK] UAC возвращён. Перезагрузись."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
