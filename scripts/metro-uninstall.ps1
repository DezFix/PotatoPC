# NAME: Удаляет Metro приложения
# DESC: Удаляет встроенные Metro приложения Microsoft из Windows 10/11
# TAGS: 1
# ICON: 🗑️
# RECOMMENDED: true

# Список приложений для удаления
$apps = @(
    "Microsoft.3DBuilder",
    "Microsoft.XboxApp",
    "Microsoft.GetHelp",
    "Microsoft.ZuneMusic",
    "Microsoft.ZuneVideo",
    "Microsoft.windowscommunicationsapps",
    "Microsoft.WindowsCamera",
    "Microsoft.549981C3F5F10",
    "Microsoft.BingWeather",
    "Microsoft.Getstarted",
    "Microsoft.Microsoft3DViewer",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.MicrosoftStickyNotes",
    "Microsoft.MixedReality.Portal",
    "Microsoft.MSPaint",
    "Microsoft.Office.OneNote",
    "Microsoft.OutlookForWindows",
    "Microsoft.People",
    "Microsoft.ScreenSketch",
    "Microsoft.SkypeApp",
    "Microsoft.Wallet",
    "Microsoft.WindowsAlarms",
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.WindowsMaps",
    "Microsoft.WindowsSoundRecorder",
    "Microsoft.XboxGameOverlay",
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxIdentityProvider",
    "Microsoft.YourPhone",
    "Microsoft.GamingApp",
    "Microsoft.Copilot",
    "Microsoft.WindowsCopilot",
    "Microsoft.AI.Copilot",
    "Microsoft.BingNews",
    "Microsoft.NewsAndInterests"
)

# Удаление приложений для текущего пользователя
foreach ($app in $apps) {
    $package = Get-AppxPackage -Name $app -ErrorAction SilentlyContinue
    if ($package) {
        Remove-AppxPackage -Package $package.PackageFullName -ErrorAction SilentlyContinue
        Write-Host "[+] Удалено для текущего пользователя: $app" -ForegroundColor Cyan
    }
}

# Удаление приложений из системного образа (для новых пользователей)
foreach ($app in $apps) {
    $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $app }
    if ($provisioned) { 
        Remove-AppxProvisionedPackage -Online -PackageName $provisioned.PackageName -ErrorAction SilentlyContinue
        Write-Host "[+] Удалено из системного образа: $app" -ForegroundColor Green
    }
}