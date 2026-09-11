$script:WorkFolder    = Join-Path $env:TEMP "PotatoPC"
$script:CleanRulesPath = ""
try {
    $rootHint = $null
    try { $rootHint = $script:ModuleDir } catch {}
    if ($rootHint) {
        $cand = Join-Path (Split-Path $rootHint -Parent) "cleaner\rules.json"
        if (Test-Path $cand) { $script:CleanRulesPath = $cand }
    }
} catch {}
$script:ScriptsFolder = Join-Path $script:WorkFolder "scripts"
$script:AppsJsonPath  = Join-Path $script:WorkFolder "apps.json"
$script:RepoZipUrl    = "https://github.com/DezFix/PotatoPC/archive/refs/heads/main.zip"
$script:AppsJsonUrl   = "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/apps.json"
$script:LogPath       = Join-Path $script:WorkFolder "potatopc.log"
$script:SettingsPath  = Join-Path $script:WorkFolder "settings.json"
$script:UIStatePath   = Join-Path $env:LOCALAPPDATA "PotatoPC\ui.json"

function Get-WindowsMajorVersion {
    try {
        $build = [int](Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuildNumber
        if ($build -ge 22000) { return 11 }
        return 10
    } catch { return 10 }
}
$script:WindowsMajorVersion = Get-WindowsMajorVersion
