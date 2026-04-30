# Start of Settings
# Subset of the vSphere Security Configuration Guide that's most commonly
# audited in EUC engagements. Each entry: setting name, expected value,
# severity if non-compliant.
$HardeningChecks = @(
    @{ Setting='UserVars.ESXiVPsDisabledProtocols';   Expected='sslv3,tlsv1,tlsv1.1'; Severity='P1'; Note='TLS 1.0 / 1.1 / SSLv3 disabled (PCI / FIPS)' }
    @{ Setting='UserVars.SuppressShellWarning';        Expected='0';                  Severity='P3'; Note='Shell warnings should NOT be suppressed' }
    @{ Setting='Misc.APDHandlingEnable';               Expected='1';                  Severity='P2'; Note='APD handling = automatic recovery from all-paths-down' }
    @{ Setting='Net.BlockGuestBPDU';                   Expected='1';                  Severity='P3'; Note='Block guest-VM BPDU forwarding (STP loop protection)' }
    @{ Setting='Mem.ShareForceSalting';                Expected='2';                  Severity='P3'; Note='Per-VM memory salting (TPS hardening)' }
    @{ Setting='Net.DVFilterBindIpAddress';            Expected='';                   Severity='P2'; Note='Should be empty unless dvFilter-based security in use' }
    @{ Setting='UserVars.ESXiShellInteractiveTimeOut'; Expected='600';                Severity='P3'; Note='Auto-logoff Shell after 10 minutes idle' }
    @{ Setting='UserVars.ESXiShellTimeOut';            Expected='600';                Severity='P3'; Note='Auto-disable Shell after 10 minutes' }
    @{ Setting='UserVars.DcuiTimeOut';                 Expected='600';                Severity='P3'; Note='Auto-logoff DCUI after 10 minutes idle' }
)
# End of Settings

$Title          = "ESXi Hardening Guide Audit"
$Header         = "[count] host/setting pair(s) deviating from VMware Security Configuration Guide"
$Comments       = "Audits a curated subset of the vSphere Security Configuration Guide across all connected ESXi hosts. Surfaces ONLY non-compliant settings - hosts where every checked setting matches the recommendation are skipped to keep the report tight."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "C2 Hardening Guide"
$Severity       = "P2"
$Recommendation = "Bring all hosts in line with the published Configuration Guide for the deployed vSphere version. Use Host Profiles or PowerCLI templates to enforce the baseline at scale. Document any explicit exceptions."

if (-not $Global:VCConnected) { return }
foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue)) {
    if (-not $h) { continue }
    foreach ($check in $HardeningChecks) {
        $cur = $null
        try { $cur = (Get-AdvancedSetting -Entity $h -Name $check.Setting -ErrorAction Stop).Value } catch { continue }
        if ([string]$cur -ne [string]$check.Expected) {
            [pscustomobject]@{
                Host        = $h.Name
                Setting     = $check.Setting
                Current     = $cur
                Recommended = $check.Expected
                ImpactNote  = $check.Note
                Severity    = $check.Severity
            }
        }
    }
}

$TableFormat = @{
    Severity = { param($v,$row) if ($v -eq 'P1') { 'bad' } elseif ($v -eq 'P2') { 'warn' } else { '' } }
}
