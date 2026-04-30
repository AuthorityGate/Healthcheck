# Start of Settings
# End of Settings

$Title          = "Helpdesk Active Sessions (Live)"
$Header         = "[count] live helpdesk session detail record(s)"
$Comments       = "When the Horizon Helpdesk plug-in is licensed and enabled, the helpdesk REST endpoint exposes per-session detail beyond what /v1/sessions provides: client OS, client version, agent version, latency, framerate, transmit/receive KBps, machine event log link. This is the ground-truth view of session quality."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "60 Sessions"
$Severity       = "Info"
$Recommendation = "Sessions with sustained RTT > 150 ms or framerate < 15 fps usually indicate WAN problem on the user side (PCoIP/BLAST congestion). Use this view to triage 'desktop is slow' tickets without bothering the user."

if (-not (Get-HVRestSession)) { return }
$rows = @()
try { $rows = @(Get-HVHelpdeskSession) } catch { }
if (-not $rows -or $rows.Count -eq 0) {
    [pscustomobject]@{ Note = 'Helpdesk plug-in not enabled / no live sessions / endpoint not exposed by this Horizon build.' }
    return
}

foreach ($r in $rows) {
    [pscustomobject]@{
        User        = $r.user_name
        Machine     = $r.machine_name
        Pool        = $r.pool_or_farm_name
        ClientOS    = $r.client_data.os
        ClientVer   = $r.client_data.client_version
        AgentVer    = $r.machine_data.agent_version
        Protocol    = $r.session_protocol
        RTT_ms      = $r.session_latency_ms
        FPS         = $r.session_frames_per_second
        TxKBps      = $r.session_kbps_transmit
        RxKBps      = $r.session_kbps_receive
        SessionState = $r.state
    }
}

$TableFormat = @{
    RTT_ms = { param($v,$row) if ([int]"$v" -gt 200) { 'bad' } elseif ([int]"$v" -gt 100) { 'warn' } else { '' } }
    FPS    = { param($v,$row) if ([int]"$v" -gt 0 -and [int]"$v" -lt 12) { 'bad' } elseif ([int]"$v" -lt 18) { 'warn' } else { '' } }
}
