function Show-DiagnosticsMenu {
    Clear-Host
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host "       WICKED RAVEN DIAGNOSTICS MODULE       " -ForegroundColor Magenta
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " 1. �������� ��������� ������ (SFC)"
    Write-Host " 2. �������������� ����������� Windows (DISM)"
    Write-Host " 3. �������� ����� (CHKDSK)"
    Write-Host " 4. �������� ����������� ������ (RAM)"
    Write-Host " 5. ����� ������� ��������"
    Write-Host " 6. ������� �������� ��������� ������"
    Write-Host " 0. �����"
    Write-Host ""
}

function Run-SFC {
    Write-Host "\n[+] ������ �������� SFC..." -ForegroundColor Yellow
    sfc /scannow
    Pause
}

function Run-DISM {
    Write-Host "\n[+] ������ DISM ��� �������������� �����������..." -ForegroundColor Yellow
    DISM /Online /Cleanup-Image /RestoreHealth
    Pause
}

function Run-CHKDSK {
    Write-Host "\n[+] �������� ����� C: � ������������ ������ ��� ��������� ��������..." -ForegroundColor Yellow
    chkdsk C: /F /R
    Write-Host "\n[!] �������� �������������. ������������� �� ��� ����������." -ForegroundColor Cyan
    Pause
}

function Run-MemoryTest {
    Write-Host "\n[+] ������������ �������� ����������� ������..." -ForegroundColor Yellow
    mdsched.exe
}

function Reset-Network {
    Write-Host "\n[+] ����� ������� ��������..." -ForegroundColor Yellow
    ipconfig /flushdns
    netsh winsock reset
    netsh int ip reset
    Write-Host "\n[!] ������. ������������� ������������." -ForegroundColor Cyan
    Pause
}

function Show-SystemErrors {
    Write-Host "\n[+] ��������� 20 ��������� ������..." -ForegroundColor Yellow
    Get-WinEvent -LogName System -MaxEvents 20 | Format-List
    Pause
}

$backToMain = $false

while (-not $backToMain) {
    Show-DiagnosticsMenu
    $choice = Read-Host "�������� ����� (0-6):"
    switch ($choice) {
        '1' { Run-SFC }
        '2' { Run-DISM }
        '3' { Run-CHKDSK }
        '4' { Run-MemoryTest }
        '5' { Reset-Network }
        '6' { Show-SystemErrors }
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
