# Start of Settings
$DisconnectedHoursThreshold = 24
# End of Settings

$Title          = 'Machines Long Disconnected from Horizon Agent'
$Header         = "[count] machine(s) with stale agent (no recent contact)"
$Comments       = "Horizon machines whose agent last reported > $DisconnectedHoursThreshold hours ago = likely powered off, decommissioned, or AD-joined-but-Horizon-deregistered. Pool capacity calculation may be wrong."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '50 Machines'
$Severity       = 'P3'
$Recommendation = "Investigate stale machines. Either restore them (if intended to be available) or remove from Horizon inventory (if deprovisioned). Inaccurate inventory affects pool sizing."

if (-not (Get-HVRestSession)) { return }

try { $machines = Invoke-HVRest -Path '/v1/inventory/machines' -NoPaging } catch { return }

foreach ($m in @($machines)) {
    if ($m.last_seen_unix_time) {
        $lastSeen = (Get-Date '1970-01-01').AddMilliseconds([int64]$m.last_seen_unix_time)
        $age = [int]((Get-Date) - $lastSeen).TotalHours
        if ($age -gt $DisconnectedHoursThreshold) {
            [pscustomobject]@{
                Machine     = $m.name
                Pool        = $m.desktop_pool_id
                Status      = $m.state
                LastSeen    = $lastSeen.ToString('yyyy-MM-dd HH:mm')
                AgeHours    = $age
                Note        = if ($age -gt 168) { 'Stale > 1 week - decommission candidate' } else { 'Stale - investigate' }
            }
        }
    }
}

$TableFormat = @{
    AgeHours = { param($v,$row) if ($v -gt 168) { 'bad' } elseif ($v -gt 48) { 'warn' } else { '' } }
}
