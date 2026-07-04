$script:WorkFolder    = Join-Path $env:TEMP "PotatoPC"
$script:ScriptsFolder = Join-Path $script:WorkFolder "scripts"
$script:AppsJsonPath  = Join-Path $script:WorkFolder "apps.json"
$script:RepoZipUrl    = "https://github.com/DezFix/PotatoPC/archive/refs/heads/main.zip"
$script:AppsJsonUrl   = "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/apps.json"
$script:LogPath       = Join-Path $script:WorkFolder "potatopc.log"
$script:SettingsPath  = Join-Path $script:WorkFolder "settings.json"

function Get-WindowsMajorVersion {
    try {
        $build = [int](Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuildNumber
        if ($build -ge 22000) { return 11 }
        return 10
    } catch { return 10 }
}
$script:WindowsMajorVersion = Get-WindowsMajorVersion
