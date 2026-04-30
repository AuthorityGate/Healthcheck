# Start of Settings
# End of Settings

$Title          = 'vMotion Network Isolation'
$Header         = 'Per-host VMkernel inventory + service mix per /24 subnet'
$Comments       = "vSCG / VMware Networking Best Practices: vMotion traffic is unencrypted by default and must NOT share a VLAN/subnet with management or VM data networks. Place vMotion on its own non-routable VLAN; consider Encrypted vMotion (per-VM setting) for tenant isolation. Lists every host's VMkernels with their service flags - rows where vMotion shares a subnet with management or other services are flagged."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.1
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = "Move the vMotion VMkernel to a dedicated port group / VLAN on a separate subnet. If vMotion must traverse a shared L2/L3, enable Encrypted vMotion ('Required') on every VM that may move."

if (-not $Global:VCConnected) { return }

$hosts = @(Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)
if ($hosts.Count -eq 0) {
    [pscustomobject]@{ Note='Get-VMHost returned no hosts.' }
    return
}

foreach ($h in $hosts) {
    $vmks = @(Get-VMHostNetworkAdapter -VMHost $h -VMKernel -ErrorAction SilentlyContinue)
    if ($vmks.Count -eq 0) {
        [pscustomobject]@{ Host=$h.Name; Cluster=if ($h.Parent) { "$($h.Parent.Name)" } else { '' }; VMK=''; IP=''; Subnet=''; Services=''; SharedWith=''; Status='NO VMKs' }
        continue
    }

    # Build subnet map: /24 -> [{vmk, ip, services[]}]
    $bySubnet = @{}
    $rows = @()
    foreach ($v in $vmks) {
        if (-not $v.IP -or -not $v.SubnetMask) {
            $rows += [pscustomobject]@{ Host=$h.Name; Cluster=if ($h.Parent) { "$($h.Parent.Name)" } else { '' }; VMK=$v.Name; IP='(no IP)'; Subnet=''; Services=''; SharedWith=''; Status='NO IP' }
            continue
        }
        $sub = ($v.IP -split '\.' | Select-Object -First 3) -join '.'
        $services = @()
        if ($v.ManagementTrafficEnabled)        { $services += 'Mgmt' }
        if ($v.VMotionEnabled)                  { $services += 'vMotion' }
        if ($v.FaultToleranceLoggingEnabled)    { $services += 'FT' }
        if ($v.VsanTrafficEnabled)              { $services += 'vSAN' }
        if ($services.Count -eq 0)              { $services += 'Other' }
        if (-not $bySubnet.ContainsKey($sub)) { $bySubnet[$sub] = @() }
        $bySubnet[$sub] += [pscustomobject]@{ VMK=$v.Name; IP=$v.IP; Services=$services }
    }

    foreach ($sub in $bySubnet.Keys) {
        $entries = $bySubnet[$sub]
        $allServices = @($entries | ForEach-Object { $_.Services } | Select-Object -Unique)
        $vmotionShares = ($allServices -contains 'vMotion' -and (($allServices | Where-Object { $_ -ne 'vMotion' }).Count -gt 0))
        foreach ($e in $entries) {
            $svcStr = ($e.Services -join '+')
            $sharedWith = ($allServices | Where-Object { -not ($e.Services -contains $_) }) -join ', '
            $status = if ($vmotionShares -and ($e.Services -contains 'vMotion' -or $allServices -contains 'vMotion')) {
                          "SHARED (vMotion + $($allServices -join '+'))"
                      } elseif ($e.Services -contains 'vMotion') {
                          'OK (vMotion isolated)'
                      } else {
                          "OK ($svcStr)"
                      }
            $rows += [pscustomobject]@{
                Host       = $h.Name
                Cluster    = if ($h.Parent) { "$($h.Parent.Name)" } else { '' }
                VMK        = $e.VMK
                IP         = $e.IP
                Subnet     = "$sub.0/24"
                Services   = $svcStr
                SharedWith = if ($sharedWith) { $sharedWith } else { '(none)' }
                Status     = $status
            }
        }
    }
    foreach ($r in $rows) { $r }
}

$TableFormat = @{
    Status = { param($v,$row) if ("$v" -match '^OK') { 'ok' } elseif ("$v" -match 'SHARED|NO ') { 'warn' } else { '' } }
}
