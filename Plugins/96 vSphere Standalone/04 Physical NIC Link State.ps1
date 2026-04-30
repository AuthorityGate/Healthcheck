# Start of Settings
# End of Settings

$Title          = "Physical NIC Link State"
$Header         = "[count] physical NIC(s) down, at unexpected speed, or half-duplex"
$Comments       = "Sanity check on physical uplinks: link down, sub-gigabit speed, or half-duplex usually indicates cable, optic, or upstream-switch issues. Half-duplex on any production NIC is a hard fault."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "96 vSphere Standalone"
$Severity       = "P2"
$Recommendation = "Replace the optic / cable, then re-seat. If the negotiated speed is below the port spec, hard-set duplex/speed on the upstream switch."

if (-not $Global:VCConnected) { return }

Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $h = $_
    foreach ($p in $h.ExtensionData.Config.Network.Pnic) {
        $linked = [bool]$p.LinkSpeed
        $speed  = if ($p.LinkSpeed) { $p.LinkSpeed.SpeedMb } else { 0 }
        $duplex = if ($p.LinkSpeed) { $p.LinkSpeed.Duplex } else { $false }
        $bad    = (-not $linked) -or ($speed -lt 1000) -or (-not $duplex)
        if ($bad) {
            [pscustomobject]@{
                Host     = $h.Name
                Pnic     = $p.Device
                Linked   = $linked
                SpeedMb  = $speed
                FullDuplex = $duplex
                MAC      = $p.Mac
            }
        }
    }
}

$TableFormat = @{
    Linked     = { param($v,$row) if ($v -ne $true) { 'bad' } else { '' } }
    FullDuplex = { param($v,$row) if ($v -ne $true) { 'bad' } else { '' } }
    SpeedMb    = { param($v,$row) if ([int]$v -lt 1000) { 'warn' } else { '' } }
}
