$script:TestRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $script:TestRoot 'src\PotatoPC.Core.psm1') -Force

$script:FakeWin11 = [PSCustomObject]@{
    ComputerName = 'TEST'
    User         = 'tester'
    OS           = 'Windows 11'
    Build        = 22631
    Major        = 11
    IsLaptop     = $false
    IsDomain     = $false
    RamGB        = 16
    IsAdmin      = $true
    PSVersion    = '5.1'
}

$script:FakeWin10 = [PSCustomObject]@{
    ComputerName = 'TEST'
    User         = 'tester'
    OS           = 'Windows 10'
    Build        = 19045
    Major        = 10
    IsLaptop     = $false
    IsDomain     = $false
    RamGB        = 8
    IsAdmin      = $true
    PSVersion    = '5.1'
}

Describe 'PotatoPC v7 config' {
    BeforeAll {
        $script:Config = Import-PotatoConfig
    }

    It 'loads profiles, tweaks and apps' {
        @($script:Config.Profiles.PSObject.Properties.Name).Count | Should Be 3
        @($script:Config.Tweaks.PSObject.Properties.Name).Count | Should Be 37
        $script:Config.Apps | Should Not Be $null
    }

    It 'has all three profiles' {
        foreach ($name in @('potato', 'office', 'game')) {
            $script:Config.Profiles.PSObject.Properties[$name] | Should Not Be $null
        }
    }

    It 'references only existing action files' {
        foreach ($id in (Get-PotatoPropertyNames $script:Config.Tweaks)) {
            $t = $script:Config.Tweaks.$id
            $apply = Resolve-PotatoPath -Path $t.apply -Root $script:Config.Root
            (Test-Path -LiteralPath $apply -PathType Leaf) | Should Be $true
            if (-not [string]::IsNullOrWhiteSpace([string]$t.undoScript)) {
                $undo = Resolve-PotatoPath -Path $t.undoScript -Root $script:Config.Root
                (Test-Path -LiteralPath $undo -PathType Leaf) | Should Be $true
            }
        }
    }

    It 'keeps every profile entry pointing at a known tweak' {
        foreach ($profileName in (Get-PotatoPropertyNames $script:Config.Profiles)) {
            $profile = $script:Config.Profiles.$profileName
            foreach ($listName in @('safe', 'full')) {
                foreach ($id in @(Get-PotatoObjectProperty $profile $listName)) {
                    $script:Config.TweakMap.ContainsKey([string]$id) | Should Be $true
                }
            }
        }
    }

    It 'uses only safe risk levels in safe profile lists' {
        foreach ($profileName in @('potato', 'office', 'game')) {
            foreach ($id in @(Get-PotatoObjectProperty $script:Config.Profiles.$profileName 'safe')) {
                $script:Config.TweakMap[[string]$id].risk | Should Be 'safe'
            }
        }
    }

    It 'rejects paths outside the application root' {
        { Resolve-PotatoPath -Path '..\evil.ps1' -Root $script:Config.Root } | Should Throw
        { Resolve-PotatoPath -Path 'C:\Windows\System32\evil.ps1' -Root $script:Config.Root } | Should Throw
    }
}

Describe 'PotatoPC v7 plans' {
    BeforeAll {
        $script:Config = Import-PotatoConfig
    }

    It 'resolves the potato safe plan' {
        $plan = Resolve-PotatoPlan -Config $script:Config -ProfileName 'potato' -SystemInfo $script:FakeWin11
        @($plan.Items).Count | Should Be 17
        $plan.Full | Should Be $false
        $plan.RiskyCount | Should Be 0
    }

    It 'resolves the potato full plan' {
        $plan = Resolve-PotatoPlan -Config $script:Config -ProfileName 'potato' -Full -SystemInfo $script:FakeWin11
        @($plan.Items).Count | Should Be 23
        $plan.RiskyCount | Should Be 6
    }

    It 'resolves the office safe and full plans' {
        $safe = Resolve-PotatoPlan -Config $script:Config -ProfileName 'office' -SystemInfo $script:FakeWin11
        @($safe.Items).Count | Should Be 9
        $full = Resolve-PotatoPlan -Config $script:Config -ProfileName 'office' -Full -SystemInfo $script:FakeWin11
        @($full.Items).Count | Should Be 12
        $full.RiskyCount | Should Be 2
    }

    It 'resolves the game safe and full plans' {
        $safe = Resolve-PotatoPlan -Config $script:Config -ProfileName 'game' -SystemInfo $script:FakeWin11
        @($safe.Items).Count | Should Be 14
        $full = Resolve-PotatoPlan -Config $script:Config -ProfileName 'game' -Full -SystemInfo $script:FakeWin11
        @($full.Items).Count | Should Be 17
        $full.RiskyCount | Should Be 1
    }

    It 'skips Windows 11 only tweaks on Windows 10' {
        $plan = Resolve-PotatoPlan -Config $script:Config -ProfileName 'potato' -SystemInfo $script:FakeWin10
        @($plan.Items | Where-Object { $_.Id -eq 'remove-recall-win11' }).Count | Should Be 0
        @($plan.Warnings | Where-Object { $_ -match 'remove-recall-win11' }).Count | Should Be 1
    }

    It 'supports include and exclude' {
        $plan = Resolve-PotatoPlan -Config $script:Config -ProfileName 'office' -SystemInfo $script:FakeWin11 -Include @('fast-login') -Exclude @('clean-junk')
        @($plan.Items | Where-Object { $_.Id -eq 'fast-login' }).Count | Should Be 1
        @($plan.Items | Where-Object { $_.Id -eq 'clean-junk' }).Count | Should Be 0
    }

    It 'requires AllowIrreversible for unattended runs with irreversible actions' {
        $plan = Resolve-PotatoPlan -Config $script:Config -ProfileName 'potato' -SystemInfo $script:FakeWin11
        { Invoke-PotatoPlan -Plan $plan -Config $script:Config -Yes -NoRestorePoint -NoReboot } | Should Throw
    }
}

Describe 'PotatoPC v7 cleaning safety' {
    It 'keeps risky cleaner items behind an explicit opt-in' {
        $path = Join-Path $script:TestRoot 'actions\02 Очистка\01_clean_junk.ps1'
        $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $text | Should Match 'POTATOPC_CLEAN_SAFE'
        $text | Should Match 'POTATOPC_ALLOW_RISKY_CLEAN'
        $text | Should Match 'Confirm'
    }
}

Describe 'PotatoPC v7 executor' {
    BeforeAll {
        $script:ExecutorConfig = [PSCustomObject]@{ Root = $script:TestRoot }
    }

    It 'runs a successful action and captures output' {
        $item = [PSCustomObject]@{ Apply = 'tests\fixtures\noop.ps1'; TimeoutSec = 30 }
        $result = Invoke-PotatoAction -Item $item -Config $script:ExecutorConfig
        $result.Ok | Should Be $true
        $result.ExitCode | Should Be 0
        $result.Output | Should Match 'noop ok'
    }

    It 'reports a non-zero exit code as failure' {
        $item = [PSCustomObject]@{ Apply = 'tests\fixtures\fail.ps1'; TimeoutSec = 30 }
        $result = Invoke-PotatoAction -Item $item -Config $script:ExecutorConfig
        $result.Ok | Should Be $false
        $result.ExitCode | Should Be 7
    }
}

Describe 'PotatoPC v7 static integrity' {
    It 'parses every PowerShell file without syntax errors' {
        $errors = @()
        $files = @(Get-ChildItem -LiteralPath $script:TestRoot -Recurse -File -Filter '*.ps1' -Force |
            Where-Object { $_.FullName -notmatch '[\\/]actions[\\/]' })
        foreach ($file in $files) {
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $errors += @($parseErrors)
        }
        $errors.Count | Should Be 0
    }
}
