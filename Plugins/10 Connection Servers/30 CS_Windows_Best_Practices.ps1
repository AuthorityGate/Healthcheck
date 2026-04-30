# Start of Settings
# End of Settings

$Title          = 'Connection Server Windows Best Practices'
$Header         = "[count] best-practice finding(s) across Horizon Connection Servers"
$Comments       = "Per-CS Windows Server hygiene scan: OS support level, patch currency, Defender state, broker service running, SSL cert expiry, recent error event volume, IIS state. Tier 2 (in-guest) probe runs when a Windows credential is supplied via Global:HVImageScanCredential. Without it, only the basic discovery shows."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '10 Connection Servers'
$Severity       = 'P2'
$Recommendation = "Each row names a CS + a finding + the fix. Address the highest severity rows first; group by CS for batched maintenance."

if (-not (Get-HVRestSession)) { return }

# InfraServerScan is imported globally by the runspace at startup. Fall
# back to a runtime import via $Global:HVRoot only if the function is
# missing - guards against ZIP extractions that nested Plugins\Plugins\
# (the old Split-Path-Parent $PSScriptRoot math broke in that layout).
if (-not (Get-Command -Name 'Invoke-WindowsBestPracticeProbe' -ErrorAction SilentlyContinue)) {
    $modPath = $null
    if ($Global:HVRoot) { $modPath = Join-Path $Global:HVRoot 'Modules\InfraServerScan.psm1' }
    if ((-not $modPath) -or (-not (Test-Path $modPath))) {
        [pscustomobject]@{ Server='(plugin error)'; Rule='InfraServerScan.psm1 not loaded'; Detail="Expected via Global:HVRoot but module not found. Reinstall or re-run RunGUI."; Fix='Reinstall HealthCheckPS1.' }
        return
    }
    Import-Module $modPath -Force -ErrorAction SilentlyContinue
}

# Discover CS servers via Horizon REST
$servers = New-Object System.Collections.Generic.HashSet[string]
try {
    $cs = Invoke-HVRest -Path '/v1/monitor/connection-servers' -NoPaging
    foreach ($c in @($cs)) {
        if ($c.name) { [void]$servers.Add($c.name) }
        elseif ($c.host_name) { [void]$servers.Add($c.host_name) }
    }
} catch { }
if ($servers.Count -eq 0) { return }

$cred = if (Test-Path Variable:Global:HVImageScanCredential) { $Global:HVImageScanCredential } else { $null }

foreach ($srv in $servers) {
    # Try to find the corresponding VM in vCenter (might be domain-joined hostname)
    $vm = $null
    if ($Global:VCConnected) {
        $shortName = ($srv -split '\.')[0]
        $vm = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $shortName -or $_.Name -ieq $srv } | Select-Object -First 1
    }
    $scan = Get-InfraServerScan -ServerFqdn $srv -Role 'ConnectionServer' -Credential $cred -Vm $vm

    [pscustomobject]@{
        Server   = $srv
        Role     = 'ConnectionServer'
        Severity = 'Info'
        Rule     = "Scanned at $($scan.Tier)"
        Detail   = if ($scan.Guest -and $scan.Guest.OsCaption) {
            "OS=$($scan.Guest.OsCaption) Build=$($scan.Guest.OsBuildNumber) UBR=$($scan.Guest.UBR) CSVersion=$($scan.Guest.HorizonCSVersion) CertDaysLeft=$($scan.Guest.CSCertDaysToExpiry)"
        } elseif ($scan.VmHardware.GuestOS) {
            "VM=$($scan.VmHardware.VmName) OS=$($scan.VmHardware.GuestOS) IP=$($scan.VmHardware.IPAddress)"
        } else {
            "Tier 2 unavailable - $($scan.Guest.WinRmError)"
        }
        Fix      = if ($scan.Tier -eq 'Tier1') { 'Set $Global:HVImageScanCredential and verify WinRM 5985 reachable to enable Tier 2 in-guest scan.' } else { 'No action - inventory only.' }
    }
    foreach ($f in $scan.Findings) { $f }
}

$TableFormat = @{
    Severity = { param($v,$row) if ($v -eq 'P1') { 'bad' } elseif ($v -eq 'P2') { 'warn' } else { '' } }
}
