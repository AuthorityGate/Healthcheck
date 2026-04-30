# Start of Settings
# End of Settings

$Title          = 'NSX Trust Manager Certificates'
$Header         = '[count] certificate(s) in NSX trust store'
$Comments       = 'Embedded NSX Manager and federation certs. Track expiry.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'P2'
$Recommendation = 'Replace expiring CA / intermediate certs via /api/v1/trust-management/certificates/import endpoint.'

if (-not (Get-NSXRestSession)) { return }
try { $c = Get-NSXTrustObject } catch { return }
if (-not $c) { return }
foreach ($x in $c) {
    [pscustomobject]@{
        DisplayName = $x.display_name
        Issuer      = $x.details.issuer
        SubjectCN   = $x.details.subject
        NotAfter    = $x.details.not_after
        UsedBy      = ($x.used_by | ForEach-Object { $_.service_types -join ',' })
    }
}
