# Start of Settings
# End of Settings

$Title          = 'AD Replication Health'
$Header         = "[count] DC pair(s) with replication issues"
$Comments       = "AD replication keeps every DC's directory copy current. Failures = entitlement drift across DCs = inconsistent auth experience for users. Daily review."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'B3 Active Directory'
$Severity       = 'P1'
$Recommendation = "Run repadmin /replsummary on a DC. Investigate every failure. Common causes: network/firewall, FSMO unreachability, schema mismatch, USN rollback."

# Opt-in: only run when the operator supplied an AD forest hint via the GUI / CLI.
if (-not (Test-Path Variable:Global:ADForestFqdn) -or -not $Global:ADForestFqdn) { return }

$adAvailable = $true
try { Import-Module ActiveDirectory -ErrorAction Stop } catch { $adAvailable = $false }

if (-not $adAvailable) {
    # Plugin 01 (AD Sites and Services) is the canonical plugin to surface
    # the RSAT-missing message. Skip silently here to avoid 4 duplicate rows.
    return
}

# Get-ADReplicationPartnerMetadata uses -Target instead of -Server. On a
# non-domain-joined runner, passing the forest FQDN as -Target fails with
# 'Unable to find a default server' because the cmdlet can't auto-discover
# a DC. Use the operator-supplied DC FQDN as -Target with -Scope Forest
# instead - returns the same forest-wide replication metadata from that
# DC's perspective.
$repTarget = if ($Global:ADServerFqdn) { $Global:ADServerFqdn } else { $Global:ADForestFqdn }
$repArgs = @{}
if (Test-Path Variable:Global:ADCredential) { $repArgs.Credential = $Global:ADCredential }

try {
    $partners = Get-ADReplicationPartnerMetadata -Target $repTarget -Scope Forest @repArgs -ErrorAction Stop
    foreach ($p in $partners) {
        $hasFailure = ($p.LastReplicationResult -ne 0) -or ($p.ConsecutiveReplicationFailures -gt 0)
        if ($hasFailure) {
            [pscustomobject]@{
                Source              = $p.Server
                Destination         = $p.Partner -replace '^.*?CN=NTDS Settings,CN=([^,]+).*$','$1'
                LastSuccess         = $p.LastReplicationSuccess
                LastResult          = $p.LastReplicationResult
                ConsecutiveFailures = $p.ConsecutiveReplicationFailures
                Note                = if ($p.LastReplicationResult -ne 0) { "Replication error code $($p.LastReplicationResult)" } else { '' }
            }
        }
    }
} catch {
    [pscustomobject]@{ Source = 'Error'; Destination = ''; Note = "Replication query failed for '$Global:ADForestFqdn': $($_.Exception.Message). Verify the runner can reach a DC of that forest (DNS + TCP/9389 ADWS) and the AD credential has rights." }
}

$TableFormat = @{
    ConsecutiveFailures = { param($v,$row) if ($v -ne $null -and $v -gt 0) { 'bad' } else { '' } }
}
