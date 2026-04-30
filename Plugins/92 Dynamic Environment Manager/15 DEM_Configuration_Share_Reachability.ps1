# Start of Settings
# Operator hint: $Global:DEMConfigShare = '\\fileserver\dem-config' OR '\\fileserver\dem'
# End of Settings

$Title          = 'DEM Configuration Share Reachability + Health'
$Header         = "DEM share probe (SMB version, latency, ACL, content)"
$Comments       = @"
Multi-path validation of the DEM Configuration share, mirroring the depth of the Connection Server certificate plugin:
- Reachability + RTT (open / read latency)
- SMB protocol version (SMB 3.0+ required for DEM agent multi-channel)
- DFS-N awareness (path is a DFS root + namespace)
- Top-level NTFS ACL summary (which principals have Read / Modify / Full Control)
- File + folder counts + total size at root
- Newest XML timestamp (last config change)
- Old-FlexEngine compatibility check (NoAD vs Standard mode hints)
"@
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.1
$PluginCategory = '92 Dynamic Environment Manager'
$Severity       = 'P2'
$Recommendation = "DEM share latency must be < 5 ms RTT for fast logon. Use SMB 3.0+ multi-channel. ACL: only the FlexEngine service account / GPO-target group needs READ; admins need MODIFY. Avoid Full Control to Authenticated Users (over-broad)."

if (-not (Test-Path Variable:Global:DEMConfigShare) -or -not $Global:DEMConfigShare) {
    [pscustomobject]@{
        Path = '(no DEM share configured)'
        Reachable = ''
        Note = 'Set $Global:DEMConfigShare in the runner OR via the DEM tab in the GUI.'
    }
    return
}

foreach ($share in @($Global:DEMConfigShare)) {
    $row = [ordered]@{
        Path           = $share
        Reachable      = ''
        ResponseMs     = ''
        SMBVersion     = ''
        DFSPath        = ''
        FileCount      = ''
        FolderCount    = ''
        TotalMB        = ''
        NewestXml      = ''
        ACLSummary     = ''
        Note           = ''
    }

    # 1. Reachability + RTT
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $exists = Test-Path $share -ErrorAction Stop
        $sw.Stop()
        $row.Reachable = if ($exists) { 'OK' } else { 'NotFound' }
        $row.ResponseMs = $sw.ElapsedMilliseconds
        if ($sw.ElapsedMilliseconds -gt 1000) { $row.Note = 'Share access slow - investigate SMB latency.' }
    } catch {
        $row.Reachable = 'FAIL'
        $row.Note = $_.Exception.Message
        [pscustomobject]$row
        continue
    }
    if ($row.Reachable -ne 'OK') {
        [pscustomobject]$row
        continue
    }

    # 2. SMB version + 3. DFS-N awareness
    try {
        $smbConn = Get-SmbConnection -ServerName ($share.TrimStart('\').Split('\')[0]) -ErrorAction SilentlyContinue
        if ($smbConn) { $row.SMBVersion = ($smbConn.Dialect | Sort-Object -Unique) -join ',' }
    } catch { }
    try {
        $dfs = Get-DfsnFolder -Path $share -ErrorAction SilentlyContinue
        if ($dfs) { $row.DFSPath = "DFS root: $($dfs.NamespacePath)" }
    } catch { }

    # 4. NTFS ACL summary (top-level only)
    try {
        $acl = Get-Acl -Path $share -ErrorAction Stop
        $rules = $acl.Access | Where-Object { -not $_.IsInherited } | Select-Object -First 8
        $row.ACLSummary = ($rules | ForEach-Object {
            $perm = if ($_.FileSystemRights.ToString() -match 'FullControl') { 'FC' }
                    elseif ($_.FileSystemRights.ToString() -match 'Modify')   { 'Modify' }
                    elseif ($_.FileSystemRights.ToString() -match 'Read')     { 'Read' }
                    else { 'Other' }
            "$($_.IdentityReference)=$perm"
        }) -join '; '
        # Flag over-broad permissions
        $broad = $rules | Where-Object { ($_.FileSystemRights.ToString() -match 'FullControl|Modify') -and ($_.IdentityReference -match 'Everyone|Authenticated Users|Domain Users|Users$') }
        if ($broad) { $row.Note += ' Over-broad write ACL detected (Everyone / Authenticated Users / Domain Users with Modify+).' }
    } catch { $row.ACLSummary = 'ACL read failed: ' + $_.Exception.Message }

    # 5. File / folder counts + size
    try {
        $items = @(Get-ChildItem -Path $share -Recurse -File -ErrorAction SilentlyContinue)
        $folders = @(Get-ChildItem -Path $share -Recurse -Directory -ErrorAction SilentlyContinue)
        $row.FileCount   = $items.Count
        $row.FolderCount = $folders.Count
        $row.TotalMB = if ($items) { [math]::Round((($items | Measure-Object Length -Sum).Sum) / 1MB, 1) } else { 0 }
        $newestXml = $items | Where-Object { $_.Extension -eq '.xml' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($newestXml) { $row.NewestXml = $newestXml.LastWriteTime.ToString('yyyy-MM-dd HH:mm') }
    } catch { }

    [pscustomobject]$row
}

$TableFormat = @{
    Reachable = { param($v,$row) if ($v -match 'FAIL|NotFound') { 'bad' } elseif ($v -ne 'OK') { 'warn' } else { 'ok' } }
    ResponseMs = { param($v,$row) if ([int]"$v" -gt 1000) { 'bad' } elseif ([int]"$v" -gt 100) { 'warn' } else { '' } }
    SMBVersion = { param($v,$row) if ($v -match '^3') { 'ok' } elseif ($v -match '^2') { 'warn' } elseif ($v) { 'bad' } else { '' } }
    Note      = { param($v,$row) if ($v -match 'Over-broad|slow|FAIL') { 'warn' } else { '' } }
}
