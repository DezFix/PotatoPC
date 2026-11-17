# NAME: Удалить файл гибернации hiberfil.sys (освободить ГБ)
# DESC: powercfg /hibernate off: удаляет hiberfil.sys (около 40% объёма RAM). Пропадут гибернация и быстрый запуск. Есть откат
# TAGS: 2
# ICON: 💽
# PRESET: potato
# CHECK: -not (Test-Path -LiteralPath (Join-Path $env:SystemDrive 'hiberfil.sys'))

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $hibFile = Join-Path $env:SystemDrive 'hiberfil.sys'
    $sizeGb = 0
    $exists = Test-Path -LiteralPath $hibFile
    if ($exists) { try { $sizeGb = [math]::Round((Get-Item -LiteralPath $hibFile -Force).Length / 1GB, 1) } catch {} }
    # powercfg пишет ошибки в stderr: при 'Stop' это оборвало бы скрипт раньше проверки кода.
    $ErrorActionPreference = "Continue"
    $out = & powercfg /hibernate off 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    if ($code -ne 0) { throw ("powercfg /hibernate off: код " + $code + "; " + $out.Trim()) }
    if (-not $exists) {
        Write-Output "[=] Файла гибернации не было - гибернация уже выключена."
        exit 0
    }
    Write-Output ("[OK] Гибернация выключена, файл hiberfil.sys удалён" + $(if ($sizeGb -gt 0) { " (освобождено около " + $sizeGb + " ГБ)." } else { "." }))
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
