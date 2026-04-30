# Start of Settings
# End of Settings

$Title          = 'Connection Server Inventory (WinRM Fallback)'
$Header         = 'Per-CS Windows-side inventory pulled directly from each host'
$Comments       = @"
Direct WinRM probe of every CS FQDN the operator supplied in the Horizon tab (and any in the optional 'Peer CS FQDNs' field on the Specialized Scope dialog). Bypasses the Horizon REST API entirely so you still get product version + build + services + cert expiry on Horizon 8.6 builds where /v1/monitor/connection-servers and /v1/config/connection-servers return only stub data (id + jwt_info).

Reads from each CS:
- HKLM:\\SOFTWARE\\VMware, Inc.\\VMware VDM\\plugins   (Connection Server install + version)
- 'VMware Horizon Connection Server' service state
- VMware Tomcat / Java cert expiry on the broker port
- OS caption + build + UBR for patch currency cross-reference

Requires: Windows credential supplied via 'Set Deep-Scan Creds...' on the main form. Without it, this plugin emits Tier 1 only (just the FQDN list). With it AND WinRM 5985 reachable, returns full per-host detail.
"@
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '10 Connection Servers'
$Severity       = 'Info'
$Recommendation = "If 'Tier 2 unavailable - WinRM error' appears: the runner cannot reach 5985/TCP on the CS, OR the supplied credential cannot auth (non-domain-joined runners need TrustedHosts pre-set + -Authentication Negotiate)."

# Source list of CS FQDNs - in priority order:
# 1. The 'Peer CS FQDNs' textbox on the Specialized Scope dialog (operator-supplied)
# 2. The HVServer FQDN(s) typed on the Horizon tab (comma/semicolon separated)
$fqdns = New-Object System.Collections.Generic.HashSet[string]
if ($Global:HVPeerConnectionServers) {
    foreach ($f in @($Global:HVPeerConnectionServers)) {
        $t = ([string]$f).Trim()
        if ($t) { [void]$fqdns.Add($t.ToLower()) }
    }
}
if ($Global:HVServer) {
    foreach ($f in @($Global:HVServer -split '[,;\s]+')) {
        $t = ([string]$f).Trim()
        if ($t) { [void]$fqdns.Add($t.ToLower()) }
    }
}
# As a final fallback, derive from the active session
if ($fqdns.Count -eq 0 -and (Get-HVRestSession)) {
    $sess = Get-HVRestSession
    if ($sess.Server) { [void]$fqdns.Add(([string]$sess.Server).ToLower()) }
}

if ($fqdns.Count -eq 0) {
    [pscustomobject]@{
        Server = '(no FQDNs)'
        Tier   = ''
        Note   = 'No CS FQDN list available. Type Connection Server FQDNs (comma-separated) on the Horizon tab, or list peers in the Specialized Scope dialog.'
    }
    return
}

# Ensure InfraServerScan is loaded
if (-not (Get-Command -Name 'Get-InfraServerScan' -ErrorAction SilentlyContinue)) {
    if ($Global:HVRoot) {
        $modPath = Join-Path $Global:HVRoot 'Modules\InfraServerScan.psm1'
        if (Test-Path $modPath) { Import-Module $modPath -Force -ErrorAction SilentlyContinue }
    }
}
if (-not (Get-Command -Name 'Get-InfraServerScan' -ErrorAction SilentlyContinue)) {
    [pscustomobject]@{ Server='(plugin error)'; Tier=''; Note='InfraServerScan module not loaded.' }
    return
}

$cred = if (Test-Path Variable:Global:HVImageScanCredential) { $Global:HVImageScanCredential } else { $null }

foreach ($srv in $fqdns) {
    $vm = $null
    if ($Global:VCConnected) {
        $shortName = ($srv -split '\.')[0]
        try {
            $vm = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $shortName -or $_.Name -ieq $srv } | Select-Object -First 1
        } catch { }
    }
    $scan = Get-InfraServerScan -ServerFqdn $srv -Role 'ConnectionServer' -Credential $cred -Vm $vm

    $g = $scan.Guest
    $vh = $scan.VmHardware
    # Get-many helper: tolerate missing properties on hashtables and PSObjects.
    function _GetField { param($Obj, [string]$Name)
        if ($null -eq $Obj) { return $null }
        if ($Obj -is [hashtable]) { if ($Obj.ContainsKey($Name)) { return $Obj[$Name] } else { return $null } }
        if ($Obj.PSObject -and $Obj.PSObject.Properties[$Name]) { return $Obj.PSObject.Properties[$Name].Value }
        return $null
    }
    # CPU / RAM: prefer guest-side WinRM probe (works without vCenter);
    # fall back to VmHardware (vCenter VM lookup) when guest probe didn't run.
    $cpu = _GetField $g 'NumLogicalCpu'
    if (-not $cpu) { $cpu = _GetField $vh 'vCpu' }
    $ramGb = _GetField $g 'TotalPhysicalMemoryGB'
    if (-not $ramGb) { $ramGb = _GetField $vh 'RamGB' }

    [pscustomobject]@{
        Server         = $srv
        Tier           = $scan.Tier
        VmName         = if ($vh -and (_GetField $vh 'VmName')) { _GetField $vh 'VmName' } else { '' }
        OS             = if ($g -and (_GetField $g 'OsCaption')) { _GetField $g 'OsCaption' } elseif (_GetField $vh 'GuestOS') { _GetField $vh 'GuestOS' } else { '' }
        OsBuild        = if ($g -and (_GetField $g 'OsBuildNumber')) { "$(_GetField $g 'OsBuildNumber').$(_GetField $g 'UBR')" } else { '' }
        CSVersion      = if ($g) { _GetField $g 'HorizonCSVersion' } else { '' }
        BrokerSvc      = if ($g) { _GetField $g 'HorizonCSServiceState' } else { '' }
        vCpu           = if ($cpu)   { [int]$cpu }   else { '' }
        RamGb          = if ($ramGb) { [math]::Round([double]$ramGb, 1) } else { '' }
        CertDaysLeft   = if ($g -and $null -ne (_GetField $g 'CSCertDaysToExpiry')) { [int](_GetField $g 'CSCertDaysToExpiry') } else { '' }
        IPAddress      = if (_GetField $vh 'IPAddress') { _GetField $vh 'IPAddress' } else { '' }
        Note           = if ($scan.Tier -eq 'Tier1') {
                            $err = _GetField $g 'WinRmError'
                            if ($err) { "Tier 2 unavailable: $err" } else { 'Tier 2 unavailable - set Deep-Scan Creds on the main form and verify WinRM 5985 reachable.' }
                         } elseif ($scan.Tier -eq 'Tier2' -and -not (_GetField $g 'HorizonCSVersion')) { 'Tier 2 connected but Horizon CS registry key not found - is this actually a Connection Server?' }
                         else { '' }
    }
}

$TableFormat = @{
    Tier = { param($v,$row) if ($v -eq 'Tier2') { 'ok' } elseif ($v -eq 'Tier1') { 'warn' } else { 'bad' } }
    BrokerSvc = { param($v,$row) if ($v -eq 'Running') { 'ok' } elseif ($v) { 'bad' } else { '' } }
    vCpu = { param($v,$row) if ([string]$v -eq '') { '' } elseif ([int]$v -lt 4) { 'bad' } elseif ([int]$v -lt 6) { 'warn' } else { 'ok' } }
    RamGb = { param($v,$row) if ([string]$v -eq '') { '' } elseif ([double]$v -lt 12) { 'bad' } elseif ([double]$v -lt 16) { 'warn' } else { 'ok' } }
    CertDaysLeft = { param($v,$row)
        if ([string]$v -eq '') { '' }
        elseif ([int]$v -lt 30) { 'bad' }
        elseif ([int]$v -lt 90) { 'warn' }
        else { 'ok' }
    }
}
