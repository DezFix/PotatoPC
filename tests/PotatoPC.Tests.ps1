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
    . (Join-Path $CoreDir 'Workshop.ps1')
    . (Join-Path $CoreDir 'Profiles.ps1')
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

Describe 'Файлы пользователей на другом диске' {
    It 'системный диск, флешка, сеть и не-NTFS не подходят' {
        (Get-DriveVerdict @{ IsSystem = $true; DriveType = 3; FileSystem = 'NTFS' }).Suitable | Should -BeFalse
        (Get-DriveVerdict @{ DriveType = 2; FileSystem = 'NTFS' }).Suitable | Should -BeFalse
        (Get-DriveVerdict @{ DriveType = 3; FileSystem = 'NTFS'; BusType = 'USB' }).Suitable | Should -BeFalse
        (Get-DriveVerdict @{ DriveType = 4; FileSystem = 'NTFS' }).Suitable | Should -BeFalse
        (Get-DriveVerdict @{ DriveType = 3; FileSystem = 'exFAT' }).Suitable | Should -BeFalse
        (Get-DriveVerdict @{ DriveType = 3; FileSystem = 'NTFS'; BusType = 'SATA' }).Suitable | Should -BeTrue
    }
    It 'лучший диск: отдельный физический важнее свободного места, с запасом 2 ГБ' {
        $d = @(
            @{ Letter = 'D'; Suitable = $true; SameDiskAsSystem = $true; Free = 400GB }
            @{ Letter = 'E'; Suitable = $true; SameDiskAsSystem = $false; Free = 200GB }
            @{ Letter = 'F'; Suitable = $true; SameDiskAsSystem = $false; Free = 100GB }
            @{ Letter = 'G'; Suitable = $false; Free = 900GB }
        )
        Select-BestProfileDrive -Drives $d -NeedBytes 10GB | Should -Be 'E'
        Select-BestProfileDrive -Drives $d -NeedBytes 199GB | Should -Be 'D'
        Select-BestProfileDrive -Drives $d -NeedBytes 1000GB | Should -BeNullOrEmpty
    }
    It 'свободное имя: «Имя.2» для папки и пометка для файла' {
        $taken = @('C:\Users\Bob', 'C:\Users\Bob.2', 'C:\x\a.txt', 'C:\x\a (со старой Windows).txt')
        $ex = { param($p) $taken -contains $p }
        Get-UniquePath -Path 'C:\Users\Bob' -Exists $ex | Should -Be 'C:\Users\Bob.3'
        Get-UniquePath -Path 'C:\Users\Ann' -Exists $ex | Should -Be 'C:\Users\Ann'
        Get-UniquePath -Path 'C:\x\a.txt' -Suffix '(со старой Windows)' -Exists $ex | Should -Be 'C:\x\a (со старой Windows 2).txt'
    }
    It 'закладки Chromium считаются и выгружаются в HTML с экранированием' {
        $f = Join-Path $TestDrive 'Bookmarks'
        [System.IO.File]::WriteAllText($f, '{"roots":{"bookmark_bar":{"type":"folder","children":[{"type":"url","name":"A & B","url":"https://a.com/?x=1&y=2","date_added":"13300000000000000"},{"type":"folder","name":"F","children":[{"type":"url","name":"<c>","url":"https://c"}]}]},"other":{"type":"folder","children":[]}}}')
        $o = Read-JsonFast $f
        Get-BookmarkCount $o | Should -Be 2
        $html = ConvertTo-BookmarksHtml -Data $o -Title 'T'
        $html | Should -Match 'NETSCAPE-Bookmark-file-1'
        $html | Should -Match ([regex]::Escape('HREF="https://a.com/?x=1&amp;y=2" ADD_DATE="1655526400">A &amp; B</A>'))
        $html | Should -Match '&lt;c&gt;'
    }
    It 'скрипт переноса при загрузке самодостаточный и разбирается' {
        $txt = New-ProfileMoveBootScript -Sid 'S-1-5-21-1-2-3-1001' -Drive 'D' -Dir $TestDrive
        $t = $null; $e = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($txt, [ref]$t, [ref]$e)
        $e.Count | Should -Be 0
        foreach ($fn in @('Move-UserProfile', 'Invoke-ProcessLive', 'Copy-ProfileJunctions', 'Add-History')) { $txt | Should -Match ('function ' + $fn + ' \{') }
    }
    It 'движок не опирается на переменные $script: (в фоновом потоке их нет)' {
        $txt = Get-Content -LiteralPath (Join-Path $CoreDir 'Profiles.ps1') -Raw -Encoding UTF8
        $txt | Should -Not -Match '\$script:'
    }
}
