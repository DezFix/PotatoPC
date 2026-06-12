# NAME: Создать файл подкачки
# DESC: Настройка файла подкачки (Фиксированный размер 4 ГБ на диске C:)
# TAGS: 1
# ICON: 📂

Write-Host "Настройка файла подкачки..." -ForegroundColor Cyan
$Drive = Get-WmiObject Win32_ComputerSystem
$Drive.AutomaticManagedPagefile = $false
$Drive.Put()
$PageFile = Get-WmiObject Win32_PageFileSetting
if ($PageFile) {
    $PageFile.InitialSize = 4096
    $PageFile.MaximumSize = 4096
    $PageFile.Put()
} else {
    Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{Name="C:\pagefile.sys"; InitialSize = 4096; MaximumSize = 4096}
}
