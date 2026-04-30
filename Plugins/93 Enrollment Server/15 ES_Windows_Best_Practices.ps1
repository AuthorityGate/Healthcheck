# Start of Settings
# End of Settings

$Title          = 'Enrollment Server Windows Best Practices'
$Header         = "[count] best-practice finding(s) across Enrollment Servers"
$Comments       = "Per-ES Windows Server hygiene scan: OS support level, patch currency, Defender state, ES service running, EA cert validity + expiry, recent error event volume. Tier 2 (in-guest) probe runs when Global:HVImageScanCredential is set."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '93 Enrollment Server'
$Severity       = 'P1'
$Recommendation = "ES findings are P1 because EA cert expiry breaks True SSO fleet-wide. Address every row with the supplied Fix."

if (-not (Get-HVRestSession)) { return }

if (-not (Get-Command -Name 'Get-InfraServerScan' -ErrorAction SilentlyContinue)) {
    $modPath = $null
    if ($Global:HVRoot) { $modPath = Join-Path $Global:HVRoot 'Modules\InfraServerScan.psm1' }
    if ((-not $modPath) -or (-not (Test-Path $modPath))) {
        [pscustomobject]@{ Server='(plugin error)'; Rule='InfraServerScan.psm1 not loaded'; Detail="Module not available via Global:HVRoot. Reinstall HealthCheckPS1."; Fix='Reinstall HealthCheckPS1.' }
        return
    }
    Import-Module $modPath -Force -ErrorAction SilentlyContinue
}

$servers = New-Object System.Collections.Generic.HashSet[string]
try {
    $tsso = Invoke-HVRest -Path '/v1/config/true-sso' -NoPaging
    foreach ($e in @($tsso.enrollment_servers)) {
        if ($e.host_name) { [void]$servers.Add($e.host_name) }
    }
} catch { }
if ($servers.Count -eq 0) { return }

$cred = if (Test-Path Variable:Global:HVImageScanCredential) { $Global:HVImageScanCredential } else { $null }

foreach ($srv in $servers) {
    $vm = $null
    if ($Global:VCConnected) {
        $shortName = ($srv -split '\.')[0]
        $vm = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $shortName -or $_.Name -ieq $srv } | Select-Object -First 1
    }
    $scan = Get-InfraServerScan -ServerFqdn $srv -Role 'EnrollmentServer' -Credential $cred -Vm $vm

    [pscustomobject]@{
        Server   = $srv
        Role     = 'EnrollmentServer'
        Severity = 'Info'
        Rule     = "Scanned at $($scan.Tier)"
        Detail   = if ($scan.Guest -and $scan.Guest.OsCaption) {
            "OS=$($scan.Guest.OsCaption) Build=$($scan.Guest.OsBuildNumber) UBR=$($scan.Guest.UBR) ESVersion=$($scan.Guest.ESVersion) EACertDaysLeft=$($scan.Guest.EACertDaysToExpiry)"
        } elseif ($scan.VmHardware.GuestOS) {
            "VM=$($scan.VmHardware.VmName) OS=$($scan.VmHardware.GuestOS) IP=$($scan.VmHardware.IPAddress)"
        } else {
            "Tier 2 unavailable - $($scan.Guest.WinRmError)"
        }
        Fix      = if ($scan.Tier -eq 'Tier1') { 'Set $Global:HVImageScanCredential to enable Tier 2.' } else { 'No action - inventory only.' }
    }
    foreach ($f in $scan.Findings) { $f }
}

$TableFormat = @{
    Severity = { param($v,$row) if ($v -eq 'P1') { 'bad' } elseif ($v -eq 'P2') { 'warn' } else { '' } }
}
