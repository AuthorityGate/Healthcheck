#Requires -Version 5.1
<#
.SYNOPSIS
    Run the full gold-image deep-scan probe against a single target and
    render the findings the same way the plugin does. Bypasses vCenter
    discovery for quick single-target validation.

.PARAMETER Target
    IP address or FQDN of the gold image VM (must have WinRM reachable).

.PARAMETER Credential
    PSCredential. Use .\Administrator form for non-domain images.

.PARAMETER ProfileName
    OR: name of an AuthorityGate credential profile.

.PARAMETER Role
    GoldDesktop | RdshMaster | AppVolumesPackaging  (default: GoldDesktop)
#>
[CmdletBinding(DefaultParameterSetName='Direct')]
param(
    [Parameter(Mandatory)][string]$Target,
    [Parameter(ParameterSetName='Direct')][pscredential]$Credential,
    [Parameter(ParameterSetName='Profile')][string]$ProfileName,
    [ValidateSet('GoldDesktop','RdshMaster','AppVolumesPackaging')][string]$Role = 'GoldDesktop'
)

$ErrorActionPreference = 'Continue'

if ($ProfileName) {
    Import-Module (Join-Path $PSScriptRoot '..\Modules\CredentialProfiles.psm1') -Force
    $Credential = Get-AGCredentialAsPSCredential -Name $ProfileName
} elseif (-not $Credential) {
    $Credential = Get-Credential -Message "Credential for $Target"
    if (-not $Credential) { return }
}

# ------ The exact in-guest probe scriptblock used by GuestImageScan.psm1 ------
$probe = {
    $r = @{}
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $r.OsCaption     = $os.Caption
        $r.OsVersion     = $os.Version
        $r.OsBuildNumber = $os.BuildNumber
        $r.OsLastBoot    = $os.LastBootUpTime
        $r.OsArchitecture = $os.OSArchitecture
    } catch { $r.OsError = $_.Exception.Message }
    try {
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $r.DisplayVersion = $cv.DisplayVersion
        $r.UBR            = $cv.UBR
        $r.ProductName    = $cv.ProductName
        $r.EditionID      = $cv.EditionID
    } catch { }
    try {
        $hf = Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending | Select-Object -First 1
        if ($hf) { $r.LastHotfixId = $hf.HotFixID; $r.LastHotfixInstalledOn = $hf.InstalledOn }
    } catch { }
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $r.PartOfDomain = [bool]$cs.PartOfDomain
        $r.Domain       = $cs.Domain
        $r.HostName     = $cs.Name
    } catch { }
    $installed = @()
    foreach ($p in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                   'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        try {
            $installed += Get-ItemProperty $p -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName } |
                Select-Object DisplayName, DisplayVersion, Publisher
        } catch { }
    }
    $r.InstalledSoftwareCount = @($installed).Count
    $r.InstalledSoftwareSample = @($installed | Sort-Object DisplayName | Select-Object -First 15)
    try {
        $r.ServicesRunning = (Get-Service -ErrorAction Stop | Where-Object Status -eq 'Running').Count
    } catch { }
    try {
        $mp = Get-MpPreference -ErrorAction Stop
        $r.DefenderRealtime = -not $mp.DisableRealtimeMonitoring
        $r.DefenderExclusionPath      = @($mp.ExclusionPath)
        $r.DefenderExclusionProcess   = @($mp.ExclusionProcess)
        $r.DefenderExclusionExtension = @($mp.ExclusionExtension)
    } catch { }
    try {
        $fsl = Get-ItemProperty 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction Stop
        $r.FSLogixEnabled       = [bool]$fsl.Enabled
        $r.FSLogixVHDLocations  = @($fsl.VHDLocations)
    } catch { }
    foreach ($k in 'HKLM:\SOFTWARE\VMware, Inc.\VMware VDM\Agent','HKLM:\SOFTWARE\Omnissa\VDM\Agent') {
        try {
            $reg = Get-ItemProperty $k -ErrorAction Stop
            if ($reg.ProductVersion) { $r.HorizonAgentVersion = $reg.ProductVersion }
        } catch { }
    }
    try { $r.DEMVersion = (Get-ItemProperty 'HKLM:\SOFTWARE\VMware, Inc.\Dynamic Environment Manager' -ErrorAction Stop).Version } catch { }
    try {
        $av = Get-ItemProperty 'HKLM:\SOFTWARE\CloudVolumes\Agent' -ErrorAction Stop
        $r.AppVolumesAgentVersion = $av.Version
        $r.AppVolumesAgentMode    = $av.AgentMode
    } catch { }
    try {
        $tools = Get-ItemProperty 'HKLM:\SOFTWARE\VMware, Inc.\VMware Tools' -ErrorAction Stop
        if ($tools.ProductVersion) {
            $r.VMwareToolsVersion = $tools.ProductVersion
        } elseif ($tools.InstallPath) {
            $exe = Join-Path $tools.InstallPath 'vmtoolsd.exe'
            if (Test-Path $exe) { $r.VMwareToolsVersion = (Get-Item $exe).VersionInfo.ProductVersion }
        }
    } catch { }
    try {
        $bl = Get-CimInstance -Namespace 'Root\CIMV2\Security\MicrosoftVolumeEncryption' `
                              -ClassName Win32_EncryptableVolume -ErrorAction Stop |
              Where-Object { $_.DriveLetter -eq 'C:' }
        if ($bl) { $r.BitLockerProtectionStatus = $bl.ProtectionStatus }
    } catch { }
    try { $r.RdpDenyTSConnections = [bool](Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -ErrorAction Stop).fDenyTSConnections } catch { }
    try {
        $sp = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform' -ErrorAction SilentlyContinue
        if ($sp) { $r.SkipRearm = $sp.SkipRearm }
    } catch { }
    return $r
}

Write-Host ""
Write-Host "=== Deep-scan probe against $Target ===" -ForegroundColor Cyan
Write-Host "Role:       $Role"
Write-Host "Credential: $($Credential.UserName)"
Write-Host ""

try {
    $session = New-PSSession -ComputerName $Target -Credential $Credential -ErrorAction Stop
    Write-Host "[+] PSSession opened." -ForegroundColor Green
    # Prefer the canonical probe scriptblock from the module (single source
    # of truth). The locally-defined $probe is a slim fallback if the module
    # is not present (e.g., this script copied to a triage workstation).
    $modPath = Join-Path $PSScriptRoot '..\Modules\GuestImageScan.psm1'
    if (Test-Path $modPath) {
        $modContent = Get-Content $modPath -Raw
        if ($modContent -match '\$Script:RemoteSb\s*=\s*\{') {
            Import-Module $modPath -Force
            $modScope = Get-Module GuestImageScan
            $canonicalProbe = & $modScope { $Script:RemoteSb }
            if ($canonicalProbe) {
                $probe = $canonicalProbe
                Write-Host "[+] Using canonical probe from GuestImageScan.psm1." -ForegroundColor DarkGray
            }
        }
    }
    $g = Invoke-Command -Session $session -ScriptBlock $probe
    Remove-PSSession $session
    Write-Host "[+] In-guest probe completed." -ForegroundColor Green
} catch {
    Write-Host "[!] Probe failed: $($_.Exception.Message)" -ForegroundColor Red
    return
}

# ------ Rule evaluation ------
$findings = New-Object System.Collections.ArrayList
function _add { param($sev, $rule, $detail, $fix)
    [void]$findings.Add([pscustomobject]@{ Severity=$sev; Rule=$rule; Detail=$detail; Fix=$fix })
}

# OS patch level
if ($g.LastHotfixInstalledOn) {
    $age = ((Get-Date) - [datetime]$g.LastHotfixInstalledOn).TotalDays
    if ($age -gt 60) { _add 'P2' 'Master patch lag' "Last hotfix installed $([int]$age) days ago ($($g.LastHotfixId))." 'Run Windows Update on the master, sysprep, re-snapshot, recompose.' }
}

# BitLocker on Win11 master
if ($Role -eq 'GoldDesktop' -and $g.BitLockerProtectionStatus -eq 1) {
    _add 'P1' 'BitLocker enabled on master volume' 'Sealed BitLocker keys do not fork to clones - clones boot to BitLocker recovery prompt.' "manage-bde -off C:; sysprep generalize; re-snapshot; configure GPO to prevent BitLocker auto-enable on clones."
}

# FSLogix
if ($Role -eq 'GoldDesktop' -and -not $g.FSLogixEnabled) {
    _add 'P3' 'FSLogix not configured on master' 'Profile container approach is the supported pattern for non-persistent VDI.' 'Install FSLogix Apps + configure HKLM:\SOFTWARE\FSLogix\Profiles.'
}

# Defender + FSLogix exclusions
if ($Role -eq 'GoldDesktop' -and $g.DefenderRealtime -and $g.FSLogixEnabled) {
    $hasFsl = ($g.DefenderExclusionPath | Where-Object { $_ -match 'fslogix|profile' }).Count -gt 0
    if (-not $hasFsl) { _add 'P2' 'Defender missing FSLogix exclusions' 'Defender real-time scan with no FSLogix exclusion = high CPU + slow profile mount.' 'Add path + process exclusions per Microsoft FSLogix AV guidance.' }
}

# Horizon Agent
if ($Role -in 'GoldDesktop','RdshMaster' -and -not $g.HorizonAgentVersion) {
    _add 'P1' 'Horizon Agent not installed' 'Master image needs Horizon Agent for clones to broker correctly.' 'Install the Horizon Agent matching your Connection Server version.'
}

# AppVolumes Agent mode
if ($Role -in 'GoldDesktop','RdshMaster' -and $g.AppVolumesAgentMode -eq 'ProvisioningMode') {
    _add 'P1' 'App Volumes Agent in provisioning mode on a runtime master' "AgentMode = ProvisioningMode; runtime/end-user VMs must be RuntimeMode." 'Reinstall Agent without provisioning flag.'
}
if ($Role -eq 'AppVolumesPackaging' -and $g.AppVolumesAgentMode -ne 'ProvisioningMode') {
    _add 'P1' 'AV Agent not in provisioning mode' "AgentMode = $($g.AppVolumesAgentMode); must be ProvisioningMode for capture VMs." 'Reinstall Agent with provisioning flag.'
}

# RDP per role
if ($Role -eq 'GoldDesktop' -and $g.RdpDenyTSConnections -eq $false) {
    _add 'P3' 'RDP enabled on desktop gold image' 'Desktop master images typically should not accept RDP - users connect via Blast/PCoIP.' 'Disable RDP via System Properties or GPO.'
}
if ($Role -eq 'RdshMaster' -and $g.RdpDenyTSConnections -eq $true) {
    _add 'P1' 'RDP disabled on RDSH master' 'RDSH role requires RDP enabled - sessions broker via RDP.' 'Enable RDP and the RDS role/feature.'
}

# Tools
if (-not $g.VMwareToolsVersion) {
    _add 'P2' 'VMware Tools version unreadable' 'Could not read VMware Tools version from registry or vmtoolsd.exe - Tools may be missing or broken.' 'Reinstall VMware Tools on the master.'
}

# Render
Write-Host ""
Write-Host "=== Probe data ===" -ForegroundColor Cyan
$display = [ordered]@{
    'Hostname'          = $g.HostName
    'OS'                = $g.OsCaption
    'OS Build / UBR'    = "$($g.OsBuildNumber).$($g.UBR)  ($($g.DisplayVersion))"
    'Domain joined'     = $g.PartOfDomain
    'Domain / Workgroup'= $g.Domain
    'Last boot'         = $g.OsLastBoot
    'Last hotfix'       = "$($g.LastHotfixId) on $($g.LastHotfixInstalledOn)"
    'VMware Tools'      = $g.VMwareToolsVersion
    'Horizon Agent'     = if ($g.HorizonAgentVersion) { $g.HorizonAgentVersion } else { '(not installed)' }
    'DEM Agent'         = if ($g.DEMVersion) { $g.DEMVersion } else { '(not installed)' }
    'AppVolumes Agent'  = if ($g.AppVolumesAgentVersion) { "$($g.AppVolumesAgentVersion) [$($g.AppVolumesAgentMode)]" } else { '(not installed)' }
    'FSLogix enabled'   = $g.FSLogixEnabled
    'FSLogix locations' = ($g.FSLogixVHDLocations -join '; ')
    'Defender real-time'= $g.DefenderRealtime
    'Defender path-excl count'    = @($g.DefenderExclusionPath).Count
    'Defender process-excl count' = @($g.DefenderExclusionProcess).Count
    'BitLocker C:'      = $(if ($g.BitLockerProtectionStatus -eq 1) { 'ON' } elseif ($g.BitLockerProtectionStatus -eq 0) { 'off' } else { '(n/a)' })
    'RDP'               = $(if ($g.RdpDenyTSConnections) { 'disabled' } else { 'enabled' })
    'Installed software' = "$($g.InstalledSoftwareCount) entries"
    'Services running'  = $g.ServicesRunning
}
foreach ($k in $display.Keys) {
    Write-Host ("  {0,-26} : {1}" -f $k, $display[$k])
}

Write-Host ""
Write-Host "=== Findings ($($findings.Count)) ===" -ForegroundColor Cyan
if ($findings.Count -eq 0) {
    Write-Host "  No findings - this image meets all evaluated rules for role '$Role'." -ForegroundColor Green
} else {
    $findings | Sort-Object Severity, Rule | Format-Table -AutoSize -Wrap -Property @{Label='Sev';Expression={$_.Severity};Width=4}, Rule, Detail, Fix
}

Write-Host "=== Installed software (top 15 alphabetically) ==="
foreach ($s in $g.InstalledSoftwareSample) {
    Write-Host ("  {0,-50} {1,-15} {2}" -f $s.DisplayName, $s.DisplayVersion, $s.Publisher)
}
