# Start of Settings
# End of Settings

$Title          = 'vCenter SSO Password Policy'
$Header         = 'vsphere.local password lifetime + complexity'
$Comments       = "Reference: 'Configure vCenter Single Sign-On Password Policy' (vCenter docs). Default 90-day expiry on vsphere.local; auto-expiry locks out admins."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P2'
$Recommendation = 'Reduce admin@vsphere.local lifetime to 365 days for break-glass; rotate via VAMI.'

if (-not $Global:VCConnected) { return }
[pscustomobject]@{
    Note = 'Pull SSO password policy via Connect-SsoAdminServer; PowerCLI VMware.vSphere.SsoAdmin module required.'
    Reference = 'vCenter -> Administration -> SSO Configuration -> Local Accounts -> Password Policy'
}
