# Start of Settings
# End of Settings

$Title          = 'Active Directory Domain Controllers'
$Header         = "[count] DC(s) in the forest"
$Comments       = "Lists every DC in the forest with site, OS version, FSMO roles. Critical for Horizon: every CS needs reachable, healthy DCs in its site."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'B3 Active Directory'
$Severity       = 'Info'
$Recommendation = "Ensure each Horizon CS has at least 2 DCs in its site (or a fallback). FSMO holders should be on stable, well-monitored DCs. EOL Windows Server on a DC = priority replacement."

# Opt-in: only run when the operator supplied an AD forest hint via the GUI / CLI.
if (-not (Test-Path Variable:Global:ADForestFqdn) -or -not $Global:ADForestFqdn) { return }

$adAvailable = $true
try { Import-Module ActiveDirectory -ErrorAction Stop } catch { $adAvailable = $false }

if (-not $adAvailable) {
    # Plugin 01 (AD Sites and Services) is the canonical plugin to surface
    # the RSAT-missing message. Skip silently here to avoid 4 duplicate rows.
    return
}

# Build a splat that targets the operator-supplied forest/DC. -Server is
# the AD module's way to say "ignore the runner's local context, query
# THIS host instead". We pass an optional credential too so the runner
# doesn't have to be domain-joined.
$adArgs = @{ Server = $(if ($Global:ADServerFqdn) { $Global:ADServerFqdn } else { $Global:ADForestFqdn }); ErrorAction = 'Stop' }
if (Test-Path Variable:Global:ADCredential) { $adArgs.Credential = $Global:ADCredential }

try {
    $forest = Get-ADForest @adArgs -Identity $Global:ADForestFqdn
    $domains = $forest.Domains
    foreach ($d in $domains) {
        $dcArgs = @{ Filter = '*'; Server = $d; ErrorAction = 'SilentlyContinue' }
        if (Test-Path Variable:Global:ADCredential) { $dcArgs.Credential = $Global:ADCredential }
        $dcs = Get-ADDomainController @dcArgs
        foreach ($dc in $dcs) {
            $fsmo = @()
            if ($dc.OperationMasterRoles) { $fsmo = $dc.OperationMasterRoles | ForEach-Object { $_.ToString() } }
            [pscustomobject]@{
                DC          = $dc.HostName
                Domain      = $dc.Domain
                Site        = $dc.Site
                OS          = $dc.OperatingSystem
                OSVersion   = $dc.OperatingSystemVersion
                IPv4        = $dc.IPv4Address
                FsmoRoles   = ($fsmo -join ', ')
                Note        = if ($dc.OperatingSystem -match 'Server 2003|Server 2008|Server 2012(?!\sR2)') { 'EOL OS - PRIORITY REPLACEMENT' } else { '' }
            }
        }
    }
} catch {
    [pscustomobject]@{ DC = 'Error'; Site = ''; OS = ''; FsmoRoles = ''; Note = "Get-ADForest failed for '$Global:ADForestFqdn': $($_.Exception.Message). Verify the runner can reach a DC of that forest (DNS + TCP/389 + TCP/9389 ADWS) and that the credential has rights to query." }
}

$TableFormat = @{
    Note = { param($v,$row) if ($v -match 'EOL') { 'bad' } else { '' } }
    OS   = { param($v,$row) if ($v -match 'Server 2003|2008(?!\sR2)|2012(?!\sR2)') { 'bad' } elseif ($v -match 'Server 2012 R2|Server 2016') { 'warn' } else { '' } }
}
