# Start of Settings
$MaxRows = 250
# End of Settings

$Title          = 'AD Group Policy Inventory + Linkage'
$Header         = 'Every GPO with link count, status, WMI filter, last modified'
$Comments       = "Group Policy is fundamental to AD operations and security. Unlinked GPOs accumulate over time (every Citrix / Horizon / DEM project leaves at least one); GPOs in 'AllSettingsDisabled' state are off but consume processing time on every gpupdate. Lists every GPO so operators can spot orphans, stale changes, and over-privileged delegations."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = 'B3 Active Directory'
$Severity       = 'P3'
$Recommendation = "Disable + document every GPO with 0 active links (LinkCount = 0). Consolidate empty GPO containers. Audit large WMI-filter farms for query cost. Keep total GPO count < 200 per domain to avoid SYSVOL / DC processing latency."

if (-not (Test-Path Variable:Global:ADForestFqdn) -or -not $Global:ADForestFqdn) { return }
try { Import-Module GroupPolicy -ErrorAction Stop } catch {
    [pscustomobject]@{ GPO=''; Note='GroupPolicy PowerShell module unavailable. RSAT-GPMC required.' }
    return
}
try { Import-Module ActiveDirectory -ErrorAction Stop } catch { }

$adArgs = @{ Server = $(if ($Global:ADServerFqdn) { $Global:ADServerFqdn } else { $Global:ADForestFqdn }) }
if (Test-Path Variable:Global:ADCredential) { $adArgs.Credential = $Global:ADCredential }

try {
    $forest = Get-ADForest -Identity $Global:ADForestFqdn @adArgs -ErrorAction Stop
    foreach ($d in $forest.Domains) {
        $g = @{ Domain=$d; ErrorAction='SilentlyContinue' }
        $gpos = @(Get-GPO -All @g | Select-Object -First $MaxRows)
        if ($gpos.Count -eq 0) {
            [pscustomobject]@{ Domain=$d; GPO=''; Status='NO GPOs returned' }
            continue
        }
        foreach ($gpo in $gpos) {
            $linkCount = 0
            $links = @()
            try {
                # GPO XML report -> count active LinksTo entries
                [xml]$rpt = Get-GPOReport -Guid $gpo.Id -ReportType Xml -Domain $d -ErrorAction Stop
                $linkNodes = @($rpt.GPO.LinksTo)
                $linkCount = $linkNodes.Count
                foreach ($l in $linkNodes) { $links += "$($l.SOMPath) (Enabled=$($l.Enabled))" }
            } catch { }
            $userEnab = $gpo.User.Enabled
            $compEnab = $gpo.Computer.Enabled
            $bothDis  = (-not $userEnab -and -not $compEnab)
            $status = if ($linkCount -eq 0) { 'UNLINKED' }
                      elseif ($bothDis) { 'BOTH SIDES DISABLED' }
                      else { 'OK' }
            [pscustomobject]@{
                Domain         = $d
                GPO            = "$($gpo.DisplayName)"
                Id             = "$($gpo.Id)"
                Owner          = "$($gpo.Owner)"
                CreationTime   = if ($gpo.CreationTime) { $gpo.CreationTime.ToString('yyyy-MM-dd') } else { '' }
                ModificationTime = if ($gpo.ModificationTime) { $gpo.ModificationTime.ToString('yyyy-MM-dd') } else { '' }
                UserEnabled    = $userEnab
                ComputerEnabled= $compEnab
                LinkCount      = $linkCount
                Links          = ($links -join ' ; ')
                WmiFilter      = if ($gpo.WmiFilter) { "$($gpo.WmiFilter.Name)" } else { '' }
                Status         = $status
            }
        }
    }
} catch {
    [pscustomobject]@{ Domain='ERROR'; Status=$_.Exception.Message }
}

$TableFormat = @{
    LinkCount = { param($v,$row) if ([int]"$v" -eq 0) { 'warn' } else { '' } }
    Status    = { param($v,$row) if ("$v" -eq 'OK') { 'ok' } elseif ("$v" -match 'UNLINK|BOTH|NO ') { 'warn' } else { '' } }
}
