# Start of Settings
# End of Settings

$Title          = "Consolidated License Expiry Calendar"
$Header         = "All license-bearing assets across the stack on one timeline"
$Comments       = "Aggregates license expiry data from every connected backend (Horizon, vCenter, Nutanix, App Volumes, UEM, etc.) into one chronologically-sorted view. The single 'when do we have to renew what' page for the engagement."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "C3 License Lifecycle"
$Severity       = "P2"
$Recommendation = "Anything within 90 days warrants a renewal procurement track open NOW. Within 30 days = escalate. Expired = either the audit caught a compliance gap OR the license was renewed but the install lags - validate."

$rows = New-Object System.Collections.ArrayList

# --- Horizon ---
if ($Global:HVSession) {
    try {
        $lic = Get-HVLicense
        if ($lic) {
            $exp = $null
            try { $exp = if ($lic.expiration_time) { (Get-Date '1970-01-01').AddMilliseconds([int64]$lic.expiration_time) } else { $null } } catch { }
            [void]$rows.Add([pscustomobject]@{
                Product = 'Horizon'
                Item    = $lic.license_key
                Edition = $lic.license_edition
                Expires = if ($exp) { $exp.ToString('yyyy-MM-dd') } else { '' }
                DaysToExpiry = if ($exp) { [int]($exp - (Get-Date)).TotalDays } else { '' }
                Source  = "Horizon $($Global:HVSession.Server)"
            })
        }
    } catch { }
}
# --- vCenter ---
if ($Global:VCConnected) {
    try {
        $lm = Get-View ServiceInstance | ForEach-Object { Get-View $_.Content.LicenseManager -ErrorAction SilentlyContinue }
        foreach ($l in @($lm.Licenses)) {
            if (-not $l) { continue }
            $expProp = $l.Properties | Where-Object Key -eq 'expirationDate'
            $expRaw = if ($expProp) { $expProp.Value } else { $null }
            $exp = $null
            try { if ($expRaw) { $exp = [datetime]$expRaw } } catch { }
            [void]$rows.Add([pscustomobject]@{
                Product = 'vSphere/vCenter'
                Item    = $l.Name
                Edition = $l.EditionKey
                Expires = if ($exp) { $exp.ToString('yyyy-MM-dd') } else { '(no expiry / perpetual)' }
                DaysToExpiry = if ($exp) { [int]($exp - (Get-Date)).TotalDays } else { '' }
                Source  = 'vCenter LicenseManager'
            })
        }
    } catch { }
}
# --- Nutanix ---
if ($Global:NTNXSession) {
    try {
        $licNtnx = Get-NTNXLicense
        foreach ($n in @($licNtnx)) {
            if (-not $n) { continue }
            $exp = $null
            try { if ($n.expiry_date) { $exp = [datetime]$n.expiry_date } } catch { }
            [void]$rows.Add([pscustomobject]@{
                Product = 'Nutanix'
                Item    = $n.edition
                Edition = $n.license_category
                Expires = if ($exp) { $exp.ToString('yyyy-MM-dd') } else { '' }
                DaysToExpiry = if ($exp) { [int]($exp - (Get-Date)).TotalDays } else { '' }
                Source  = "Prism $($Global:NTNXSession.Server)"
            })
        }
    } catch { }
}
# --- App Volumes ---
if ($Global:AVSession) {
    try {
        $avLic = Get-AVLicense
        if ($avLic) {
            $exp = $null
            try { if ($avLic.expiration_date) { $exp = [datetime]$avLic.expiration_date } } catch { }
            [void]$rows.Add([pscustomobject]@{
                Product = 'App Volumes'
                Item    = $avLic.serial_number
                Edition = $avLic.product_name
                Expires = if ($exp) { $exp.ToString('yyyy-MM-dd') } else { '' }
                DaysToExpiry = if ($exp) { [int]($exp - (Get-Date)).TotalDays } else { '' }
                Source  = "AppVol $($Global:AVSession.Server)"
            })
        }
    } catch { }
}
# --- Veeam ---
if ($Global:VeeamSession) {
    try {
        $vbrLic = Get-VeeamLicense
        if ($vbrLic) {
            $exp = $null
            try { if ($vbrLic.expirationDate) { $exp = [datetime]$vbrLic.expirationDate } } catch { }
            [void]$rows.Add([pscustomobject]@{
                Product = 'Veeam B&R'
                Item    = $vbrLic.licensedTo
                Edition = $vbrLic.edition
                Expires = if ($exp) { $exp.ToString('yyyy-MM-dd') } else { '' }
                DaysToExpiry = if ($exp) { [int]($exp - (Get-Date)).TotalDays } else { '' }
                Source  = "VBR $($Global:VeeamSession.Server)"
            })
        }
    } catch { }
}

if ($rows.Count -eq 0) {
    [pscustomobject]@{ Note = 'No licensed assets connected. Calendar is empty.' }
    return
}
$rows | Sort-Object @{Expression='DaysToExpiry'; Descending=$false}

$TableFormat = @{
    DaysToExpiry = { param($v,$row)
        if ($v -eq '' -or $null -eq $v) { '' }
        elseif ([int]"$v" -lt 0)        { 'bad' }
        elseif ([int]"$v" -lt 30)       { 'bad' }
        elseif ([int]"$v" -lt 90)       { 'warn' }
        else                            { 'ok' }
    }
}
