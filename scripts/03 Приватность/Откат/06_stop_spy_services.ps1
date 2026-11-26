# NAME: Откат: Службы телеметрии
# DESC: Возвращает службам DiagTrack, dmwappushservice и сборщику диагностики заводской режим запуска
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    $restore = @(
        @{ Name = 'DiagTrack'; Mode = 'Automatic' },
        @{ Name = 'dmwappushservice'; Mode = 'Manual' },
        @{ Name = 'DcpSvc'; Mode = 'Manual' },
        @{ Name = 'diagnosticshub.standardcollector.service'; Mode = 'Manual' }
    )
    foreach ($s in $restore) {
        if (-not (Get-Service -Name $s.Name -ErrorAction SilentlyContinue)) { continue }
        try { Set-Service -Name $s.Name -StartupType $s.Mode -ErrorAction Stop; Write-Output ("[*] " + $s.Name + " -> " + $s.Mode) }
        catch { Write-Output ("[!] " + $s.Name + ": " + $_.Exception.Message) }
    }
    Start-Service -Name DiagTrack -ErrorAction SilentlyContinue
    Write-Output "[OK] Службы возвращены."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
