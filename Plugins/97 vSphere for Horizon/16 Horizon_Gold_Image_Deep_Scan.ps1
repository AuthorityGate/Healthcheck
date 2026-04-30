# Start of Settings

# Tier 2 (in-guest WinRM) probe runs only when a PSCredential is supplied
# via the global $Global:HVImageScanCredential. The runner / GUI sets this
# from the operator's credential prompt. Without it, we still emit Tier 1
# (vCenter-side) findings.
$ScanTimeoutSeconds = 60

# End of Settings

$Title          = 'Horizon Gold Desktop Image Deep Scan'
$Header         = "[count] anti-pattern(s) across desktop pool gold images"
$Comments       = "Comprehensive introspection of every parent / gold image referenced by an Instant Clone or Linked Clone desktop pool. Tier 1 reads VM hardware + Tools data from vCenter. Tier 2 (when a Windows credential is available) walks the guest registry for OS patch state, BitLocker state, FSLogix configuration, Horizon/DEM/AppVolumes Agent versions, Defender exclusions, and consumer-experience scheduled tasks. Each anti-pattern lands as one report row naming the machine + the rule + the fix."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '97 vSphere for Horizon'
$Severity       = 'P2'
$Recommendation = "Treat each gold image as code: each row in the report is a Pull Request to the master. Apply the Fix column, sysprep generalize where applicable, re-snapshot, and recompose the dependent pools."

# vCenter is required to scan the VMs themselves. Horizon REST is optional -
# without it we still scan whatever the operator picked manually via the
# "Pick Gold Images..." dialog, even in vCenter-only mode.
if (-not $Global:VCConnected) { return }

# Load shared introspection module.
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) -ChildPath '..\Modules\GuestImageScan.psm1'
if (-not (Test-Path $modulePath)) {
    [pscustomobject]@{
        Machine = '(plugin error)'
        Rule    = 'GuestImageScan.psm1 not found'
        Detail  = "Expected at $modulePath"
        Fix     = 'Reinstall HealthCheckPS1.'
    }
    return
}
Import-Module $modulePath -Force

# Discover desktop pool parent VMs (Horizon REST) AND merge with the
# manually-picked list from the GUI. Either source alone is valid.
$parents = New-Object System.Collections.Generic.HashSet[string]
if (Get-HVRestSession) {
    foreach ($p in (Get-HVDesktopPool)) {
        foreach ($prop in 'provisioning_settings','instant_clone_engine_provisioning_settings') {
            $s = $p.$prop
            if ($s -and $s.parent_vm_path) {
                [void]$parents.Add(($s.parent_vm_path -split '/')[-1])
            }
        }
    }
}
if (Test-Path Variable:Global:HVManualGoldImageList) {
    foreach ($n in @($Global:HVManualGoldImageList)) {
        if ($n) { [void]$parents.Add($n) }
    }
}
if ($parents.Count -eq 0) {
    # Make the silence loud: tell the operator why no scan output appeared.
    $reason = if (Get-HVRestSession) {
        "Horizon REST is connected but no desktop pools reference a parent VM. Pick gold images manually via the 'Pick Gold Images...' dialog, then re-run."
    } else {
        "No gold images selected. Use the 'Pick Gold Images...' dialog on the main screen, check the parent / template VMs, then click 'Save Selected'. The selection persists across runs."
    }
    [pscustomobject]@{
        Machine  = '(no targets)'
        Role     = 'GoldDesktop'
        Severity = 'Info'
        Rule     = 'No gold images selected for deep scan'
        Detail   = $reason
        Fix      = "Open 'Pick Gold Images...' on the main GUI, check Win11/Win10/RDSH/AV-packaging parents, click Save Selected, then re-run the health check."
    }
    return
}

$globalCred = if (Test-Path Variable:Global:HVImageScanCredential) { $Global:HVImageScanCredential } else { $null }
$perVmCreds = if (Test-Path Variable:Global:HVManualGoldImageCreds) { $Global:HVManualGoldImageCreds } else { @{} }

# Per-VM credential resolver: prefer the per-VM profile mapping, fall back
# to the global Deep-Scan credential. Names hold a profile name; we
# decrypt via the CredentialProfiles module, cached so each profile is
# decrypted at most once per run.
$resolvedCache = @{}
function Resolve-ScanCred($vmName) {
    if ($perVmCreds -and $perVmCreds.ContainsKey($vmName)) {
        $profileName = $perVmCreds[$vmName]
        if ($resolvedCache.ContainsKey($profileName)) { return $resolvedCache[$profileName] }
        try {
            $c = Get-AGCredentialAsPSCredential -Name $profileName
            $resolvedCache[$profileName] = $c
            return $c
        } catch {
            Write-Warning "Per-VM cred '$profileName' for VM '$vmName' could not be decrypted: $($_.Exception.Message). Falling back to global Deep-Scan cred."
        }
    }
    return $globalCred
}

function _inv {
    # Helper: emit one inventory row per attribute. Keeps the plugin output
    # shape consistent with the findings rows so the table renders cleanly,
    # and so the JSON sidecar carries every probed value for downstream
    # enrichment (HealthCheckAGI consumes these rows).
    param([string]$Machine, [string]$Role, [string]$Attribute, [string]$Value, [string]$Source = 'Probe')
    [pscustomobject]@{
        Machine  = $Machine
        Role     = $Role
        Severity = 'Info'
        Rule     = $Attribute
        Detail   = $Value
        Fix      = "[$Source]"
    }
}

function _fmtList {
    param($v, [int]$Max = 0)
    if (-not $v) { return '(none)' }
    $arr = @($v)
    if ($arr.Count -eq 0) { return '(none)' }
    if ($Max -gt 0 -and $arr.Count -gt $Max) {
        return ($arr[0..($Max-1)] -join '; ') + " ... (+$($arr.Count - $Max) more)"
    }
    return ($arr -join '; ')
}

foreach ($n in $parents) {
    $vm = Get-VM -Name $n -ErrorAction SilentlyContinue
    if (-not $vm) {
        [pscustomobject]@{
            Machine = $n; Role = 'GoldDesktop'; Severity = 'P2'
            Rule    = 'Parent VM not found in vCenter'
            Detail  = "Horizon pool references parent '$n' but vCenter does not see it."
            Fix     = 'Verify VM still exists; update pool or restore VM.'
        }
        continue
    }
    $cred = Resolve-ScanCred -vmName $n
    $scan = Get-GuestImageScan -Vm $vm -Role 'GoldDesktop' -Credential $cred -WinRmTimeoutSeconds $ScanTimeoutSeconds

    $hw   = $scan.VmHardware
    $g    = $scan.Guest
    $mach = $vm.Name
    $role = 'GoldDesktop'

    # ---- Scan summary header row -------------------------------------------
    _inv $mach $role 'Scan Tier' "$($scan.Tier)$(if ($scan.Tier -eq 'Tier1') { ' - in-guest probe NOT run; supply credential or check WinRM reachability for full data' })" 'Summary'

    # ---- VM hardware (Tier 1, vCenter-side - always present) ---------------
    if ($hw) {
        _inv $mach $role 'vCPU'                 ([string]$hw.vCpu)             'VmHardware'
        _inv $mach $role 'RAM (GB)'             ([string]$hw.RamGB)            'VmHardware'
        _inv $mach $role 'Hardware Version'     ([string]$hw.HardwareVer)      'VmHardware'
        _inv $mach $role 'Firmware'             ([string]$hw.Firmware)         'VmHardware'
        _inv $mach $role 'Secure Boot'          ([string]$hw.SecureBoot)       'VmHardware'
        _inv $mach $role 'vTPM Present'         ([string]$hw.vTPM)             'VmHardware'
        _inv $mach $role 'NumNetworkAdapters'   ([string]$hw.NumNics)          'VmHardware'
        _inv $mach $role 'NumDisks'             ([string]$hw.NumDisks)         'VmHardware'
        _inv $mach $role 'Power State'          ([string]$hw.PowerState)       'VmHardware'
        _inv $mach $role 'Guest OS (vCenter)'   ([string]$hw.GuestOS)          'VmHardware'
        _inv $mach $role 'IP Address (vCenter)' ([string]$hw.IPAddress)        'VmHardware'
        _inv $mach $role 'Cluster'              ([string]$hw.Cluster)          'VmHardware'
        _inv $mach $role 'Datastore'            (_fmtList $hw.Datastores)      'VmHardware'
        _inv $mach $role 'Snapshot Count'       ([string]$hw.SnapshotCount)    'VmHardware'
        _inv $mach $role 'CD Drive Connected'   ([string]$hw.CdConnected)      'VmHardware'
    }

    # ---- Tier 2 in-guest probe (only present when WinRM/VMTools succeeded) -
    if ($g) {
        # Identity & OS
        _inv $mach $role 'Hostname'             ([string]$g.HostName)          'Guest'
        _inv $mach $role 'OS Caption'           ([string]$g.OsCaption)         'Guest'
        _inv $mach $role 'OS Version'           ([string]$g.OsVersion)         'Guest'
        _inv $mach $role 'OS Build / UBR'       "$($g.OsBuildNumber).$($g.UBR)" 'Guest'
        _inv $mach $role 'OS Display Version'   ([string]$g.DisplayVersion)    'Guest'
        _inv $mach $role 'OS Edition'           ([string]$g.EditionID)         'Guest'
        _inv $mach $role 'OS Architecture'      ([string]$g.OsArchitecture)    'Guest'
        _inv $mach $role 'Last Boot'            ([string]$g.OsLastBoot)        'Guest'
        _inv $mach $role 'Domain Joined'        ([string]$g.PartOfDomain)      'Guest'
        _inv $mach $role 'Domain / Workgroup'   ([string]$g.Domain)            'Guest'

        # Patching
        $hfDate = if ($g.LastHotfixInstalledOn) { (Get-Date $g.LastHotfixInstalledOn -Format 'yyyy-MM-dd') } else { '' }
        $hfAge  = if ($g.LastHotfixInstalledOn) { [int]((Get-Date) - [datetime]$g.LastHotfixInstalledOn).TotalDays } else { '' }
        _inv $mach $role 'Last Hotfix'          "$($g.LastHotfixId) ($hfDate, ${hfAge}d ago)" 'Guest'

        # Agents - the consulting questions live here
        _inv $mach $role 'VMware Tools'         ([string]$g.VMwareToolsVersion) 'Agent'
        _inv $mach $role 'Horizon Agent'        ($(if ($g.HorizonAgentVersion) { "$($g.HorizonAgentVersion) (build $($g.HorizonAgentBuild))" } else { '(not installed)' })) 'Agent'
        _inv $mach $role 'DEM Agent'            ($(if ($g.DEMVersion) { [string]$g.DEMVersion } else { '(not installed)' })) 'Agent'
        _inv $mach $role 'AppVolumes Agent'     ($(if ($g.AppVolumesAgentVersion) { "$($g.AppVolumesAgentVersion) [Mode=$($g.AppVolumesAgentMode)]" } else { '(not installed)' })) 'Agent'

        # Profile management
        _inv $mach $role 'FSLogix Enabled'         ([string]$g.FSLogixEnabled)               'FSLogix'
        _inv $mach $role 'FSLogix VHD Locations'   (_fmtList $g.FSLogixVHDLocations)         'FSLogix'

        # Anti-virus / hardening
        _inv $mach $role 'Defender Real-time'      ([string]$g.DefenderRealtime)             'Defender'
        _inv $mach $role 'Defender Path Excl.'     "$(@($g.DefenderExclusionPath).Count) entries" 'Defender'
        _inv $mach $role 'Defender Process Excl.'  "$(@($g.DefenderExclusionProcess).Count) entries" 'Defender'
        _inv $mach $role 'Defender Ext. Excl.'     "$(@($g.DefenderExclusionExtension).Count) entries" 'Defender'

        # Per-exclusion detail rows so consultants and AGI both see the actual
        # values (not just counts). One row per exclusion entry.
        foreach ($p in @($g.DefenderExclusionPath))      { _inv $mach $role 'Defender Excl. Path'      ([string]$p) 'Defender' }
        foreach ($p in @($g.DefenderExclusionProcess))   { _inv $mach $role 'Defender Excl. Process'   ([string]$p) 'Defender' }
        foreach ($p in @($g.DefenderExclusionExtension)) { _inv $mach $role 'Defender Excl. Extension' ([string]$p) 'Defender' }

        # Encryption / RDP
        $blState = if ($g.BitLockerProtectionStatus -eq 1) { 'ON' } elseif ($g.BitLockerProtectionStatus -eq 0) { 'off' } else { '(n/a)' }
        _inv $mach $role 'BitLocker C:'           $blState                                    'Hardening'
        _inv $mach $role 'RDP'                    ($(if ($g.RdpDenyTSConnections) { 'disabled' } else { 'enabled' })) 'Hardening'
        _inv $mach $role 'Sysprep SkipRearm'      ([string]$g.SkipRearm)                      'Hardening'

        # Software / services
        _inv $mach $role 'Services Running'       ([string]$g.ServicesRunning)                'Inventory'
        _inv $mach $role 'Installed Software Count' ([string]$g.InstalledSoftwareCount)       'Inventory'

        # Per-software detail rows. Probe captures the FULL list now, not a
        # sample - downstream tools (HealthCheckAGI) compare images by
        # diffing these rows.
        $swList = if ($g.InstalledSoftware) { @($g.InstalledSoftware) } else { @($g.InstalledSoftwareSample) }
        foreach ($sw in $swList) {
            $name = if ($sw.DisplayName)    { [string]$sw.DisplayName }    else { '?' }
            $ver  = if ($sw.DisplayVersion) { [string]$sw.DisplayVersion } else { '' }
            $pub  = if ($sw.Publisher)      { [string]$sw.Publisher }      else { '' }
            _inv $mach $role 'Installed Software' "$name | $ver | $pub" 'Software'
        }

        # ---- Comprehensive expansion: surface every captured field ----
        # System / chassis
        if ($g.System) {
            $s = $g.System
            _inv $mach $role 'System Manufacturer' ([string]$s.Manufacturer)    'System'
            _inv $mach $role 'System Model'        ([string]$s.Model)           'System'
            _inv $mach $role 'System Serial'       ([string]$s.SerialNumber)    'System'
            _inv $mach $role 'BIOS Vendor'         ([string]$s.BiosVendor)      'System'
            _inv $mach $role 'BIOS Version'        ([string]$s.BiosVersion)     'System'
            _inv $mach $role 'BIOS Release Date'   ([string]$s.BiosReleaseDate) 'System'
            _inv $mach $role 'System UUID'         ([string]$s.UUID)            'System'
        }
        # CPUs
        foreach ($cpu in @($g.CPUs)) {
            _inv $mach $role 'CPU' "$($cpu.Name) | $($cpu.NumberOfCores)c/$($cpu.NumberOfLogicalProcessors)t @ $($cpu.MaxClockSpeed)MHz" 'CPU'
        }
        # Memory modules
        foreach ($m in @($g.MemoryModules)) {
            _inv $mach $role 'Memory Module' "$($m.DeviceLocator) | $($m.CapacityGB)GB | $($m.Manufacturer) $($m.PartNumber) | $($m.Speed)MHz" 'Memory'
        }
        # Logical disks
        foreach ($d in @($g.LogicalDisks)) {
            _inv $mach $role 'Logical Disk' "$($d.DeviceID) | $($d.FileSystem) | $($d.SizeGB)GB | Free=$($d.FreeGB)GB ($($d.FreePct)%) | '$($d.VolumeName)'" 'Disk'
        }
        # Physical disks
        foreach ($d in @($g.PhysicalDisks)) {
            _inv $mach $role 'Physical Disk' "$($d.Model) | $($d.InterfaceType) | $($d.SizeGB)GB | $($d.MediaType) | SN=$($d.SerialNumber)" 'Disk'
        }
        # Network adapters (IP-bound)
        foreach ($n in @($g.NetworkAdapters)) {
            $ips = @($n.IPAddress) -join ','
            $gws = @($n.DefaultIPGateway) -join ','
            $dns = @($n.DNSServerSearchOrder) -join ','
            _inv $mach $role 'Network Adapter' "$($n.Description) | MAC=$($n.MACAddress) | IP=$ips | GW=$gws | DNS=$dns | DHCP=$($n.DHCPEnabled)" 'Network'
        }
        # Hosts file entries
        foreach ($h in @($g.HostsFile)) { _inv $mach $role 'Hosts File Entry' ([string]$h) 'Network' }
        # SMB shares offered
        foreach ($sh in @($g.Shares)) { _inv $mach $role 'SMB Share Offered' "$($sh.Name) -> $($sh.Path) | $($sh.Description)" 'Network' }
        # Mapped drives
        foreach ($md in @($g.MappedDrives)) { _inv $mach $role 'Mapped Drive' "$($md.LocalName) -> $($md.RemoteName) | User=$($md.UserName)" 'Network' }
        # Local users
        foreach ($u in @($g.LocalUsers)) {
            _inv $mach $role 'Local User' "$($u.Name) | Enabled=$($u.Enabled) | LastLogon=$($u.LastLogon) | $($u.Description)" 'Identity'
        }
        # Local groups + members
        foreach ($grp in @($g.LocalGroups)) {
            $memberStr = if ($grp.Members) { (@($grp.Members) | ForEach-Object { $_.Name }) -join ', ' } else { '(empty)' }
            _inv $mach $role 'Local Group' "$($grp.Name) | $($grp.Description) | Members=$memberStr" 'Identity'
        }
        # All running services (full inventory)
        foreach ($svc in @($g.Services)) {
            _inv $mach $role 'Service' "$($svc.Name) | $($svc.DisplayName) | $($svc.Status) | $($svc.StartType)" 'Service'
        }
        # All scheduled tasks (full inventory)
        foreach ($t in @($g.ScheduledTasksAll)) {
            _inv $mach $role 'Scheduled Task' "$($t.TaskPath)$($t.TaskName) | State=$($t.State) | Author=$($t.Author) | LastRun=$($t.LastRunTime)" 'ScheduledTask'
        }
        # Printers
        foreach ($pr in @($g.Printers)) {
            _inv $mach $role 'Printer' "$($pr.Name) | Port=$($pr.PortName) | Driver=$($pr.DriverName) | Local=$($pr.Local) | Default=$($pr.Default)" 'Printer'
        }
        # Windows roles/features (Server)
        foreach ($f in @($g.WindowsFeaturesInstalled)) {
            _inv $mach $role 'Windows Feature' "$($f.Name) | $($f.DisplayName)" 'Feature'
        }
        # Optional features (Client)
        foreach ($f in @($g.OptionalFeaturesEnabled)) {
            _inv $mach $role 'Optional Feature' ([string]$f.FeatureName) 'Feature'
        }
        # Capabilities
        foreach ($f in @($g.WindowsCapabilitiesInstalled)) {
            _inv $mach $role 'Windows Capability' ([string]$f.Name) 'Feature'
        }
        # Startup programs
        foreach ($sp in @($g.StartupPrograms)) {
            _inv $mach $role 'Startup Program' "$($sp.Source) | $($sp.Name) -> $($sp.Command)" 'Startup'
        }
        # Office Click-to-Run
        if ($g.Office) {
            $o = $g.Office
            _inv $mach $role 'Office Channel'  ([string]$o.UpdateChannel) 'Office'
            _inv $mach $role 'Office Version'  ([string]$o.VersionToReport) 'Office'
            _inv $mach $role 'Office Products' ([string]$o.ProductReleaseIds) 'Office'
            _inv $mach $role 'Office SharedComputerLicensing' ([string]$o.SharedComputerLicensing) 'Office'
        }
        # PowerShell + .NET
        if ($g.PowerShellVersion) { _inv $mach $role 'PowerShell Version' "$($g.PowerShellVersion) ($($g.PowerShellEdition))" 'Runtime' }
        foreach ($n in @($g.DotNetVersions)) {
            _inv $mach $role '.NET Version' "$($n.Key) | $($n.Version) | Release=$($n.Release)" 'Runtime'
        }
        # Hotfix history
        foreach ($hf in @($g.HotfixHistory)) {
            _inv $mach $role 'Hotfix' "$($hf.HotFixID) | $($hf.InstalledOn) | $($hf.Description)" 'Patch'
        }
        # Power plans
        foreach ($pp in @($g.PowerPlans)) {
            _inv $mach $role 'Power Plan' "$($pp.ElementName) | Active=$($pp.IsActive)" 'Power'
        }
        # TPM
        if ($g.Tpm) {
            $t = $g.Tpm
            _inv $mach $role 'Guest TPM' "Activated=$($t.IsActivated) | Enabled=$($t.IsEnabled) | Owned=$($t.IsOwned) | Spec=$($t.SpecVersion) | Mfg=$($t.ManufacturerVersion)" 'TPM'
        }
        # Antivirus products
        foreach ($av in @($g.AntivirusProducts)) {
            _inv $mach $role 'AV Product' "$($av.displayName) | productState=0x$('{0:X}' -f [int]$av.productState) | $($av.pathToSignedProductExe)" 'AV'
        }
        # Pending reboot
        if ($null -ne $g.PendingReboot) {
            _inv $mach $role 'Pending Reboot' "$($g.PendingReboot) | Reasons=$((@($g.PendingRebootReasons)) -join ', ')" 'Reboot'
        }
        # Time zone / locale / time source
        if ($g.TimeZone)      { _inv $mach $role 'Time Zone'      ([string]$g.TimeZone)      'Locale' }
        if ($g.Culture)       { _inv $mach $role 'Culture'        ([string]$g.Culture)       'Locale' }
        if ($g.W32TimeSource) { _inv $mach $role 'NTP Source'     ([string]$g.W32TimeSource) 'Time' }
        # Event log size config
        foreach ($el in @($g.EventLogConfig)) {
            _inv $mach $role 'Event Log' "$($el.LogfileName) | MaxMB=$($el.MaxSizeMB) | UsedMB=$($el.UsedSizeMB) | Records=$($el.NumberOfRecords) | Policy=$($el.OverwritePolicy)" 'EventLog'
        }
        # User profiles (FSLogix-relevant)
        foreach ($up in @($g.UserProfiles)) {
            _inv $mach $role 'User Profile' "$($up.LocalPath) | SID=$($up.SID) | Loaded=$($up.Loaded) | LastUse=$($up.LastUseTime)" 'Profile'
        }
        # Drivers (3rd-party only)
        foreach ($drv in @($g.Drivers)) {
            _inv $mach $role 'Driver (3rd-party)' "$($drv.DeviceName) | $($drv.DriverProviderName) | v$($drv.DriverVersion) | $($drv.DeviceClass)" 'Driver'
        }

        # In-guest probe diagnostics (only if Tier 2 attempted but partially failed)
        if ($g.OsError)      { _inv $mach $role 'Probe OS Error'      ([string]$g.OsError)      'Diagnostic' }
        if ($g.WinRmError)   { _inv $mach $role 'Probe WinRM Error'   ([string]$g.WinRmError)   'Diagnostic' }
        if ($g.VMToolsError) { _inv $mach $role 'Probe VMTools Error' ([string]$g.VMToolsError) 'Diagnostic' }
    }

    # ---- Per-VM JSON sidecar -------------------------------------
    # Write the entire structured probe object as a stand-alone JSON file in
    # the report output folder. This is the consultant-grade artifact:
    # a per-image as-built snapshot consumable by HealthCheckAGI, diff tools,
    # CMDB import scripts, etc. The main HTML report still gets the
    # human-readable inventory rows above.
    if ($Global:HVOutputPath) {
        try {
            $stamp     = (Get-Date).ToString('yyyyMMdd-HHmmss')
            $safeName  = ($vm.Name -replace '[^A-Za-z0-9_.-]','_')
            $dumpFile  = Join-Path $Global:HVOutputPath "GoldImageDump-$safeName-$stamp.json"
            $dumpDoc   = [pscustomobject]@{
                Schema       = 'GoldImageDump/1'
                Generated    = (Get-Date).ToString('o')
                Machine      = $vm.Name
                Role         = $role
                ScanTier     = $scan.Tier
                VmHardware   = $hw
                Guest        = $g
                Findings     = $scan.Findings
            }
            $dumpDoc | ConvertTo-Json -Depth 16 | Out-File -FilePath $dumpFile -Encoding utf8
            _inv $mach $role 'Per-VM JSON Dump' $dumpFile 'Export'
        } catch {
            _inv $mach $role 'Per-VM JSON Dump' "FAILED: $($_.Exception.Message)" 'Export'
        }
    }

    # ---- Findings (rule-evaluated; severity-weighted) ----------------------
    foreach ($f in $scan.Findings) { $f }
}

$TableFormat = @{
    Severity = { param($v,$row) if ($v -eq 'P1') { 'bad' } elseif ($v -eq 'P2') { 'warn' } else { '' } }
}
