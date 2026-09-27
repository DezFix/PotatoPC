$script:TestRoot = Split-Path -Parent $PSScriptRoot

Describe 'PotatoPC security helpers' {
    BeforeAll {
        . (Join-Path $script:TestRoot 'modules\_protect.ps1')
    }

    It 'accepts a valid YARA manifest' {
        $manifest = ConvertFrom-ProtectYaraManifest -Content "# comment`nMALW_Test.yar`nRAT_Test.yar`n"
        $manifest.Valid | Should Be $true
        @($manifest.Names).Count | Should Be 2
    }

    It 'rejects path traversal in a YARA manifest' {
        $manifest = ConvertFrom-ProtectYaraManifest -Content "..\outside.yar`n"
        $manifest.Valid | Should Be $false
    }

    It 'rejects unsafe local paths' {
        $unsafe = @('..\outside.ps1', '\\server\share\file.ps1', 'C:\temp\*.ps1', 'C:\temp\bad|name.ps1')
        foreach ($path in $unsafe) {
            $result = ConvertTo-ProtectPath -Path $path -AllowMissing
            if ($null -ne $result) { throw "Path was accepted: $path" }
        }
    }

    It 'keeps protected paths inside their root' {
        $root = Join-Path $env:TEMP 'PotatoPC-test-root'
        $child = Join-Path $root 'child'
        $sibling = Join-Path $env:TEMP 'PotatoPC-test-sibling'
        Test-ProtectPathWithin -Path $child -Root $root | Should Be $true
        Test-ProtectPathWithin -Path $sibling -Root $root | Should Be $false
    }

    It 'restricts restore targets to the built-in scan roots' {
        $tempRoot = [string]$env:TEMP
        Test-ProtectRestoreTarget -OriginalPath (Join-Path $tempRoot 'restore-test.bin') -ScanRoot $tempRoot | Should Be $true
        Test-ProtectRestoreTarget -OriginalPath 'C:\Windows\System32\restore-test.bin' -ScanRoot 'C:\Windows\System32' | Should Be $false
    }

    It 'pins every bundled YARA rule hash' {
        $script:YaraRuleHashes.Count | Should Be 30
        foreach ($hash in @($script:YaraRuleHashes.Values)) { $hash | Should Match '^[0-9A-F]{64}$' }
        $ruleNames = @(Get-Content -LiteralPath (Join-Path $script:TestRoot 'protect\rules.txt') -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
        (@($ruleNames | Where-Object { -not $script:YaraRuleHashes.ContainsKey($_) }).Count) | Should Be 0
        (Get-TextSha256 -Text (($ruleNames -join "`n") + "`n")) | Should Be $script:YaraRulesManifestSha256
    }
}

Describe 'PotatoPC scanner helpers' {
    BeforeAll {
        function Set-BgResult { param([string]$Key, $Value) $script:CapturedScanStatus = $Value }
        . (Join-Path $script:TestRoot 'modules\_protect.ps1')
        $script:SavedWorkFolder = $script:WorkFolder
        $script:SavedRepoCacheFolder = $script:RepoCacheFolder
        $script:SavedLocalRepoRoot = $script:LocalRepoRoot
    }

    It 'publishes scanner phase and progress state' {
        $script:ScanOperationId = 'test-operation'
        Set-ProtectScanStatus -Phase 'scan' -Index 3 -Total 10 -Progress 0.42 -Message 'Проверяю файл' -OperationId 'test-operation'
        $script:CapturedScanStatus.Phase | Should Be 'scan'
        $script:CapturedScanStatus.Index | Should Be 3
        $script:CapturedScanStatus.Total | Should Be 10
        [double]$script:CapturedScanStatus.Progress | Should Be 0.42
    }

    It 'excludes runtime and repository roots from scan targets' {
        $script:WorkFolder = Join-Path $env:TEMP 'PotatoPC-scanner-test'
        $script:RepoCacheFolder = Join-Path $script:WorkFolder 'cache'
        $script:LocalRepoRoot = Join-Path $env:TEMP 'PotatoPC-scanner-repo'
        $targets = @(Get-ProtectScanTargets)
        foreach ($target in $targets) {
            if (Test-ProtectPathWithin -Path $target -Root $script:WorkFolder) { throw ('Runtime root was not excluded: ' + $target) }
            if (Test-ProtectPathWithin -Path $target -Root $script:LocalRepoRoot) { throw ('Repository root was not excluded: ' + $target) }
        }
        $script:WorkFolder = $script:SavedWorkFolder
        $script:RepoCacheFolder = $script:SavedRepoCacheFolder
        $script:LocalRepoRoot = $script:SavedLocalRepoRoot
    }

    It 'returns a trusted Defender executable or an empty result' {
        $exe = [string](Get-DefenderScanExecutable)
        if (-not [string]::IsNullOrWhiteSpace($exe)) { $exe | Should Match '^[A-Za-z]:\\' }
    }

    It 'keeps Protection firewall-free and Defender read-only' {
        $protectText = Get-Content -LiteralPath (Join-Path $script:TestRoot 'modules\_protect.ps1') -Raw -Encoding UTF8
        $auditText = Get-Content -LiteralPath (Join-Path $script:TestRoot 'modules\_audit.ps1') -Raw -Encoding UTF8
        $defenderScriptPath = @(Get-ChildItem -LiteralPath $script:TestRoot -Recurse -File -Filter '03_light_defender.ps1' -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($defenderScriptPath.Count -ne 1) { throw 'Defender helper script not found' }
        $defenderScript = Get-Content -LiteralPath $defenderScriptPath[0].FullName -Raw -Encoding UTF8
        if ($protectText -match 'Get-NetFirewallProfile|Set-NetFirewallProfile') { throw 'Firewall logic remains in Protection' }
        if ($auditText -match 'Get-NetFirewallProfile|Set-NetFirewallProfile') { throw 'Firewall logic remains in audit' }
        if ($defenderScript -match 'Set-MpPreference|DisableRealtimeMonitoring|DisableArchiveScanning|DisableScanningMappedNetworkDrivesForFullScan') { throw 'Defender settings are modified' }
    }
}

Describe 'PotatoPC rollback helpers' {
    BeforeAll {
        . (Join-Path $script:TestRoot 'modules\_scripts.ps1')
        $script:ScriptsFolder = Join-Path $script:TestRoot 'scripts'
    }

    It 'finds rollback scripts in the dedicated source folder' {
        $paths = @(Get-RollbackScriptPaths)
        $paths.Count | Should Be 8
        ($paths | Where-Object { (Split-Path $_ -Leaf) -eq '08_undo_updates.ps1' }).Count | Should Be 1
    }

    It 'does not expose rollback scripts in the normal list' {
        $items = @(Load-Scripts)
        $rollbackCategory = Split-Path (Get-RollbackFolder) -Leaf
        @($items | Where-Object { $_.Category -eq $rollbackCategory }).Count | Should Be 0
    }

    It 'builds a confirmation containing the selected rollback names' {
        $path = Join-Path (Get-RollbackFolder) '08_undo_updates.ps1'
        $text = Get-RollbackConfirmationMessage -Paths @($path)
        $text.Contains('08_undo_updates.ps1') | Should Be $true
    }
}

Describe 'PotatoPC winget parser' {
    BeforeAll {
        . (Join-Path $script:TestRoot 'modules\_updates.ps1')
    }

    It 'parses a standard winget upgrade table' {
        $raw = @'
Name                 Id              Version   Available Source
-------------------------------------------------- --------------- ----------
Example App          Vendor.Example  1.0.0     2.0.0     winget
'@
        $packages = @(ConvertFrom-WingetUpgradeOutput -RawOutput $raw)
        $packages.Count | Should Be 1
        $packages[0].Id | Should Be 'Vendor.Example'
        $packages[0].NewVersion | Should Be '2.0.0'
    }
}

Describe 'PotatoPC password helper' {
    BeforeAll {
        . (Join-Path $script:TestRoot 'modules\_users.ps1')
    }

    It 'generates the requested password length' {
        $password = New-RandomPassword -Length 24
        $password.Length | Should Be 24
        $password | Should Match '^[A-Za-z0-9!@#$%^&*]+$'
    }
}

Describe 'PotatoPC static integrity' {
    It 'parses every PowerShell file without AST errors' {
        $errors = @()
        $files = @(Get-ChildItem -LiteralPath $script:TestRoot -Recurse -File -Filter '*.ps1' -Force)
        foreach ($file in $files) {
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $errors += @($parseErrors)
        }
        $errors.Count | Should Be 0
    }

    It 'parses project JSON files' {
        Get-Content -LiteralPath (Join-Path $script:TestRoot 'apps.json') -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop | Out-Null
        Get-Content -LiteralPath (Join-Path $script:TestRoot 'cleaner\rules.json') -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop | Out-Null
    }

    It 'parses the WPF XAML document' {
        $xaml = [xml](Get-Content -LiteralPath (Join-Path $script:TestRoot 'assets\window.xaml') -Raw -Encoding UTF8)
        foreach ($name in @('PageProt','ProtectPanel','ScanProgressText','ScanProgressBar','ScanBtn','DefenderScanBtn','RefreshProtectBtn')) {
            if ($xaml.OuterXml -notmatch ('x:Name="' + [regex]::Escape($name) + '"')) { throw ('XAML control missing: ' + $name) }
        }
    }
}
