# NAME: Память из диска
# DESC: Если мало RAM, Windows возьмет место у диска. Лечит вылеты
# TAGS: 2
# ICON: 💾
# PRESET: potato
# RECOMMENDED: true

#Requires -RunAsAdministrator
param([int]$SizeMB = 0)
$ErrorActionPreference = "Stop"
try {
    $cs = Get-CimInstance Win32_ComputerSystem
    $ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    Write-Output ("[*] RAM: " + $ramGB + " ГБ")

    # Расчет если юзер не задал вручную
    if ($SizeMB -le 0) {
        $ramMB = [int]($cs.TotalPhysicalMemory / 1MB)
        if ($ramMB -le 4096) { $SizeMB = 4096 }
        elseif ($ramMB -le 8192) { $SizeMB = 6144 }
        else { $SizeMB = 4096 }
    }
    Write-Output ("[*] Ставлю файл подкачки: " + $SizeMB + " МБ")

    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $freeMB = [int]($disk.FreeSpace / 1MB)
    if ($freeMB -lt ($SizeMB + 10240)) {
        Write-Output ("[X] Мало места на C: свободно " + $freeMB + " МБ, надо " + ($SizeMB + 10240))
        exit 1
    }

    # Уже так? ничего не делаем
    $cur = Get-CimInstance Win32_PageFileSetting -Filter "Name='C:\\pagefile.sys'" -ErrorAction SilentlyContinue
    if ($cur -and $cur.InitialSize -eq $SizeMB -and $cur.MaximumSize -eq $SizeMB) {
        Write-Output "[=] Уже настроено, ничего не меняю."
        exit 0
    }

    Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $false } -ErrorAction Stop
    if ($cur) {
        Set-CimInstance -InputObject $cur -Property @{ InitialSize = $SizeMB; MaximumSize = $SizeMB } -ErrorAction Stop
    } else {
        New-CimInstance -ClassName Win32_PageFileSetting -Property @{ Name = "C:\pagefile.sys"; InitialSize = $SizeMB; MaximumSize = $SizeMB } -ErrorAction Stop | Out-Null
    }
    Write-Output "[OK] Готово. Перезагрузись чтобы применилось."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
