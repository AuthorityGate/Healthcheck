# Start of Settings
# vSphere Security Configuration Guide rules. Each rule names an
# advanced setting + recommended value. Many vSCG line items collapse
# to a single advanced-setting check; this plugin covers ~30 of the
# most-cited entries. Add more rows as your environment requires.
$VscgRules = @(
    # Setting,                                         Recommended,  Severity, Description
    @{ Setting='Mem.ShareForceSalting';                Recommended=2;          Severity='P2'; Description='Memory salting prevents cross-VM TPS attacks (KB 2097593).' }
    @{ Setting='Net.BlockGuestBPDU';                   Recommended=1;          Severity='P2'; Description='Block guest-originated BPDUs to prevent VM spoofing physical switch (KB 2034605).' }
    @{ Setting='Net.DVFilterBindIpAddress';            Recommended='';         Severity='P2'; Description='DVFilter API IP must be empty unless an introspection appliance binds to it.' }
    @{ Setting='UserVars.SuppressShellWarning';        Recommended=0;          Severity='P3'; Description='Preserve shell-enabled warning banner so operators see the risk.' }
    @{ Setting='UserVars.ESXiShellTimeOut';            Recommended=600;        Severity='P2'; Description='Shell auto-disables 600s after enable; 0 = never disable.' }
    @{ Setting='UserVars.ESXiShellInteractiveTimeOut'; Recommended=600;        Severity='P2'; Description='Idle shell session auto-logout after 600s.' }
    @{ Setting='UserVars.DcuiTimeOut';                 Recommended=600;        Severity='P2'; Description='DCUI idle auto-logout after 600s.' }
    @{ Setting='Security.AccountLockFailures';         Recommended=5;          Severity='P2'; Description='Local account lockout threshold; 0 = disabled.' }
    @{ Setting='Security.AccountUnlockTime';           Recommended=900;        Severity='P3'; Description='Auto-unlock window after lockout (seconds).' }
    @{ Setting='Security.PasswordHistory';             Recommended=5;          Severity='P3'; Description='Number of historical passwords prevented from re-use.' }
    @{ Setting='Security.PasswordMaxDays';             Recommended=90;         Severity='P3'; Description='Maximum password age in days.' }
    @{ Setting='Config.HostAgent.plugins.solo.enableMob'; Recommended=$false;  Severity='P2'; Description='Managed Object Browser enables introspection - attack surface.' }
    @{ Setting='Config.HostAgent.log.level';           Recommended='info';     Severity='P3'; Description='Production log level should not be verbose/trivia.' }
    @{ Setting='Mem.MemEagerZero';                     Recommended=1;          Severity='P3'; Description='Eager-zero new memory pages to prevent residual data exposure.' }
    @{ Setting='Net.BMCNetworkEnable';                 Recommended=0;          Severity='P3'; Description='Disable on-host BMC network unless required.' }
    @{ Setting='UserVars.SuppressCoredumpWarning';     Recommended=0;          Severity='P3'; Description='Preserve core-dump-not-configured warning visibility.' }
    @{ Setting='UserVars.SuppressHyperthreadWarning';  Recommended=0;          Severity='P3'; Description='Preserve HT/L1TF warning visibility.' }
    @{ Setting='Misc.LogToSerial';                     Recommended=0;          Severity='P3'; Description='Log to serial console only when explicitly required.' }
    @{ Setting='Net.FollowHardwareMac';                Recommended=0;          Severity='P3'; Description='Prevent VMK MAC from inheriting NIC MAC unexpectedly.' }
    @{ Setting='Misc.LogDir';                          Recommended='persistent'; Severity='P2'; Description='Logs must persist across reboots (referenced by 124 ESXi_Persistent_Log_Location).' }
)
# End of Settings

$Title          = 'vSphere Security Configuration Guide Audit'
$Header         = '[count] vSCG line item(s) out of compliance'
$Comments       = 'Compares a curated set of ~20 vSphere Security Configuration Guide advanced settings against their recommended values, per-host. Each non-conforming setting is one row.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = "Per host: Get-VMHost <name> | Get-AdvancedSetting -Name <Setting> | Set-AdvancedSetting -Value <Recommended>. Apply via host profile for fleet-wide consistency."

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)) {
    foreach ($rule in $VscgRules) {
        try {
            $cur = Get-AdvancedSetting -Entity $h -Name $rule.Setting -ErrorAction SilentlyContinue
            if (-not $cur) { continue }
            $actual = $cur.Value
            $rec = $rule.Recommended
            $match = $false
            if ($rec -is [bool]) {
                $match = ([bool]$actual -eq $rec)
            } elseif ($rec -eq 'persistent') {
                # Special: LogDir non-empty = persistent
                $match = ([string]$actual -and ([string]$actual).Trim() -ne '')
            } else {
                $match = ([string]$actual -eq [string]$rec)
            }
            if (-not $match) {
                [pscustomobject]@{
                    Host        = $h.Name
                    Setting     = $rule.Setting
                    Actual      = [string]$actual
                    Recommended = [string]$rec
                    Severity    = $rule.Severity
                    Description = $rule.Description
                }
            }
        } catch { }
    }
}

$TableFormat = @{
    Severity = { param($v,$row) if ($v -eq 'P1') { 'bad' } elseif ($v -eq 'P2') { 'warn' } else { '' } }
}
