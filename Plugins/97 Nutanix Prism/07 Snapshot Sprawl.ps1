# Start of Settings
$WarnAgeDays = 30
$BadAgeDays  = 90
# End of Settings

$Title          = "Nutanix Snapshot Sprawl + Age"
$Header         = "[count] VM-level snapshot(s) with age + size"
$Comments       = "Every VM snapshot tracked by Prism. Long-lived snapshots inflate storage usage and slow restores; >90 days = remediate. Includes both Acropolis snapshots AND Async DR / Protection Domain snapshots when visible to the calling user."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 Nutanix Prism"
$Severity       = "P3"
$Recommendation = "Snapshots > 30 days = warn, > 90 days = bad. Audit the originator (often a forgotten manual snapshot from a maintenance window). Convert long-term retention requirements to Protection Policy schedules instead of ad-hoc snapshots."

if (-not (Get-NTNXRestSession)) { return }
$snaps = @(Get-NTNXSnapshot)
if (-not $snaps) {
    [pscustomobject]@{ Note='No VM snapshots reported (or view_vm_snapshot permission missing).' }
    return
}

foreach ($s in $snaps) {
    $created = $null; $ageDays = $null
    if ($s.creation_time -or ($s.metadata -and $s.metadata.creation_time)) {
        $raw = if ($s.creation_time) { $s.creation_time } else { $s.metadata.creation_time }
        try { $created = [datetime]::Parse([string]$raw); $ageDays = [int]((Get-Date) - $created).TotalDays } catch { }
    }
    [pscustomobject]@{
        Snapshot     = $s.name
        VM           = if ($s.vm_reference) { $s.vm_reference.name } else { $s.vm_name }
        Cluster      = if ($s.cluster_reference) { $s.cluster_reference.name } else { '' }
        SnapshotType = $s.snapshot_type
        Created      = if ($created) { $created.ToString('yyyy-MM-dd HH:mm') } else { '' }
        AgeDays      = $ageDays
        SizeGB       = if ($s.size_bytes) { [math]::Round([double]$s.size_bytes / 1GB, 2) } else { '' }
        Description  = if ($s.description) { $s.description.Substring(0,[Math]::Min(80,$s.description.Length)) } else { '' }
    }
}

$TableFormat = @{
    AgeDays = { param($v,$row) if ([int]"$v" -ge $BadAgeDays) { 'bad' } elseif ([int]"$v" -ge $WarnAgeDays) { 'warn' } else { '' } }
}
