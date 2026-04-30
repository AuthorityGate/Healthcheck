#Requires -Version 5.1
<#
.SYNOPSIS
    Install everything AuthorityGate HealthCheck needs to run, from a single
    double-click. Idempotent - re-runs are safe.

.DESCRIPTION
    Performs the following, with explicit per-step status:
      1. Verifies PowerShell version (5.1+).
      2. Enables TLS 1.2 for the current session (older PS defaults to TLS 1.0
         which PSGallery rejects).
      3. Ensures NuGet PackageProvider is present.
      4. Marks PSGallery as a Trusted PSRepository (no per-call prompts).
      5. Installs / updates VMware.PowerCLI (required for vCenter / vSAN /
         Lifecycle / Hardware plugin categories).
      6. Verifies install by importing the module and running a no-op cmdlet.

    Returns exit code 0 on success, non-zero on the first hard failure with
    an explicit error message. Designed to be auto-invoked by the GUI when
    a prerequisite is missing.

.EXAMPLE
    PS> .\Install-Prerequisites.ps1
    PS> .\Install-Prerequisites.ps1 -SkipPowerCLI    # for Horizon-only / UAG-only / NSX-only deployments
#>
[CmdletBinding()]
param(
    [switch]$SkipPowerCLI,
    [switch]$Force,
    # Default install scope is CurrentUser - NO admin required. Pass -AllUsers
    # to install machine-wide instead; that path REQUIRES the script to be
    # launched from an elevated PowerShell session.
    [switch]$AllUsers
)

$ErrorActionPreference = 'Stop'

# --- Elevation detection ----------------------------------------------------
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin  = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$scope    = if ($AllUsers) { 'AllUsers' } else { 'CurrentUser' }

Write-Host ''
Write-Host '################################################################################' -ForegroundColor Cyan
Write-Host '#  AuthorityGate HealthCheck - Install Prerequisites                                 #' -ForegroundColor Cyan
Write-Host '################################################################################' -ForegroundColor Cyan
Write-Host ''
Write-Host ("  Install scope     : {0}" -f $scope)
Write-Host ("  Running elevated  : {0}" -f $isAdmin)
Write-Host ''
if ($AllUsers -and -not $isAdmin) {
    Write-Host '  ERROR: -AllUsers requires elevation. Re-launch PowerShell "Run as Administrator" and run again.' -ForegroundColor Red
    exit 9
}
if (-not $AllUsers) {
    Write-Host '  This script does NOT require Administrator. It installs into your user' -ForegroundColor Green
    Write-Host '  profile (%USERPROFILE%\Documents\WindowsPowerShell\Modules) using' -ForegroundColor Green
    Write-Host '  -Scope CurrentUser. Pass -AllUsers from an elevated shell if you instead' -ForegroundColor Green
    Write-Host '  want a machine-wide install.' -ForegroundColor Green
    Write-Host ''
}

function Write-Step([string]$msg) {
    Write-Host ''
    Write-Host ('==== ' + $msg + ' ' + ('=' * (74 - $msg.Length))) -ForegroundColor Cyan
}
function Write-Ok([string]$msg)   { Write-Host ('  [OK]   ' + $msg) -ForegroundColor Green }
function Write-Warn2([string]$msg) { Write-Host ('  [WARN] ' + $msg) -ForegroundColor Yellow }
function Write-Bad([string]$msg)  { Write-Host ('  [FAIL] ' + $msg) -ForegroundColor Red }

# --- 1. PowerShell version --------------------------------------------------
Write-Step 'PowerShell version'
$ver = $PSVersionTable.PSVersion
Write-Host "  Detected: $($ver.ToString())"
if ($ver.Major -lt 5 -or ($ver.Major -eq 5 -and $ver.Minor -lt 1)) {
    Write-Bad 'PowerShell 5.1 or newer is required.'
    Write-Host '  Update Windows Management Framework to 5.1 (KB3191564) or install PowerShell 7.x.' -ForegroundColor Yellow
    exit 2
}
Write-Ok "PowerShell $($ver) is sufficient."

# --- 2. TLS 1.2 for the session --------------------------------------------
Write-Step 'TLS 1.2'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Write-Ok 'TLS 1.2 enabled for this session.'
} catch {
    Write-Bad "Could not enable TLS 1.2: $($_.Exception.Message)"
    exit 3
}

# --- 3. NuGet PackageProvider ----------------------------------------------
Write-Step 'NuGet package provider'
$nuget = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue |
    Where-Object { $_.Version -ge [version]'2.8.5.201' } | Select-Object -First 1
if (-not $nuget) {
    Write-Host "  Installing NuGet PackageProvider (>= 2.8.5.201) - scope $scope..."
    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope $scope -Force -Confirm:$false | Out-Null
        Write-Ok 'NuGet provider installed.'
    } catch {
        Write-Bad "NuGet provider install failed: $($_.Exception.Message)"
        Write-Host '  Most common cause: no internet access from this machine to www.powershellgallery.com.' -ForegroundColor Yellow
        Write-Host '  Workaround: download the .nupkg manually and use Save-Module on a connected machine, then copy.' -ForegroundColor Yellow
        exit 4
    }
} else {
    Write-Ok "NuGet provider $($nuget.Version) already present."
}

# --- 4. PSGallery trust -----------------------------------------------------
Write-Step 'PSGallery repository'
$gal = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
if (-not $gal) {
    Write-Bad 'PSGallery repository is missing. This is unusual; rerun PowerShell as Administrator and try again.'
    exit 5
}
if ($gal.InstallationPolicy -ne 'Trusted') {
    Write-Host '  Marking PSGallery as Trusted (avoids per-install prompts)...'
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
}
Write-Ok 'PSGallery present and trusted.'

# --- 5. VMware.PowerCLI -----------------------------------------------------
if (-not $SkipPowerCLI) {
    Write-Step 'VMware.PowerCLI'
    $existing = Get-Module -ListAvailable -Name VMware.PowerCLI -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending | Select-Object -First 1
    if ($existing -and -not $Force) {
        Write-Ok "VMware.PowerCLI $($existing.Version) already installed."
    } else {
        Write-Host "  Installing VMware.PowerCLI from PSGallery - scope $scope (~150 MB; 5-10 minutes)..."
        try {
            Install-Module -Name VMware.PowerCLI -Scope $scope -Force -AllowClobber -SkipPublisherCheck -Confirm:$false
            $now = Get-Module -ListAvailable -Name VMware.PowerCLI |
                Sort-Object Version -Descending | Select-Object -First 1
            if ($now) {
                Write-Ok "VMware.PowerCLI $($now.Version) installed."
            } else {
                Write-Bad 'Install reported success but VMware.PowerCLI is not available in $env:PSModulePath.'
                exit 6
            }
        } catch {
            Write-Bad "VMware.PowerCLI install failed: $($_.Exception.Message)"
            Write-Host ''
            Write-Host '  Common causes + remediations:' -ForegroundColor Yellow
            Write-Host '    1. No internet to www.powershellgallery.com / api.nuget.org.' -ForegroundColor Yellow
            Write-Host '       Test:  Test-NetConnection www.powershellgallery.com -Port 443' -ForegroundColor Yellow
            Write-Host '    2. Corporate proxy intercepts TLS.' -ForegroundColor Yellow
            Write-Host '       Configure: $env:HTTPS_PROXY = http://proxy.corp.local:8080 ; re-run.' -ForegroundColor Yellow
            Write-Host '    3. Old PowerShellGet conflicts with new VMware.PowerCLI signing.' -ForegroundColor Yellow
            Write-Host '       Fix: Install-Module PowerShellGet -Force -AllowClobber ; close + reopen PS ; re-run.' -ForegroundColor Yellow
            Write-Host '    4. Disk full or AV blocking writes to %USERPROFILE%\Documents\WindowsPowerShell\Modules.' -ForegroundColor Yellow
            exit 7
        }
    }

    # Optional: relax cert validation default for lab use; user can override per-session.
    try {
        Import-Module VMware.VimAutomation.Core -ErrorAction SilentlyContinue
        Set-PowerCLIConfiguration -InvalidCertificateAction Prompt -Confirm:$false -Scope User -ErrorAction SilentlyContinue | Out-Null
        Write-Ok 'PowerCLI imports cleanly.'
    } catch {
        Write-Warn2 "PowerCLI installed but Import-Module reported: $($_.Exception.Message)"
    }
} else {
    Write-Step 'VMware.PowerCLI'
    Write-Warn2 'Skipped (-SkipPowerCLI). vCenter / vSAN / Lifecycle / Hardware plugin categories will not run.'
}

# --- 5a. VMware.Hv.Helper (Omnissa PowerCLI Horizon snap-in) ---------------
# Wraps Horizon's SOAP/Web Services API. Unlike REST (which has gaps on
# Horizon 8.6 - /v1/monitor/connection-servers returns id+jwt only and
# /v1/entitlements 404s on many builds), the SOAP layer returns full pod
# inventory + per-pool entitlements. v0.94.0 uses Hv.Helper as a first-class
# fallback when REST returns stub data.
if (-not $SkipPowerCLI) {
    Write-Step 'VMware.Hv.Helper (Omnissa PowerCLI Horizon snap-in)'
    $hv = Get-Module -ListAvailable -Name VMware.Hv.Helper -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending | Select-Object -First 1
    if ($hv -and -not $Force) {
        Write-Ok "VMware.Hv.Helper $($hv.Version) already installed."
    } else {
        Write-Host "  Installing VMware.Hv.Helper from PSGallery - scope $scope (~5 MB; ~30 sec)..."
        try {
            Install-Module -Name VMware.Hv.Helper -Scope $scope -Force -AllowClobber -SkipPublisherCheck -Confirm:$false
            $now = Get-Module -ListAvailable -Name VMware.Hv.Helper |
                Sort-Object Version -Descending | Select-Object -First 1
            if ($now) {
                Write-Ok "VMware.Hv.Helper $($now.Version) installed."
            } else {
                Write-Warn2 'Install reported success but VMware.Hv.Helper is not in $env:PSModulePath. SOAP fallback will be unavailable; REST-only pods will still work.'
            }
        } catch {
            # Non-fatal: REST-only mode still functions, just with the data
            # gaps on Horizon 8.6 that motivated this fallback.
            Write-Warn2 "VMware.Hv.Helper install failed (REST-only fallback only): $($_.Exception.Message)"
        }
    }
}

# --- 5b. RSAT modules (DnsServer / DhcpServer / ActiveDirectory / GPMC) -----
# The B3 AD + B4 DNS/DHCP plugins call cmdlets from these RSAT modules. RSAT
# is NOT a PSGallery module - it is a Windows Optional Feature. Best-effort
# install requires elevation; we don't fail the whole bootstrap if RSAT
# can't be added (the operator may not be running as admin, or may be on
# a Server core build). Each module installs independently so a missing
# DnsServer doesn't block ActiveDirectory.
Write-Step 'RSAT (ActiveDirectory / GroupPolicy / DnsServer / DhcpServer)'
$rsatTargets = @(
    @{ Cap='Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'; Module='ActiveDirectory' }
    @{ Cap='Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0'; Module='GroupPolicy' }
    @{ Cap='Rsat.Dns.Tools~~~~0.0.1.0';                    Module='DnsServer' }
    @{ Cap='Rsat.DHCP.Tools~~~~0.0.1.0';                   Module='DhcpServer' }
)
$rsatMissing = @($rsatTargets | Where-Object { -not (Get-Module -ListAvailable $_.Module -ErrorAction SilentlyContinue) })
if ($rsatMissing.Count -eq 0) {
    Write-Ok "All RSAT modules already loadable: $(($rsatTargets.Module) -join ', ')"
} elseif (-not $isAdmin) {
    Write-Warn2 "RSAT install requires elevation; running as standard user. Missing: $(($rsatMissing.Module) -join ', ')"
    Write-Host '  To install: right-click PowerShell -> Run as Administrator -> .\Tools\Install-RSAT.ps1' -ForegroundColor Yellow
    Write-Host '  Server alternative: Install-WindowsFeature RSAT-AD-PowerShell,RSAT-DNS-Server,RSAT-DHCP,GPMC' -ForegroundColor Yellow
} else {
    foreach ($r in $rsatMissing) {
        try {
            $cap = Get-WindowsCapability -Online -Name $r.Cap -ErrorAction Stop
            if ($cap.State -eq 'Installed') {
                Write-Ok "$($r.Module) already Installed at OS level (reload PowerShell to make it loadable)."
            } else {
                Add-WindowsCapability -Online -Name $r.Cap -ErrorAction Stop | Out-Null
                Write-Ok "$($r.Module) installed via $($r.Cap)."
            }
        } catch {
            Write-Warn2 "$($r.Module) install failed: $($_.Exception.Message)"
        }
    }
    # Check what is now loadable
    $stillMissing = @($rsatTargets | Where-Object { -not (Get-Module -ListAvailable $_.Module -ErrorAction SilentlyContinue) })
    if ($stillMissing.Count -gt 0) {
        Write-Warn2 "Open a NEW PowerShell session for these to become loadable: $(($stillMissing.Module) -join ', ')"
    }
}

# --- 6. .NET / Word availability (informational) ----------------------------
Write-Step 'Word automation availability (optional)'
$wordKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
$word = Get-ItemProperty -Path "$wordKey\*" -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like 'Microsoft Office*' -or $_.DisplayName -like 'Microsoft 365*' } | Select-Object -First 1
if ($word) {
    Write-Ok "Office detected ($($word.DisplayName)) - Word .docx output will work."
} else {
    Write-Warn2 'Microsoft Word not detected in the registry. HTML reports still work; Word .docx output will fail until Word is installed.'
}

Write-Host ''
Write-Host '==== Prerequisites: SUCCESS ====================================================' -ForegroundColor Green
Write-Host ''
exit 0
