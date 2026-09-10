# NAME: Почистить мусор
# DESC: Чистит временные файлы. Отдаёт гигабайты диску
# TAGS: 1
# ICON: 🧹
# PRESET: potato, office, game
# RECOMMENDED: true

$ErrorActionPreference = "Stop"
try {
    $before = 0
    foreach ($d in @($env:TEMP, "C:\Windows\Temp")) {
        if (Test-Path $d) {
            $s = (Get-ChildItem -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            if ($s) { $before += $s }
            Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $mb = [math]::Round($before / 1MB, 1)
    Write-Output ("[OK] Временных файлов удалено примерно на " + $mb + " МБ.")
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
