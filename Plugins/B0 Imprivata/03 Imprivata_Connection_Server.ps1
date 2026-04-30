# Start of Settings
# End of Settings

$Title          = 'Imprivata on Connection Servers'
$Header         = "[count] CS server(s) probed for Imprivata integration"
$Comments       = "Imprivata OneSign integrates with Horizon at the Connection Server layer for tap-and-go and SSO workflows. This plugin probes each CS for Imprivata service registration, SSO module, and trusted appliance configuration. Tier 2 in-guest scan via WinRM."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = 'B0 Imprivata'
$Severity       = 'P2'
$Recommendation = "Verify Imprivata SSO module installed on each CS in the pod. Verify trusted appliance URL matches deployed Imprivata appliance(s). Test logon end-to-end via the Imprivata 'Workflow Bench'."

if (-not (Get-HVRestSession)) { return }

$cred = if (Test-Path Variable:Global:HVImageScanCredential) { $Global:HVImageScanCredential } else { $null }

$servers = New-Object System.Collections.Generic.HashSet[string]
try {
    $cs = Invoke-HVRest -Path '/v1/monitor/connection-servers' -NoPaging
    foreach ($c in @($cs)) {
        if ($c.name) { [void]$servers.Add($c.name) } elseif ($c.host_name) { [void]$servers.Add($c.host_name) }
    }
} catch { }
if ($servers.Count -eq 0) { return }

$probeBlock = {
    $r = @{}
    foreach ($path in 'HKLM:\SOFTWARE\Imprivata\OneSign','HKLM:\SOFTWARE\WOW6432Node\Imprivata\OneSign') {
        try {
            $reg = Get-ItemProperty $path -ErrorAction Stop
            if ($reg.Version) { $r.OneSignVersion = $reg.Version }
            if ($reg.ApplianceUrl) { $r.ApplianceUrl = $reg.ApplianceUrl }
        } catch { }
    }
    try {
        $svc = Get-Service -DisplayName '*Imprivata*' -ErrorAction SilentlyContinue
        $r.Services = @($svc | Select-Object Name, Status, StartType)
    } catch { }
    return $r
}

foreach ($srv in $servers) {
    $row = [pscustomobject]@{
        ConnectionServer = $srv
        Tier = 'Tier1'
        ImprivataInstalled = '(unknown)'
        OneSignVersion = ''
        ApplianceUrl = ''
        ServiceStatus = ''
        Note = if (-not $cred) { 'Set $Global:HVImageScanCredential for Tier 2.' } else { '' }
    }

    if ($cred) {
        try {
            $session = New-PSSession -ComputerName $srv -Credential $cred -ErrorAction Stop
            $g = Invoke-Command -Session $session -ScriptBlock $probeBlock
            Remove-PSSession $session -ErrorAction SilentlyContinue
            $row.Tier = 'Tier2'
            $row.ImprivataInstalled = if ($g.OneSignVersion) { 'Yes' } else { 'No' }
            $row.OneSignVersion = $g.OneSignVersion
            $row.ApplianceUrl = $g.ApplianceUrl
            $row.ServiceStatus = if ($g.Services) { ($g.Services | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join '; ' } else { '(none)' }
        } catch {
            $row.Note = "WinRM probe failed: $($_.Exception.Message)"
        }
    }
    $row
}
