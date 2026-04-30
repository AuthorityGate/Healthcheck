# Start of Settings
# End of Settings

$Title          = 'Active Directory Sites and Services'
$Header         = "[count] AD site(s) + subnets + site link(s)"
$Comments       = "AD Sites + Subnets dictate which DC a client uses for auth. Subnet missing from AD Sites = client falls back to global DC discovery = far-site DC = slow logon. Critical for multi-site Horizon: each office subnet must be associated with the correct AD site."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'B3 Active Directory'
$Severity       = 'P2'
$Recommendation = "Every IP subnet used by Horizon clients/desktops must be associated with the correct AD site. Site links + costs reflect WAN topology. Audit on network changes."

# If the operator did not opt-in to AD scanning (no forest hint), skip silently.
if (-not (Test-Path Variable:Global:ADForestFqdn) -or -not $Global:ADForestFqdn) { return }

# Requires the ActiveDirectory PowerShell module (RSAT-AD-PowerShell on Windows Server,
# RSAT optional features on Windows 10/11). If not installed, emit a single
# guidance row and DEMOTE this plugin's severity to Info - prereq-missing is
# operator action, not an environment finding.
$adAvailable = $true
try { Import-Module ActiveDirectory -ErrorAction Stop } catch { $adAvailable = $false }
if (-not $adAvailable) { $Severity = 'Info' }

if (-not $adAvailable) {
    # This is the only plugin in B3 that emits the prereq notice when RSAT is
    # missing. The other three plugins (DCs / Replication / FSMO) detect the
    # same condition and skip silently, so the consultant sees one clear
    # actionable row instead of four duplicates.
    $Global:_B3RsatMissingReported = $true
    [pscustomobject]@{
        Type     = 'Prereq missing'
        Name     = 'ActiveDirectory PowerShell module'
        Detail   = "Target forest '$Global:ADForestFqdn' could not be queried."
        Fix      = "Run Tools\\Install-RSAT.ps1 from this repo (auto-installs the RSAT capability), OR Settings -> Apps -> Optional Features -> 'RSAT: Active Directory Domain Services and Lightweight Directory Services Tools'."
        Note     = 'After install, OPEN A NEW PowerShell window and re-run the health check. AD module is loaded once per PowerShell session.'
    }
    return
}

# All AD cmdlets get -Server pointing at the operator-supplied target so we
# don't fall back to the runner's local domain context. Optional credential
# is honored when set in the GUI.
$adArgs = @{ Server = $(if ($Global:ADServerFqdn) { $Global:ADServerFqdn } else { $Global:ADForestFqdn }) }
if (Test-Path Variable:Global:ADCredential) { $adArgs.Credential = $Global:ADCredential }

try {
    # Sites
    $sites = Get-ADReplicationSite -Filter * @adArgs -ErrorAction Stop
    foreach ($s in $sites) {
        $subnets = @()
        try {
            $subnets = @(Get-ADReplicationSubnet -Filter "Site -eq '$($s.DistinguishedName)'" @adArgs -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
        } catch { }
        [pscustomobject]@{
            Type   = 'Site'
            Name   = $s.Name
            Detail = "Description: $($s.Description); Subnets: $($subnets.Count)"
            Note   = if ($subnets.Count -eq 0) { 'SITE HAS NO SUBNETS - clients in unknown subnets will hit random DCs.' } else { ($subnets -join ', ') }
        }
    }

    # Site Links
    $links = Get-ADReplicationSiteLink -Filter * @adArgs -ErrorAction SilentlyContinue
    foreach ($l in $links) {
        [pscustomobject]@{
            Type   = 'SiteLink'
            Name   = $l.Name
            Detail = "Cost: $($l.Cost); Schedule: $($l.ReplicationFrequencyInMinutes) min; Sites: $(($l.SitesIncluded -join ', '))"
            Note   = ''
        }
    }

    # Standalone subnets (orphan)
    try {
        $allSubnets = Get-ADReplicationSubnet -Filter * @adArgs -ErrorAction SilentlyContinue
        $orphan = @($allSubnets | Where-Object { -not $_.Site })
        if ($orphan.Count -gt 0) {
            foreach ($o in $orphan) {
                [pscustomobject]@{
                    Type   = 'OrphanSubnet'
                    Name   = $o.Name
                    Detail = ''
                    Note   = 'Subnet not associated with any site - clients in this subnet hit random DCs.'
                }
            }
        }
    } catch { }

} catch {
    [pscustomobject]@{
        Type = 'Error'
        Name = ''
        Detail = ''
        Note = "Get-ADReplicationSite failed for '$Global:ADForestFqdn': $($_.Exception.Message). Verify (1) DNS resolution to a DC of the forest from the runner, (2) TCP/9389 ADWS reachable, (3) the supplied AD credential has rights to query."
    }
}

$TableFormat = @{
    Note = { param($v,$row) if ($v -match 'NO SUBNETS|orphan|not associated') { 'bad' } else { '' } }
}
