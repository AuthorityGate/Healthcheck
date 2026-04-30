# Start of Settings
# End of Settings

$Title          = 'Imprivata OneSign Agent in Gold Images'
$Header         = "[count] gold image(s) with Imprivata Agent state assessment"
$Comments       = "Imprivata OneSign Agent installed in the master image enables tap-and-go (proximity card auth) and workflow SSO for healthcare workflows. Tier 1: detect via Horizon REST + plugin discovery (gold images named per the Horizon pool's parent_vm_path). Tier 2 (in-guest WinRM): verify Imprivata service installed + version + appliance bind."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'B0 Imprivata'
$Severity       = 'P3'
$Recommendation = "Imprivata Agent must be installed in master image (not delivered via App Volumes - kernel-level driver). Configure Imprivata Appliance URL in master before snapshot. Verify Agent runs in 'Enabled' state. Re-test on each master refresh."

if (-not $Global:VCConnected -or -not (Get-HVRestSession)) { return }

$cred = if (Test-Path Variable:Global:HVImageScanCredential) { $Global:HVImageScanCredential } else { $null }

# Discover gold images
$parents = New-Object System.Collections.Generic.HashSet[string]
foreach ($p in (Get-HVDesktopPool)) {
    foreach ($prop in 'provisioning_settings','instant_clone_engine_provisioning_settings') {
        $s = $p.$prop
        if ($s -and $s.parent_vm_path) {
            [void]$parents.Add(($s.parent_vm_path -split '/')[-1])
        }
    }
}
if ($parents.Count -eq 0) { return }

$probeBlock = {
    $r = @{}
    try {
        $reg = Get-ItemProperty 'HKLM:\SOFTWARE\Imprivata\OneSign' -ErrorAction Stop
        $r.OneSignVersion = $reg.Version
        $r.AgentVersion = $reg.AgentVersion
    } catch { $r.OneSignVersion = $null }
    try {
        $reg2 = Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Imprivata\OneSign' -ErrorAction Stop
        if (-not $r.OneSignVersion -and $reg2.Version) { $r.OneSignVersion = $reg2.Version }
    } catch { }
    try {
        $svc = Get-Service -Name 'ImprivataOneSignAgent' -ErrorAction Stop
        $r.ServiceStatus = $svc.Status
        $r.ServiceStartType = $svc.StartType
    } catch {
        try {
            $svc2 = Get-Service -DisplayName '*Imprivata*' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($svc2) { $r.ServiceStatus = $svc2.Status; $r.ServiceStartType = $svc2.StartType; $r.ServiceName = $svc2.Name }
        } catch { }
    }
    try {
        $appliance = Get-ItemProperty 'HKLM:\SOFTWARE\Imprivata\OneSign\Settings' -ErrorAction SilentlyContinue
        if ($appliance) { $r.ApplianceUrl = $appliance.ApplianceUrl }
    } catch { }
    return $r
}

foreach ($n in $parents) {
    $vm = Get-VM -Name $n -ErrorAction SilentlyContinue
    if (-not $vm) { continue }
    $vmIp = if ($vm.Guest -and $vm.Guest.IPAddress) { @($vm.Guest.IPAddress)[0] } else { '' }

    $row = [pscustomobject]@{
        ParentVM        = $vm.Name
        Cluster         = if ($vm.VMHost -and $vm.VMHost.Parent) { $vm.VMHost.Parent.Name } else { '' }
        GuestOS         = if ($vm.Guest -and $vm.Guest.OSFullName) { $vm.Guest.OSFullName } else { '' }
        Tier            = 'Tier1'
        ImprivataInstalled = '(unknown)'
        OneSignVersion  = ''
        ServiceStatus   = ''
        ApplianceUrl    = ''
        Note            = if (-not $cred) { 'Set $Global:HVImageScanCredential for Tier 2.' } else { '' }
    }

    if ($cred -and $vmIp) {
        try {
            $session = New-PSSession -ComputerName $vmIp -Credential $cred -ErrorAction Stop
            $g = Invoke-Command -Session $session -ScriptBlock $probeBlock
            Remove-PSSession $session -ErrorAction SilentlyContinue
            $row.Tier = 'Tier2'
            $row.ImprivataInstalled = if ($g.OneSignVersion) { 'Yes' } else { 'No' }
            $row.OneSignVersion = $g.OneSignVersion
            $row.ServiceStatus = $g.ServiceStatus
            $row.ApplianceUrl = $g.ApplianceUrl
        } catch {
            $row.Note = "WinRM probe failed: $($_.Exception.Message)"
        }
    }

    $row
}
