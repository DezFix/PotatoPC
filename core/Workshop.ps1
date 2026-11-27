# PotatoPC v7 - «Мастерская Potato»: свои установщики для того, что winget не умеет ставить правильно.
#
# Microsoft Office: ставится официальным Office Deployment Tool (setup.exe с officecdn.microsoft.com,
# подпись Microsoft проверяется). Сам Office качается с серверов Microsoft; временная папка с setup.exe
# и configuration.xml удаляется в любом случае. Ключ в комплект не входит.

function Get-WorkshopItems {
    # Карточки раздела «Мастерская Potato» на странице «Программы».
    return @(
        @{ Id = 'potato.office'; Name = 'Microsoft Office'; Site = 'office.com'; Size = '≈ 3 ГБ'
           Badge = 'с серверов Microsoft'
           Desc = 'Word, Excel, PowerPoint, Outlook. Выбор редакции (LTSC 2024 или Microsoft 365), языка и приложений. Ключ не входит.' }
    )
}

function Get-OfficeEditions {
    return [ordered]@{
        std2024 = @{ Title = 'LTSC Standard 2024'; Sub = 'Word, Excel, PowerPoint, Outlook, OneNote. Покупается один раз.'
                     Product = 'Standard2024Volume'; Channel = 'PerpetualVL2024'; Access = $false; Key = $true }
        pro2024 = @{ Title = 'LTSC Pro Plus 2024'; Sub = 'То же + Access. Покупается один раз.'
                     Product = 'ProPlus2024Volume'; Channel = 'PerpetualVL2024'; Access = $true; Key = $true }
        m365    = @{ Title = 'Microsoft 365'; Sub = 'Всё + OneDrive. По подписке, вход через аккаунт.'
                     Product = 'O365ProPlusRetail'; Channel = 'Current'; Access = $true; Key = $false }
    }
}

function Get-OfficeLanguages {
    return [ordered]@{ 'ru-ru' = 'Русский'; 'en-us' = 'English'; 'uk-ua' = 'Українська' }
}

function Get-OfficeApps {
    # Id для ExcludeApp в configuration.xml -> подпись.
    return [ordered]@{ Word = 'Word'; Excel = 'Excel'; PowerPoint = 'PowerPoint'; Outlook = 'Outlook'; OneNote = 'OneNote'; Access = 'Access' }
}

function Get-OsOfficeLanguage {
    # Язык интерфейса Windows, если он есть среди наших языков Office.
    $c = ''
    try { $c = [string](Get-UICulture).Name } catch {}
    $c = $c.ToLowerInvariant()
    if ((Get-OfficeLanguages).Contains($c)) { return $c }
    return ''
}

function Get-OfficeState {
    # Что уже стоит: Office нового типа (Click-to-Run) и старые MSI-версии.
    $r = @{ C2R = $false; Products = @(); Version = ''; Platform = ''; Msi = @() }
    try {
        $c = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction Stop
        $ids = @(([string]$c.ProductReleaseIds) -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($ids.Count) { $r.C2R = $true; $r.Products = $ids; $r.Version = [string]$c.VersionToReport; $r.Platform = [string]$c.Platform }
    } catch {}
    foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        try {
            foreach ($i in @(Get-ChildItem -LiteralPath $k -ErrorAction Stop)) {
                $p = $null; try { $p = Get-ItemProperty -LiteralPath $i.PSPath -ErrorAction Stop } catch { continue }
                $n = [string]$p.DisplayName
                # MSI-Office: ключ с GUID, имя «Microsoft Office …», не компонент и не обновление.
                if ($n -match '^Microsoft Office (Standard|Professional|Home|Small Business|Basic|Enterprise|Профессиональный|Стандартный|Для дома)' -and
                    $p.WindowsInstaller -eq 1 -and -not $p.SystemComponent -and -not $p.ParentKeyName -and $n -notmatch '(?i)click-to-run') {
                    if ($r.Msi -notcontains $n) { $r.Msi += $n }
                }
            }
        } catch {}
    }
    return $r
}

function Get-OfficeProductTitle {
    param([string]$Id)
    foreach ($e in (Get-OfficeEditions).Values) { if ($e.Product -eq $Id) { return ('Office ' + $e.Title) } }
    switch -Regex ($Id) {
        '^O365'        { return 'Microsoft 365' }
        '2021'         { return 'Office 2021' }
        '2019'         { return 'Office 2019' }
        default        { return $Id }
    }
}

function Test-OfficeKey {
    param([string]$Key)
    return ($Key -match '^[A-Z0-9]{5}(-[A-Z0-9]{5}){4}$')
}

function New-OfficeConfigXml {
    <#
      configuration.xml для setup.exe /configure.
      Opt: Edition (ключ Get-OfficeEditions), Langs (первый - язык интерфейса), Apps (что ставить), Key, Bits (64|32).
    #>
    param([hashtable]$Opt)
    $ed = (Get-OfficeEditions)[$Opt.Edition]
    if (-not $ed) { throw ('Неизвестная редакция: ' + $Opt.Edition) }
    $x = New-Object System.Text.StringBuilder
    [void]$x.AppendLine('<Configuration>')
    [void]$x.AppendLine(('  <Add OfficeClientEdition="{0}" Channel="{1}">' -f $Opt.Bits, $ed.Channel))
    $pk = if ($ed.Key -and $Opt.Key) { ' PIDKEY="' + $Opt.Key + '"' } else { '' }
    [void]$x.AppendLine(('    <Product ID="{0}"{1}>' -f $ed.Product, $pk))
    foreach ($l in @($Opt.Langs)) { [void]$x.AppendLine(('      <Language ID="{0}" />' -f $l)) }
    $skip = @('Groove', 'Lync', 'Publisher', 'Bing', 'Teams')
    if ($Opt.Edition -ne 'm365') { $skip += 'OneDrive' }
    foreach ($a in (Get-OfficeApps).Keys) { if (@($Opt.Apps) -notcontains $a) { $skip += $a } }
    foreach ($a in ($skip | Select-Object -Unique)) { [void]$x.AppendLine(('      <ExcludeApp ID="{0}" />' -f $a)) }
    [void]$x.AppendLine('    </Product>')
    [void]$x.AppendLine('  </Add>')
    if ($pk) { [void]$x.AppendLine('  <Property Name="AUTOACTIVATE" Value="1" />') }
    [void]$x.AppendLine('  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />')
    [void]$x.AppendLine('  <Updates Enabled="TRUE" />')
    [void]$x.AppendLine('  <RemoveMSI />')
    [void]$x.AppendLine('  <Display Level="Full" AcceptEULA="TRUE" />')
    [void]$x.AppendLine('</Configuration>')
    return $x.ToString()
}

function Get-OdtErrorHint {
    param([int]$Code)
    switch ($Code) {
        17002   { return 'установку прервали или закрыли окно Office' }
        17004   { return 'выбранный язык или редакция недоступны для этого канала' }
        30015   { return 'нет связи с серверами Microsoft; проверьте интернет' }
        30088   { return 'не хватает места на диске' }
        30180   { return 'не удалось скачать файлы Office; проверьте интернет' }
        default { return 'подробный журнал установщика лежит в %TEMP% (файлы <имя ПК>-*.log)' }
    }
}

function Invoke-OfficeOdt {
    # Фон. Один запуск setup.exe /configure с готовым xml. Возвращает код выхода.
    param([string]$Setup, [string]$Xml, [string]$Dir, [string]$Name)
    $cfg = Join-Path $Dir ($Name + '.xml')
    [System.IO.File]::WriteAllText($cfg, $Xml, (New-Object System.Text.UTF8Encoding($false)))
    $r = Invoke-ProcessLive -FilePath $Setup -Arguments ('/configure "' + $cfg + '"') -TimeoutSec 10800 -Quiet
    if ($r.Cancelled) { return -2 }
    if ($r.TimedOut) { return -3 }
    return [int]$r.Code
}

function Install-OfficeOdt {
    # Фон. Скачать ODT, проверить подпись, поставить Office, убрать временные файлы.
    param([hashtable]$Opt)
    $ed = (Get-OfficeEditions)[$Opt.Edition]
    $title = 'Office ' + $ed.Title
    $dir = Join-Path $WorkFolder ('office-' + [guid]::NewGuid().ToString('N'))
    $ok = $false; $why = ''
    try {
        New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        Write-Log ('Установка ' + $title + ' (' + (@($Opt.Langs) -join ', ') + ', ' + $Opt.Bits + ' бит)') 'head'
        Set-JobProgress -1 'Скачиваю установщик Office'
        $setup = Join-Path $dir 'setup.exe'
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
        $wc = New-Object System.Net.WebClient
        try { $wc.DownloadFile('https://officecdn.microsoft.com/pr/wsus/setup.exe', $setup) } finally { $wc.Dispose() }
        $sig = Get-AuthenticodeSignature -LiteralPath $setup -ErrorAction Stop
        if ($sig.Status -ne 'Valid' -or [string]$sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
            throw 'у скачанного установщика нет действительной подписи Microsoft - установка отменена'
        }
        Write-Log 'Установщик Office скачан, подпись Microsoft проверена' 'ok'
        if (Test-JobCancel) { throw 'отменено' }

        # Другой Office нового типа (365 вместо LTSC и наоборот) вместе не встанет - сначала убираем его.
        $st = Get-OfficeState
        if ($st.C2R -and ($st.Products -notcontains $ed.Product)) {
            Write-Log ('Удаляю установленный ' + ((@($st.Products) | ForEach-Object { Get-OfficeProductTitle $_ }) -join ', ') + ' - две версии Office вместе не работают') 'warn'
            Set-JobProgress -1 'Удаляю старый Office'
            $rm = "<Configuration>`r`n  <Remove All=`"TRUE`" />`r`n  <Property Name=`"FORCEAPPSHUTDOWN`" Value=`"TRUE`" />`r`n  <Display Level=`"Full`" AcceptEULA=`"TRUE`" />`r`n</Configuration>`r`n"
            $c = Invoke-OfficeOdt -Setup $setup -Xml $rm -Dir $dir -Name 'remove'
            if ($c -ne 0) { throw ('не удалось удалить старый Office (код ' + $c + ') - ' + (Get-OdtErrorHint $c)) }
            Write-Log 'Старый Office удалён' 'ok'
        }
        if (Test-JobCancel) { throw 'отменено' }

        Set-JobProgress -1 'Скачиваю и ставлю Office с серверов Microsoft (15-30 минут)'
        Write-Log 'Скачиваю и ставлю Office с серверов Microsoft - это 15-30 минут, ход установки показывает окно Office'
        $c = Invoke-OfficeOdt -Setup $setup -Xml (New-OfficeConfigXml -Opt $Opt) -Dir $dir -Name 'configuration'
        if ($c -eq -2) { throw 'отменено' }
        if ($c -eq -3) { throw 'установка заняла больше 3 часов и была остановлена' }
        if ($c -ne 0) { throw ('установщик вернул код ' + $c + ' - ' + (Get-OdtErrorHint $c)) }
        $ok = $true
        Write-Log ($title + ' установлен' + $(if ($Opt.Key) { '' } else { '. Ключ не указан - Office попросит активацию при первом запуске' })) 'ok'
        Add-History -Kind 'app' -Name ('Установка: ' + $title)
    } catch {
        $why = $_.Exception.Message
        Write-Log ('Установка ' + $title + ' не удалась: ' + $why) 'err'
        Add-History -Kind 'app' -Name ('Установка: ' + $title) -Result 'fail' -Detail $why
    } finally {
        try { if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop } } catch { Write-Log ('Не удалось удалить временную папку ' + $dir) 'warn' }
        Set-JobProgress 1 ''
    }
    return @{ Ok = $ok; Why = $why; Title = $title }
}
