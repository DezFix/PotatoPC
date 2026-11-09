[CmdletBinding()]
param(
    [ValidateSet('potato', 'office', 'game')]
    [string]$Profile,

    [switch]$Full,
    [string[]]$Include = @(),
    [string[]]$Exclude = @(),

    [switch]$List,
    [switch]$DryRun,
    [switch]$Yes,
    [switch]$NoRestorePoint,
    [switch]$NoReboot,
    [switch]$Reboot,
    [switch]$StopOnError,
    [switch]$AllowIrreversible,

    [switch]$Undo,
    [string]$Session,
    [string]$ExportPlan,

    [switch]$Version
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

Import-Module (Join-Path $PSScriptRoot 'PotatoPC.psd1') -Force

if ($Version) {
    Write-Host 'PotatoPC v7.0.0'
    exit 0
}

try {
    $config = Import-PotatoConfig

    if ($Undo) {
        $loaded = Get-PotatoSession -Id $Session
        Invoke-PotatoUndo -Session $loaded -Yes:$Yes
        exit 0
    }

    if ($List -or (-not $Profile -and -not $ExportPlan)) {
        Show-PotatoCatalog -Config $config
        if (-not $Profile) {
            Write-Host ''
            Write-Host 'Примеры:' -ForegroundColor White
            Write-Host '  .\PotatoPC.ps1 -Profile potato -DryRun'
            Write-Host '  .\PotatoPC.ps1 -Profile office -Full -Yes'
            Write-Host '  .\PotatoPC.ps1 -Profile game -DryRun -ExportPlan plan.json'
            Write-Host '  .\PotatoPC.ps1 -Undo -Session 20261109-154400-123'
            exit 0
        }
    }

    if (-not $Profile) {
        throw 'Укажи -Profile potato|office|game.'
    }

    $plan = Resolve-PotatoPlan -Config $config -ProfileName $Profile -Full:$Full -Include $Include -Exclude $Exclude

    if ($ExportPlan) {
        $fullPath = [System.IO.Path]::GetFullPath($ExportPlan)
        $json = $plan | ConvertTo-Json -Depth 12
        [System.IO.File]::WriteAllText($fullPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-PotatoLog -Message ('План сохранён: ' + $fullPath) -Level 'Ok'
        exit 0
    }

    $result = Invoke-PotatoPlan -Plan $plan -Config $config -Yes:$Yes -NoRestorePoint:$NoRestorePoint -NoReboot:$NoReboot -Reboot:$Reboot -StopOnError:$StopOnError -AllowIrreversible:$AllowIrreversible -DryRun:$DryRun
    if ($result.Status -in @('completed', 'dry-run', 'cancelled')) { exit 0 }
    exit 1
} catch {
    Write-PotatoLog -Message ('Ошибка: ' + $_.Exception.Message) -Level 'Error'
    exit 1
}
