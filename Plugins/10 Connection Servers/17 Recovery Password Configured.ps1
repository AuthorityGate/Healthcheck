# Start of Settings
# End of Settings

$Title          = "ADAM / LDAP Recovery Password Configured"
$Header         = "[count] pod(s) without an ADAM/vdmadmin recovery password set"
$Comments       = "Reference: Horizon Admin Guide -> 'Setting a Recovery Password for the LDAP Configuration'. Without a recovery password, you cannot restore the View LDAP if the entire pod becomes corrupt. The password is set per-pod via 'vdmadmin -L'."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "10 Connection Servers"
$Severity       = "P3"
$Recommendation = "On a Connection Server: vdmadmin -L -p <password> -reminder '<reminder>' -timeout 0. Store the password in your password vault."

if (-not (Get-HVRestSession)) { return }

# REST does not surface the recovery-password state; we report the global-settings advisory only.
try {
    $g = Get-HVGlobalSettings
} catch { return }
if (-not $g) { return }

# Best-effort: the public REST schema doesn't include this. Surface a single info row prompting manual verification, but include any related security-policy fields we can read.
[pscustomobject]@{
    Pod                          = $g.pod_name
    AutomaticStatusUpdate        = $g.enable_automatic_status_updates
    EnableExtendedSessionTimeout = $g.enable_extended_session_timeout
    ManualVerificationRequired   = 'YES - run "vdmadmin -L -list" on a Connection Server to confirm reminder is set'
    KBReference                  = 'Horizon Admin Guide / "Set Recovery Password"'
}

$TableFormat = @{ ManualVerificationRequired = { param($v,$row) 'warn' } }
