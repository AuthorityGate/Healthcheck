# Start of Settings
# End of Settings

$Title          = 'Enrollment Server Service Account'
$Header         = 'Enrollment service binding hint'
$Comments       = "The Enrollment Server runs under SYSTEM but uses the machine account when calling the CA. Verify the machine account is a member of the CA's 'Cert Issuance' group."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '93 Enrollment Server'
$Severity       = 'P2'
$Recommendation = "Add the ES machine account (or a dedicated AD group containing it) to the CA's permissions on the cert template + 'Issue and Manage Certificates'."

if (-not (Get-HVRestSession)) { return }
[pscustomobject]@{
    ManualVerification = 'Validate ES machine account permissions in certtmpl.msc on the issuing CA.'
    Reference          = 'Setting Up True SSO -> Configure Enrollment Server'
}
