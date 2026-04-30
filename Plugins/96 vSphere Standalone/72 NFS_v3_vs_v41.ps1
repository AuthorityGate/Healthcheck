# Start of Settings
# End of Settings

$Title          = 'NFS v3 vs v4.1 Inventory'
$Header         = '[count] NFS datastore(s); v3 entries surfaced'
$Comments       = "NFS v4.1 supports Kerberos auth, session trunking (multipathing), and parallel NFS (pNFS). NFS v3 has no native multipath - performance scaling requires multiple v3 mounts to multiple IPs. Migration is non-trivial (datastore remount + Storage vMotion)."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '96 vSphere Standalone'
$Severity       = 'P3'
$Recommendation = 'For new NFS mounts use v4.1 with Kerberos. For existing v3 datastores, migrate when array supports v4.1 - the upgrade path is unmount/remount + Storage vMotion of all VMs.'

if (-not $Global:VCConnected) { return }

foreach ($ds in (Get-Datastore -ErrorAction SilentlyContinue | Where-Object { $_.Type -in 'NFS','NFS41' } | Sort-Object Name)) {
    [pscustomobject]@{
        Datastore  = $ds.Name
        Type       = $ds.Type
        RemoteHost = $ds.RemoteHost
        RemotePath = $ds.RemotePath
        CapacityGB = [math]::Round($ds.CapacityGB,1)
        FreeGB     = [math]::Round($ds.FreeSpaceGB,1)
    }
}

$TableFormat = @{
    Type = { param($v,$row) if ($v -eq 'NFS') { 'warn' } else { '' } }
}
