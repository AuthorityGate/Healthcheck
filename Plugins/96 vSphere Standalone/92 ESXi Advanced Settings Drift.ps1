# Start of Settings
# Critical advanced settings tracked for drift across hosts.
$TrackedSettings = @(
    'NFS.MaxVolumes'
    'Net.TcpipHeapSize'
    'Net.TcpipHeapMax'
    'Misc.APDHandlingEnable'
    'UserVars.ESXiVPsDisabledProtocols'
    'UserVars.SuppressShellWarning'
    'UserVars.SuppressHyperthreadWarning'
    'Power.CpuPolicy'
    'Mem.MemMinFreePct'
    'Numa.MigImbalanceThreshold'
    'VSAN.SwapThickProvisionDisabled'
)
# End of Settings

$Title          = "ESXi Advanced Settings Drift"
$Header         = "[count] critical advanced setting / host pair captured"
$Comments       = "Tracks a curated set of advanced ESXi settings across hosts. Drift between hosts in the same cluster usually means a manual change went un-baselined (a frequent cause of intermittent storage / network anomalies on one specific host)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P3"
$Recommendation = "Capture cluster baselines once and remediate drift via Host Profiles or PowerCLI scripts. Audit changes via vCenter event log."

if (-not $Global:VCConnected) { return }

$rows = @()
foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue)) {
    if (-not $h) { continue }
    foreach ($s in $TrackedSettings) {
        $v = $null
        try { $v = (Get-AdvancedSetting -Entity $h -Name $s -ErrorAction Stop).Value } catch { $v = '(unset)' }
        $rows += [pscustomobject]@{
            Host    = $h.Name
            Setting = $s
            Value   = $v
        }
    }
}
# Identify settings whose value differs across hosts
$drifts = $rows | Group-Object Setting | Where-Object { ($_.Group | Select-Object -Unique Value).Count -gt 1 }
$driftSet = ($drifts | ForEach-Object { $_.Name }) -as [string[]]
foreach ($r in $rows) {
    [pscustomobject]@{
        Host    = $r.Host
        Setting = $r.Setting
        Value   = $r.Value
        Drift   = ([bool]($driftSet -contains $r.Setting))
    }
}

$TableFormat = @{
    Drift = { param($v,$row) if ($v -eq $true) { 'warn' } else { '' } }
}
