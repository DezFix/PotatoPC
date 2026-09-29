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
        $paths.Count | Should Be 9
        ($paths | Where-Object { (Split-Path $_ -Leaf) -eq '08_undo_updates.ps1' }).Count | Should Be 1
        ($paths | Where-Object { (Split-Path $_ -Leaf) -eq '09_undo_autostart.ps1' }).Count | Should Be 1
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

Describe 'PotatoPC cleaning guard' {
    BeforeAll {
        . (Join-Path $script:TestRoot 'cleaner\CleanGuard.ps1')
    }

    It 'keeps a drive root intact while normalising paths' {
        # Обрезание слэша у "C:\" превратило корень в "C:" и ломало
        # префиксное сравнение - чистка могла бы снести весь диск.
        (ConvertTo-CleanFullPath 'C:\') | Should Be 'C:\'
        (ConvertTo-CleanFullPath 'C:\Users\User\Temp\') | Should Be 'C:\Users\User\Temp'
        (ConvertTo-CleanFullPath '') | Should Be ''
    }

    It 'protects a root and everything under it, ignoring case' {
        Test-CleanPathWithin -Path 'C:\ProgramData\PotatoPC\cache\repo' -Root 'C:\ProgramData\PotatoPC' | Should Be $true
        Test-CleanPathWithin -Path 'c:\programdata\potatopc' -Root 'C:\ProgramData\PotatoPC' | Should Be $true
    }

    It 'does not let a similarly named sibling through' {
        # Префиксное сравнение без слэша считало бы PotatoPCX защищённым -
        # лишняя блокировка была бы безобидна, обратная ошибка опасна.
        Test-CleanPathWithin -Path 'C:\ProgramData\PotatoPCX' -Root 'C:\ProgramData\PotatoPC' | Should Be $false
        Test-CleanPathWithin -Path 'C:\Temp2\file.txt' -Root 'C:\Temp' | Should Be $false
        Test-CleanPathWithin -Path 'C:\Temp2' -Root 'C:\Temp' | Should Be $false
    }

    It 'refuses to judge an unparsable path as safe' {
        Test-CleanProtectedPath -Path '' | Should Be $true
    }

    It 'blocks a system folder itself but lets its cleanable subfolders through' {
        # Регрессия: системные корни лежали в точечной защите префиксом, и проверка
        # видела защищённым вообще всё - раздел очистки показывал "(нет)".
        Test-CleanProtectedPath -Path $env:SystemRoot | Should Be $true
        Test-CleanProtectedPath -Path (Join-Path $env:SystemRoot 'Temp') | Should Be $false
        Test-CleanProtectedPath -Path (Join-Path $env:LOCALAPPDATA 'Temp') | Should Be $false
    }

    It 'refuses to walk a junction, reparse point or protected path' {
        $fake = [PSCustomObject]@{ Attributes = [System.IO.FileAttributes]::ReparsePoint }
        Test-CleanReparseItem -Item $fake | Should Be $true
        $plain = [PSCustomObject]@{ Attributes = [System.IO.FileAttributes]::Directory }
        Test-CleanReparseItem -Item $plain | Should Be $false
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

    It 'ships the shared cleaning guard the cleaner script depends on' {
        # 02 Очистка/01_clean_junk.ps1 и вкладка «Очистка» подключают этот файл.
        # Без него оба отказываются чистить (см. остановку в 01_clean_junk.ps1),
        # а обход защиты вернул бы удаление папок PotatoPC.
        $guard = Join-Path $script:TestRoot 'cleaner\CleanGuard.ps1'
        if (-not (Test-Path -LiteralPath $guard -PathType Leaf)) { throw 'cleaner/CleanGuard.ps1 не найден' }
        $text = Get-Content -LiteralPath $guard -Raw -Encoding UTF8
        foreach ($fn in @('Test-CleanProtectedPath','Test-CleanPathWithin','Get-CleanGuardRoots',
                          'Measure-CleanPaths','Clear-CleanPaths','Test-CleanReparseItem')) {
            if ($text -notmatch ('function\s+' + [regex]::Escape($fn) + '\s*\{')) { throw ('Guard missing function: ' + $fn) }
        }
        # Комментарии вырезаем: упоминание опасного cmdlet'а в тексте не должно
        # считаться его использованием.
        $code = [regex]::Replace($text, '(?s)<#.*?#>', '')
        $code = ($code -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        # Удалять содержимое папок можно только через безопасные функции.
        if ($code -match '\bRemove-Item\b') { throw 'Guard deletes with Remove-Item instead of the guarded helpers' }
        if ($code -match 'Remove-Item\s') { throw 'Guard pipes to Remove-Item (bypasses protection)' }
        if ($code -match 'Get-ChildItem[^\r\n]*-Recurse') { throw 'Guard walks the tree with Get-ChildItem -Recurse (follows junctions)' }
        if ($code -match '(?i)Get-NetNeighbor[^\r\n]*\|[^\r\n]*Remove-') { throw 'Guard pipes adapters into a removal cmdlet' }
    }

    It 'keeps the cleaner header honest about protection' {
        $junk = Get-ChildItem -LiteralPath (Join-Path $script:TestRoot 'scripts') -Recurse -File -Filter '01_clean_junk.ps1' | Select-Object -First 1
        $text = Get-Content -LiteralPath $junk.FullName -Raw -Encoding UTF8
        # Скрипт обязан подключить общий движок и отказаться работать без него.
        if ($text -notmatch 'CleanGuard\.ps1') { throw 'Чистилка не подключает cleaner/CleanGuard.ps1' }
        if ($text -notmatch 'exit 1') { throw 'Чистилка не прерывается при отсутствии движка очистки' }
        foreach ($legacy in @('Test-JunkProtected','Measure-Junk','Clear-Junk','Resolve-JunkPaths')) {
            if ($text -match ('function\s+' + [regex]::Escape($legacy) + '\s*\{')) { throw ('Дубликат движка очистки: ' + $legacy) }
        }
    }

    It 'parses the WPF XAML document' {
        $xaml = [xml](Get-Content -LiteralPath (Join-Path $script:TestRoot 'assets\window.xaml') -Raw -Encoding UTF8)
        foreach ($name in @('PageProt','ProtectPanel','ScanProgressText','ScanProgressBar','ScanBtn','DefenderScanBtn','RefreshProtectBtn')) {
            if ($xaml.OuterXml -notmatch ('x:Name="' + [regex]::Escape($name) + '"')) { throw ('XAML control missing: ' + $name) }
        }
    }
}
