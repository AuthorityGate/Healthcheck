# Start of Settings
# End of Settings

$Title          = 'AD FSMO Role Holders'
$Header         = "FSMO role placement"
$Comments       = "FSMO holders = single-instance functions per AD domain/forest. PDC Emulator = time + password change handler (most operationally critical). Schema/Domain Naming Master = forest root. Tracking + planned-failover for these roles is essential."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'B3 Active Directory'
$Severity       = 'P3'
$Recommendation = "Document FSMO holders per domain in operational runbook. PDC Emulator should be on a stable, monitored DC. Plan transfer procedure for any planned outage of FSMO holder."

# Opt-in: only run when the operator supplied an AD forest hint via the GUI / CLI.
if (-not (Test-Path Variable:Global:ADForestFqdn) -or -not $Global:ADForestFqdn) { return }

$adAvailable = $true
try { Import-Module ActiveDirectory -ErrorAction Stop } catch { $adAvailable = $false }

if (-not $adAvailable) {
    # Plugin 01 (AD Sites and Services) is the canonical plugin to surface
    # the RSAT-missing message. Skip silently here to avoid 4 duplicate rows.
    return
}

$adArgs = @{ Server = $(if ($Global:ADServerFqdn) { $Global:ADServerFqdn } else { $Global:ADForestFqdn }) }
if (Test-Path Variable:Global:ADCredential) { $adArgs.Credential = $Global:ADCredential }

try {
    $forest = Get-ADForest -Identity $Global:ADForestFqdn @adArgs -ErrorAction Stop
    [pscustomobject]@{ Role = 'Schema Master'; Scope = 'Forest'; Holder = $forest.SchemaMaster; Note = '' }
    [pscustomobject]@{ Role = 'Domain Naming Master'; Scope = 'Forest'; Holder = $forest.DomainNamingMaster; Note = '' }

    foreach ($d in $forest.Domains) {
        $domArgs = @{ Identity = $d; Server = $d; ErrorAction = 'SilentlyContinue' }
        if (Test-Path Variable:Global:ADCredential) { $domArgs.Credential = $Global:ADCredential }
        $domain = Get-ADDomain @domArgs
        if ($domain) {
            [pscustomobject]@{ Role = 'PDC Emulator'; Scope = $d; Holder = $domain.PDCEmulator; Note = 'Most operationally critical FSMO' }
            [pscustomobject]@{ Role = 'RID Master'; Scope = $d; Holder = $domain.RIDMaster; Note = '' }
            [pscustomobject]@{ Role = 'Infrastructure Master'; Scope = $d; Holder = $domain.InfrastructureMaster; Note = '' }
        }
    }
} catch {
    [pscustomobject]@{ Role = 'Error'; Holder = ''; Note = "$($_.Exception.Message). Verify runner reaches '$Global:ADForestFqdn' DCs (DNS + TCP/9389 ADWS) and credential has rights." }
}
