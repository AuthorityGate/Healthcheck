# Start of Settings
# End of Settings

$Title          = 'ESXi execInstalledOnly Disabled'
$Header         = "[count] host(s) with VMkernel.Boot.execInstalledOnly = FALSE (ransomware risk)"
$Comments       = "Reference: vSphere Security Configuration Guide. The VMkernel.Boot.execInstalledOnly boot-time setting, when TRUE, restricts execution to binaries delivered as part of a signed VIB. With it FALSE, an attacker who lands a script or ELF on the host (via SSH, exploited service, or compromised vCenter) can execute arbitrary code - the exact pattern used by ESXiArgs and follow-on ransomware families. Strongly recommended to be TRUE on every production host."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P1'
$Recommendation = "Per host: esxcli system settings kernel set -s execInstalledOnly -v TRUE  (requires reboot to take effect at the next boot). Or via vSphere Client: Host -> Configure -> Advanced System Settings -> VMkernel.Boot.execInstalledOnly = true. Confirm with esxcli system settings kernel list -o execInstalledOnly post-reboot."

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue)) {
    if ($h.ConnectionState -ne 'Connected') { continue }

    # Two values matter:
    #   Configured  - the value you set; takes effect at next boot.
    #   Runtime     - what the kernel is actually enforcing right now.
    # Both can drift independently. Read both and flag any host where either
    # one is FALSE.
    $configured = $null
    $runtime    = $null
    try {
        $esxcli = Get-EsxCli -V2 -VMHost $h -ErrorAction Stop
        $row = $esxcli.system.settings.kernel.list.Invoke(@{ option = 'execInstalledOnly' }) | Select-Object -First 1
        if ($row) {
            $configured = $row.Configured
            $runtime    = $row.Runtime
        }
    } catch {
        # Fall back to advanced settings - the legacy attribute name
        $adv = Get-AdvancedSetting -Entity $h -Name 'VMkernel.Boot.execInstalledOnly' -ErrorAction SilentlyContinue
        if ($adv) {
            $configured = [string]$adv.Value
            $runtime    = '(unknown via advanced settings)'
        }
    }

    # If we still couldn't read the setting, surface the host so it isn't
    # silently skipped.
    if ($null -eq $configured -and $null -eq $runtime) {
        [pscustomobject]@{
            Host       = $h.Name
            Cluster    = if ($h.Parent) { $h.Parent.Name } else { '' }
            Configured = '(unable to read)'
            Runtime    = '(unable to read)'
            Risk       = 'Cannot verify - investigate host management connectivity.'
        }
        continue
    }

    $cfgFalse = ($configured -eq $false) -or ($configured -match '^(false|no|0|FALSE|NO)$')
    $runFalse = ($runtime    -eq $false) -or ($runtime    -match '^(false|no|0|FALSE|NO)$')

    if ($cfgFalse -or $runFalse) {
        [pscustomobject]@{
            Host       = $h.Name
            Cluster    = if ($h.Parent) { $h.Parent.Name } else { '' }
            Configured = "$configured"
            Runtime    = "$runtime"
            Risk       = if ($runFalse) {
                'Currently allowing arbitrary binary execution (ransomware staging risk).'
            } else {
                'Configured FALSE for next boot - will lose protection at next reboot.'
            }
        }
    }
}

$TableFormat = @{
    Configured = { param($v,$row) if ($v -match 'false|no|0') { 'bad' } elseif ($v -match 'unable') { 'warn' } else { '' } }
    Runtime    = { param($v,$row) if ($v -match 'false|no|0') { 'bad' } elseif ($v -match 'unable|unknown') { 'warn' } else { '' } }
}
