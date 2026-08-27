# Загрузка XAML из assets/window.xaml (с fallback на встроенный путь)
$__xamlCandidates = @(
    (Join-Path (Split-Path $script:ModuleDir -Parent) "assets\window.xaml"),
    (Join-Path $script:ModuleDir "assets\window.xaml"),
    (Join-Path $script:ModuleDir "..\assets\window.xaml")
)
$__xamlPath = $null
foreach ($p in $__xamlCandidates) { if (Test-Path $p) { $__xamlPath = $p; break } }
if ($__xamlPath) {
    try { [xml]$xaml = [IO.File]::ReadAllText($__xamlPath) } catch { throw "Не удалось загрузить XAML: $__xamlPath : $_" }
} else {
    throw "XAML не найден. Ожидался assets/window.xaml рядом с modules."
}
Remove-Variable __xamlPath, __xamlCandidates -ErrorAction SilentlyContinue
