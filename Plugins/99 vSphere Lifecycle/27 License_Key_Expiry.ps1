# Start of Settings
$WarnDays = 90
$BadDays  = 30
# End of Settings

$Title          = 'License Key Expiry'
$Header         = '[count] license key(s) expiring within ' + $WarnDays + ' days'
$Comments       = "vSphere / vCenter / vSAN / NSX licenses with expiry dates. Most production licenses are perpetual (no expiry); subscriptions / evals expire. Expired licenses don't disable running workloads but block reconfigure / power-on / vMotion / new-VM."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '99 vSphere Lifecycle'
$Severity       = 'P2'
$Recommendation = 'Renew via Customer Connect / Broadcom Support Portal. Apply new keys via vCenter -> Administration -> Licensing well before expiry.'

if (-not $Global:VCConnected) { return }

try {
    $licMgr = Get-View 'LicenseManager' -ErrorAction Stop
    foreach ($lic in $licMgr.Licenses) {
        $exp = $null
        if ($lic.Properties) {
            foreach ($p in $lic.Properties) {
                if ($p.Key -eq 'expirationHours' -and $p.Value -gt 0) {
                    $exp = (Get-Date).AddHours([int]$p.Value)
                }
                if ($p.Key -eq 'ExpirationDate') { $exp = $p.Value }
            }
        }
        $daysLeft = if ($exp) { ($exp - (Get-Date)).Days } else { -1 }
        if ($daysLeft -ge 0 -and $daysLeft -le $WarnDays) {
            [pscustomobject]@{
                LicenseName = $lic.Name
                Edition     = $lic.EditionKey
                Total       = $lic.Total
                Used        = $lic.Used
                ExpiresOn   = $exp
                DaysLeft    = $daysLeft
            }
        }
    }
} catch { }

$TableFormat = @{
    DaysLeft = { param($v,$row) if ([int]$v -lt $BadDays) { 'bad' } elseif ([int]$v -lt $WarnDays) { 'warn' } else { '' } }
}
