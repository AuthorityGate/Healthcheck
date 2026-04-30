# Start of Settings
# End of Settings

$Title          = "ESXi Build and Patch Currency"
$Header         = "Per-host ESXi build + last-boot info (vCenter row appended)"
$Comments       = "Per-host ESXi version, build, hardware model, and boot/uptime timestamps. Drift across the cluster (mixed builds) is a vMotion risk; very-old builds are CVE-exposed (e.g., ESXi 6.7 EOL Oct 2022, ESXi 7.0 GA EOL Apr 2025). vCenter is appended as the last row so build currency is visible in one table."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P2"
$Recommendation = "Plan upgrade to ESXi 8.0 U2+ (or 7.0 U3+ if hardware compatibility limits 8.0). Same build across all hosts in cluster is required for full vMotion compat. Apply security patches within 30 days of release."

if (-not $Global:VCConnected) { return }

$hosts = @(Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)
if ($hosts.Count -eq 0) {
    [pscustomobject]@{ Note='Get-VMHost returned no hosts.' }
    return
}
foreach ($h in $hosts) {
    if (-not $h) { continue }
    $bn = $null; $patched = $null; $hwModel = ''
    try {
        $vmh = Get-View $h.Id -Property 'Config.Product','Hardware.SystemInfo','Summary.QuickStats','Runtime.BootTime' -ErrorAction Stop
        $bn  = $vmh.Config.Product.Build
        $hwModel = "$($vmh.Hardware.SystemInfo.Vendor) $($vmh.Hardware.SystemInfo.Model)"
        $patched = if ($vmh.Runtime.BootTime) { [datetime]$vmh.Runtime.BootTime } else { $null }
    } catch { }
    [pscustomobject]@{
        Type       = 'ESXi'
        Name       = $h.Name
        Cluster    = if ($h.Parent) { "$($h.Parent.Name)" } else { '' }
        Version    = "$($h.Version)"
        Build      = if ($bn) { "$bn" } else { "$($h.Build)" }
        ApiVersion = "$($h.ApiVersion)"
        Hardware   = $hwModel
        BootTime   = if ($patched) { $patched.ToString('yyyy-MM-dd HH:mm') } else { '' }
        UptimeDays = if ($patched) { [int]((Get-Date) - $patched).TotalDays } else { '' }
        Connection = "$($h.ConnectionState)"
    }
}

# vCenter row (always emitted so build-currency is visible alongside ESXi)
$vc = $global:DefaultVIServer
if ($vc) {
    [pscustomobject]@{
        Type       = 'vCenter'
        Name       = "$($vc.Name)"
        Cluster    = '-'
        Version    = "$($vc.Version)"
        Build      = "$($vc.Build)"
        ApiVersion = "$($vc.ApiVersion)"
        Hardware   = '-'
        BootTime   = ''
        UptimeDays = ''
        Connection = 'Connected'
    }
}

$TableFormat = @{
    Version    = { param($v,$row) if ("$v" -match '^[345]\.') { 'bad' } elseif ("$v" -match '^6\.') { 'warn' } else { '' } }
    UptimeDays = { param($v,$row) if ("$v" -match '^\d+$' -and [int]"$v" -gt 365) { 'warn' } else { '' } }
    Connection = { param($v,$row) if ("$v" -ne 'Connected') { 'bad' } else { '' } }
}
