# Start of Settings
# End of Settings

$Title          = "ESXi Hosts Disconnected or Not Responding"
$Header         = "[count] host(s) not in 'Connected' state"
$Comments       = "Hosts in 'Disconnected', 'NotResponding', or 'Maintenance' cannot run desktops. Maintenance is intentional but tracked here for visibility."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "95 vSphere Backing Infra"
$Severity       = "P1"
$Recommendation = "For NotResponding/Disconnected: check management network, hostd service (vCLI: /etc/init.d/hostd restart), and certificate trust. For Maintenance: confirm planned, then exit."

if (-not $Global:VCConnected) { return }

Get-VMHost -ErrorAction SilentlyContinue | Where-Object { $_.ConnectionState -ne 'Connected' } | ForEach-Object {
    [pscustomobject]@{
        Host            = $_.Name
        State           = $_.ConnectionState
        PowerState      = $_.PowerState
        Cluster         = $_.Parent.Name
        Build           = $_.Build
        Version         = $_.Version
        UptimeDays      = if ($_.ConnectionState -eq 'Connected') { [int]((Get-Date) - $_.ExtensionData.Summary.Runtime.BootTime).TotalDays } else { 'n/a' }
    }
}

$TableFormat = @{
    State = { param($v,$row) if ($v -in 'NotResponding','Disconnected') { 'bad' } elseif ($v -eq 'Maintenance') { 'warn' } else { '' } }
}
