# NAME: 09 · Откат «чистки реестра»: вернуть автозагрузку
# DESC: Возвращает включёнными те записи Run/RunOnce и файлы папок автозагрузки, которые отключил 02 Очистка/09_clean_autostart.ps1 (по его копии от даты)
# TAGS: 1
# ICON: ↩️

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

# Откат работает по копии, которую 09_clean_autostart.ps1 положил в
# C:\ProgramData\PotatoPC\backups\autostart-*.json. Без копии откатывать нечего:
# значения в реестре скрипт не удалял, он лишь помечал их выключенными, поэтому
# состояние можно вернуть точным списком, а не «включить всё подряд».

function Restore-Approved {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
    $bytes = New-Object byte[] 12
    $bytes[0] = 2   # 0x02 = включено
    [System.BitConverter]::GetBytes([int64][DateTime]::UtcNow.ToFileTimeUtc()).CopyTo($bytes, 4)
    $k = Get-Item -LiteralPath $Path -ErrorAction Stop
    try { $k.SetValue($Name, $bytes, [Microsoft.Win32.RegistryValueKind]::Binary) } finally { $k.Close() }
}

try {
    $backupDir = if ($env:ProgramData) { Join-Path $env:ProgramData 'PotatoPC\backups' } else { Join-Path $env:TEMP 'PotatoPC' }
    if (-not (Test-Path -LiteralPath $backupDir -PathType Container)) {
        Write-Output ("[=] Копий автозагрузки нет: " + $backupDir)
        Write-Output "    Значит, 02 Очистка/09_clean_autostart.ps1 не запускался - откатывать нечего."
        exit 0
    }
    $files = @(Get-ChildItem -LiteralPath $backupDir -Filter 'autostart-*.json' -File -Force -ErrorAction Stop |
        Sort-Object Name -Descending)
    if ($files.Count -eq 0) {
        Write-Output ("[=] В папке нет копий автозагрузки: " + $backupDir)
        exit 0
    }
    Write-Output ("[*] Найдено копий: {0}. Откатываю последнюю: {1}" -f $files.Count, $files[0].Name)
    $data = $null
    try { $data = Get-Content -LiteralPath $files[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
    catch { Write-Output ("[X] Копия не читается: " + $_.Exception.Message); exit 1 }
    $items = @($data.Items)
    if ($items.Count -eq 0) {
        Write-Output "[=] В копии нет отключённых записей."
        exit 0
    }
    $ok = 0; $err = 0
    foreach ($it in $items) {
        try {
            if ([string]$it.Kind -eq 'Folder') {
                $src = [string]$it.Path
                # В копии лежит ИСХОДНЫЙ путь, а отключающий скрипт переименовал
                # файл в <имя>.disabled. Раньше проверка шла по исходному пути
                # (которого уже нет) и уходила в continue ДО проверки .disabled -
                # ветка переименования была мёртвым кодом, и всё из папок
                # автозагрузки отключалось навсегда.
                $disabled = $src
                if (-not (Test-Path -LiteralPath $disabled) -and (Test-Path -LiteralPath ($src + '.disabled'))) {
                    $disabled = $src + '.disabled'
                }
                if (-not (Test-Path -LiteralPath $disabled)) {
                    Write-Output ("[!] Файла нет (ни «" + $src + "», ни «" + $src + ".disabled»): " + $src)
                    $err++
                    continue
                }
                if ($disabled.EndsWith('.disabled', [System.StringComparison]::OrdinalIgnoreCase)) {
                    Rename-Item -LiteralPath $disabled -NewName ([System.IO.Path]::GetFileName(($disabled -replace '(?i)\.disabled$', ''))) -Force -ErrorAction Stop
                }
            } else {
                Restore-Approved -Path ([string]$it.Approved) -Name ([string]$it.Name) -ErrorAction Stop
            }
            $ok++
        } catch {
            $err++
            Write-Output ("[!] " + $it.Name + ": " + $_.Exception.Message)
        }
    }
    # Копию убираем, чтобы повторный откат не включил то, что выключил новый запуск.
    try { Remove-Item -LiteralPath $files[0].FullName -Force -ErrorAction Stop } catch {}
    if ($err -gt 0) {
        Write-Output ("[OK] Включено обратно: {0}, ошибок: {1}. Взгляни во вкладку «Автозагрузка»." -f $ok, $err)
    } else {
        Write-Output ("[OK] Включено обратно: {0}. Взгляни во вкладку «Автозагрузка»." -f $ok)
    }
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
