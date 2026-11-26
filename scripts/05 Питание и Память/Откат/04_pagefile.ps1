# NAME: Откат: Файл подкачки как был
# DESC: Возвращает файл подкачки по снимку, сделанному перед изменением; без снимка - отдаёт его под управление Windows
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
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $data = Get-FirstSnapshot 'pagefile-*.json'
    $mine = { @(Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq 'C:\pagefile.sys' }) }
    if ($data -and -not [bool]$data.Automatic -and @($data.Entries).Count -gt 0) {
        if ([bool]$cs.AutomaticManagedPagefile) { Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $false } -ErrorAction Stop }
        foreach ($pf in (& $mine)) { Remove-CimInstance -InputObject $pf -ErrorAction SilentlyContinue }
        foreach ($e in @($data.Entries)) {
            New-CimInstance -ClassName Win32_PageFileSetting -ErrorAction Stop -Property @{ Name = [string]$e.Name; InitialSize = [uint32]$e.InitialSize; MaximumSize = [uint32]$e.MaximumSize } | Out-Null
        }
        Write-Output "[*] Ручные размеры возвращены по снимку."
    } else {
        if (-not [bool]$cs.AutomaticManagedPagefile) { Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true } -ErrorAction Stop }
        foreach ($pf in (& $mine)) { Remove-CimInstance -InputObject $pf -ErrorAction SilentlyContinue }
        Write-Output "[*] Файл подкачки под управлением Windows."
    }
    Clear-Snapshots "pagefile-*.json"
    Write-Output "[OK] Готово. Перезагрузись, чтобы применилось."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
