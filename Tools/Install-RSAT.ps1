#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the RSAT Active Directory PowerShell module on the runner workstation.
    Required before the B3 Active Directory plugins can produce real findings.

.DESCRIPTION
    On Windows 10/11 (1809+) and Windows Server 2019+, RSAT ships as an
    optional Windows capability. This script installs it via DISM.
    Requires elevation.

.EXAMPLE
    .\Tools\Install-RSAT.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Capabilities to install. Each entry maps a capability ID to the
# PowerShell module the operator expects to find afterward. The B3 AD
# plugins need ActiveDirectory + GroupPolicy; the B4 DNS / DHCP plugins
# need DnsServer + DhcpServer.
$caps = @(
    @{ Cap='Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'; Module='ActiveDirectory' }
    @{ Cap='Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0'; Module='GroupPolicy' }
    @{ Cap='Rsat.Dns.Tools~~~~0.0.1.0';                    Module='DnsServer' }
    @{ Cap='Rsat.DHCP.Tools~~~~0.0.1.0';                   Module='DhcpServer' }
)

# Skip altogether if every module is already loadable.
$missing = @($caps | Where-Object { -not (Get-Module -ListAvailable $_.Module -ErrorAction SilentlyContinue) })
if ($missing.Count -eq 0) {
    Write-Host "[+] All RSAT modules already available: $($caps.Module -join ', ')" -ForegroundColor Green
    return
}

# Must be elevated
$me = [System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "RSAT install requires admin rights. Re-launching elevated..."
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath
    )
    return
}

foreach ($entry in $missing) {
    Write-Host "[+] Installing RSAT capability: $($entry.Cap) (module $($entry.Module))..." -ForegroundColor Cyan
    try {
        $cap = Get-WindowsCapability -Online -Name $entry.Cap -ErrorAction Stop
        if ($cap.State -eq 'Installed') {
            Write-Host "    Capability already Installed; reloading PowerShell may be required." -ForegroundColor Green
        } else {
            Add-WindowsCapability -Online -Name $entry.Cap -ErrorAction Stop | Out-Null
            Write-Host "    Install complete." -ForegroundColor Green
        }
    } catch {
        Write-Warning "Capability install failed for $($entry.Cap): $($_.Exception.Message)"
        Write-Host "    Manual fallback (Windows Server): Install-WindowsFeature RSAT-AD-PowerShell, RSAT-DNS-Server, RSAT-DHCP, GPMC" -ForegroundColor Yellow
        Write-Host "    Manual fallback (Windows 10/11) : Settings -> Apps -> Optional Features -> Add a Feature" -ForegroundColor Yellow
    }
}

# Verify
$stillMissing = @($caps | Where-Object { -not (Get-Module -ListAvailable $_.Module -ErrorAction SilentlyContinue) })
if ($stillMissing.Count -eq 0) {
    Write-Host "[+] All RSAT modules now available." -ForegroundColor Green
} else {
    Write-Warning "Capabilities installed but the following modules still not loadable: $($stillMissing.Module -join ', '). Open a NEW PowerShell window and re-test."
}
