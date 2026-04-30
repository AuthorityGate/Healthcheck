# Start of Settings
# End of Settings

$Title          = 'App Volumes Recent Attachment Failures'
$Header         = '[count] attachment record(s) with non-success status'
$Comments       = 'Failed attachments break user logon (no apps appear). Common cause: datastore full or VC out of provisioning slots.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'P1'
$Recommendation = 'Triage by error message. Verify datastore free, VC ops slots, and AD machine account permissions.'

if (-not (Get-AVRestSession)) { return }
$at = Get-AVAttachment
if (-not $at) { return }
foreach ($a in $at.attachments) {
    if ($a.status -and $a.status -ne 'success' -and $a.status -ne 'attached') {
        [pscustomobject]@{
            Status   = $a.status
            User     = $a.user_name
            Computer = $a.computer_name
            Volume   = $a.app_package_name
            When     = $a.attached_at
        }
    }
}
