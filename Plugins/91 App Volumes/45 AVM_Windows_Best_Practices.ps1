# Start of Settings
# End of Settings

$Title          = 'App Volumes Manager Windows Best Practices'
$Header         = "[count] best-practice finding(s) across App Volumes Managers"
$Comments       = "Per-AVM Windows Server hygiene scan: OS support level, patch currency, Defender state, AVM service running, recent error event volume, IIS state (AVM uses IIS for the management UI). Tier 2 (in-guest) probe runs when a Windows credential is supplied via Global:HVImageScanCredential."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'P2'
$Recommendation = "Each row names an AVM + a finding + the fix. Group fixes by AVM for batched maintenance."

if (-not (Get-AVRestSession)) { return }

if (-not (Get-Command -Name 'Get-InfraServerScan' -ErrorAction SilentlyContinue)) {
    $modPath = $null
    if ($Global:HVRoot) { $modPath = Join-Path $Global:HVRoot 'Modules\InfraServerScan.psm1' }
    if ((-not $modPath) -or (-not (Test-Path $modPath))) {
        [pscustomobject]@{ Server='(plugin error)'; Rule='InfraServerScan.psm1 not loaded'; Detail="Module not available via Global:HVRoot. Reinstall HealthCheckPS1."; Fix='Reinstall HealthCheckPS1.' }
        return
    }
    Import-Module $modPath -Force -ErrorAction SilentlyContinue
}

# Discover AVM servers
$servers = New-Object System.Collections.Generic.HashSet[string]
try {
    $m = Invoke-AVRest -Path '/cv_api/managers'
    foreach ($mc in @($m.managers)) {
        if ($mc.name) { [void]$servers.Add($mc.name) }
        elseif ($mc.hostname) { [void]$servers.Add($mc.hostname) }
    }
} catch { }
# Also: the AV server we connected to is implicitly an AVM
if ($Global:AVServer) { [void]$servers.Add($Global:AVServer) }
if ($servers.Count -eq 0) { return }

$cred = if (Test-Path Variable:Global:HVImageScanCredential) { $Global:HVImageScanCredential } else { $null }

foreach ($srv in $servers) {
    $vm = $null
    if ($Global:VCConnected) {
        $shortName = ($srv -split '\.')[0]
        $vm = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $shortName -or $_.Name -ieq $srv } | Select-Object -First 1
    }
    $scan = Get-InfraServerScan -ServerFqdn $srv -Role 'AppVolumesManager' -Credential $cred -Vm $vm

    [pscustomobject]@{
        Server   = $srv
        Role     = 'AppVolumesManager'
        Severity = 'Info'
        Rule     = "Scanned at $($scan.Tier)"
        Detail   = if ($scan.Guest -and $scan.Guest.OsCaption) {
            "OS=$($scan.Guest.OsCaption) Build=$($scan.Guest.OsBuildNumber) UBR=$($scan.Guest.UBR) AVMVersion=$($scan.Guest.AVMVersion)"
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
