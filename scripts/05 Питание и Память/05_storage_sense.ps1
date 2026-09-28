# NAME: 05 · Контроль памяти: авточистка диска Windows
# DESC: Включает Storage Sense (StoragePolicy 01=1), раз в месяц (04=1) и удаление Temp старше 30 дней (256=30)
# TAGS: 1
# ICON: 🧽
# PRESET: potato, office

$ErrorActionPreference = "Stop"
try {
    $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    # Одного 01=1 мало: периодичность (04) и возраст Temp (256) остаются
    # пользовательскими, а заголовок обещал чистку Temp раз в месяц.
    Set-ItemProperty -LiteralPath $p -Name "01" -Value 1 -Type DWord -Force
    Set-ItemProperty -LiteralPath $p -Name "04" -Value 1 -Type DWord -Force
    Set-ItemProperty -LiteralPath $p -Name "256" -Value 30 -Type DWord -Force
    foreach ($n in @("01","04","256")) {
        $v = Get-ItemProperty -LiteralPath $p -Name $n -ErrorAction SilentlyContinue
        if ($null -eq $v) { throw ("параметр не записался: " + $n) }
    }
    Write-Output "[OK] Контроль памяти включён: чистка раз в месяц, Temp старше 30 дней."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
