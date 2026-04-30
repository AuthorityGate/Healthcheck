# Start of Settings
# End of Settings

$Title          = "Port-Group Security Policy"
$Header         = "[count] port-group(s) with insecure security policy"
$Comments       = "VMware KB 1010935 / 1037389 / vSphere Hardening Guide: a port-group with PromiscuousMode=Accept, ForgedTransmits=Accept, or MacChanges=Accept allows traffic capture or MAC spoofing. Default-deny all three unless a workload (firewall VM, NSX edge) explicitly needs them."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P2"
$Recommendation = "Set Promiscuous=Reject, ForgedTransmits=Reject, MacChanges=Reject at the switch and override per port-group only where needed. Document the exceptions."

if (-not $Global:VCConnected) { return }

# Standard port groups
Get-VirtualPortGroup -ErrorAction SilentlyContinue | Where-Object { -not $_.ExtensionData.Config } | ForEach-Object {
    $sp = $_.ExtensionData.Spec.Policy.Security
    if (-not $sp) { return }
    if ($sp.AllowPromiscuous -or $sp.ForgedTransmits -or $sp.MacChanges) {
        [pscustomobject]@{
            Type        = 'Standard'
            PortGroup   = $_.Name
            Host        = $_.VMHost.Name
            Promiscuous = $sp.AllowPromiscuous
            ForgedTx    = $sp.ForgedTransmits
            MacChanges  = $sp.MacChanges
        }
    }
}
# DV port groups
Get-VDPortgroup -ErrorAction SilentlyContinue | ForEach-Object {
    $sp = $_.ExtensionData.Config.DefaultPortConfig.SecurityPolicy
    if (-not $sp) { return }
    if (($sp.AllowPromiscuous -and $sp.AllowPromiscuous.Value) `
       -or ($sp.ForgedTransmits -and $sp.ForgedTransmits.Value) `
       -or ($sp.MacChanges -and $sp.MacChanges.Value)) {
        [pscustomobject]@{
            Type        = 'Distributed'
            PortGroup   = $_.Name
            Host        = $_.VDSwitch.Name
            Promiscuous = $sp.AllowPromiscuous.Value
            ForgedTx    = $sp.ForgedTransmits.Value
            MacChanges  = $sp.MacChanges.Value
        }
    }
}

$TableFormat = @{
    Promiscuous = { param($v,$row) if ($v -eq $true) { 'bad' } else { '' } }
    ForgedTx    = { param($v,$row) if ($v -eq $true) { 'warn' } else { '' } }
    MacChanges  = { param($v,$row) if ($v -eq $true) { 'warn' } else { '' } }
}
