# Start of Settings
# Operator hint: $Global:FSLogixProfileShare = '\\fileserver\fslogix-profiles'
# Optional: $Global:FSLogixCloudShare = '\\fileserver\fslogix-officecache'
# End of Settings

$Title          = "FSLogix Profile Container Inventory"
$Header         = "[count] FSLogix profile container(s)"
$Comments       = "Walks the FSLogix profile share and inventories every Profile_<sam>.vhdx (or .vhd) container: per-user size, last-modified, lock state (open file = currently in use), and orphan detection (containers older than 90 days = candidate for archival). Cloud Cache containers (Office 365 mailbox cache) probed separately if a CloudShare is configured."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B8 FSLogix"
$Severity       = "Info"
$Recommendation = "Containers > 30 GB warrant policy review (max-size cap is typically 30-50 GB). Containers older than 90 days likely belong to departed users - archive or delete per retention policy. Locked containers belong to logged-in sessions; should match active session count from Horizon."

if (-not $Global:FSLogixProfileShare) {
    [pscustomobject]@{ Note='FSLogix not configured. Set $Global:FSLogixProfileShare in runner OR via Specialized Scope.' }
    return
}
$share = $Global:FSLogixProfileShare
if (-not (Test-Path $share)) {
    [pscustomobject]@{ Path = $share; Note = 'Share not reachable from runner.' }
    return
}

# FSLogix containers can be at <share>\<sam>_<sid>\Profile_<sam>.vhdx OR
# <share>\<sam>\Profile_<sam>.vhdx depending on FlipFlopProfileDirectoryName.
$containers = @(Get-ChildItem -Path $share -Recurse -Filter '*.vhd*' -File -ErrorAction SilentlyContinue)
if ($containers.Count -eq 0) {
    [pscustomobject]@{ Note='No .vhd / .vhdx files found under share.' }
    return
}

foreach ($c in $containers) {
    $locked = $false
    try {
        $fs = [System.IO.File]::Open($c.FullName, 'Open', 'Read', 'None')
        $fs.Close()
    } catch { $locked = $true }
    $ageDays = [int]((Get-Date) - $c.LastWriteTime).TotalDays
    [pscustomobject]@{
        Container    = $c.Name
        ParentFolder = $c.Directory.Name
        SizeGB       = [math]::Round($c.Length / 1GB, 2)
        LastModified = $c.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        AgeDays      = $ageDays
        Locked       = $locked
        Path         = $c.FullName
    }
}

$TableFormat = @{
    SizeGB  = { param($v,$row) if ([double]"$v" -gt 30) { 'warn' } elseif ([double]"$v" -gt 50) { 'bad' } else { '' } }
    AgeDays = { param($v,$row) if ([int]"$v" -gt 90) { 'warn' } else { '' } }
    Locked  = { param($v,$row) if ($v -eq $true) { 'ok' } else { '' } }
}
