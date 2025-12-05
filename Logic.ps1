# ==========================================
# POTATO PC: LOGIC MODULE
# ==========================================

function Log($textBox, $text, $color="Black") {
    $textBox.SelectionColor = [System.Drawing.Color]::FromName($color)
    $textBox.AppendText("[$([DateTime]::Now.ToString('HH:mm:ss'))] $text`r`n")
    $textBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Fix-Winget {
    param($TempDir)
    try {
        $urls = @(
            "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx",
            "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx",
            "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        )
        $files = @("$TempDir\vclibs.appx", "$TempDir\ui.xaml.appx", "$TempDir\winget.msixbundle")
        
        for($i=0; $i -lt 3; $i++) {
            Invoke-WebRequest -Uri $urls[$i] -OutFile $files[$i] -UseBasicParsing
            Add-AppxPackage -Path $files[$i] -ErrorAction SilentlyContinue
        }
        return $true
    } catch { return $false }
}

function Core-KillService($Name, $BackupDir, $Logger) {
    $services = Get-Service $Name -ErrorAction SilentlyContinue
    if (!$services) { return }
    foreach ($s in $services) {
        if ($s.Status -ne 'Stopped' -or $s.StartType -ne 'Disabled') {
            Log $Logger "Стоп служба: $($s.Name)" "DarkMagenta"
            try {
                [PSCustomObject]@{Name=$s.Name;Start=$s.StartType;Status=$s.Status} | Export-Csv "$BackupDir\Services_Back.csv" -Append -NoType -Force
                Stop-Service $s.Name -Force -ErrorAction Stop
                Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.Name)" "Start" 4 -Type DWord -Force
            } catch { Log $Logger "Ошибка службы $($s.Name)" "Gray" }
        }
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Core-RemoveApp($Pattern, $Logger) {
    $White = @("Microsoft.WindowsStore", "Microsoft.DesktopAppInstaller", "Microsoft.Windows.Photos", "Microsoft.WindowsCalculator")
    $apps = Get-AppxPackage -AllUsers | Where-Object {$_.Name -like "*$Pattern*" -and $_.Name -notin $White}
    if ($apps) {
        foreach ($a in $apps) {
            Log $Logger "Удаление: $($a.Name)" "Red"
            try { Remove-AppxPackage -Package $a.PackageFullName -AllUsers -ErrorAction Stop } 
            catch { Log $Logger "Ошибка удаления $($a.Name)" "Gray" }
            [System.Windows.Forms.Application]::DoEvents()
        }
    }
}

function Core-RegTweak($path, $name, $val) {
    if (!(Test-Path $path)) { New-Item $path -Force | Out-Null }
    Set-ItemProperty $path $name $val -Type DWord -Force -ErrorAction SilentlyContinue
}
