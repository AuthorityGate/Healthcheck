# Start of Settings
# End of Settings

$Title          = 'AD Trust Relationships'
$Header         = 'Forest, external, and realm trusts (every trust listed)'
$Comments       = 'Trusts cross security boundaries. External trusts to legacy domains, unilateral SID-history-enabled trusts, and selective-auth misconfiguration are common audit findings. Lists every trust with direction, type, transitivity, and SID-filter / quarantine status.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = 'B3 Active Directory'
$Severity       = 'P2'
$Recommendation = 'External trusts SHOULD have SIDFilteringQuarantined = True (SID-filter enforced). Forest trusts SHOULD have ForestTransitive = True. Document business justification for every trust; remove unused trusts.'

if (-not (Test-Path Variable:Global:ADForestFqdn) -or -not $Global:ADForestFqdn) { return }
$adAvailable = $true
try { Import-Module ActiveDirectory -ErrorAction Stop } catch { $adAvailable = $false }
if (-not $adAvailable) { return }

$adArgs = @{ Server = $(if ($Global:ADServerFqdn) { $Global:ADServerFqdn } else { $Global:ADForestFqdn }) }
if (Test-Path Variable:Global:ADCredential) { $adArgs.Credential = $Global:ADCredential }

try {
    $forest = Get-ADForest -Identity $Global:ADForestFqdn @adArgs -ErrorAction Stop
    $domains = @($forest.Domains)
    $found = $false
    foreach ($d in $domains) {
        $tArgs = @{ Filter='*'; Server=$d; ErrorAction='SilentlyContinue' }
        if (Test-Path Variable:Global:ADCredential) { $tArgs.Credential = $Global:ADCredential }
        $trusts = @(Get-ADTrust @tArgs)
        foreach ($t in $trusts) {
            $found = $true
            $isForest = ($t.TrustType -eq 'Forest' -or $t.ForestTransitive -eq $true)
            $sidFilt  = [bool]$t.SIDFilteringQuarantined
            $status = if ($t.TrustType -eq 'External' -and -not $sidFilt) { 'BAD (SID filter disabled on external trust)' }
                      elseif ($isForest -and -not $t.ForestTransitive) { 'WARN (non-transitive forest trust)' }
                      else { 'OK' }
            [pscustomobject]@{
                FromDomain     = $d
                Target         = $t.Target
                Direction      = "$($t.Direction)"
                TrustType      = "$($t.TrustType)"
                Transitive     = [bool]$t.IntraForest -or [bool]$t.ForestTransitive
                ForestTrust    = [bool]$t.ForestTransitive
                SIDFilter      = $sidFilt
                SelectiveAuth  = [bool]$t.SelectiveAuthentication
                Status         = $status
            }
        }
    }
    if (-not $found) {
        [pscustomobject]@{ FromDomain=$Global:ADForestFqdn; Target=''; Direction=''; TrustType=''; Status='NO TRUSTS DEFINED'; Note='No external/forest/realm trusts present in any domain in the forest.' }
    }
} catch {
    [pscustomobject]@{ FromDomain=$Global:ADForestFqdn; Status='ERROR'; Note=$_.Exception.Message }
}

$TableFormat = @{
    Status        = { param($v,$row) if ("$v" -eq 'OK') { 'ok' } elseif ("$v" -match 'BAD|ERROR') { 'bad' } elseif ("$v" -match 'WARN|NO ') { 'warn' } else { '' } }
    SIDFilter     = { param($v,$row) if ($v -eq $false -and "$($row.TrustType)" -eq 'External') { 'bad' } else { '' } }
}
