# NAME: Откат: Включить OneDrive
# DESC: Снимает политику-запрет и возвращает OneDrive в автозагрузку. Если OneDrive был удалён - ставит его из системного установщика
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    Del-Prop "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC"

    # Где стоит OneDrive: у пользователя или для всей машины.
    $exes = @()
    if ($env:LOCALAPPDATA) { $exes += (Join-Path $env:LOCALAPPDATA "Microsoft\OneDrive\OneDrive.exe") }
    $exes += (Join-Path $env:ProgramFiles "Microsoft OneDrive\OneDrive.exe")
    if (${env:ProgramFiles(x86)}) { $exes += (Join-Path ${env:ProgramFiles(x86)} "Microsoft OneDrive\OneDrive.exe") }
    $exe = @($exes | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)

    if ($exe.Count -eq 0) {
        # Старый твик удалял OneDrive - ставим обратно системным установщиком (он сам пропишет автозапуск).
        $cands = @((Join-Path $env:SystemRoot "System32\OneDriveSetup.exe"), (Join-Path $env:SystemRoot "SysWOW64\OneDriveSetup.exe"))
        $setup = @($cands | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
        if ($setup.Count -eq 0) {
            Write-Output "[!] OneDrive не установлен и системного установщика нет - политику снял, сам OneDrive поставь на странице «Программы»."
            exit 0
        }
        $proc = Start-Process -FilePath $setup[0] -Wait -PassThru -ErrorAction Stop
        if ($proc -and $proc.ExitCode -ne 0) { Write-Output ("[*] OneDriveSetup вернул код " + $proc.ExitCode) }
        Write-Output "[OK] OneDrive установлен заново и включён."
        exit 0
    }

    $run = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    if (-not (Test-Path -LiteralPath $run)) { New-Item -Path $run -Force | Out-Null }
    Set-ItemProperty -LiteralPath $run -Name "OneDrive" -Value ('"' + $exe[0] + '" /background') -Type String -Force
    # Сразу не запускаем: из окна администратора OneDrive стартовать отказывается.
    Write-Output "[OK] OneDrive снова включён - запустится при следующем входе в Windows (или из меню Пуск)."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
