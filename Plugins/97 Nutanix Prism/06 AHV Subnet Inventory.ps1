# Start of Settings
# End of Settings

$Title          = "AHV Subnet (Network) Inventory"
$Header         = "[count] AHV subnet(s) defined"
$Comments       = "Every AHV subnet (the AHV equivalent of a vSphere port group): VLAN ID, IPAM-managed flag, IP pool ranges, default gateway, DHCP server config, attached VPC. Used to confirm VLAN trunking is consistent and IPAM scopes have free addresses."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 Nutanix Prism"
$Severity       = "Info"
$Recommendation = "IPAM-managed subnets without an IP pool (or exhausted pool) cause provisioning failures. Verify VLAN ID matches the upstream switch trunk; mismatched VLANs silently drop traffic."

if (-not (Get-NTNXRestSession)) { return }
$subnets = @(Get-NTNXSubnet)
if (-not $subnets) {
    [pscustomobject]@{ Note='No subnets visible to this account.' }
    return
}

foreach ($sn in $subnets) {
    $ipPools = @()
    if ($sn.ip_config -and $sn.ip_config.pool_list) {
        $ipPools = $sn.ip_config.pool_list | ForEach-Object { $_.range }
    }
    [pscustomobject]@{
        Name           = $sn.name
        Cluster        = if ($sn.cluster_reference) { $sn.cluster_reference.name } else { '' }
        SubnetType     = $sn.subnet_type
        VLAN           = $sn.vlan_id
        IPAMManaged    = [bool]$sn.is_external
        Network        = if ($sn.ip_config) { "$($sn.ip_config.subnet_ip)/$($sn.ip_config.prefix_length)" } else { '' }
        Gateway        = if ($sn.ip_config) { $sn.ip_config.default_gateway_ip } else { '' }
        DHCPServer     = if ($sn.ip_config -and $sn.ip_config.dhcp_options) { $sn.ip_config.dhcp_options.dhcp_server_address } else { '' }
        IPPoolRanges   = ($ipPools -join '; ')
        VPC            = if ($sn.vpc_reference) { $sn.vpc_reference.name } else { '' }
        IsAdvanced     = [bool]$sn.advanced_networking
    }
}
