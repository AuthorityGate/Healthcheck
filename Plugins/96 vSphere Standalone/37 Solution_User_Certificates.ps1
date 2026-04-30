# Start of Settings
# End of Settings

$Title          = 'Solution User Certificates'
$Header         = 'vCenter solution user / machine cert age'
$Comments       = 'vCenter solution-user certs (machine, vpxd, vpxd-extension, vsphere-webclient) auto-renew via VMCA. Manual replacement is uncommon.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'Info'
$Recommendation = 'Verify all 4 solution users present + cert validity > 1 year via /usr/lib/vmware-vmafd/bin/dir-cli list (on VCSA).'

if (-not $Global:VCConnected) { return }
[pscustomobject]@{
    Note = 'Run on VCSA shell: /usr/lib/vmware-vmafd/bin/vecs-cli store list. Beyond PowerCLI scope.'
    Reference = 'KB 2111219'
}
