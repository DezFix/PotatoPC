$script:WorkFolder    = Join-Path $env:TEMP "PotatoPC"
$script:RepoCacheFolder = if ($env:ProgramData) { Join-Path $env:ProgramData 'PotatoPC\cache' } else { Join-Path $script:WorkFolder 'cache' }
$script:CleanRulesPath = ""
try {
    $rootHint = $null
    try { $rootHint = $script:ModuleDir } catch {}
    if ($rootHint) {
        $cand = Join-Path (Split-Path $rootHint -Parent) "cleaner\rules.json"
        if (Test-Path $cand) { $script:CleanRulesPath = $cand }
    }
} catch {}
$script:LocalRepoRoot = ''
try { if ($script:ModuleDir) { $script:LocalRepoRoot = Split-Path $script:ModuleDir -Parent } } catch {}
$script:ScriptsFolder = Join-Path $script:WorkFolder "scripts"
$script:AppsJsonPath  = Join-Path $script:WorkFolder "apps.json"
try {
    $localScripts = Join-Path $script:LocalRepoRoot 'scripts'
    $localApps = Join-Path $script:LocalRepoRoot 'apps.json'
    if ((Test-Path -LiteralPath $localScripts -PathType Container) -and (Test-Path -LiteralPath $localApps -PathType Leaf)) {
        $script:ScriptsFolder = $localScripts
        $script:AppsJsonPath = $localApps
    }
} catch {}
$script:RepoZipUrl    = if ($env:POTATOPC_REPO_ZIP_URL) { [string]$env:POTATOPC_REPO_ZIP_URL } else { "https://github.com/DezFix/PotatoPC/archive/refs/heads/main.zip" }
$script:RepoZipSha256 = [string]$env:POTATOPC_REPO_SHA256
$script:AppsJsonUrl   = "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/apps.json"
$script:ProtectRulesManifestUrl = if ($env:POTATOPC_PROTECT_MANIFEST_URL) { [string]$env:POTATOPC_PROTECT_MANIFEST_URL } else { 'https://raw.githubusercontent.com/DezFix/PotatoPC/b5b26c3/protect/rules.txt' }
$script:ProtectRulesBaseUrl = if ($env:POTATOPC_PROTECT_BASE_URL) { [string]$env:POTATOPC_PROTECT_BASE_URL } else { 'https://raw.githubusercontent.com/Yara-Rules/rules/0f93570194a80d2f2032869055808b0ddcdfb360/malware' }
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
# Метка сборки: bump вручную при релизных правках, видна в первой строке лога.
# Позволяет отличить запущенную версию (локально/по ссылке/кэш) без гаданий.
$script:BuildTag = '2026-09-14-r5'
