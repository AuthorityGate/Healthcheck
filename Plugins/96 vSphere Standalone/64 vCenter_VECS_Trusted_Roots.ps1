# Start of Settings
$WarnDays = 60
# End of Settings

$Title          = 'vCenter VECS Trusted Root Certificates'
$Header         = '[count] trusted root cert(s) expiring or expired'
$Comments       = 'VECS (VMware Endpoint Certificate Store) holds trusted CA roots. Stale or expired roots break solution-user trust chains and can cause silent auth failures. Distinct from STS / Machine SSL.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P2'
$Recommendation = "On vCenter shell: /usr/lib/vmware-vmafd/bin/vecs-cli entry list --store TRUSTED_ROOTS --text. Remove expired roots with /usr/lib/vmware-vmafd/bin/vecs-cli entry delete --store TRUSTED_ROOTS --alias <alias>."

if (-not $Global:VCConnected) { return }

# vecs-cli is shell-only; surface a manual-check row that prints the canonical
# diagnostic command. Future enhancement: parse vCenter's /api/trustedinfrastructure REST.
[pscustomobject]@{
    Source        = 'VECS TRUSTED_ROOTS store'
    Status        = 'Manual check required'
    Diagnostic    = "/usr/lib/vmware-vmafd/bin/vecs-cli entry list --store TRUSTED_ROOTS --text | grep -E 'Alias|Not After'"
    Recommendation= 'Audit each entry; remove expired or unused roots; preserve VMCA root.'
}
