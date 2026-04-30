# Start of Settings
# End of Settings

$Title          = "Data Resilience + Protection Rules"
$Header         = "Replication Factor + Protection Rule + Recovery Plan summary"
$Comments       = "Cluster-level resilience posture: configured RF (data redundancy), Protection Rules (replication schedules), Recovery Plans (DR runbooks). For Horizon-on-AHV, RF=2 minimum cluster-wide, RF=3 recommended for VDI gold images + persistent disks."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 Nutanix Prism"
$Severity       = "P2"
$Recommendation = "Clusters running Horizon-critical workload with no Protection Rule = no DR. Recovery Plans must be regularly tested (quarterly minimum). Protection Rule schedules out of sync with RPO objectives = silent data-loss exposure."

if (-not (Get-NTNXRestSession)) { return }

$rows = @()
foreach ($c in @(Get-NTNXCluster)) {
    if (-not $c) { continue }
    $rows += [pscustomobject]@{
        Type        = 'Cluster'
        Name        = $c.name
        Detail      = "Current RF: $($c.cluster_redundancy_state.current_redundancy_factor) | Desired: $($c.cluster_redundancy_state.desired_redundancy_factor) | DomainAware: $($c.domain_awareness_level)"
        State       = if ($c.cluster_redundancy_state.current_redundancy_factor -ge 2) { 'OK' } else { 'AT-RISK' }
        Note        = if ($c.cluster_redundancy_state.current_redundancy_factor -lt $c.cluster_redundancy_state.desired_redundancy_factor) { 'Cluster is rebuilding redundancy - in-flight failure scope' } else { '' }
    }
}
foreach ($p in @(Get-NTNXProtectionRule)) {
    if (-not $p) { continue }
    $rows += [pscustomobject]@{
        Type        = 'ProtectionRule'
        Name        = $p.name
        Detail      = "Snapshot+Replication policy: $(if ($p.start_time) { 'auto' } else { 'manual' }) | Schedules: $(@($p.availability_zone_connectivity_list).Count) AZ link(s)"
        State       = $p.state
        Note        = $p.description
    }
}
foreach ($r in @(Get-NTNXRecoveryPlan)) {
    if (-not $r) { continue }
    $rows += [pscustomobject]@{
        Type        = 'RecoveryPlan'
        Name        = $r.name
        Detail      = "Stages: $(@($r.stage_list).Count) | LastUpdated: $($r.last_update_time)"
        State       = $r.state
        Note        = $r.description
    }
}
if ($rows.Count -eq 0) {
    [pscustomobject]@{ Note='No cluster / protection-rule / recovery-plan data. Likely PE-only or insufficient permissions on this account.' }
    return
}
$rows

$TableFormat = @{
    State = { param($v,$row) if ($v -match 'OK|COMPLETED|ACTIVE') { 'ok' } elseif ($v -match 'AT-RISK|ERROR|FAILED') { 'bad' } elseif ($v) { 'warn' } else { '' } }
}
