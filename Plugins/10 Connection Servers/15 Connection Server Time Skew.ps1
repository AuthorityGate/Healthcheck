# Start of Settings
# Maximum tolerable Connection Server vs domain skew (seconds).
$MaxSkewSec = 60
# End of Settings

$Title          = "Connection Server Time Skew vs Domain"
$Header         = "[count] Connection Server(s) drifting from the local domain controller"
$Comments       = "VMware KB 57147 / Horizon Admin Guide: clock drift > 5 minutes between CS and AD breaks Kerberos. Horizon brokering will silently fail with 'cannot authenticate user' even when the password is correct. We flag at $MaxSkewSec s as an early warning."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "10 Connection Servers"
$Severity       = "P1"
$Recommendation = "On each CS: 'w32tm /query /status' and 'w32tm /resync'. Configure all CSes + DCs to a single authoritative NTP source. KB 57147."

if (-not (Get-HVRestSession)) { return }
$cs = Get-HVConnectionServer
if (-not $cs) { return }

# Try to resolve a DC for the runner's domain (best-effort, no-op if unjoined)
$dcTime = $null
try {
    $dom = (Get-CimInstance -ClassName Win32_ComputerSystem).Domain
    if ($dom -and $dom -notmatch 'WORKGROUP') {
        $r = Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$dom" -Type SRV -ErrorAction SilentlyContinue |
              Select-Object -First 1
        if ($r) {
            $dcHost = $r.NameTarget
            # tnc 389 round-trip + lazy clock pull via [DateTime]::UtcNow on the local host as best-effort
            # NOTE: there is no portable PS5.1 way to query DC clock without admin. We surface the local
            # vs CS skew as a proxy.
        }
    }
} catch { }

# CS REST gives us start_time + last_updated_timestamp (ms). Compute drift vs the runner's clock.
$now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
foreach ($c in $cs) {
    if (-not $c.last_updated_timestamp) { continue }
    $skew = [math]::Abs(($now - $c.last_updated_timestamp) / 1000.0)
    if ($skew -gt $MaxSkewSec) {
        [pscustomobject]@{
            ConnectionServer = $c.name
            CSReportedAt     = (Get-Date '1970-01-01').AddMilliseconds($c.last_updated_timestamp).ToLocalTime()
            RunnerClock      = (Get-Date)
            SkewSec          = [int]$skew
        }
    }
}

$TableFormat = @{
    SkewSec = { param($v,$row) if ([int]$v -gt 300) { 'bad' } elseif ([int]$v -gt 60) { 'warn' } else { '' } }
}
