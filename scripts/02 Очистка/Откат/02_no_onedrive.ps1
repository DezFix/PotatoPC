# NAME: Откат: Вернуть OneDrive
# DESC: Снимает политику-запрет и ставит OneDrive обратно из системного установщика. Если установщика нет - скачай OneDrive с microsoft.com
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC"
    $cands = @((Join-Path $env:SystemRoot "System32\OneDriveSetup.exe"), (Join-Path $env:SystemRoot "SysWOW64\OneDriveSetup.exe"))
    if ($env:LOCALAPPDATA) { $cands += (Join-Path $env:LOCALAPPDATA "Microsoft\OneDrive\OneDriveSetup.exe") }
    $setup = @($cands | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
    if ($setup.Count -eq 0) {
        Write-Output "[!] OneDriveSetup не найден - политику снял, сам OneDrive скачай с microsoft.com."
    } else {
        $proc = Start-Process -FilePath $setup[0] -Wait -PassThru -ErrorAction Stop
        if ($proc -and $proc.ExitCode -ne 0) { Write-Output ("[*] OneDriveSetup вернул код " + $proc.ExitCode) }
    }
    Write-Output "[OK] OneDrive снова разрешён."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
