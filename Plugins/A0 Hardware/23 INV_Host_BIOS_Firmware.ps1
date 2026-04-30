# Start of Settings
# End of Settings

$Title          = 'Host BIOS Firmware'
$Header         = 'Per-host BIOS version + release date'
$Comments       = 'BIOS version drift between hosts in the same cluster causes inconsistent microcode (Spectre/Meltdown mitigations). Schedule yearly BIOS updates via vendor tooling.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = 'A0 Hardware'
$Severity       = 'Info'
$Recommendation = 'Update via Dell DSU / HPE SUM / Lenovo XClarity. Snapshot via this report quarterly.'

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue)) {
    $b = $null
    try { $b = $h.ExtensionData.Hardware.BiosInfo } catch { }

    # FirmwareMajorRelease / MinorRelease are optional in BiosInfo - some
    # vendors / hardware tiers omit them. Guard with null checks before
    # invoking ToString() to avoid the "method on null-valued expression" PSOD.
    $major = if ($b -and ($null -ne $b.FirmwareMajorRelease)) { $b.FirmwareMajorRelease } else { '' }
    $minor = if ($b -and ($null -ne $b.FirmwareMinorRelease)) { $b.FirmwareMinorRelease } else { '' }
    $firmware = if ($major -ne '' -or $minor -ne '') { "$major.$minor" } else { 'n/a' }

    [pscustomobject]@{
        Host             = $h.Name
        Cluster          = if ($h.Parent) { $h.Parent.Name } else { '' }
        Vendor           = $h.Manufacturer
        Model            = $h.Model
        BiosVersion      = if ($b) { $b.BiosVersion } else { 'unknown' }
        ReleaseDate      = if ($b -and $b.ReleaseDate) { ([datetime]$b.ReleaseDate).ToString('yyyy-MM-dd') } else { 'unknown' }
        FirmwareRevision = $firmware
        BiosAgeDays      = if ($b -and $b.ReleaseDate) { [int]((Get-Date) - [datetime]$b.ReleaseDate).TotalDays } else { 'unknown' }
    }
}
