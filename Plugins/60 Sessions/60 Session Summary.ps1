# Start of Settings
# End of Settings

$Title          = "Session Summary"
$Header         = "Session counts by state and protocol"
$Comments       = "Active vs disconnected sessions, broken out by display protocol."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "60 Sessions"
$Severity       = "Info"

$s = Get-HVSession
if (-not $s) { return }

$s | Group-Object session_state, session_protocol | ForEach-Object {
    $first = $_.Group | Select-Object -First 1
    [pscustomobject]@{
        State    = $first.session_state
        Protocol = $first.session_protocol
        Count    = $_.Count
    }
} | Sort-Object Count -Descending
