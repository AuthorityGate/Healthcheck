# AuthorityGate HealthCheck

GUI-driven health-check runner for the **Omnissa / VMware Horizon** stack: Horizon, **App Volumes, Dynamic Environment Manager, Enrollment Server, Unified Access Gateway**, plus the **vSphere / vSAN / NSX** infrastructure that backs it. Plugin-based architecture with VHA-style severity tagging; deep gold-image capture; consultant-grade HTML + Word reporting.

- **No parameters required.** Double-click `RunGUI.cmd`, configure connections in the form, click **Run**.
- **5 independent connection tabs:** Horizon, vCenter, App Volumes, UAG, NSX. Run with any one, any combination, or all five. Plugins skip silently when their target side isn't connected.
- **386 KB-aligned plugins** across 21 categories — vSphere security configuration guide compliance, HA/DRS sizing, storage performance, VDI gold-image deep capture, and more. Severity tags (P1/P2/P3/Info) follow the VMware Health Analyzer convention.
- **Two report formats.** HTML (always) and Word `.docx` (optional) with title page, version table, executive summary, generated TOC, and native Word tables per finding.

## Plugin coverage at a glance

| # | Category | Plugins | Highlights |
|---|---|---|---|
| 00 | Initialize | 2 | Auth verification per side |
| 10 | Connection Servers | 18 | Inventory, health, version drift, vCenter registration, **event DB**, **time skew vs domain (KB 57147)**, **Composer deprecation**, **SAML / RADIUS / smart-card / TrueSSO / Workspace ONE / Helpdesk**, recovery password |
| 20 | Cloud Pod Architecture | 4 | Pods, sites, global desktop + application entitlements |
| 30 | Desktop Pools | 12 | Inventory, provisioning errors, capacity, spare drift, snapshot age, customization, network, OU, USB redirection |
| 40 | RDS Farms | 6 | Inventory, host health, app pools, anti-affinity, capacity, logoff/disconnect timers |
| 50 | Machines | 8 | State summary, problem states, agent drift, orphan assignments, vCenter mismatch, missing-from-pool, persistent disk drift, agent heartbeat |
| 60 | Sessions | 8 | Per-state, per-pool, per-protocol, per-gateway, vs CCU, long-active, client distribution |
| 70 | Events | 4 | Critical, failed-auth, **provisioning failures**, push-image / recompose failures |
| 80 | Licensing & Certificates | 6 | Horizon license, CS cert probe, **`vdm` friendly-name**, SAML metadata currency, federation certs, chain depth |
| 90 | Gateways (UAG) | 11 | UAG version, **edge services, TLS profile, certs (user + admin), auth methods, syslog, password policy, sessions, network** |
| 91 | App Volumes | 23 | Manager cluster, license, datastores, packages, assignments, attachments, writables, storage groups, AD, ThinApp, errors |
| 92 | Dynamic Environment Manager | 14 | Config + profile share reachability, agent version, FlexEngine logon, FlexProfiles, triggered tasks, redirection, elevation, conditions, backup |
| 93 | Enrollment Server | 10 | Inventory, issuance failures, CA registrations, cert template, time sync, forest trust, success rate |
| 94 | NSX | 24 | Manager cluster, edges, transport nodes/zones, Tier-0/Tier-1, segments, **DFW policies**, alarms, **certs**, **backup + history**, LB, IPSec, users, role bindings, DHCP/DNS, uplink profiles, service insertion, VTEP MTU |
| 95 | vSphere Backing Infra | 15 | Host state, **NTP (KB 57147)**, **power policy (KB 1018196)**, build currency, HA/DRS, datastore free, snapshots, mounted ISO (KB 78809), **scratch (KB 1033696)**, **core dump (KB 2004299)**, host profile, mgmt redundancy, BIOS power, microcode, memory reliability |
| 96 | vSphere Standalone | 38 | **MTU drift (KB 1038828)**, **port-group security (KB 1010935)**, NIC teaming, link state, **multipathing (KB 2069356)**, **dead paths (KB 1009039)**, **vSAN health (KB 2114803)**, storage policy, firewall, **SSH/Shell + Lockdown (KB 1017910)**, syslog (KB 2003322), **host cert expiry (KB 2113034)**, **CPU ready (KB 2002181)**, ballooning (KB 1004775), Tools currency (KB 1014294), **HW drift, NTP/DNS list, SSO password policy, dvs health-check, TLS profile, encryption posture, custom attributes, DRS rules, recent failed tasks, roles + permissions, datacenter inventory, disconnected NICs, thin disks, vMotion frequency, solution users, plugin manager** |
| 97 | vSphere for Horizon | 14 | **Cluster sizing (KB 70327)**, **SDRS unsupported (KB 2148895)**, parent VM hardware/SCSI/NIC (KB 1010398), time-sync, vCenter ops limits, **CBRC (KB 2107811)**, **service-account privileges (KB 88016)**, datastore SIOC + latency, snapshot consolidation, alarms, **Hot-Add disabled, Secure Boot, vTPM (Win11)** |
| 98 | vSAN | 13 | **OSA vs ESA**, disk groups, dedupe + compression, **encryption**, default policy, **HCL currency**, resync, **witness host**, file services, performance service, **slack space**, network latency |
| 99 | vSphere Lifecycle | 7 | vLCM image mode, image profile drift, pending reboot, build vs CVE, **VAMI health**, DB disk, Tools versions |
| A0 | Hardware | 8 | Hyper-Threading, memory modules, CPU SKU drift, BIOS drift, **PSU sensors**, HBA inventory, SMART pre-fail, asset / warranty |

## Quick start

1. Clone or download.
2. (Optional) Install [VMware PowerCLI](https://developer.vmware.com/powercli) — required for the vSphere / vSAN categories. `Install-Module VMware.PowerCLI`.
3. Double-click **`RunGUI.cmd`**. Pick the tabs you need (Horizon, vCenter, App Volumes, UAG, NSX), fill credentials, hit each tab's **Test** to verify, then **Run Health Check**.

```text
[ Horizon ]  [ vCenter ]  [ App Volumes ]  [ UAG ]  [ NSX ]
[x] Connect to this target
Server FQDN:  cs1.corp.example.com
Username:     svc-horizon
Password:     ******
Domain:       CORP
[ ] Skip cert validation (lab)
[ Test ]
```

## CLI

```powershell
# Horizon + vCenter, HTML + Word
.\Invoke-HorizonHealthCheck.ps1 -Server cs1.corp.example.com -VCServer vc1.corp.example.com -Word

# vCenter only — full vSphere + vSAN check, no Horizon required
.\Invoke-HorizonHealthCheck.ps1 -VCServer vc1.corp.example.com -SkipCertificateCheck

# Horizon only
.\Invoke-HorizonHealthCheck.ps1 -Server cs1.corp.example.com

# Single plugin set
.\Invoke-HorizonHealthCheck.ps1 -Server cs1 -PluginFilter "*Pool*"
```

CLI currently exposes Horizon + vCenter; App Volumes / UAG / NSX are GUI-only today (run them via `RunGUI.cmd`). Reports land in `.\Reports\HealthCheck-<server>-<timestamp>.{html,docx}`.

## Compatibility

| Target | Minimum supported | Recommended / tested |
|---|---|---|
| **VMware / Omnissa Horizon** | Horizon 8 **2106** (REST API GA) | **Horizon 8 2206+** for full coverage; tested against **Omnissa Horizon 8 2406 / 2412** |
| **App Volumes** | 4.x | Omnissa **App Volumes 2403+** |
| **DEM** | DEM 9.x | Omnissa **DEM 2403+** (REST + FlexEngine) |
| **Enrollment Server** | 2106+ | Co-installed with current Horizon |
| **Unified Access Gateway** | 2103+ | Omnissa **UAG 2406+ LTSR** |
| **NSX** | NSX-T 3.2 | **NSX 4.1+** / NSX-T 4.x |
| **vCenter Server** | **6.7** | **7.0 U3+** or **8.0 U2/U3**; ready for **vSphere 9.x** |
| **ESXi**            | **6.7** | **7.0 U3+** or **8.0 U2/U3** |
| **PowerCLI**        | 12.7 | **13.x** (current) |
| **PowerShell**      | 5.1 (Windows-bundled) | 7.4+ |
| **Microsoft Word**  | 2007 | 2019+ (only for `.docx`) |

A plugin that hits an endpoint not present on the connected version returns zero items rather than failing — older targets simply produce a thinner report.

## Severity model (VHA convention)

| Code | Meaning |
|------|---------|
| **P1** | Critical — fix now (outage, security, or data loss in flight) |
| **P2** | High — fix in the next maintenance window |
| **P3** | Medium — planned remediation |
| **Info** | Informational only — no action implied |

The HTML report colour-bands each section; the Word doc tags every plugin's heading with `[P1]` / `[P2]` / `[P3]` / `[Info]` / `[OK]`.

## Architecture

```
AuthorityGateHealthCheck/
├─ Start-HorizonHealthCheckGUI.ps1   # WinForms launcher (no params, 5 tabs)
├─ RunGUI.cmd                        # Double-clickable shortcut
├─ Invoke-HorizonHealthCheck.ps1     # CLI runner
├─ GlobalVariables.ps1               # Default thresholds
├─ Modules/
│  ├─ HorizonRest.psm1               # Bearer-auth REST wrapper for Horizon 8 / 2x
│  ├─ AppVolumesRest.psm1            # Cookie-session REST wrapper for App Volumes
│  ├─ UAGRest.psm1                   # Basic-auth REST wrapper for UAG admin
│  ├─ NSXRest.psm1                   # Basic-auth REST wrapper for NSX 3.x / 4.x
│  ├─ HtmlReport.psm1                # Severity-banded HTML
│  └─ WordReport.psm1                # Comprehensive .docx via Word.Application COM
└─ Plugins/
   ├─ 00 Initialize/...
   ├─ 10 Connection Servers/...
   ├─ 20 Cloud Pod Architecture/...
   ├─ 30 Desktop Pools/...
   ├─ 40 RDS Farms/...
   ├─ 50 Machines/...
   ├─ 60 Sessions/...
   ├─ 70 Events/...
   ├─ 80 Licensing and Certificates/...
   ├─ 90 Gateways/...                  # UAG admin REST
   ├─ 91 App Volumes/...
   ├─ 92 Dynamic Environment Manager/...
   ├─ 93 Enrollment Server/...
   ├─ 94 NSX/...
   ├─ 95 vSphere Backing Infra/...
   ├─ 96 vSphere Standalone/...
   ├─ 97 vSphere for Horizon/...       # Both Horizon + vCenter required
   ├─ 98 vSAN/...
   ├─ 99 vSphere Lifecycle/...
   ├─ 99 Disconnect/...
   └─ A0 Hardware/...
```

## Plugin contract

Every plugin sets metadata variables and emits objects via the pipeline. The runner captures both.

```powershell
# Start of Settings
$ThresholdHours = 48
# End of Settings

$Title          = "Long-Disconnected Sessions"
$Header         = "[count] session(s) disconnected longer than $ThresholdHours hours"
$Comments       = "Disconnected sessions hold a desktop and consume CCU."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "60 Sessions"
$Severity       = "P2"        # P1 | P2 | P3 | Info
$Recommendation = "Lower the disconnected-session timeout in Global Settings."
$TableFormat = @{ DaysLeft = { param($v,$row) if ([int]$v -lt 30) { 'bad' } elseif ([int]$v -lt 60) { 'warn' } else { '' } } }

if (-not (Get-HVRestSession)) { return }
Get-HVSession | Where-Object { $_.session_state -eq 'DISCONNECTED' } | ForEach-Object {
    [pscustomobject]@{ User = $_.user_name; Machine = $_.machine_name; ... }
}
```

`[count]` in `$Header` is replaced with the number of objects emitted. If a plugin emits zero objects the section renders as `[OK]` and is skipped in the P1/P2/P3 tally.

## Adding a check

1. Pick (or create) a category folder under `Plugins\`.
2. Drop a new file `NN Some Description.ps1`.
3. Set the metadata variables, gate on the right session (`Get-HVRestSession`, `$Global:VCConnected`, `Get-AVRestSession`, `Get-UAGRestSession`, `Get-NSXRestSession`), emit `[pscustomobject]` rows.
4. The runner picks it up automatically; the GUI shows it in the plugin tree on next launch.

## Requirements

**AuthorityGate HealthCheck only reads.** Every backend should be configured with a dedicated read-only service account. See [`docs/PERMISSIONS.md`](docs/PERMISSIONS.md) for the per-target least-privilege guide — it specifies the exact built-in role to use for each backend (`Read-only` on vCenter, `Administrators (Read only)` on Horizon, `Auditor` on NSX, `Administrator (Read-only)` on App Volumes, default Domain User on AD), the `GET`-only API endpoints the tool calls, the compensating controls for backends without a read-only role (UAG), and the audit-log queries you should run after each scan to prove the service accounts never touched a write verb.

| Requirement | Notes |
|---|---|
| TCP/443 to Horizon Connection Servers | Horizon REST (`GET` only). |
| TCP/443 to vCenter | vSphere SDK (read role). |
| TCP/443 to App Volumes Manager | AV REST (`GET` only). |
| TCP/9443 to UAG admin | UAG REST (`GET` only; no read-only role exists — see PERMISSIONS doc). |
| TCP/443 to NSX Manager | NSX REST, `Auditor` role. |
| TCP/9389 to a Domain Controller (ADWS) | AD plugins; default Domain User suffices. |
| TCP/5985 (or 5986) to gold images | Optional — enables in-guest deep scan. Requires Local Admin on the image. |
| **Read-only roles on every side** | Every plugin uses `Get-*` / REST `GET` only. If a plugin appears to require write rights, that's a bug — open an issue. |
| `VMware.PowerCLI` | Required for `95 / 96 / 97 / 98 / 99 / A0`. |
| Microsoft Word 2007+ | Only when `-Word` / GUI "Generate Word .docx" is enabled. |

## Configuration

Defaults live in `GlobalVariables.ps1`. Per-plugin tunables live between `# Start of Settings` and `# End of Settings` at the top of each plugin — sweep through annually and edit thresholds in place.

GUI state (server FQDNs, output path, plugin selections — never passwords) persists at `%APPDATA%\HorizonHealthCheck\state.json` (the on-disk folder name is preserved across the v0.94.1 product rename so existing operators don't lose their saved tab settings).

## Acknowledgements

- VMware Health Analyzer (VHA) — severity convention (P1/P2/P3) and per-finding KB-ID format.

## License

See `LICENSE`. Production / commercial use by non-AuthorityGate-PSO clients requires a license key — contact `Sales@authoritygate.com`. Pre-v2.0 releases on the `v1.x-final-mit` tag remain MIT-licensed.
