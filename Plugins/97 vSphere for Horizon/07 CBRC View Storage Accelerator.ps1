# Start of Settings
# Recommended CBRC reservation per host (MB). Default 2048; up to 32768 supported.
$MinCbrcMB = 2048
# End of Settings

$Title          = "CBRC / View Storage Accelerator"
$Header         = "[count] host(s) without CBRC enabled or with insufficient cache"
$Comments       = "Content Based Read Cache (CBRC) backs View Storage Accelerator. Enabling it on each host significantly reduces boot-storm IOPS for instant-clone pools. References: Horizon Admin Guide -> 'Configure View Storage Accelerator', VMware KB 2107811."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 vSphere for Horizon"
$Severity       = "P3"
$Recommendation = "Per host: 'Get-AdvancedSetting -Entity (host) -Name CBRC.Enable | Set-AdvancedSetting -Value 1' and CBRC.DCacheMemReservationMB to >= $MinCbrcMB. Apply via host profile."

if (-not $Global:VCConnected) { return }

Get-VMHost -ErrorAction SilentlyContinue | ForEach-Object {
    $h    = $_
    $en   = (Get-AdvancedSetting -Entity $h -Name 'CBRC.Enable' -ErrorAction SilentlyContinue).Value
    $mem  = (Get-AdvancedSetting -Entity $h -Name 'CBRC.DCacheMemReservationMB' -ErrorAction SilentlyContinue).Value
    $size = (Get-AdvancedSetting -Entity $h -Name 'CBRC.DCacheSize' -ErrorAction SilentlyContinue).Value
    $bad  = ($en -ne 1) -or ([int]$mem -lt $MinCbrcMB)
    if ($bad) {
        [pscustomobject]@{
            Host               = $h.Name
            CBRC_Enabled       = $en -eq 1
            DCacheReservMB     = $mem
            DCacheSize         = $size
            MinReservation     = $MinCbrcMB
        }
    }
}

$TableFormat = @{
    CBRC_Enabled    = { param($v,$row) if ($v -ne $true) { 'bad' } else { 'ok' } }
    DCacheReservMB  = { param($v,$row) if ([int]$v -lt $MinCbrcMB) { 'warn' } else { '' } }
}
