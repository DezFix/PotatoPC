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
        $script:YaraRuleHashes.Count | Should Be 27
        foreach ($hash in @($script:YaraRuleHashes.Values)) { $hash | Should Match '^[0-9A-F]{64}$' }
        $ruleNames = @(Get-Content -LiteralPath (Join-Path $script:TestRoot 'protect\rules.txt') -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
        (@($ruleNames | Where-Object { -not $script:YaraRuleHashes.ContainsKey($_) }).Count) | Should Be 0
        (Get-TextSha256 -Text (($ruleNames -join "`n") + "`n")) | Should Be $script:YaraRulesManifestSha256
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
        [xml](Get-Content -LiteralPath (Join-Path $script:TestRoot 'assets\window.xaml') -Raw -Encoding UTF8) | Out-Null
    }
}
