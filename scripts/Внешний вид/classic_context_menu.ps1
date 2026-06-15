# NAME: Классическое контекстное меню
# DESC: Возвращает старое меню правой кнопки мыши в Windows 11
# TAGS: 1 , win11
# ICON: 🖱️


$path = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
if (!(Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
Set-ItemProperty -Path $path -Name "(Default)" -Value "" -Force
Write-Host "Классическое контекстное меню включено (нужна перезагрузка)"
