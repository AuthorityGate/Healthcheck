#Requires -Version 5.1
<#
.SYNOPSIS
    Print the machine fingerprint for the current Windows machine.

.DESCRIPTION
    The HealthCheckPS1 license is bound to a stable per-machine fingerprint
    derived from HKLM:\SOFTWARE\Microsoft\Cryptography\MachineGuid (SHA-256,
    namespace-salted). Use this script when:

      - The machine where you want HealthCheckPS1 to run cannot reach the
        internet (air-gapped customer environment), so the in-tool wizard
        cannot auto-open the browser to license.authoritygate.com.

      - You need to populate the Manual License Request form
        (https://license.authoritygate.com/request) by hand from a different
        workstation.

    Run this on the offline scanner machine, copy the printed fingerprint,
    paste it into the form's "Machine fingerprint" field, submit. The license
    JWT will be emailed to you. Carry it back to the offline machine and
    paste it into the License tab in HealthCheckPS1.

.EXAMPLE
    .\Show-MachineFingerprint.ps1
#>

[CmdletBinding()]
param()

$here = Split-Path -Parent $PSCommandPath
Import-Module (Join-Path $here '..\Modules\Licensing.psm1') -Force

$detail = Get-AGMachineFingerprint -ShowSource
$fp = $detail.Fingerprint
$mc = $env:COMPUTERNAME

Write-Host ""
Write-Host "  Machine fingerprint" -ForegroundColor Cyan
Write-Host "  -------------------" -ForegroundColor Cyan
Write-Host "  $fp" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Hostname:           $mc" -ForegroundColor DarkGray
Write-Host "  Source:             $($detail.Source)$(if ($detail.FromCache) { ' (cached)' })" -ForegroundColor DarkGray
Write-Host "  Storage path:       $(Get-AGLicenseStorePath)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Submit at:          https://license.authoritygate.com/request" -ForegroundColor White
Write-Host ""
Write-Host "  Or use the URL below to pre-fill the form (replace YOUR_EMAIL):"
Write-Host ""
Write-Host "    https://license.authoritygate.com/request?email=YOUR_EMAIL&fp=$fp&hostname=$([System.Uri]::EscapeDataString($mc))" -ForegroundColor DarkCyan
Write-Host ""
