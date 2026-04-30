# Start of Settings
# Acceptable VIB acceptance levels in priority order. CommunitySupported VIBs
# are unsigned community-built code and should not run in production.
$AllowedAcceptance = @('VMwareCertified','VMwareAccepted','PartnerSupported')
# End of Settings

$Title          = 'ESXi VIB Acceptance Level'
$Header         = '[count] host(s) accepting CommunitySupported VIBs'
$Comments       = 'KB 2046670: ESXi host Software.AcceptanceLevel controls which VIB signatures are honored at install time. CommunitySupported = unsigned/community code; not for production. PartnerSupported is the production minimum.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = "On each host: esxcli software acceptance set --level=PartnerSupported  (or VMwareAccepted / VMwareCertified). Re-evaluate any non-conforming VIBs after raising the bar."

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)) {
    try {
        $esxcli = Get-EsxCli -V2 -VMHost $h -ErrorAction Stop
        $level  = $esxcli.software.acceptance.get.Invoke()
        if ($level -notin $AllowedAcceptance) {
            [pscustomobject]@{
                Host            = $h.Name
                AcceptanceLevel = $level
                Allowed         = ($AllowedAcceptance -join ', ')
            }
        }
    } catch { }
}

$TableFormat = @{
    AcceptanceLevel = { param($v,$row) if ($v -eq 'CommunitySupported') { 'bad' } else { 'warn' } }
}
