# Permissions & Least-Privilege Guide

**AuthorityGate HealthCheck only reads.** No plugin in this repository writes, modifies, deletes, or reconfigures anything on any backend. Every check uses `Get-*` cmdlets, `GET` REST verbs, or read-side WMI/registry queries.

This document specifies, per backend, the **minimum** account configuration that lets the tool run a complete health check. Where a built-in read-only role exists, **use it**. Where one does not exist (UAG, in-guest WinRM probes), the document explains the smallest custom role that works and the compensating controls to apply.

> **Hard rule:** never grant more than what is in this document. If a plugin appears to require additional rights, that is a bug — open an issue rather than escalating the service account.

---

## Quick reference

| Backend | Recommended role | Privilege class | Network port |
|---|---|---|---|
| **vCenter Server** | `Read-only` (built-in), propagated to root with `System.Read` | Read-only, no write | TCP/443 |
| **Horizon Connection Server** | `Administrators (Read only)` (built-in) | Read-only, no write | TCP/443 |
| **App Volumes Manager** | `Administrator (Read-only)` (built-in) | Read-only, no write | TCP/443 |
| **Unified Access Gateway** | Admin REST user, **network-restricted to runner**, MFA-on-jumphost | No read-only role exists | TCP/9443 |
| **NSX Manager** | `Auditor` (built-in) | Read-only, no write | TCP/443 |
| **Active Directory** | Domain User (default) — no elevation | Read-only via AD ACL | TCP/9389 (ADWS) |
| **In-guest WinRM probe** | Local Administrator (gold images only, JIT recommended) | Local admin only | TCP/5985 (HTTP) or 5986 (HTTPS) |
| **DEM config share** | Read share-level + NTFS-Read on the SMB share | Read-only | TCP/445 |
| **Imprivata appliance** | Operator (read-only) | Read-only | TCP/443 |
| **MFA / RADIUS probe** | n/a — no auth, network-only probe | None | UDP/1812 (no creds sent) |

---

## 1. vCenter Server

### Built-in role

Use the **`Read-only`** built-in role. It contains exactly two privileges: `System.Anonymous` and `System.Read`. Propagate it from the **root vCenter object**, not just a single datacenter, so plugins that walk the inventory tree (`50 INV_vCenter_Inventory_Summary`, `30 INV_vSAN_Cluster_Full_Configuration`, etc.) can enumerate everything they need.

### Setup

```text
vSphere Client → Administration → Access Control → Global Permissions → Add
  User/Group: svc-healthcheck-ro@vsphere.local   (or AD: svc-healthcheck-ro@corp)
  Role:       Read-only
  [x] Propagate to children
```

### What this allows

* `Get-VM`, `Get-VMHost`, `Get-Cluster`, `Get-Datastore`, `Get-Datacenter`
* `Get-VirtualSwitch`, `Get-VDSwitch`, `Get-VirtualPortGroup`
* `Get-Snapshot`, `Get-AdvancedSetting`, `Get-VMHostHba`, `Get-VMHostNetworkAdapter`
* vSAN cluster, disk, object, policy queries via `Get-VsanClusterConfiguration`, `Get-VsanDisk`, etc.
* Lifecycle Manager (vLCM) image / baseline reads via `Get-LcmImage`, `Get-LcmCompliance`
* Tasks, alarms, events (read-only)

### What this does **not** allow

* Modifying any setting (no `Set-*`, `New-*`, `Remove-*`)
* Console access to VMs (no `VirtualMachine.Interact.ConsoleInteract`)
* Power operations (no `VirtualMachine.Interact.PowerOn`/`PowerOff`)
* Issuing certificates, installing VIBs, mounting ISOs

### Plugin that audits this account

Plugin `08 vCenter_Service_Account_Privileges` walks the **service account's own** privilege list and warns if anything beyond `System.Read` is granted. Run the tool against itself once after onboarding the account; the report should show `[OK]` for that plugin.

### vCenter SSO password rotation

Configure the SSO password policy with `vmdir`'s default 90-day expiry. The tool's GUI stores the password DPAPI-encrypted per-user-per-machine; rotate via `Manage Credentials...` after each cycle.

---

## 2. Horizon Connection Server

### Built-in role

Use the **`Administrators (Read only)`** built-in role. It is shipped with Horizon and grants every `GET` endpoint in the REST API (`/rest/v1/...`) without the ability to push images, recompose pools, or manage entitlements.

### Setup

```text
Horizon Console → Settings → Administrators → Add
  Group:    CN=horizon-healthcheck-ro,OU=Service Accounts,DC=corp,DC=example,DC=com
  Roles:    [x] Administrators (Read only)
  Access groups: / (root)
```

### What this allows

* Pool, farm, application, entitlement enumeration
* Session listing (current + historical via Event Database, read-only)
* Certificate, license, RADIUS / SAML / TrueSSO / smart-card configuration reads
* Connection Server inventory + version + recovery password readback (note: recovery password is intentionally readable by RO admins per VMware design — protect this account accordingly)
* Workspace ONE federation status

### What this does **not** allow

* Pushing images, recomposing pools, deleting machines
* Modifying entitlements, settings, or RADIUS/SAML configuration
* Disconnecting or logging off live sessions

### Compensating controls

* **Recovery password access:** the `Administrators (Read only)` role can read the connection-server recovery password via the REST API. If this is unacceptable in your environment, create a custom role that drops `MANAGE_RECOVERY_PASSWORD` and accept the matching plugin will report a permissions warning.
* Source-IP-restrict the service account at the AD level (Authentication Silo) to the runner workstation only.

---

## 3. App Volumes Manager

### Built-in role

Use **`Administrator (Read-only)`**. App Volumes 2403+ ships with three roles: `Administrator`, `Administrator (Read-only)`, and `Manager`. The read-only variant grants every `GET` endpoint we need (`/cv_api/machines`, `/cv_api/app_packages`, `/cv_api/assignments`, `/cv_api/storages`, `/cv_api/writables`, `/cv_api/storage_groups`, `/cv_api/system_messages`).

### Setup

```text
App Volumes Manager → Configuration → Administrator Roles → New
  Role: Administrator (Read-only)
  Group/User: svc-av-healthcheck-ro@corp.example.com
```

### What this allows

* Machine enumeration including agent_mode (ProvisioningMode vs RuntimeMode)
* Volume / package inventory and assignment graph
* Datastore, storage-group, ThinApp, AD-domain, license inventory
* System message + activity-log readback

### What this does **not** allow

* Provisioning, attaching, or detaching volumes
* Deleting AppStacks/packages
* Modifying storage groups or AD bindings

---

## 4. Unified Access Gateway (UAG)

### No read-only role exists

UAG's admin REST API on TCP/9443 has only one effective auth tier: the `admin` super-user. There is **no** read-only admin in current shipping versions. Mitigate accordingly:

1. **Dedicated UAG admin user per appliance**, named `healthcheck-ro` even though it is full admin functionally — names matter for audit.
2. **Strong password rotation** every 30 days (UAG admin REST password is independent of OS-side `root`).
3. **Network ACL** the management interface (port 9443) so only the runner workstation IP can reach it. UAG supports admin-network restriction via `adminNetwork` in the deployment INI.
4. **Audit log shipping**: enable UAG admin syslog and ship to your SIEM. The tool's calls land as `GET /rest/v1/monitor/...`, `GET /rest/v1/config/edgeservices`, etc., so any non-`GET` activity from this account is automatically suspicious.
5. Optional: a **separate UAG admin password per appliance** (UAG configs are per-instance), kept in AuthorityGate HealthCheck's profile store as one profile per UAG.

### What the tool actually calls

All endpoints are `GET`-only:

* `/rest/v1/config/system`
* `/rest/v1/config/edgeservices`
* `/rest/v1/config/system/tlsprofile`
* `/rest/v1/monitor/stats`
* `/rest/v1/monitor/sessions`
* `/rest/v1/config/identitybridging/*`
* `/rest/v1/config/system/syslog`

If you operate a UAG fleet, prefer a single bastion that proxies the runner's read calls and logs them centrally.

---

## 5. NSX Manager

### Built-in role

Use the **`Auditor`** role. It is shipped with NSX-T 3.x and NSX 4.x and grants read-only access to every Manager (`/api/v1/*`) and Policy (`/policy/api/v1/*`) endpoint.

### Setup

```text
NSX Manager → System → User Management → Role Assignments for Users → Add
  User:  svc-nsx-healthcheck-ro@corp.example.com   (vIDM-federated or local)
  Role:  Auditor
```

### What this allows

* Manager cluster + edge cluster + transport node/zone enumeration
* Tier-0 / Tier-1 / segment / DFW policy readback
* Alarms, certificates, backups, LB, IPSec, role bindings, DHCP/DNS, uplink profiles
* Service insertion + VTEP MTU diagnostics

### What this does **not** allow

* Editing DFW rules, segments, T0/T1 routing
* Triggering manual backups, rotating certificates
* Modifying RBAC or vIDM federation

---

## 6. Active Directory

### Standard Domain User — no elevation

Most AD plugins (`01 AD_Sites_and_Services`, `02 AD_Domain_Controllers`, `03 AD_Replication_Health`, `04 AD_FSMO_Roles`) read information that **every authenticated Domain User can already read** under the default AD ACL. **Do not** put the service account in `Domain Admins` or `Enterprise Admins`.

### Setup

```text
1. Create an AD service account: svc-healthcheck-ro@corp.example.com
2. Group memberships: only "Domain Users" (default).
3. Set the account password to never expire **only if** you compensate with
   Authentication Silo + LAPS-style rotation. Otherwise rotate per your policy.
4. Optional hardening:
   - Add to "Protected Users" group (kerberos-only, no NTLM).
   - Mark account "Sensitive and cannot be delegated".
   - Restrict logon-to: only the runner workstation.
```

### What this allows

The default ACL on AD lets authenticated users read:

* Forest / domain functional level (`Get-ADForest`, `Get-ADDomain`)
* Site topology (`Get-ADReplicationSite`, `Get-ADReplicationSiteLink`, `Get-ADReplicationSubnet`)
* Replication metadata (`Get-ADReplicationPartnerMetadata`)
* DC list, FSMO holders, schema version, tombstone lifetime

### What this does **not** allow

* Any write to the directory
* Reading sensitive attributes like LAPS passwords, BitLocker recovery keys, or KRBTGT secrets
* Group Policy edits

### Network ports

* **TCP/9389** — Active Directory Web Services (used by the `ActiveDirectory` PowerShell module)
* **TCP/389 / 636** — LDAP / LDAPS fallback
* **TCP/88** — Kerberos for service-account auth

---

## 7. In-Guest WinRM Probe (Gold Images, RDSH Masters, AppVolumes Packaging VMs)

### Why local Administrator

The gold-image deep-scan probe reads:

* `Get-CimInstance Win32_OperatingSystem` and `Win32_ComputerSystem`
* `Get-HotFix` (patch lag detection)
* `HKLM:\SOFTWARE\VMware, Inc.\VMware VDM\Agent` (Horizon Agent version)
* `HKLM:\SOFTWARE\FSLogix\Profiles` (FSLogix config)
* `HKLM:\SOFTWARE\CloudVolumes\Agent` (App Volumes agent mode)
* `Get-MpPreference` (Defender exclusions)
* `Get-CimInstance -Namespace Root\CIMV2\Security\MicrosoftVolumeEncryption Win32_EncryptableVolume` (BitLocker)
* `HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server` (RDP state)

These touch the registry HKLM hive and the BitLocker WMI namespace — Windows offers **no read-only equivalent**. The probe needs either local Administrator or a custom RBAC delegation that approximates it. Most environments accept the Administrator dependency on **gold-image VMs only** (which are short-lived, snapshotted, not user-facing).

### Recommended pattern

1. **Per-image local account, not domain account.** Gold images are typically workgroup-joined; create a per-image `svc-healthcheck-ro` local Administrator. Random 32-char password per image.
2. **Just-In-Time enablement.** The account is `Disabled` by default. Before each scheduled scan run, the gold-image admin enables it (manual or via a 1-line scheduled task), the run completes, the account auto-disables again.
3. **Store credentials in AuthorityGate HealthCheck's DPAPI profile store**, one profile per image, type `Local`. The store is at `%LOCALAPPDATA%\AuthorityGate\HorizonHealthCheck\credentials.xml` — DPAPI-bound to the runner user on the runner workstation. No other host can decrypt it.
4. **WinRM listener:** HTTP/5985 on the gold-image's internal-only network is acceptable on a trusted lab segment. HTTPS/5986 is preferred where a server-auth cert can be issued.
5. **TrustedHosts on runner:** for non-domain images, add the IP/hostname to `WSMan:\localhost\Client\TrustedHosts` so NTLM negotiation works. The provided `Tools\Test-GoldImageWinRM.ps1` walks operators through this.

### Compensating controls

* The credential never touches disk in plaintext (`ConvertFrom-SecureString` produces DPAPI ciphertext only).
* All probe commands are `Get-*` / read registry only — never `Set-*`, `Invoke-WMIMethod`, `New-Item`, etc.
* Plugin output explicitly lists what was read — easy to audit by diffing the report against this document.
* Defender / EDR signature: the probe's Invoke-VMScript fallback path will trip CrowdStrike and similar EDRs because remote-PowerShell-via-vmtoolsd looks like an attack pattern. **This is expected**. Either whitelist the runner workstation in your EDR, accept the alerts as legitimate health-check activity, or use the WinRM path (which does not look like an attack).

### What WinRM auth method to use

* **Domain images:** Kerberos — preferred. No TrustedHosts entry needed.
* **Workgroup / non-domain images (typical for gold):** Negotiate with NTLM fallback. Requires TrustedHosts entry on the runner.

---

## 8. Dynamic Environment Manager (DEM)

### Config share access

DEM stores its configuration in a UNC share, typically `\\fileserver\dem-config$`. The tool reads:

* `General\FlexEngine.xml` (FlexEngine config currency)
* `FlexProfiles\` (profile templates)
* `Triggered Tasks\` (scheduled task definitions)
* `Conditions\` (condition definitions)
* `Backup\` (backup history)

### Required permissions

* **Share-level:** `Read`
* **NTFS-level:** `Read & Execute, List folder contents, Read`

Grant to the same `svc-healthcheck-ro@corp` account or to a dedicated read-only group (preferred).

### What this does **not** allow

* Editing any DEM config
* Deleting profile archives
* Triggering FlexEngine logon/logoff actions

---

## 9. Imprivata OneSign

### Operator role (read-only)

The Imprivata appliance admin REST exposes an `Operator` role that grants read access to Authentication Server status, agent inventory, and policy currency. No write privilege.

### Setup

Refer to your Imprivata Admin Console → Users → Add Operator. Imprivata does not federate to AD by default; create a local appliance user.

### Network port

TCP/443 to each Imprivata appliance's admin interface.

---

## 10. MFA / RADIUS External Probe

The `01 MFA_External_Probe` plugin sends an unauthenticated UDP/1812 packet (well-formed RADIUS Access-Request with a deliberately wrong shared-secret) to verify the RADIUS server responds within a deadline. **No credentials are needed or sent** — the test is purely a reachability + response-time probe.

If your security policy disallows even unauthenticated UDP probes from the runner workstation, disable the plugin via the GUI's plugin tree.

---

## Service-account naming convention

Pick names that are unambiguous in audit logs. Recommended:

| Backend | Suggested account name |
|---|---|
| vCenter | `svc-vsphere-healthcheck-ro@vsphere.local` |
| Horizon | `svc-horizon-healthcheck-ro@corp.example.com` |
| App Volumes | `svc-av-healthcheck-ro@corp.example.com` |
| UAG | `healthcheck-ro` (local UAG admin, no domain) |
| NSX | `svc-nsx-healthcheck-ro@corp.example.com` |
| AD | `svc-ad-healthcheck-ro@corp.example.com` |
| In-guest gold image | `svc-img-healthcheck-ro` (local on each image) |

The `-ro` suffix is intentional — it makes accidental over-privilege visible in audit reports.

---

## Credential storage

* GUI session: passwords held only in WinForms in-memory `TextBox.Text`, never written to disk.
* Saved profiles: stored at `%LOCALAPPDATA%\AuthorityGate\HorizonHealthCheck\credentials.xml`, encrypted with **DPAPI** (per-user, per-machine). No master password protects the store at the application layer — Windows protects it. Moving the file to a different user account or machine renders it undecipherable.
* CLI usage: pass `-Credential (Get-Credential)` per run, do not bake credentials into shortcuts or scheduled tasks. For automation, use Windows Task Scheduler's stored-credential feature or a privileged-access tool that injects per-run.
* Export across machines: `Export-AGCredentialProfiles` produces a portable file encrypted with PBKDF2(100K) + AES-256 from a passphrase. The DPAPI ciphertext is decrypted at export time and re-encrypted with the passphrase, so the export survives moving between machines/users. Keep the passphrase out of band.

---

## Auditing the tool's own activity

Every backend listed above logs the service account's API calls. After each run, sample-audit:

* **vCenter:** Events tab → filter by user `svc-vsphere-healthcheck-ro` → all entries should be category `Info` and verb `read` / `query` / `enumerate`. Any `Set` / `Reconfigure` / `Power*` is a bug — file an issue.
* **Horizon:** Events DB query for `EventType` matching the service account → all should be `ADMIN_READ` class.
* **App Volumes:** Activity Log → filter by Manager username → all rows should be `read` operations.
* **NSX:** Audit log under `/var/log/policy/audit.log` and `/var/log/syslog` → only `GET` requests should appear.
* **AD:** Domain Controller Security log → 4624 (logon) entries only; no 4720/4732/4756 (account-mgmt) entries.

---

## Removing access

When decommissioning the runner workstation or rotating the project off this tooling:

1. Disable / delete each `svc-*-healthcheck-ro` account.
2. Run `Remove-Module CredentialProfiles; Remove-Item $env:LOCALAPPDATA\AuthorityGate\HorizonHealthCheck -Recurse` on the runner.
3. Remove the runner's IP from any backend network ACLs / Authentication Silos.
4. If TrustedHosts was edited for gold-image WinRM, restore it: `Set-Item WSMan:\localhost\Client\TrustedHosts -Value '' -Force`.

---

## Reporting permission gaps

If a plugin requires a privilege not listed here, open a GitHub issue tagged `permissions`. Do not work around it by escalating the service account. The plugin should either be fixable to use a less-privileged path, or be excluded from the default plugin set with documentation.
