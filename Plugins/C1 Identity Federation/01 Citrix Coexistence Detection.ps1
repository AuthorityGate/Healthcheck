# Start of Settings
# Optional override: $Global:CitrixDDC = 'ddc1.corp.local'
# Otherwise the plugin searches AD + DNS for the well-known names
# (ddc, storefront, citrix-ddc, controller).
# End of Settings

$Title          = "Citrix Coexistence Detection"
$Header         = "Citrix presence in this estate"
$Comments       = "Detects Citrix Virtual Apps & Desktops alongside Horizon. Probes well-known DNS names + TCP ports (1494 ICA, 2598 Session Reliability, 80/443 StoreFront). Many enterprises run BOTH platforms during migration windows; the report should call out coexistence for capacity / licensing / federation planning."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "C1 Identity Federation"
$Severity       = "Info"
$Recommendation = "If Citrix is detected: confirm whether the customer is consolidating onto Horizon (audit per-user license overlap), running both for application affinity (different app sets per platform), or in mid-migration. License double-pay = avoidable cost; document the exit path."

$candidates = @()
if ($Global:CitrixDDC) { $candidates += $Global:CitrixDDC }
# Common naming conventions
foreach ($base in @('ddc','controller','citrix-ddc','xa-controller','xenapp-ddc','storefront','citrix-sf')) {
    foreach ($suffix in @($env:USERDNSDOMAIN)) {
        if ($suffix) { $candidates += "$base.$suffix" }
    }
}

$rows = New-Object System.Collections.ArrayList
# NOTE: do NOT use $host as a foreach variable - $Host is a PowerShell
# automatic read-only variable; assignment throws 'Cannot overwrite
# variable Host because it is read-only or constant.'
foreach ($cand in ($candidates | Select-Object -Unique)) {
    if (-not $cand) { continue }
    $resolved = $false
    try { $null = [System.Net.Dns]::GetHostAddresses($cand); $resolved = $true } catch { }
    if (-not $resolved) { continue }
    $row = [ordered]@{
        Host      = $cand
        DNS       = $resolved
        ICA1494   = $false
        SR2598    = $false
        HTTPS443  = $false
        Note      = ''
    }
    foreach ($p in @(@{Name='ICA1494';Port=1494},@{Name='SR2598';Port=2598},@{Name='HTTPS443';Port=443})) {
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $iar = $tcp.BeginConnect($cand, $p.Port, $null, $null)
            if ($iar.AsyncWaitHandle.WaitOne(2500)) { $tcp.EndConnect($iar); $row[$p.Name] = $true }
            $tcp.Close()
        } catch { }
    }
    if ($row.ICA1494 -or $row.SR2598) { $row.Note = 'Citrix VDA / DDC detected' }
    elseif ($row.HTTPS443) { $row.Note = 'StoreFront / web frontend candidate' }
    [void]$rows.Add([pscustomobject]$row)
}

if ($rows.Count -eq 0) {
    [pscustomobject]@{ Note = 'No Citrix-style hostname resolved in $env:USERDNSDOMAIN. Set $Global:CitrixDDC manually if Citrix exists under a non-standard name.' }
    return
}
$rows

$TableFormat = @{
    ICA1494 = { param($v,$row) if ($v -eq $true) { 'warn' } else { '' } }
    SR2598  = { param($v,$row) if ($v -eq $true) { 'warn' } else { '' } }
}
