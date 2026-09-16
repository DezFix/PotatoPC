# NAME: 08 04 · Диагностика: что лишнего включено (только показ)
# DESC: Проверяет SMBv1, службы телеметрии, план питания и автозагрузку. Только отчёт, ничего не отключает
# TAGS: 1
# ICON: 🔬

$ErrorActionPreference = "Stop"
try {
    Write-Output "=== Только чтение: ничего не меняю ==="
    try {
        $s = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
        Write-Output ("[*] SMBv1 (древний, обычно не нужен): " + $s.State)
    } catch { Write-Output "[!] SMBv1 не проверился" }
    foreach ($svc in @("DiagTrack","dmwappushservice","DusmSvc","WerSvc","XblGameSave","XboxNetApiSvc")) {
        $o = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($o) { Write-Output ("[*] Служба {0}: {1} (запуск: {2})" -f $svc, $o.Status, $o.StartType) }
    }
    try {
        $plan = (powercfg /getactivescheme 2>$null | Out-String).Trim()
        Write-Output ("[*] План питания: " + $plan)
    } catch {}
    try {
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
        Write-Output ("[*] Диск C: свободно {0} ГБ из {1} ГБ" -f [math]::Round($disk.FreeSpace/1GB,1), [math]::Round($disk.Size/1GB,1))
    } catch {}
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $up = (Get-Date) - $os.LastBootUpTime
        Write-Output ("[*] Аптайм: {0}д {1}ч, свободно RAM: {2} МБ" -f $up.Days, $up.Hours, [math]::Round($os.FreePhysicalMemory/1KB))
    } catch {}
    try {
        $n = @(Get-CimInstance Win32_StartupCommand -ErrorAction Stop).Count
        Write-Output ("[*] Записей в автозагрузке (WMI): " + $n + " — детали смотри во вкладке «Автозагрузка»")
    } catch {}
    Write-Output "[OK] Проверка закончена."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
