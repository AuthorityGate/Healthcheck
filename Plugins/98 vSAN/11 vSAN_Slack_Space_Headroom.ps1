# Start of Settings
# End of Settings

$Title          = 'vSAN Slack Space Headroom'
$Header         = 'vSAN cluster slack-space % (target: 25-30% free)'
$Comments       = "Reference: Broadcom KB - 'vSAN Capacity Management' / VMware Compute Policies. vSAN reserves slack space (the 'reserve capacity' setting) so it can rebalance after a host or disk-group failure. Below 25% free, vSAN can refuse new writes during a rebuild. The plugin tries Get-VsanSpaceUsage first, then falls back to the cluster's vSAN datastore (Get-Datastore -Type vsan) when TotalCapacityGB is missing - a 0-byte total with non-zero free is the signature of a permission gap or older PowerCLI build, NOT an actual capacity problem."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = '98 vSAN'
$Severity       = 'Info'   # promoted to P1/P2 below only if a cluster genuinely runs hot
$Recommendation = 'Add capacity (drives or hosts) before slack falls below 25%. If a row shows "data unavailable" the service account likely lacks vSAN read permissions on that cluster - grant the role and re-run.'

if (-not $Global:VCConnected) { return }

$worstSlack = 100.0   # tracks lowest free% across clusters - drives final severity
$anyBadData = $false

Get-Cluster -ErrorAction SilentlyContinue | Where-Object { $_.VsanEnabled } | ForEach-Object {
    $cl = $_
    $totalGB = 0.0
    $freeGB  = 0.0
    $usedGB  = 0.0
    $source  = ''
    $note    = ''

    # 1) Preferred: Get-VsanSpaceUsage (PowerCLI 12+)
    $u = $cl | Get-VsanSpaceUsage -ErrorAction SilentlyContinue
    if ($u) {
        if ($u.PSObject.Properties['TotalCapacityGB'] -and $u.TotalCapacityGB) { $totalGB = [double]$u.TotalCapacityGB }
        if ($u.PSObject.Properties['FreeSpaceGB']     -and $u.FreeSpaceGB)     { $freeGB  = [double]$u.FreeSpaceGB }
        if ($u.PSObject.Properties['UsedCapacityGB']  -and $u.UsedCapacityGB)  { $usedGB  = [double]$u.UsedCapacityGB }
        # If TotalCapacityGB came back 0 but Free + Used add up, derive total
        if ($totalGB -le 0 -and ($freeGB -gt 0 -or $usedGB -gt 0)) {
            $totalGB = $freeGB + $usedGB
            if ($totalGB -gt 0) { $source = 'Get-VsanSpaceUsage (Total derived from Free+Used)' }
        } elseif ($totalGB -gt 0) {
            $source = 'Get-VsanSpaceUsage'
        }
    }

    # 2) Fallback: the vSAN datastore directly. CapacityGB / FreeSpaceGB
    #    are populated even when the vSAN cmdlet is permission-blocked.
    if ($totalGB -le 0) {
        $vsanDs = Get-Datastore -RelatedObject $cl -ErrorAction SilentlyContinue |
                    Where-Object { $_.Type -eq 'vsan' } | Select-Object -First 1
        if ($vsanDs) {
            $totalGB = [double]$vsanDs.CapacityGB
            $freeGB  = [double]$vsanDs.FreeSpaceGB
            $usedGB  = $totalGB - $freeGB
            if ($totalGB -gt 0) { $source = 'Get-Datastore (vsan datastore)' }
        }
    }

    if ($totalGB -le 0) {
        # Genuinely no usable data - don't fire P1, emit Info row
        $anyBadData = $true
        [pscustomobject]@{
            Cluster = $cl.Name
            FreePct = $null
            FreeGB  = if ($freeGB -gt 0) { [math]::Round($freeGB,1) } else { $null }
            UsedGB  = if ($usedGB -gt 0) { [math]::Round($usedGB,1) } else { $null }
            TotalGB = $null
            Status  = 'data unavailable'
            Source  = if ($source) { $source } else { 'no source answered' }
            Note    = 'TotalCapacityGB not reported - check vSAN read permissions or PowerCLI version'
        }
        return
    }

    $pct = [math]::Round(($freeGB / $totalGB) * 100, 1)
    if ($pct -lt $worstSlack) { $worstSlack = $pct }

    $status = if ($pct -lt 25) { 'BELOW 25% - rebuild risk' }
              elseif ($pct -lt 30) { 'tight (25-30%)' }
              else { 'healthy' }

    [pscustomobject]@{
        Cluster = $cl.Name
        FreePct = $pct
        FreeGB  = [math]::Round($freeGB, 1)
        UsedGB  = [math]::Round($usedGB, 1)
        TotalGB = [math]::Round($totalGB, 1)
        Status  = $status
        Source  = $source
        Note    = ''
    }
}

# Dynamic severity. Only P1 when at least one cluster genuinely has < 25%
# slack with trustworthy capacity data. Bad-data-only runs stay Info so a
# permission gap doesn't masquerade as a capacity emergency.
if ($worstSlack -lt 25) { $Severity = 'P1' }
elseif ($worstSlack -lt 30) { $Severity = 'P2' }
elseif ($anyBadData) { $Severity = 'Info' }
else { $Severity = 'Info' }

$TableFormat = @{
    FreePct = { param($v,$row)
        if ($null -eq $v -or "$v" -eq '') { '' }
        elseif ([double]$v -lt 25) { 'bad' }
        elseif ([double]$v -lt 30) { 'warn' }
        else { 'ok' }
    }
    Status = { param($v,$row)
        if ($v -match 'BELOW') { 'bad' }
        elseif ($v -match 'tight') { 'warn' }
        elseif ($v -match 'unavailable') { 'warn' }
        elseif ($v -match 'healthy') { 'ok' }
        else { '' }
    }
}
