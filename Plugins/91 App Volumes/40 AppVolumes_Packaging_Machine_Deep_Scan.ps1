# Start of Settings

# Optional: a comma-separated list (or array) of VM names you maintain as
# packaging / capture VMs. If supplied via $Global:AVPackagingVmHints we
# use that as the discovery seed in addition to AV-side detection.
# End of Settings

$Title          = 'App Volumes Packaging Machine Deep Scan'
$Header         = "[count] anti-pattern(s) across App Volumes packaging / capture VMs"
$Comments       = "Comprehensive deep scan of every VM identified as an App Volumes capture / provisioning machine. Discovery: queries the AV /cv_api/machines endpoint for entries whose agent_mode indicates ProvisioningMode, plus optional admin-supplied hints via Global:AVPackagingVmHints. Per machine: validates the AV Agent runs in ProvisioningMode, the OS matches the runtime fleet's OS, hardware is minimal (capture VMs are throwaway), and no production-only software is installed (Office365 etc. should be packaged INTO an AV volume, not baked into the capture VM)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'P2'
$Recommendation = "Treat the packaging VM as a clean-room. Each row of findings is something to reset: AppVolumes Agent in wrong mode, OS-version drift vs the runtime pool, bloated software baseline. Reset the master capture VM to a known-good baseline + Agent in ProvisioningMode, and recapture any volumes packaged from a contaminated state."

if (-not $Global:VCConnected -or -not (Get-AVRestSession)) { return }

$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) -ChildPath '..\Modules\GuestImageScan.psm1'
if (-not (Test-Path $modulePath)) {
    [pscustomobject]@{ Machine='(plugin error)'; Rule='GuestImageScan.psm1 not found'; Detail="Expected at $modulePath"; Fix='Reinstall HealthCheckPS1.' }
    return
}
Import-Module $modulePath -Force

# 1. Discovery via AV REST.
$candidates = New-Object System.Collections.Generic.HashSet[string]
try {
    $m = Get-AVMachine
    foreach ($mc in @($m.machines)) {
        # Field names vary across AV versions; check the common ones for
        # "this is a provisioning / capture VM".
        $isProv = $false
        foreach ($field in 'agent_mode','machine_state','machine_type','status') {
            $v = $mc.$field
            if ($v -and ($v -match 'Provision|Capture|Packaging')) { $isProv = $true }
        }
        if ($isProv) {
            $name = if ($mc.computer_name) { $mc.computer_name } elseif ($mc.name) { $mc.name } elseif ($mc.hostname) { $mc.hostname }
            if ($name) { [void]$candidates.Add(($name -split '\.')[0]) }
        }
    }
} catch { }

# 2. Operator hints
if (Test-Path Variable:Global:AVPackagingVmHints) {
    foreach ($h in @($Global:AVPackagingVmHints)) {
        if ($h) { [void]$candidates.Add($h) }
    }
}

if ($candidates.Count -eq 0) {
    [pscustomobject]@{
        Machine  = '(no packaging VMs identified)'
        Role     = 'AppVolumesPackaging'
        Severity = 'Info'
        Rule     = 'No discovery hits'
        Detail   = "AV /cv_api/machines returned no entries with ProvisioningMode-style agent_mode, and Global:AVPackagingVmHints not set."
        Fix      = 'Set $Global:AVPackagingVmHints = @(\"pkg-vm-01\",\"capture-vm-02\") in the runner OR ensure capture VMs register with AV Manager in ProvisioningMode.'
    }
    return
}

$cred = if (Test-Path Variable:Global:HVImageScanCredential) { $Global:HVImageScanCredential } else { $null }

foreach ($n in $candidates) {
    $vm = Get-VM -Name $n -ErrorAction SilentlyContinue
    if (-not $vm) {
        # Try fuzzy: VM may include domain suffix or differ by case
        $vm = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $n -or $_.Name -ilike "$n*" } | Select-Object -First 1
    }
    if (-not $vm) {
        [pscustomobject]@{ Machine=$n; Role='AppVolumesPackaging'; Severity='P3'; Rule='Capture VM not found in vCenter'; Detail="AV references '$n' but no matching vCenter VM."; Fix='Verify the VM still exists; update AV registration if renamed/decommissioned.' }
        continue
    }
    $scan = Get-GuestImageScan -Vm $vm -Role 'AppVolumesPackaging' -Credential $cred -WinRmTimeoutSeconds 60

    [pscustomobject]@{
        Machine  = $vm.Name
        Role     = 'AppVolumesPackaging'
        Severity = 'Info'
        Rule     = "Scanned at $($scan.Tier)"
        Detail   = "vCPU=$($scan.VmHardware.vCpu) RAM=$($scan.VmHardware.RamGB)GB OS='$($scan.VmHardware.GuestOS)' AgentMode=$($scan.Guest.AppVolumesAgentMode) IP=$($scan.VmHardware.IPAddress)"
        Fix      = if ($scan.Tier -eq 'Tier1') { 'Supply PSCredential via $Global:HVImageScanCredential and confirm WinRM reachable for Tier 2.' } else { 'No action - inventory only.' }
    }
    foreach ($f in $scan.Findings) { $f }

    # Tier 2 / role-specific extra rule: large installed-software footprint
    # on a capture VM means apps are being baked-in instead of captured.
    if ($scan.Tier -eq 'Tier2' -and $scan.Guest -and $scan.Guest.InstalledSoftware) {
        $count = @($scan.Guest.InstalledSoftware).Count
        if ($count -gt 25) {
            [pscustomobject]@{
                Machine  = $vm.Name
                Role     = 'AppVolumesPackaging'
                Severity = 'P2'
                Rule     = 'Capture VM has bloated software footprint'
                Detail   = "$count installed-software entries detected. Capture VMs should be a minimal clean Windows baseline; apps belong INSIDE captured AV volumes, not pre-installed on the capture VM."
                Fix      = 'Rebuild the capture VM from a clean OS baseline + AV Agent in ProvisioningMode + nothing else. Move all baked-in apps into AV volumes.'
            }
        }
    }
}

$TableFormat = @{
    Severity = { param($v,$row) if ($v -eq 'P1') { 'bad' } elseif ($v -eq 'P2') { 'warn' } else { '' } }
}
