function Import-PotatoConfig {
    param([string]$Root = (Get-PotatoRoot))

    $configDir = Join-Path $Root 'config'
    $profilesPath = Join-Path $configDir 'profiles.json'
    $tweaksPath = Join-Path $configDir 'tweaks.json'
    $appsPath = Join-Path $configDir 'apps.json'

    $profiles = Read-PotatoJson -Path $profilesPath
    $tweaks = Read-PotatoJson -Path $tweaksPath
    $apps = if (Test-Path -LiteralPath $appsPath -PathType Leaf) { Read-PotatoJson -Path $appsPath } else { $null }

    $warnings = New-Object System.Collections.Generic.List[string]
    $tweakMap = @{}

    foreach ($id in (Get-PotatoPropertyNames $tweaks)) {
        $t = $tweaks.$id
        $name = [string](Get-PotatoObjectProperty $t 'name')
        if ([string]::IsNullOrWhiteSpace($name)) { throw ("Твик '$id' без name.") }

        $risk = [string](Get-PotatoObjectProperty $t 'risk')
        if ($risk -notin @('safe', 'caution', 'advanced')) {
            throw ("Твик '$id': неизвестный risk '$risk'.")
        }

        $apply = [string](Get-PotatoObjectProperty $t 'apply')
        if ([string]::IsNullOrWhiteSpace($apply)) { throw ("Твик '$id' без apply.") }
        $applyFull = Resolve-PotatoPath -Path $apply -Root $Root
        if (-not (Test-Path -LiteralPath $applyFull -PathType Leaf)) {
            throw ("Твик '$id': нет файла действия '$apply'.")
        }

        $undoScript = [string](Get-PotatoObjectProperty $t 'undoScript')
        if (-not [string]::IsNullOrWhiteSpace($undoScript)) {
            $undoFull = Resolve-PotatoPath -Path $undoScript -Root $Root
            if (-not (Test-Path -LiteralPath $undoFull -PathType Leaf)) {
                throw ("Твик '$id': нет файла отката '$undoScript'.")
            }
        }

        $timeout = Get-PotatoObjectProperty $t 'timeoutSec'
        if ($null -eq $timeout) { $t.timeoutSec = 300 }

        $tweakMap[$id] = $t
    }

    $used = @{}
    foreach ($profileName in (Get-PotatoPropertyNames $profiles)) {
        $profile = $profiles.$profileName
        foreach ($listName in @('safe', 'full')) {
            $list = @(Get-PotatoObjectProperty $profile $listName)
            foreach ($id in $list) {
                $key = [string]$id
                if ([string]::IsNullOrWhiteSpace($key)) { continue }
                if (-not $tweakMap.ContainsKey($key)) {
                    throw ("Профиль '$profileName' ссылается на неизвестный твик '$key'.")
                }
                if ($used.ContainsKey($key)) {
                    $warnings.Add("Твик '$key' встречается в профилях несколько раз.")
                } else {
                    $used[$key] = $true
                }
            }
        }
        if (@(Get-PotatoObjectProperty $profile 'safe').Count -eq 0) {
            $warnings.Add("Профиль '$profileName' не содержит safe-твиков.")
        }
    }

    foreach ($id in (Get-PotatoPropertyNames $tweaks)) {
        if (-not $used.ContainsKey($id)) {
            $warnings.Add("Твик '$id' не входит ни в один профиль (только вручную).")
        }
    }

    return [PSCustomObject]@{
        Root      = $Root
        ConfigDir = $configDir
        Profiles  = $profiles
        Tweaks    = $tweaks
        TweakMap  = $tweakMap
        Apps      = $apps
        Warnings  = @($warnings)
    }
}
