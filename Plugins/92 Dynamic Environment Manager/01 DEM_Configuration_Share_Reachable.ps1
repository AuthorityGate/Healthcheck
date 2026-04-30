# Start of Settings
# End of Settings

$Title          = 'DEM Configuration Share Reachable'
$Header         = 'DEM config share path inventory'
$Comments       = "Reference: 'DEM Architecture' (Omnissa DEM docs). The DEM config share holds FlexProfile + group-policy template definitions. Unreachable share = Agent fallback (no profile)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '92 Dynamic Environment Manager'
$Severity       = 'P1'
$Recommendation = 'Verify SMB share path, DFS-N, NTFS perms (Domain Computers: Read), and SMBv2/v3 negotiation.'

$gpoCfg = Get-ChildItem -Path 'HKLM:\SOFTWARE\Policies\VMware, Inc.\VMware UEM\Agent\FlexEngine' -ErrorAction SilentlyContinue
if (-not $gpoCfg) { return }
$share = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\VMware, Inc.\VMware UEM\Agent\FlexEngine' -ErrorAction SilentlyContinue).ConfigShare
[pscustomobject]@{
    ConfigShare = $share
    Reachable   = if ($share) { (Test-Path $share) } else { $false }
}
