# Start of Settings
# End of Settings

$Title          = 'Standard vSwitch Inventory'
$Header         = '[count] standard vSwitch(es) on host(s) where vDS is available'
$Comments       = "Standard vSwitches require per-host configuration; vDS centralizes config at vCenter and supports advanced features (NIOC, LACP, LLDP, port mirroring, NetFlow). On any vCenter that already has vDS in use, remaining vSS represent migration debt."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = 'Migrate vSS port groups to vDS via Networking -> Migrate Networking. Plan downtime per host. Keep one minimal vSS for management failover only when explicitly required.'

if (-not $Global:VCConnected) { return }

# Only flag if at least one vDS exists in this vCenter
$haveVds = @(Get-VDSwitch -ErrorAction SilentlyContinue).Count -gt 0

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)) {
    foreach ($vss in (Get-VirtualSwitch -VMHost $h -Standard -ErrorAction SilentlyContinue)) {
        [pscustomobject]@{
            Host       = $h.Name
            Switch     = $vss.Name
            Mtu        = $vss.Mtu
            NumPorts   = $vss.NumPorts
            UsedPorts  = $vss.NumPortsAvailable
            Uplinks    = ($vss.Nic -join ',')
            Note       = if ($haveVds) { 'vDS exists in this vCenter; consider migrating off vSS.' } else { 'No vDS in vCenter - vSS may be intentional.' }
        }
    }
}
