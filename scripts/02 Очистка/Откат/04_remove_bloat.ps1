# NAME: Откат: Вернуть встроенные приложения
# DESC: Переподключает удалённые встроенные приложения, если их файлы ещё в системе. Удалённое из образа - поставь из Microsoft Store
# TAGS: 1
# ICON: undo

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Del-Prop($Path, $Name) {
    try { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop } catch {}
}

try {
    # Ровно тот список, который удаляет твик.
    $names = @(
        "Microsoft.3DBuilder","Microsoft.GetHelp","Microsoft.ZuneMusic","Microsoft.ZuneVideo","Microsoft.windowscommunicationsapps",
        "Microsoft.BingWeather","Microsoft.Getstarted","Microsoft.Microsoft3DViewer","Microsoft.MicrosoftOfficeHub",
        "Microsoft.MicrosoftSolitaireCollection","Microsoft.MixedReality.Portal","Microsoft.Office.OneNote","Microsoft.OutlookForWindows",
        "Microsoft.People","Microsoft.SkypeApp","Microsoft.Wallet","Microsoft.WindowsFeedbackHub","Microsoft.WindowsMaps",
        "Microsoft.WindowsSoundRecorder","Microsoft.BingNews","Microsoft.NewsAndInterests","Microsoft.549981C3F5F10"
    )
    $n = 0; $err = 0
    $packages = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object { $names -contains $_.Name })
    if ($packages.Count -eq 0) { Write-Output "[=] Файлов удалённых приложений в системе нет - ставь нужные из Microsoft Store." }
    foreach ($pkg in $packages) {
        try {
            $manifest = Join-Path ([string]$pkg.InstallLocation) "AppXManifest.xml"
            if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw "нет AppXManifest.xml" }
            Add-AppxPackage -Register $manifest -DisableDevelopmentMode -ErrorAction Stop | Out-Null
            $n++
        } catch { $err++; Write-Output ("[!] " + $pkg.Name + ": " + $_.Exception.Message) }
    }
    Write-Output ("[*] Переподключено: " + $n + "; не вышло: " + $err)
    Write-Output "[OK] Готово. Чего нет в списке - установи из Microsoft Store."
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
