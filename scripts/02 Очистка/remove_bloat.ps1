# NAME: Убрать мусор
# DESC: Удаляет лишние приложения. Больше места и памяти
# TAGS: 2
# ICON: 🗑️
# PRESET: potato, office
# RECOMMENDED: true

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    $apps = @(
        "Microsoft.3DBuilder","Microsoft.XboxApp","Microsoft.GetHelp",
        "Microsoft.ZuneMusic","Microsoft.ZuneVideo","Microsoft.windowscommunicationsapps",
        "Microsoft.BingWeather","Microsoft.Getstarted","Microsoft.Microsoft3DViewer",
        "Microsoft.MicrosoftOfficeHub","Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.MixedReality.Portal","Microsoft.Office.OneNote","Microsoft.OutlookForWindows",
        "Microsoft.People","Microsoft.ScreenSketch","Microsoft.SkypeApp","Microsoft.Wallet",
        "Microsoft.WindowsAlarms","Microsoft.WindowsFeedbackHub","Microsoft.WindowsMaps",
        "Microsoft.WindowsSoundRecorder","Microsoft.XboxGameOverlay","Microsoft.XboxGamingOverlay",
        "Microsoft.YourPhone","Microsoft.GamingApp","Microsoft.Copilot",
        "Microsoft.BingNews","Microsoft.NewsAndInterests","Microsoft.549981C3F5F10"
    )
    $n = 0
    foreach ($app in $apps) {
        $pkg = Get-AppxPackage -Name $app -ErrorAction SilentlyContinue
        if ($pkg) {
            Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue
            $n++
        }
        $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $app }
        if ($prov) {
            Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue
        }
    }
    Write-Output ("[OK] Удалено приложений: " + $n)
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
