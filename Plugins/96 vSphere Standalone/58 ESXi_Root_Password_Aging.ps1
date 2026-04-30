# Start of Settings
# Threshold for stale root password (days since last change)
$RootPwAgeWarnDays = 365
$RootPwAgeBadDays  = 730
# End of Settings

$Title          = 'ESXi Root Password Aging'
$Header         = "[count] host(s) with stale root password"
$Comments       = "ESXi root password age tracked at /etc/shadow. Old root passwords = elevated risk. Rotate at least annually."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = "Rotate root password annually via PAM (or scripted). Different per-host password OR central PAM-managed. Document rotation procedure."

if (-not $Global:VCConnected) { return }

# Note: this is best-effort. Reading /etc/shadow requires SSH which is normally
# disabled. We surface guidance instead - the consultant verifies via manual
# check or via PAM tool.

[pscustomobject]@{
    Check = 'ESXi root password aging'
    Detail = 'Cannot programmatically read /etc/shadow without SSH (disabled in lockdown).'
    Note = 'Manual check: SSH to a host (after enabling temporarily), run `chage -l root`. Or check your PAM tool for last-rotation timestamp.'
    Recommendation = "Rotate root passwords annually. Use Lockdown Mode + PAM-managed credentials so rotation is mechanical."
}
