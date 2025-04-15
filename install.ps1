function Show-InstallMenu {
    Clear-Host
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host "     WICKED RAVEN INSTALL SYSTEM    " -ForegroundColor Magenta
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " 1. ���������� �� ��������"
    Write-Host " 2. ������ ��������� ����������"
    Write-Host " 0. �����"
    Write-Host ""
}

function Check-Choco {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "[!] Chocolatey �� ������." -ForegroundColor Yellow
        $install = Read-Host "���������� Chocolatey? (y/n)"
        if ($install -eq 'y') {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
        } else {
            Write-Host "[-] Chocolatey �� ����� ����������." -ForegroundColor DarkYellow
            return $false
        }
    }
    return $true
}

function Show-PresetMenu {
    Clear-Host
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host "         ��������� �� ��������      " -ForegroundColor Magenta
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " 1. ����������� �����"
    Write-Host " 2. ���������� �����"
    Write-Host " 3. ��� ������"
    Write-Host " 0. �����"
    Write-Host ""
}

function Ask-OpenOfficeInstall {
    $global:installOpenOffice = $false
    $answer = Read-Host "[?] ���������� OpenOffice? (y/n)"
    if ($answer -eq 'y') {
        $global:installOpenOffice = $true
    } else {
        Write-Host "[-] OpenOffice ��������." -ForegroundColor DarkYellow
    }
}

function Show-LicenseAgreement($apps) {
    Write-Host "�� ����������� ���������� ��������� ����������:" -ForegroundColor Cyan
    foreach ($app in $apps) {
        Write-Host "- $app" -ForegroundColor White
    }
    $confirm = Read-Host "���������� ���������? (y/n)"
    if ($confirm -ne 'y') {
        Write-Host "[-] ��������� ��������." -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Install-StandardPreset {
    $apps = @("SumatraPDF", "7-Zip", "AnyDesk")
    if (-not (Show-LicenseAgreement $apps)) { return }
    Ask-OpenOfficeInstall
    Write-Host "[+] ��������� ������������ ������ ��������..." -ForegroundColor Yellow
    choco install -y sumatrapdf 7zip anydesk
    if ($global:installOpenOffice) {
        choco install -y openoffice
    }
    Pause
}

function Install-GamerPreset {
    $apps = @("Steam", "Discord")
    if (-not (Show-LicenseAgreement $apps)) { return }
    Write-Host "[+] ��������� ����������� ������..." -ForegroundColor Yellow
    choco install -y steam discord
    Pause
}

function Install-AllPresets {
    Install-StandardPreset
    Install-GamerPreset
}

function Show-ManualInstallList {
    Clear-Host
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host "         ������ ���������           " -ForegroundColor Magenta
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host ""

    $categories = @{
        "��������" = @(
            @{Name='Opera'; Id='opera'},
            @{Name='Google Chrome'; Id='googlechrome'},
            @{Name='Mozilla Firefox'; Id='firefox'}
        )
        "�����������" = @(
            @{Name='SumatraPDF'; Id='sumatrapdf'},
            @{Name='7-Zip'; Id='7zip'},
            @{Name='AnyDesk'; Id='anydesk'},
            @{Name='BCUninstaller'; Id='bcuninstaller'},
            @{Name='NAPS2'; Id='naps2'},
            @{Name='Warp'; Id='warp'}
        )
        "�����" = @(
            @{Name='Telegram'; Id='telegram'},
            @{Name='Viber'; Id='viber'},
            @{Name='Microsoft Teams'; Id='msteams'},
            @{Name='Zoom'; Id='zoom'}
        )
        "���� � �����" = @(
            @{Name='Steam'; Id='steam'},
            @{Name='Discord'; Id='discord'}
        )
        "����" = @(
            @{Name='OpenOffice'; Id='openoffice'}
        )
    }

    $allApps = @()
    $index = 1
    foreach ($category in $categories.Keys) {
        Write-Host "--- $category ---" -ForegroundColor Cyan
        foreach ($app in $categories[$category]) {
            $app.Index = $index
            $allApps += $app
            Write-Host "$index. $($app.Name)"
            $index++
        }
    }

    Write-Host ""
    $choice = Read-Host "������� ������ ����� �������, ��� ���������� (0 ��� ������):"

    if ($choice -eq '0') { return }

    $indexes = $choice -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[0-9]+$' }
    foreach ($i in $indexes) {
        $num = [int]$i - 1
        if ($num -ge 0 -and $num -lt $allApps.Count) {
            choco install -y $($allApps[$num].Id)
        } else {
            Write-Host "[!] �������� �����: $($i)" -ForegroundColor Red
        }
    }
    Pause
}

$backToMain = $false

while (-not $backToMain) {
    Show-InstallMenu
    $choice = Read-Host "�������� ����� (0-2):"
    switch ($choice) {
        '1' {
            if (Check-Choco) {
                $presetBack = $false
                while (-not $presetBack) {
                    Show-PresetMenu
                    $presetChoice = Read-Host "�������� ������ (0-3):"
                    switch ($presetChoice) {
                        '1' { Install-StandardPreset }
                        '2' { Install-GamerPreset }
                        '3' { Install-AllPresets }
                        '0' { $presetBack = $true }
                        default { Write-Host "�������� ����. ���������� �����." -ForegroundColor Red; Pause }
                    }
                }
            }
        }
        '2' {
            if (Check-Choco) {
                Show-ManualInstallList
            }
        }
        '0' {
            Write-Host "������� � ������� ����..." -ForegroundColor Green
            Start-Sleep -Seconds 1
            iex (irm "https://raw.githubusercontent.com/DezFix/PotatoPC/refs/heads/main/menu.ps1")
            $backToMain = $true
        }
        default {
            Write-Host "�������� ����. ���������� �����." -ForegroundColor Red
            Pause
        }
    }
}
