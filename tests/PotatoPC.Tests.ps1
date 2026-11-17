# Тесты PotatoPC v7 (Pester 5).
#   Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck
#   Invoke-Pester .\tests
# Проверяют то, что ломается чаще всего: синтаксис, шапки плагинов, кодировку,
# страницы, XAML и разбор вывода winget. Окно не открывают.

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    $script:CoreDir = Join-Path $Root 'core'
    $script:AppRoot = $Root
    . (Join-Path $CoreDir 'Config.ps1')
    . (Join-Path $CoreDir 'Runtime.ps1')
    . (Join-Path $CoreDir 'Plugins.ps1')
    . (Join-Path $CoreDir 'Winget.ps1')
    $script:AllPs1 = @(Get-ChildItem -LiteralPath $Root -Recurse -Filter '*.ps1' -File | Where-Object { $_.FullName -notmatch '[\\/](_archive_v6|\.git)[\\/]' })
    $script:Plugins = @(Get-Plugins -Force)
}

Describe 'Файлы' {
    It 'все .ps1 без синтаксических ошибок' {
        $bad = foreach ($f in $AllPs1) {
            $t = $null; $e = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$t, [ref]$e)
            if ($e.Count) { $f.Name + ': ' + $e[0].Message }
        }
        $bad | Should -BeNullOrEmpty
    }
    It 'все .ps1 в UTF-8 с BOM (иначе Windows PowerShell 5.1 ломает кириллицу)' {
        $bad = foreach ($f in $AllPs1) {
            $b = [System.IO.File]::ReadAllBytes($f.FullName)
            if ($b.Length -lt 3 -or $b[0] -ne 0xEF -or $b[1] -ne 0xBB -or $b[2] -ne 0xBF) { $f.Name }
        }
        $bad | Should -BeNullOrEmpty
    }
    It 'XAML читается как XML' {
        foreach ($x in @(Get-ChildItem -LiteralPath (Join-Path $Root 'assets') -Filter '*.xaml')) { { [xml](Get-Content -LiteralPath $x.FullName -Raw) } | Should -Not -Throw }
    }
    It 'SHA256SUMS совпадает с файлами' {
        $map = Get-ManifestMap
        $map.Count | Should -BeGreaterThan 10
        $bad = foreach ($k in $map.Keys) {
            $p = Join-Path $Root $k
            if (-not (Test-Path -LiteralPath $p) -or (Get-RepoFileHash -Path $p) -ne $map[$k]) { $k }
        }
        $bad | Should -BeNullOrEmpty
    }
}

Describe 'Плагины' {
    It 'найдены' { $Plugins.Count | Should -BeGreaterThan 20 }
    It 'у каждого есть NAME, DESC и TAGS' {
        $bad = foreach ($p in $Plugins) {
            $h = Read-PluginHeader -Path $p.Path
            if (-not $h['NAME'] -or -not $h['DESC'] -or -not $h['TAGS']) { $p.Id }
        }
        $bad | Should -BeNullOrEmpty
    }
    It 'выражения CHECK разбираются' {
        $bad = foreach ($p in @($Plugins | Where-Object Check)) { try { [void][scriptblock]::Create($p.Check) } catch { $p.Id } }
        $bad | Should -BeNullOrEmpty
    }
    It 'пресеты только potato/office/game' {
        $bad = foreach ($p in $Plugins) { foreach ($x in $p.Presets) { if ($x -notin @('potato', 'office', 'game')) { $p.Id + ': ' + $x } } }
        $bad | Should -BeNullOrEmpty
    }
    It 'каждый откат ссылается на существующий раздел' {
        $cats = @($Plugins | Where-Object { -not $_.IsUndo } | ForEach-Object { $_.CatNum } | Select-Object -Unique)
        $bad = foreach ($u in @($Plugins | Where-Object { $_.IsUndo -and $_.UndoFor.Count })) { foreach ($c in $u.UndoFor) { if ($cats -notcontains $c) { $u.Id + ' -> ' + $c } } }
        $bad | Should -BeNullOrEmpty
    }
    It 'все плагины из поставки отмечены как доверенные' {
        @($Plugins | Where-Object { -not $_.Trusted }).Id | Should -BeNullOrEmpty
    }
}

Describe 'Страницы' {
    It 'у каждой страницы есть шапка и Build-Page_<id>' {
        $bad = foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $Root 'pages') -Filter '*.ps1')) {
            $h = Read-PluginHeader -Path $f.FullName
            if (-not $h['PAGE'] -or -not $h['TITLE'] -or -not $h['ICON']) { $f.Name + ': нет шапки'; continue }
            $txt = Get-Content -LiteralPath $f.FullName -Raw
            if ($txt -notmatch ('function\s+Build-Page_' + [regex]::Escape($h['PAGE']) + '\b')) { $f.Name + ': нет Build-Page_' + $h['PAGE'] }
        }
        $bad | Should -BeNullOrEmpty
    }
}

Describe 'winget' {
    It 'разбирает таблицу upgrade с именами из нескольких слов' {
        $t = @"
Name                Id              Version    Available  Source
-------------------------------------------------------------------
Google Chrome       Google.Chrome   130.0.6723 131.0.6778 winget
7-Zip 23.01 (x64)   7zip.7zip       23.01      24.08      winget
"@
        $rows = @(ConvertFrom-WingetTable -Text $t)
        $rows.Count | Should -Be 2
        $rows[0][0] | Should -Be 'Google Chrome'
        $rows[1][1] | Should -Be '7zip.7zip'
        $rows[1][3] | Should -Be '24.08'
    }
}
