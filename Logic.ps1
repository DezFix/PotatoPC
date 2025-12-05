# ==========================================
# POTATO PC: LOGIC MODULE v2.0 (FAST WINGET)
# ==========================================

function Log($textBox, $text, $color="Black") {
    $textBox.SelectionColor = [System.Drawing.Color]::FromName($color)
    $textBox.AppendText("[$([DateTime]::Now.ToString('HH:mm:ss'))] $text`r`n")
    $textBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Fix-Winget {
    param($TempDir, $Logger)
    
    Log $Logger "--- ЗАПУСК УСТАНОВКИ WINGET ---" "DarkMagenta"
    
    try {
        $wc = New-Object System.Net.WebClient
        
        # 1. VCLibs (Библиотека C++)
        $vcFile = "$TempDir\vclibs.appx"
        Log $Logger "Скачивание VCLibs (1/3)..." "Blue"
        $wc.DownloadFile("https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx", $vcFile)
        Log $Logger "Установка VCLibs..." "Gray"
        Add-AppxPackage -Path $vcFile -ErrorAction SilentlyContinue

        # 2. UI.Xaml (Графическая библиотека)
        $uiFile = "$TempDir\ui.xaml.appx"
        Log $Logger "Скачивание UI.Xaml (2/3)..." "Blue"
        # Используем стабильную версию 2.8
        $wc.DownloadFile("https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx", $uiFile)
        Log $Logger "Установка UI.Xaml..." "Gray"
        Add-AppxPackage -Path $uiFile -ErrorAction SilentlyContinue

        # 3. Сам Winget (App Installer)
        $wgFile = "$TempDir\winget.msixbundle"
        Log $Logger "Скачивание Winget (3/3)..." "Blue"
        $wc.DownloadFile("https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle", $wgFile)
        
        Log $Logger "Регистрация пакета Winget..." "DarkMagenta"
        Add-AppxPackage -Path $wgFile -ForceApplicationShutdown -ErrorAction Stop
        
        Log $Logger "УСПЕШНО: Winget установлен!" "Green"
        return $true
    } catch {
        Log $Logger "ОШИБКА установки: $($_.Exception.Message)" "Red"
        return $false
    }
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
            } catch { Log $Logger "Не удалось остановить: $($s.Name)" "Gray" }
        }
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Core-RemoveApp($Pattern, $Logger) {
    $White = @("Microsoft.WindowsStore", "Microsoft.DesktopAppInstaller", "Microsoft.Windows.Photos", "Microsoft.WindowsCalculator")
    $apps = Get-AppxPackage -AllUsers | Where-Object {$_.Name -like "*$Pattern*" -and $_.Name -notin $White}
    
    if ($apps) {
        foreach ($a in $apps) {
            Log $Logger "Удаление App: $($a.Name)" "Red"
            try { 
                Remove-AppxPackage -Package $a.PackageFullName -AllUsers -ErrorAction Stop 
            } 
            catch { 
                Log $Logger "Ошибка удаления: $($a.Name)" "Gray" 
            }
            [System.Windows.Forms.Application]::DoEvents()
        }
    }
}

function Core-RegTweak($path, $name, $val) {
    if (!(Test-Path $path)) { New-Item $path -Force | Out-Null }
    Set-ItemProperty $path $name $val -Type DWord -Force -ErrorAction SilentlyContinue
}
