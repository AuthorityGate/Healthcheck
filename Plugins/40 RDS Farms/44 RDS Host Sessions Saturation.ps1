# Start of Settings
# End of Settings

$Title          = 'RDS Host Saturation'
$Header         = '[count] RDS host(s) at >= 90% of session limit'
$Comments       = "RDS hosts at session-cap reject new logons; users see 'Cannot connect, try again later'. Add capacity proactively."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '40 RDS Farms'
$Severity       = 'P2'
$Recommendation = "Add another RDS host to the farm; verify load-balancing settings ('Use balance script' or 'View load balancing')."

if (-not (Get-HVRestSession)) { return }
$rds = @(Get-HVRdsServer)
$farms = @(Get-HVFarm)
if ($rds.Count -eq 0 -or $farms.Count -eq 0) { return }

# Build farm-id + farm-name -> max_sessions_count map. We index by BOTH id
# and name so we can match whatever the rds-server response uses.
$farmMap = @{}
foreach ($f in $farms) {
    if (-not $f) { continue }
    $cap = $null
    try {
        if ($f.PSObject.Properties['session_settings'] -and $f.session_settings) {
            $rawCap = $f.session_settings.max_sessions_count
            if ($null -ne $rawCap) {
                $intCap = 0
                if ([int]::TryParse([string]$rawCap, [ref]$intCap)) { $cap = $intCap }
            }
        }
    } catch { }
    if (-not $cap -or $cap -le 0) { continue }
    foreach ($keyProp in @('id','name')) {
        $kv = $null
        try { $kv = [string]($f.$keyProp) } catch { }
        if ($kv) { $farmMap[$kv] = $cap }
    }
}
if ($farmMap.Count -eq 0) { return }

foreach ($r in $rds) {
    if (-not $r) { continue }
    # Look up by farm_id first, then farm_name. Skip silently if neither
    # matches (an rds-server pointing at a now-deleted farm, for example).
    $cap = $null
    foreach ($keyProp in @('farm_id','farm_name')) {
        $kv = $null
        try { $kv = [string]($r.$keyProp) } catch { }
        if ($kv -and $farmMap.ContainsKey($kv)) { $cap = $farmMap[$kv]; break }
    }
    if (-not $cap -or $cap -le 0) { continue }
    $sess = 0
    try {
        $rawSess = $r.session_count
        if ($null -ne $rawSess) { [int]::TryParse([string]$rawSess, [ref]$sess) | Out-Null }
    } catch { }
    $pct = [math]::Round(($sess / $cap) * 100, 1)
    if ($pct -ge 90) {
        [pscustomobject]@{
            Host        = $r.name
            Farm        = if ($r.farm_name) { $r.farm_name } else { $r.farm_id }
            Sessions    = $sess
            Cap         = $cap
            PercentFull = $pct
        }
    }
}

