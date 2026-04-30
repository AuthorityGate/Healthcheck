# Start of Settings
# Hosts on or below this build are flagged 'BELOW BASELINE'. ALL hosts are
# always reported regardless. Update yearly. Defaults below reflect ESXi 8.0
# U3 GA / vCenter 8.0 U3 GA - reasonable late-2024 floor; tighten per your
# support matrix and the VMware/Broadcom 'Patches and Updates' KB.
$MinAcceptableEsxiBuild = 24022510    # ~ ESXi 8.0 U3 GA (2024-09)
$MinAcceptableVcsaBuild = 24022515    # ~ vCenter 8.0 U3 GA (2024-09)
# End of Settings

$Title          = "ESXi / vCenter Build Currency"
$Header         = "All hosts + vCenter listed; hosts at or below baseline build are flagged"
$Comments       = "Per VMware Lifecycle / VMSA security advisories, ESXi must be patched within ~90 days of release. Every host is listed with its current build, version, cluster, and a status flag relative to the configured baseline. vCenter appears as the final row. The baseline build is configurable at the top of this plugin - update yearly."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.2
$PluginCategory = "95 vSphere Backing Infra"
$Severity       = "P2"
$Recommendation = "Stage host upgrades via vSphere Lifecycle Manager (vLCM). Reference: VMSA bulletins + KB 'Build numbers and versions of ESXi/vCenter' (KB 2143832 / 2143838). Update the MinAcceptableEsxiBuild / MinAcceptableVcsaBuild constants in this plugin annually."

if (-not $Global:VCConnected) { return }

$hosts = @(Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)
if ($hosts.Count -eq 0) {
    [pscustomobject]@{ Note = 'Get-VMHost returned no hosts. Verify vCenter connection and account permissions on host objects.' }
    return
}

foreach ($h in $hosts) {
    $build = 0
    if ($h.Build) { $build = [int]("$($h.Build)" -replace '[^0-9]','') }
    $status = if ($build -le 0) { 'UNKNOWN' }
              elseif ($build -le $MinAcceptableEsxiBuild) { 'BELOW BASELINE' }
              else { 'OK' }
    $cluster = ''
    try { if ($h.Parent) { $cluster = "$($h.Parent.Name)" } } catch { }

    [pscustomobject]@{
        Type          = 'ESXi'
        Name          = $h.Name
        Cluster       = $cluster
        Version       = "$($h.Version)"
        Build         = "$($h.Build)"
        BaselineBuild = $MinAcceptableEsxiBuild
        Status        = $status
        ConnectionState = "$($h.ConnectionState)"
        PowerState    = "$($h.PowerState)"
    }
}

# vCenter row (always emitted)
$vc = $global:DefaultVIServer
if ($vc) {
    $vcBuild = 0
    if ($vc.Build) { $vcBuild = [int]("$($vc.Build)" -replace '[^0-9]','') }
    $vcStatus = if ($vcBuild -le 0) { 'UNKNOWN' }
                elseif ($vcBuild -le $MinAcceptableVcsaBuild) { 'BELOW BASELINE' }
                else { 'OK' }
    [pscustomobject]@{
        Type          = 'vCenter'
        Name          = "$($vc.Name)"
        Cluster       = '-'
        Version       = "$($vc.Version)"
        Build         = "$($vc.Build)"
        BaselineBuild = $MinAcceptableVcsaBuild
        Status        = $vcStatus
        ConnectionState = 'Connected'
        PowerState    = '-'
    }
}

$TableFormat = @{
    Status = { param($v,$row) if ("$v" -eq 'OK') { 'ok' } elseif ("$v" -match 'BELOW|UNKNOWN') { 'warn' } else { '' } }
    Build  = { param($v,$row) if ("$($row.Status)" -match 'BELOW|UNKNOWN') { 'warn' } else { '' } }
    ConnectionState = { param($v,$row) if ("$v" -ne 'Connected' -and "$v" -ne '-') { 'bad' } else { '' } }
}
