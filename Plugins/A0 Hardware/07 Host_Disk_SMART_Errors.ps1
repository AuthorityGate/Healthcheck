# Start of Settings
# End of Settings

$Title          = 'Host Disk SMART Errors'
$Header         = '[count] device(s) with SMART pre-fail / failure indicators'
$Comments       = @"
Reference: Broadcom KB 2148572. SMART pre-fail = imminent failure - replace before data loss. Logic is per-attribute aware:
- Drive Temperature: pre-fail when actual reading > 70 C OR Value > Threshold (direction is HIGHER = worse, opposite of normalized SMART).
- Reallocated / Pending / Uncorrectable Sector counts: Value <= Threshold means the drive's normalized health for that counter has dropped below the manufacturer's failing line. Raw counts of 0 with Threshold 90 are NOT pre-fail (that's just '0 reallocations, threshold not applicable') and are excluded.
- Wear Leveling / Media Wearout / Available Spare: normalized (100 -> 0); pre-fail at Value <= Threshold.
- Power-On Hours / Power Cycle Count / Drive Rated Temperature: informational, not pre-fail.
- ESXi Status column ('fail', 'prefail', 'degraded') is honored even when the numeric comparison is inconclusive.
NVMe drives don't have ATA-style reallocated-sector counters; this plugin trusts the Status column and the Available-Spare/Wearout normalized indicators on those.
"@
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.2
$PluginCategory = 'A0 Hardware'
$Severity       = 'Info'   # promoted to P1 below only if a genuine pre-fail signal fires
$Recommendation = 'Replace the drive while it is still readable. For vSAN cache devices, follow the vSAN disk-replacement procedure (vSphere Client -> Cluster -> Configure -> vSAN -> Disk Management -> Remove Disk Group -> replace -> recreate group).'

if (-not $Global:VCConnected) { return }

# Attribute-aware classifier. Returns:
#   'prefail'   - this row is a real pre-failure signal
#   'info'      - real data but not a failure (skip from result set)
#   'skip'      - meaningless given the values (raw 0 vs normalized threshold)
function Test-SmartAttribute {
    param(
        [string]$Parameter,
        $Value,
        $Threshold,
        [string]$Status
    )
    # Status column is authoritative when it's explicit
    if ($Status -and ($Status -match '^(fail|failed)$')) {
        return @{ Verdict = 'prefail'; Reason = "Drive status reports: $Status" }
    }
    if ($Status -and ($Status -match 'prefail|degraded')) {
        # Reported pre-fail from the firmware itself - trust it but verify with Value/Threshold below
        $statusPrefail = $true
    } else {
        $statusPrefail = $false
    }

    $vNum = $null; $tNum = $null
    $vOk = [int]::TryParse([string]$Value,     [ref]([ref]([int]0)).Value)
    # Use a real ref var since the inline trick above doesn't work cleanly
    $vTmp = 0; $tTmp = 0
    $vOk = [int]::TryParse([string]$Value,     [ref]$vTmp); if ($vOk) { $vNum = $vTmp }
    $tOk = [int]::TryParse([string]$Threshold, [ref]$tTmp); if ($tOk) { $tNum = $tTmp }

    $p = ($Parameter | ForEach-Object { $_.ToLower() })

    # 1. Drive temperature (HIGHER = worse). ESXi reports Value in deg C,
    #    Threshold = max safe deg C. Behavior:
    #    - When the drive REPORTS a Threshold > 0: trust it strictly
    #      (Value > Threshold = pre-fail).
    #    - When Threshold == 0 (no per-drive max reported, common on
    #      older SanDisk / OEM SSDs): use a conservative absolute limit.
    #      Most SSDs spec 70-85 deg C as normal operating max, with
    #      catastrophic damage above ~90 deg C. 71 deg C with no rated
    #      threshold is hot but NOT imminent failure - emit Info.
    if ($p -match 'drive\s+temperature' -or $p -eq 'temperature' -or $p -match 'composite\s+temperature') {
        if ($null -ne $vNum -and $null -ne $tNum -and $tNum -gt 0 -and $vNum -gt $tNum) {
            return @{ Verdict = 'prefail'; Reason = "Temperature $vNum C > drive-rated max $tNum C" }
        }
        if ($null -ne $vNum -and $vNum -gt 90) {
            return @{ Verdict = 'prefail'; Reason = "Temperature $vNum C exceeds 90 C catastrophic limit" }
        }
        return @{ Verdict = 'info'; Reason = '' }
    }

    # 2. Drive Rated Max Temperature - this is just the spec sheet limit, never pre-fail.
    if ($p -match 'rated\s+(max\s+)?temperature' -or $p -match 'temperature\s+rate') {
        return @{ Verdict = 'info'; Reason = '' }
    }

    # 3. Power-on hours / power-cycle count - never failure indicators
    if ($p -match 'power[- ]?on\s+hours' -or $p -match 'power[- ]?cycle' -or $p -match 'start[- ]?stop') {
        return @{ Verdict = 'info'; Reason = '' }
    }

    # 4. Reallocated/Pending/Uncorrectable Sector counters. ESXi reports either
    #    a normalized score (100 or 200 = full health, decreases as drive ages,
    #    Threshold = manufacturer's failing line) OR a raw event count (0 = no
    #    events, any non-zero = real reallocations).
    #
    #    Some drives (SanDisk SSDs in particular) report the normalized score
    #    with Threshold = 0 - meaning "the firmware doesn't declare a failing
    #    line for this attribute", NOT "raw count comparison". A Value of 100
    #    with Threshold 0 is healthy.
    #
    #    Classifier:
    #      - Value 0: clean (no events; no normalized concern).
    #      - Value 95-200: looks like normalized full-health score. Pre-fail
    #        only when Threshold > 0 AND Value <= Threshold. With Threshold = 0
    #        we trust the score and treat it as healthy.
    #      - Value 1-94 with Threshold > 0 and Value <= Threshold: pre-fail
    #        (normalized score genuinely below the failing line).
    #      - Value 1-94 with Threshold = 0: probably a raw event count
    #        (firmware reports actual reallocations) - pre-fail. Even 1 event
    #        worth flagging on a healthcheck.
    #      - Value 1-94 with Threshold > 0 but Value > Threshold: ambiguous,
    #        emit Info.
    if ($p -match 'reallocat(ed|ion)' -or $p -match 'pending\s+sector' -or
        $p -match 'uncorrectable\s+sector' -or $p -match 'reported\s+uncorrectable') {
        if ($null -eq $vNum) {
            if ($statusPrefail) { return @{ Verdict = 'prefail'; Reason = "Status: $Status" } }
            return @{ Verdict = 'info'; Reason = '' }
        }
        if ($vNum -eq 0) {
            return @{ Verdict = 'skip'; Reason = 'No events (Value=0)' }
        }
        # Normalized full-health signature - Value sits at the top of the
        # decreasing scale (100 or 200). Threshold = 0 = no declared failing
        # line; trust the high score as healthy.
        if ($vNum -ge 95 -and $vNum -le 200) {
            if ($null -ne $tNum -and $tNum -gt 0 -and $vNum -le $tNum) {
                return @{ Verdict = 'prefail'; Reason = "Normalized health $vNum <= Threshold $tNum" }
            }
            $reason = if ($null -ne $tNum -and $tNum -gt 0) {
                "Normalized health $vNum (above threshold $tNum)"
            } else {
                "Normalized health $vNum (no failing line declared)"
            }
            return @{ Verdict = 'info'; Reason = $reason }
        }
        # Value 1-94: either a degraded normalized score or a raw event count.
        if ($null -ne $tNum -and $tNum -gt 0) {
            if ($vNum -le $tNum) {
                return @{ Verdict = 'prefail'; Reason = "Normalized health $vNum <= Threshold $tNum" }
            }
            # Above threshold, low normalized score - unusual, emit Info
            return @{ Verdict = 'info'; Reason = "Value $vNum below normal range but above threshold $tNum" }
        }
        # No threshold - treat as raw event count. Any non-zero is a real event.
        return @{ Verdict = 'prefail'; Reason = "Raw event count: $vNum" }
    }

    # 5. Wear Leveling Count / Media Wearout / Available Spare - all normalized,
    #    Value drops toward Threshold as the SSD ages.
    if ($p -match 'wear[- ]?level' -or $p -match 'media\s+wear' -or
        $p -match 'available\s+spare' -or $p -match 'used\s+reserved' -or
        $p -match 'remaining\s+life|life\s+used|percent.*used') {
        if ($null -ne $vNum -and $null -ne $tNum -and $tNum -gt 0 -and $vNum -le $tNum) {
            return @{ Verdict = 'prefail'; Reason = "Wear/spare $vNum <= Threshold $tNum" }
        }
        if ($statusPrefail) { return @{ Verdict = 'prefail'; Reason = "Status: $Status" } }
        return @{ Verdict = 'info'; Reason = '' }
    }

    # 6. Read/Write/Seek error rates - normalized; lower = worse.
    if ($p -match 'error\s+rate|seek\s+error|raw\s+read') {
        if ($null -ne $vNum -and $null -ne $tNum -and $tNum -gt 0 -and $vNum -le $tNum) {
            return @{ Verdict = 'prefail'; Reason = "Normalized $vNum <= Threshold $tNum" }
        }
        return @{ Verdict = 'info'; Reason = '' }
    }

    # 7. NVMe Critical Warning bits - any non-zero is bad
    if ($p -match 'critical\s+warning') {
        if ($null -ne $vNum -and $vNum -ne 0) {
            return @{ Verdict = 'prefail'; Reason = "NVMe critical warning bits set: $vNum" }
        }
        return @{ Verdict = 'info'; Reason = '' }
    }

    # 8. Default: if firmware says prefail, honor it; otherwise no judgment
    if ($statusPrefail) { return @{ Verdict = 'prefail'; Reason = "Status: $Status" } }
    return @{ Verdict = 'info'; Reason = '' }
}

$prefailFound = $false

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue)) {
    if ($h.ConnectionState -ne 'Connected') { continue }

    try {
        $esxcli = Get-EsxCli -V2 -VMHost $h -ErrorAction Stop
    } catch {
        [pscustomobject]@{
            Host       = $h.Name
            Cluster    = $h.Parent.Name
            Device     = '(esxcli unreachable)'
            Parameter  = 'n/a'
            Value      = ''
            Threshold  = ''
            Status     = 'unknown'
            Note       = "esxcli probe failed: $($_.Exception.Message)"
        }
        continue
    }

    try {
        $devices = $esxcli.storage.core.device.list.Invoke() |
            Where-Object { $_.IsLocal -eq 'true' -and $_.IsRemovable -eq 'false' }
    } catch {
        $devices = @()
    }

    foreach ($d in $devices) {
        try {
            $smart = $esxcli.storage.core.device.smart.get.Invoke(@{ devicename = $d.Device }) 2>$null
        } catch {
            continue
        }
        if (-not $smart) { continue }

        foreach ($p in $smart) {
            $r = Test-SmartAttribute -Parameter $p.Parameter -Value $p.Value -Threshold $p.Threshold -Status $p.Status
            if ($r.Verdict -ne 'prefail') { continue }
            $prefailFound = $true
            [pscustomobject]@{
                Host       = $h.Name
                Cluster    = $h.Parent.Name
                Device     = $d.Device
                Parameter  = $p.Parameter
                Value      = $p.Value
                Threshold  = $p.Threshold
                Status     = if ($p.Status) { $p.Status } else { 'pre-fail' }
                Note       = $r.Reason
            }
        }
    }
}

# Only escalate to P1 when at least one row is a real pre-fail. Otherwise
# the only rows are esxcli-unreachable diagnostics, which are warn at most.
if ($prefailFound) { $Severity = 'P1' }

$TableFormat = @{
    Status = { param($v,$row)
        if ($v -match 'fail|prefail') { 'bad' }
        elseif ($v -eq 'unknown') { 'warn' }
        else { '' }
    }
}
