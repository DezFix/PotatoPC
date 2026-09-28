# NAME: 04 · Удалить встроенные приложения (Bloatware)
# DESC: Сносит 24 AppX через Remove-AppxPackage: Solitaire, Советы, Новости, Skype и т.п. + убирает из образа системы
# TAGS: 2
# ICON: 🗑️
# PRESET: potato, office

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
try {
    # Xbox и Copilot здесь не трогаем: у них свои скрипты (08_remove_xbox.ps1 и
    # 05_remove_copilot.ps1). Удаление XboxGamingOverlay из образа молча ломало
    # Game Bar, а про обратное в откате не было ни слова.
    $apps = @(
        "Microsoft.3DBuilder","Microsoft.GetHelp",
        "Microsoft.ZuneMusic","Microsoft.ZuneVideo","Microsoft.windowscommunicationsapps",
        "Microsoft.BingWeather","Microsoft.Getstarted","Microsoft.Microsoft3DViewer",
        "Microsoft.MicrosoftOfficeHub","Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.MixedReality.Portal","Microsoft.Office.OneNote","Microsoft.OutlookForWindows",
        "Microsoft.People","Microsoft.ScreenSketch","Microsoft.SkypeApp","Microsoft.Wallet",
        "Microsoft.WindowsAlarms","Microsoft.WindowsFeedbackHub","Microsoft.WindowsMaps",
        "Microsoft.WindowsSoundRecorder","Microsoft.YourPhone",
        "Microsoft.BingNews","Microsoft.NewsAndInterests","Microsoft.549981C3F5F10"
    )
    $n = 0; $nProv = 0
    $errors = 0
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop)
    foreach ($app in $apps) {
        $pkgs = @(Get-AppxPackage -Name $app -ErrorAction Stop)
        foreach ($pkg in $pkgs) {
            try {
                Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                $remaining = @(Get-AppxPackage -Name $app -ErrorAction Stop | Where-Object { $_.PackageFullName -eq $pkg.PackageFullName })
                if ($remaining.Count -gt 0) { throw "пакет остался после удаления" }
                $n++
            } catch {
                $errors++
                Write-Output ("[!] " + $app + ": " + $_)
            }
        }
        $provs = @($provisioned | Where-Object { $_.DisplayName -eq $app })
        foreach ($prov in $provs) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
                $remaining = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.PackageName -eq $prov.PackageName })
                if ($remaining.Count -gt 0) { throw "пакет остался в образе" }
                $nProv++
            } catch {
                $errors++
                Write-Output ("[!] " + $app + " (образ): " + $_)
            }
        }
    }
    $summary = "[OK] Удалено приложений: " + $n + "; из образа: " + $nProv
    if ($errors -gt 0) {
        # Часть пакетов занята работающими программами - это не провал всей
        # операции, раньше из-за одного такого пакета скрипт светил "✗ Ошибка".
        $summary += "; не удалось: " + $errors + " (занято программами - закрой их и прогони ещё раз)"
    }
    Write-Output $summary
    exit 0
} catch {
    Write-Output ("[X] Ошибка: " + $_)
    exit 1
}
