# Start of Settings
# End of Settings

$Title          = 'ESXi VMkernel Adapters Inventory'
$Header         = "[count] VMkernel adapter(s) across hosts"
$Comments       = "Per-host VMkernel adapters with their service tags (Mgmt, vMotion, Provisioning, FT, vSAN, NFS). Surfaces config drift and missing redundancy at the kernel-NIC layer."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'Info'
$Recommendation = "Each major service tag should have at least 1 dedicated vmkernel. Mgmt + HA Heartbeat must be redundant. vMotion vmkernel = dedicated and ideally on its own VLAN."

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue)) {
    if ($h.ConnectionState -ne 'Connected') { continue }
    foreach ($vmk in (Get-VMHostNetworkAdapter -VMHost $h -VMKernel -ErrorAction SilentlyContinue)) {
        $tags = @()
        if ($vmk.ManagementTrafficEnabled) { $tags += 'Mgmt' }
        if ($vmk.VMotionEnabled)           { $tags += 'vMotion' }
        if ($vmk.FaultToleranceLoggingEnabled) { $tags += 'FT' }
        if ($vmk.VsanTrafficEnabled)       { $tags += 'vSAN' }
        try { if ($vmk.ProvisioningTrafficEnabled) { $tags += 'Provisioning' } } catch { }

        [pscustomobject]@{
            Host       = $h.Name
            Cluster    = if ($h.Parent) { $h.Parent.Name } else { '' }
            Adapter    = $vmk.DeviceName
            IP         = $vmk.IP
            SubnetMask = $vmk.SubnetMask
            MTU        = $vmk.Mtu
            PortGroup  = $vmk.PortGroupName
            Services   = ($tags -join ',')
        }
    }
}

$TableFormat = @{
    Services = { param($v,$row) if (-not $v) { 'warn' } else { '' } }
    MTU      = { param($v,$row) if ($v -lt 1500) { 'bad' } else { '' } }
}
