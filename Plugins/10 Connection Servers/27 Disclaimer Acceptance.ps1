# Start of Settings
# End of Settings

$Title          = 'Connection Server Logon Banner / Disclaimer'
$Header         = 'Logon banner configured'
$Comments       = "Many compliance frameworks (DISA STIG, HIPAA, PCI) require a pre-authentication legal banner. Horizon supports a 'message of the day' / disclaimer in Global Settings."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '10 Connection Servers'
$Severity       = 'P3'
$Recommendation = "Settings -> Global Settings -> 'Display a pre-login message'. Use the canonical legal text for your industry."

if (-not (Get-HVRestSession)) { return }
try { $g = Get-HVGlobalSettings } catch { return }
if (-not $g) { return }
[pscustomobject]@{
    PreLoginMessageEnabled = $g.pre_login_message_enabled
    PreLoginMessage        = if ($g.pre_login_message) { $g.pre_login_message.Substring(0, [Math]::Min(140, $g.pre_login_message.Length)) + '...' } else { '(none)' }
}

