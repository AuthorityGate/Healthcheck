# Start of Settings

# Maximum vCPUs that make sense for a typical Horizon desktop parent.
# Knowledge workers: 2-4 vCPU. Power user / CAD: 4-8. Anything > 8 on a
# generic pool is almost certainly mis-sized.
$MaxParentVCpu = 8

# Maximum RAM in GB that makes sense for a typical Horizon desktop parent.
# Knowledge workers: 4-8 GB. Power user / CAD: 16-32 GB. Anything > 32 GB
# on a generic pool is almost certainly the wrong template - someone is
# trying to use a server VM as a desktop image. The 128 GB case is
# definitely an outlier worth flagging.
$MaxParentRamGB = 32

# Anti-patterns we look for, one row per parent + per offense.
# End of Settings

$Title          = 'Horizon Parent VM Configuration Audit'
$Header         = '[count] anti-pattern(s) found across Horizon parent / gold VMs'
$Comments       = "Audits every parent VM referenced by a Horizon pool against the Horizon best-practice checklist: right-sizing, paravirtual SCSI + VMXNET3, no legacy devices, vTPM and Secure Boot for Win11 (with the Win11-specific guest hygiene rules), no VM-level encryption applied to the parent, no extra snapshots beyond the published one, and Tools time-sync disabled. Each row names the parent + the specific issue + the fix."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '97 vSphere for Horizon'
$Severity       = 'P2'
$Recommendation = "Treat the parent VM as a 'minimum viable desktop' template: prune devices, right-size CPU/RAM, generalize via sysprep before snapshot, and never enable BitLocker / VM Encryption on the parent (sealed keys do not fork to Instant Clones). Re-take the snapshot and re-publish the image after each fix."

if (-not $Global:VCConnected) { return }

# 1. Build the set of parent VM names: Horizon REST auto-discovery (when
# connected) + manual gold-image list from the picker. Either source alone
# is valid - the audit runs against whatever VMs are in scope.
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
if ($parents.Count -eq 0) { return }

foreach ($n in $parents) {
    $vm = Get-VM -Name $n -ErrorAction SilentlyContinue
    if (-not $vm) { continue }

    $cfg     = $vm.ExtensionData.Config
    $devs    = $cfg.Hardware.Device
    $os      = if ($vm.Guest -and $vm.Guest.OSFullName) { $vm.Guest.OSFullName } else { $cfg.GuestFullName }
    $isWin11 = ($os -match 'Windows 11')
    $isLinuxGuest = ($os -match 'Linux|Ubuntu|RHEL|CentOS|SUSE|Photon')
    $cluster = if ($vm.VMHost -and $vm.VMHost.Parent) { $vm.VMHost.Parent.Name } else { '' }

    function _row {
        param($issue, $detail, $severity = 'P2', $fix = '')
        [pscustomobject]@{
            ParentVM = $vm.Name
            Cluster  = $cluster
            GuestOS  = $os
            Issue    = $issue
            Severity = $severity
            Detail   = $detail
            Fix      = $fix
        }
    }

    # ---- 2. RIGHT-SIZING ----------------------------------------------
    if ($vm.NumCpu -gt $MaxParentVCpu) {
        _row 'Oversized vCPU' "Parent has $($vm.NumCpu) vCPU; recommended max for desktop pool is $MaxParentVCpu." 'P2' "Right-size to 2-4 (knowledge worker) or 4-8 (power user) vCPU before snapshot + recompose."
    }
    $ramGB = [math]::Round($vm.MemoryGB, 0)
    if ($ramGB -gt $MaxParentRamGB) {
        _row 'Oversized RAM' "Parent has $ramGB GB RAM; recommended max for desktop pool is $MaxParentRamGB GB. A 128 GB desktop is almost always a server template misclassified as a desktop." 'P1' "Right-size to 4-8 GB (knowledge worker), 16-32 GB (CAD/power user). Never deploy with > 32 GB on a generic IC pool."
    }

    # ---- 3. STORAGE / NIC HARDWARE ------------------------------------
    foreach ($d in $devs) {
        $tn = $d.GetType().Name
        switch -Regex ($tn) {
            'ParaVirtualSCSIController' { } # ok
            'LsiLogic.*Controller'       { _row 'Legacy SCSI controller' "$tn detected on parent. PVSCSI is the recommended type for IC pools (lower CPU overhead)." 'P3' "Edit Settings -> SCSI Controller -> change type to VMware Paravirtual." }
            'BusLogic.*Controller'       { _row 'Legacy SCSI controller' "$tn is deprecated. Replace with PVSCSI." 'P2' "Edit Settings -> SCSI Controller -> change type to VMware Paravirtual." }
            'VirtualE1000(e?)'           { _row 'Legacy NIC type' "$tn detected. VMXNET3 is required for Blast Extreme media optimization and offload features." 'P2' "Edit Settings -> Network Adapter -> Adapter Type = VMXNET3. Sysprep before snapshot (NIC change resets driver state)." }
            'VirtualPCNet32'             { _row 'Legacy NIC type' "$tn is deprecated. Replace with VMXNET3." 'P2' "Edit Settings -> Network Adapter -> VMXNET3." }
            'VirtualFloppy'              { _row 'Legacy device present' "Virtual floppy attached - never useful in production VDI." 'P3' "Edit Settings -> remove Floppy device." }
            'VirtualSerialPort'          { _row 'Legacy device present' 'Serial port attached.' 'P3' "Edit Settings -> remove Serial device unless explicitly required." }
            'VirtualParallelPort'        { _row 'Legacy device present' 'Parallel port attached.' 'P3' "Edit Settings -> remove Parallel device." }
            'VirtualSoundCard'           { _row 'Sound card present' 'A sound card on the parent typically maps to host audio - irrelevant for Horizon (audio handled by Blast).' 'P3' "Edit Settings -> remove Sound device." }
        }
    }

    # ---- 4. CD/DVD CONNECTED AT BOOT ----------------------------------
    foreach ($cd in ($devs | Where-Object { $_.GetType().Name -eq 'VirtualCdrom' })) {
        if ($cd.Connectable -and $cd.Connectable.StartConnected) {
            _row 'CD/DVD connected at boot' "$($cd.DeviceInfo.Label) is set to 'Connect at power on'. Blocks vMotion and clutters clones." 'P3' "Edit Settings -> CD/DVD Drive -> uncheck 'Connect at power on'."
        }
    }

    # ---- 5. SNAPSHOTS - more than 2 means residue ---------------------
    $snaps = @(Get-Snapshot -VM $vm -ErrorAction SilentlyContinue)
    if ($snaps.Count -gt 2) {
        _row 'Excess snapshots on parent' "$($snaps.Count) snapshots present on the parent. Best practice: keep only the active 'published' snapshot + 1 rollback. More accumulates delta size and slows recompose." 'P3' "Identify the active snapshot in Horizon Console -> Pool -> Image Settings; consolidate the rest in vSphere Client."
    }

    # ---- 6. TOOLS TIME-SYNC -------------------------------------------
    if ($cfg.Tools -and $cfg.Tools.SyncTimeWithHost) {
        _row 'Tools time-sync enabled' "VMware Tools 'Synchronize time with host' is ON. For AD-joined Windows guests this overrides the AD time hierarchy and breaks Kerberos when ESXi and AD drift." 'P2' "Edit Settings -> VM Options -> Tools -> uncheck 'Synchronize time with host'. Use AD time hierarchy for Windows; chrony/ntp on Linux."
    }

    # ---- 7. WINDOWS 11 vTPM + BITLOCKER ANTI-PATTERN ------------------
    $hasTpm    = ($devs | Where-Object { $_.GetType().Name -eq 'VirtualTPM' }) -ne $null
    $secureBoot = ($cfg.BootOptions -and $cfg.BootOptions.EfiSecureBootEnabled)

    if ($isWin11) {
        if (-not $hasTpm) {
            _row 'Win11 parent missing vTPM' 'Windows 11 parent has no VirtualTPM device. Win11 22H2+ requires TPM 2.0; Instant Clones forked from this parent will fail Win11 servicing checks.' 'P2' "Configure Standard Key Provider on vCenter, then VM Edit Settings -> Add Device -> Trusted Platform Module."
        }
        if (-not $secureBoot) {
            _row 'Win11 parent missing Secure Boot' 'Win11 parent has Secure Boot disabled. Required for Win11 + vTPM combination + Credential Guard.' 'P2' 'Edit Settings -> VM Options -> Boot Options -> enable Secure Boot (UEFI firmware required first).'
        }
        # 8. BITLOCKER detection - we cannot read the guest registry from
        # vCenter alone, but we surface it as a manual-check reminder for
        # every Win11 parent. Sealed BitLocker keys do not fork.
        _row 'Verify BitLocker disabled on Win11 parent' "Manual check required: log into the parent guest, run 'manage-bde -status'. BitLocker MUST NOT be enabled on the parent volume; sealed keys cannot be re-keyed across Instant Clone forks. Win11 will try to enable BitLocker automatically on first sign-in if unattend.xml is misconfigured." 'P2' "If BitLocker is on: manage-bde -off C: , wait for decrypt to complete, sysprep generalize, then re-snapshot. Set the GPO 'Computer Configuration -> Admin Templates -> Windows Components -> BitLocker Drive Encryption -> Disable BitLocker' to prevent re-enable on clones."
    }

    # ---- 9. VM-LEVEL ENCRYPTION (Standard / External KP) on parent ----
    # If the parent itself is encrypted with VM Encryption (vSphere KMS),
    # Instant Clone forking does not propagate the key envelope correctly -
    # clones will not decrypt. (vTPM is fine; whole-VM encryption is not.)
    $encrypted = $false
    try {
        if ($cfg.KeyId -and $cfg.KeyId.KeyId) { $encrypted = $true }
    } catch { }
    if ($encrypted) {
        _row 'Parent VM has VM-level encryption' 'The parent itself is encrypted via vSphere VM Encryption / Key Provider. This breaks Instant Clone forking - clones cannot decrypt. vTPM is allowed; full VM Encryption is not.' 'P1' "Decrypt parent: Edit Settings -> VM Options -> Encryption -> change to 'Not encrypted'. Re-snapshot, re-publish."
    }

    # ---- 10. HARDWARE VERSION FOR CLUSTER -----------------------------
    $hv = [int]($vm.HardwareVersion -replace '[^0-9]','')
    if ($hv -lt 14) {
        _row 'Hardware version below vmx-14' "Parent at $($vm.HardwareVersion). Vmx-14+ required for vTPM, Secure Boot, hot-add features. Vmx-19+ recommended for ESXi 7/8 clusters." 'P2' 'Power off parent -> Compatibility -> Upgrade VM Compatibility -> select target hardware version >= 19.'
    }

    # ---- 11. CONNECTED ISO --------------------------------------------
    foreach ($cd in ($devs | Where-Object { $_.GetType().Name -eq 'VirtualCdrom' })) {
        $bk = $cd.Backing
        if ($bk -and ($bk.GetType().Name -match 'IsoBacking') -and $bk.FileName) {
            _row 'ISO mounted on parent' "$($cd.DeviceInfo.Label) -> $($bk.FileName). Blocks vMotion and is rarely intentional on a published image." 'P3' "Edit Settings -> CD/DVD -> Datastore ISO File -> change to Client Device, disconnect."
        }
    }

    # ---- 12. EFI vs BIOS firmware mismatch (Win11 needs EFI) ----------
    if ($isWin11 -and $cfg.Firmware -and $cfg.Firmware -ne 'efi') {
        _row 'Win11 parent on legacy BIOS firmware' "Firmware = $($cfg.Firmware). Windows 11 requires UEFI firmware; legacy BIOS will block Win11 install/upgrade." 'P1' 'This requires guest reinstall or migration. Cannot toggle BIOS->UEFI on a running Windows install without significant remediation.'
    }
}

$TableFormat = @{
    Severity = { param($v,$row) if ($v -eq 'P1') { 'bad' } elseif ($v -eq 'P2') { 'warn' } else { '' } }
}
