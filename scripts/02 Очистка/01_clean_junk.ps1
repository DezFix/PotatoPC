# NAME: 01 · Чистка временных файлов (Temp, кэши, логи)
# DESC: Удаляет только мусор по cleaner/rules.json: Temp, кэши браузеров/игр, DNS-кэш. Свои папки PotatoPC и данные пользователя защищены
# TAGS: 1
# ICON: 🧹
# PRESET: potato, office, game

$ErrorActionPreference = "Stop"

# Движок очистки один на всё приложение: cleaner/CleanGuard.ps1 обслуживает и
# вкладку «Очистка», и этот скрипт. Копия функций здесь означала бы, что
# защита чистки может разойтись с тем, что реально чистит GUI.
$guardPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'cleaner\CleanGuard.ps1'
if (-not (Test-Path -LiteralPath $guardPath -PathType Leaf)) {
    Write-Output ("[X] Не найден движок очистки: " + $guardPath)
    Write-Output "    Файл cleaner/CleanGuard.ps1 обязателен. Без него чистка не запускается: без защиты легко снести свои же папки."
    exit 1
}
. $guardPath
if (-not (Get-Command -Name Test-CleanProtectedPath -CommandType Function -ErrorAction SilentlyContinue)) {
    Write-Output "[X] cleaner/CleanGuard.ps1 не загрузился (нет функции защиты). Чистка прервана."
    exit 1
}

# Кто мы: папка этого скрипта, все её родители до корня репозитория и сам файл.
# Репозиторий лежит в %TEMP%\PotatoPC или в кэше ProgramData — и то, и другое
# защищено, но явная регистрация страхует от смены пути развёртывания.
$scriptRoots = @()
try { $scriptRoots += $PSCommandPath } catch {}
try {
    $walk = (ConvertTo-CleanFullPath $PSScriptRoot)
    while (-not [string]::IsNullOrWhiteSpace($walk)) {
        $scriptRoots += $walk
        $parent = [System.IO.Path]::GetDirectoryName($walk)
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $walk) { break }
        $walk = $parent
    }
} catch {}
Add-CleanGuardRoot -Path $scriptRoots

try {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $rulesPath = Join-Path $repoRoot 'cleaner\rules.json'
    $groups = $null
    if (Test-Path -LiteralPath $rulesPath) {
        try { $groups = (Get-Content $rulesPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop).Groups } catch {}
    }
    if (-not $groups) {
        $groups = @(@{ Name = 'Система'; Items = @(
            @{ Name = 'Временные файлы'; Paths = @('${TEMP}', '${WINDIR}/Temp') } ) })
    }
    $freed = 0L; $errs = 0; $n = 0
    foreach ($g in $groups) {
        foreach ($item in $g.Items) {
            $iname = [string]$item.Name
            if ([string]$item.Action -eq 'flushdns') {
                foreach ($ln in (Invoke-CleanAction -Name 'flushdns')) { Write-Output ("[*] " + $ln) }
                continue
            }
            if ([string]$item.Action -eq 'arpclear') {
                foreach ($ln in (Invoke-CleanAction -Name 'arpclear')) { Write-Output ("[*] " + $ln) }
                continue
            }
            $rp = @(Resolve-CleanPaths -Paths @($item.Paths) -ChildSubdir ([string]$item.ChildSubdir))
            if ($rp.Count -eq 0) { continue }
            $before = [long](Measure-CleanPaths -Resolved $rp -MinAgeDays ([int]$item.MinAgeDays))
            if ($before -le 0) { continue }
            $errs += [int](Clear-CleanPaths -Resolved $rp -MinAgeDays ([int]$item.MinAgeDays))
            $freed += $before
            $n++
            Write-Output ("[*] {0}: ~{1} МБ" -f $iname, [math]::Round($before / 1MB, 1))
        }
    }
    $skipped = @(Get-CleanSkippedReport)
    if ($skipped.Count -gt 0) {
        Write-Output ("[*] Защищено, не тронуто: " + $skipped.Count + " (свои папки PotatoPC, ссылки, занятые файлы)")
    }
    if ($errs -gt 0) {
        Write-Output ("[OK] Почищено пунктов: {0}, освобождено ~{1} МБ. Не удалось удалить: {2} (занято другими программами)" -f $n, [math]::Round($freed / 1MB, 1), $errs)
    } else {
        Write-Output ("[OK] Почищено пунктов: {0}, освобождено ~{1} МБ, ошибок: 0" -f $n, [math]::Round($freed / 1MB, 1))
    }
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
