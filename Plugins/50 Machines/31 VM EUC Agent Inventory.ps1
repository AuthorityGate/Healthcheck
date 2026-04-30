# Start of Settings
if (-not $Global:VMAgentProbeMax) { $Global:VMAgentProbeMax = 50 }
# End of Settings

$Title          = "VM EUC Agent Inventory (Tier 2)"
$Header         = "[count] VM(s) probed for Horizon / AppVol / DEM / FSLogix agents"
$Comments       = @"
Reads each sampled VM's installed-software registry to discover the EUC agent stack. Per-VM:
- Horizon Agent version + install path
- App Volumes Agent
- VMware Dynamic Environment Manager (FlexEngine) Agent
- FSLogix Apps Agent
- Imprivata OneSign Agent (if installed)

Cross-version drift = the most common 'why does this user's logon look different' root cause. A pool with mixed agent versions usually means someone updated the parent VM but didn't push the new image.
"@
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "50 Machines"
$Severity       = "P3"
$Recommendation = "Same pool / same agent version is the goal. Mixed agent versions in one pool = re-push parent. Horizon Agents older than 8.6 lose support. AppVol Agents older than 4.x cannot mount packaged volumes from a 4.x manager."

if (-not (Get-HVRestSession)) { return }
$cred = $Global:HVImageScanCredential
if (-not $cred) {
    [pscustomobject]@{ Note = 'No Tier-2 credential. Click "Set Deep-Scan Creds..." on the GUI toolbar.' }
    return
}

$pools = @(Get-HVDesktopPool)
$allMachines = @(Get-HVMachine)
$sample = New-Object System.Collections.ArrayList
foreach ($pool in $pools) {
    if (-not $pool.id) { continue }
    $first = $allMachines | Where-Object { $_.desktop_pool_id -eq $pool.id -and $_.dns_name } | Select-Object -First 1
    if ($first) { [void]$sample.Add($first) }
    if ($sample.Count -ge $Global:VMAgentProbeMax) { break }
}
if ($sample.Count -eq 0) {
    [pscustomobject]@{ Note = 'No VMs with a dns_name to probe.' }
    return
}

# PowerShell 5.1-compatible probe block: registry-only software discovery,
# no Win32_Product (slow + side effects), no null-coalescing.
$probeBlock = {
    function Find-Product {
        param([string]$Match)
        foreach ($p in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )) {
            $hit = Get-ItemProperty $p -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like "*$Match*" } | Select-Object -First 1
            if ($hit) { return "$($hit.DisplayName) $($hit.DisplayVersion)" }
        }
        return ''
    }
    $hzn = Find-Product 'Horizon Agent'
    if (-not $hzn) { $hzn = Find-Product 'View Agent' }
    if (-not $hzn) { $hzn = Find-Product 'Omnissa Horizon Agent' }
    $av = Find-Product 'App Volumes Agent'
    if (-not $av) { $av = Find-Product 'AppVolumes Agent' }
    $dem = Find-Product 'Dynamic Environment Manager'
    if (-not $dem) { $dem = Find-Product 'FlexEngine' }
    $fsl = Find-Product 'FSLogix Apps'
    $imp = Find-Product 'Imprivata OneSign'
    $vmt = Find-Product 'VMware Tools'

    [pscustomobject]@{
        HorizonAgent   = $hzn
        AppVolAgent    = $av
        DEMAgent       = $dem
        FSLogixAgent   = $fsl
        ImprivataAgent = $imp
        VMwareTools    = $vmt
    }
}

foreach ($m in $sample) {
    $tcp = $false
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect($m.dns_name, 5985, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(2500)) { $c.EndConnect($iar); $tcp = $true }
        $c.Close()
    } catch { }
    if (-not $tcp) {
        [pscustomobject]@{ VM=$m.dns_name; Pool=$m.desktop_pool_id; HorizonAgent='(WinRM unreachable)'; AppVolAgent=''; DEMAgent=''; FSLogixAgent=''; ImprivataAgent=''; VMwareTools='' }
        continue
    }
    try {
        $session = New-PSSession -ComputerName $m.dns_name -Credential $cred -ErrorAction Stop
        $r = Invoke-Command -Session $session -ScriptBlock $probeBlock -ErrorAction Stop
        Remove-PSSession $session -ErrorAction SilentlyContinue
        [pscustomobject]@{
            VM             = $m.dns_name
            Pool           = $m.desktop_pool_id
            HorizonAgent   = $r.HorizonAgent
            AppVolAgent    = $r.AppVolAgent
            DEMAgent       = $r.DEMAgent
            FSLogixAgent   = $r.FSLogixAgent
            ImprivataAgent = $r.ImprivataAgent
            VMwareTools    = $r.VMwareTools
        }
    } catch {
        [pscustomobject]@{ VM=$m.dns_name; Pool=$m.desktop_pool_id; HorizonAgent='(probe failed)'; AppVolAgent=''; DEMAgent=''; FSLogixAgent=''; ImprivataAgent=''; VMwareTools=''; Note=$_.Exception.Message.Substring(0,[Math]::Min(100,$_.Exception.Message.Length)) }
    }
}
