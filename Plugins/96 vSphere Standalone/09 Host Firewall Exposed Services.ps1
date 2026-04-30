# Start of Settings
# Services that should NOT be enabled by default (fail loud if a host has them on).
$RestrictedServices = @('CIMHttpsServer','iofiltervp','rdt','syslog','vSphereClient','wol','snmp')
# End of Settings

$Title          = "ESXi Firewall - Exposed / Open Services"
$Header         = "[count] host/service combinations with firewall rule enabled and not restricted to source IPs"
$Comments       = "vSphere Hardening Guide: every enabled inbound firewall rule should be restricted to a known-source IP list (NOT 0.0.0.0/0). Default 'AllowAll=True' on enabled services bypasses the firewall."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P2"
$Recommendation = "Host -> Configure -> Firewall -> select rule -> 'Edit' -> uncheck 'Allow connections from any IP address' and add explicit subnets/IPs. Apply via host profile."

if (-not $Global:VCConnected) { return }

Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $h  = $_
    $fw = Get-VMHostFirewallException -VMHost $h -ErrorAction SilentlyContinue
    foreach ($r in $fw) {
        if ($r.Enabled -and $r.ExtensionData.AllowedHosts.AllIp) {
            [pscustomobject]@{
                Host    = $h.Name
                Service = $r.Name
                Enabled = $r.Enabled
                AllIPs  = $r.ExtensionData.AllowedHosts.AllIp
                Notable = ($r.Name -in $RestrictedServices)
            }
        }
    }
}

$TableFormat = @{
    AllIPs  = { param($v,$row) if ($v -eq $true) { 'warn' } else { '' } }
    Notable = { param($v,$row) if ($v -eq $true) { 'bad' } else { '' } }
}
