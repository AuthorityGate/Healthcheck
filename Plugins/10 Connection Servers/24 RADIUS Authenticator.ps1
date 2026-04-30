# Start of Settings
# End of Settings

$Title          = 'RADIUS Authenticator (2FA)'
$Header         = '[count] RADIUS authenticator(s) configured'
$Comments       = "Reference: Horizon Admin Guide -> 'Set up 2-factor authentication'. RADIUS commonly fronts MFA (RSA SecurID, Duo, Azure MFA). Mis-set 'shared secret' results in silent timeouts at logon."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '10 Connection Servers'
$Severity       = 'P2'
$Recommendation = 'Verify each RADIUS authenticator: primary + backup hosts, shared secret, NAS identifier, and authentication port.'

if (-not (Get-HVRestSession)) { return }
try { $r = Invoke-HVRest -Path '/v1/config/radius-authenticators' } catch { return }
if (-not $r) { return }
foreach ($a in $r) {
    [pscustomobject]@{
        Name        = $a.name
        PrimaryHost = $a.primary_auth_host
        BackupHost  = $a.secondary_auth_host
        AuthPort    = $a.primary_auth_port
        AuthType    = $a.authentication_type
        Timeout     = $a.server_timeout_in_seconds
        Enabled     = $a.enabled
    }
}

