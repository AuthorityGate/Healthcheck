# Licensing & Telemetry — Design Plan

**Status:** Proposed (awaiting decisions)
**Owner:** AuthorityGate Engineering
**Audience:** AuthorityGate (build), customers (read on request)

---

## 1. Goal

Move HealthCheckPS1 from "MIT — anyone may use, modify, distribute" to "source-available, commercial use requires AuthorityGate license", and instrument every run so AuthorityGate has telemetry on who is using the tool, against what, and on whose engagement.

Three pillars:

1. **License update** — LICENSE file rewritten to a Source-Available model. PSO clients use freely; non-PSO clients email `Sales@authoritygate.com`.
2. **License gating** — Tool will not execute without a valid license. Licenses are emailed (signed JWT), bound to a single machine, valid for **3 days**.
3. **Run telemetry** — Each run posts metadata (email, time, hostname, targets, doc author, customer engagement) to `License.AuthorityGate.com`. New dashboard page tracks issuance + usage.

---

## 2. License model change

### 2.1 Current state
LICENSE in repo is **MIT**. The MIT grant is irrevocable on copies already distributed — anyone who downloaded the MIT-licensed code keeps those rights forever for the version they hold. Going forward we can re-license future versions.

### 2.2 Proposed: AuthorityGate Source-Available License v1.0

Modeled on Sentry's Functional Source License (FSL) + Business Source License (BSL) carve-outs. Key terms:

| Right | Free use | License required |
|---|---|---|
| **Read source code** | yes | — |
| **Evaluation / non-production use** | yes (30-day evaluation cap) | — |
| **Personal lab / training** | yes | — |
| **Production / commercial use by an AuthorityGate PSO customer** | yes | — |
| **Production use by anyone else** | no | yes — `Sales@authoritygate.com` |
| **Redistribution of binaries / modifications** | no | yes — written permission |
| **Modifications for internal use** | yes if you also have a license | yes — notify `Sales@authoritygate.com` |
| **Sublicensing as a competing product** | never | never |

### 2.3 Migration plan

1. Tag current `main` as `v1.x-final-mit` so the MIT history is preserved.
2. Cut `v2.0.0` with new LICENSE + license-gating code.
3. Update README to:
   - Quote the new license terms in the "License" section
   - Add a one-line callout: "Production use requires a license. Email `Sales@authoritygate.com`."
4. Existing MIT clones remain legally usable in their downloaded form forever — that is intentional and unavoidable.

---

## 3. Architecture

### 3.1 Components

```
+--------------------------+        +-------------------------------------+
|   HealthCheckPS1 Tool    |        |   License.AuthorityGate.com       |
|                          |        |                                     |
|  Modules/Licensing.psm1  | <----> |  /api/license/request               |
|  GUI License tab         |        |  /api/license/status                |
|  Pre-run license check   |        |  /api/usage                         |
|  Post-run telemetry POST |        |  Admin: /admin/licenses             |
|  Local: license.jwt      |        |  Admin: /admin/usage                |
+--------------------------+        +-------------------------------------+
                                          |          |
                                          |          +--> PostgreSQL
                                          |          |     licenses table
                                          |          |     usage_events table
                                          |          |
                                          +--> Email (Sales@authoritygate.com)
```

### 3.2 License token format

Ed25519-signed JWT. Tool ships with the public key embedded; verifies offline (no per-run dashboard call needed for validation).

```json
{
  "iss": "license.authoritygate.com",
  "sub": "consultant@customer.com",
  "machine": "<sha256(MachineGuid)>",
  "hostname": "WS-JDOE01",
  "engagement": "ACME-Q2-2026",
  "iat": 1714324800,
  "exp": 1714584000,
  "lic_id": "<uuid>",
  "v": 1
}
```

`exp` = `iat + 72h` (3 days, hard-coded server-side).

### 3.3 Machine fingerprint

`SHA-256( "HCPS1-fp-v1|" + HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid )`

- Stable across reboots, Windows updates, software installs
- Rotates only on Windows reinstall (which is the right semantic — reinstalled machine == new license)
- 32-byte hex, never reveals the underlying GUID externally

### 3.4 Activation flow

Two equivalent paths — pick whichever fits the user. Both end with the same signed JWT in the user's mailbox.

#### Path A — Self-service via the License.AuthorityGate.com web form (primary, recommended)

```
User                  Browser                    License.AuthorityGate.com         Sales (auto + manual)
 |                       |                                |                              |
 | Open tool, click      |                                |                              |
 | "Show my fingerprint" |                                |                              |
 |---------------------->| Tool prints SHA-256 fingerprint                               |
 |                       |                                                               |
 | Open License.AuthorityGate.com -> Request License                                     |
 |---------------------------------------->|                                             |
 |                                          | Form: email, fingerprint, hostname,        |
 |                                          |       engagement, doc author, company      |
 | Submit form ----------------------------->                                            |
 |                                          | Insert licenses row, status=pending        |
 |                                          | If email domain on PSO allowlist ----+     |
 |                                          |   auto-approve, sign JWT             |     |
 |                                          | else                                 |     |
 |                                          |   email Sales@ for approval ---------+---->|
 |                                          |                                            | Operator clicks Approve
 |                                          |<-------------------------------------------|
 |                                          | Sign Ed25519 JWT, status=active            |
 |                                          | Email JWT to user --->                     |
 | Receive email with token <--------------------------------------------------------------
 | Open tool, paste token, click Activate                                                |
 | Tool verifies sig + fp + exp, saves license.jwt                                       |
```

#### Path B — Tool-initiated request (offered as a button in the first-run wizard)

```
User -> Tool first-run wizard -> "Request License via Email"
        Tool POST /api/license/request to License.AuthorityGate.com
        (same downstream flow as Path A from "Insert licenses row" onward)
```

The two paths share the same database table, the same JWT format, and the same email template — Path B just bypasses the human filling out the web form by having the tool do the POST directly. Customers who block outbound HTTPS from the tool's runner can use Path A from any internet-connected workstation.

### 3.5 Per-run flow

```
Tool starts
 |
 v
Read license.jwt -> verify sig + machine match + exp > now
 |
 +-- invalid? -> Hard-stop. Show renewal instructions.
 |
 v (valid)
Run health check normally
 |
 v
Generate report
 |
 v
POST /api/usage (telemetry payload, auth via bearer = license JWT)
 |
 +-- failed? -> Queue locally to %LOCALAPPDATA%\AuthorityGate\HorizonHealthCheck\usage-queue\.
 |               Flush queue at start of next successful run.
 v
Done
```

### 3.6 Telemetry payload

```json
{
  "license_id": "uuid",
  "license_email": "consultant@customer.com",
  "machine_fingerprint": "sha256-hex",
  "hostname": "WS-JDOE01",
  "tool_version": "2.0.0",
  "run_id": "uuid",
  "started_at": "2026-04-28T15:30:00Z",
  "completed_at": "2026-04-28T15:42:00Z",
  "duration_seconds": 720,
  "doc_author": "Jane Doe",
  "customer_engagement": "ACME-Q2-2026",
  "targets": [
    { "type": "vCenter",     "fqdn": "vc01.acme.com" },
    { "type": "Horizon",     "fqdn": "cs01.acme.com" },
    { "type": "AppVolumes",  "fqdn": "av01.acme.com" }
  ],
  "plugin_count_total": 386,
  "plugin_count_executed": 312,
  "findings_summary": { "P1": 12, "P2": 47, "P3": 28, "Info": 250 },
  "report_filename": "HealthCheck-vc01.acme.com-20260428-154200.html",
  "report_size_bytes": 851234
}
```

**What is NOT sent**: probe data, finding text, customer asset IPs, gold-image inventory, credentials, anything that could reveal the customer's infrastructure beyond the FQDN of what was scanned. Telemetry is "metadata only."

### 3.7 License-server database schema (PostgreSQL)

```sql
CREATE TABLE licenses (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email               TEXT NOT NULL,
  hostname            TEXT,
  machine_fp          TEXT NOT NULL,
  customer_engagement TEXT,
  issued_at           TIMESTAMPTZ,
  expires_at          TIMESTAMPTZ,
  status              TEXT NOT NULL CHECK (status IN ('pending','active','expired','revoked')),
  signed_jwt          TEXT,
  issued_by_user_id   UUID REFERENCES users(id),
  request_ip          INET,
  request_user_agent  TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX licenses_email_idx     ON licenses(email);
CREATE INDEX licenses_status_idx    ON licenses(status, expires_at);
CREATE INDEX licenses_engagement_idx ON licenses(customer_engagement);
CREATE UNIQUE INDEX licenses_active_per_machine ON licenses(email, machine_fp) WHERE status = 'active';

CREATE TABLE usage_events (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  license_id           UUID REFERENCES licenses(id) ON DELETE SET NULL,
  license_email        TEXT,
  machine_fp           TEXT,
  hostname             TEXT,
  tool_version         TEXT,
  run_id               UUID,
  started_at           TIMESTAMPTZ,
  completed_at         TIMESTAMPTZ,
  duration_seconds     INTEGER,
  doc_author           TEXT,
  customer_engagement  TEXT,
  targets              JSONB,        -- array of {type, fqdn}
  plugin_count_total   INTEGER,
  plugin_count_executed INTEGER,
  findings_summary     JSONB,        -- {P1, P2, P3, Info}
  report_filename      TEXT,
  report_size_bytes    BIGINT,
  source_ip            INET,
  received_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX usage_received_idx   ON usage_events(received_at DESC);
CREATE INDEX usage_email_idx      ON usage_events(license_email);
CREATE INDEX usage_engagement_idx ON usage_events(customer_engagement);
```

### 3.8 License.AuthorityGate.com pages

The license server's admin and self-service pages all live under `License.AuthorityGate.com`. Public users land on the request form; AuthorityGate operators access admin pages behind SSO.

A new section under `License.AuthorityGate.com/admin/licensing/`:

**`/admin/licensing` (overview)**
- Top tiles: pending requests count, active licenses count, runs in last 7d, runs in last 30d
- Recent activity feed (combined): newest 20 license requests + newest 20 runs

**`/admin/licensing/requests`**
- Table of `pending` licenses
- Columns: email, hostname, fingerprint (truncated), engagement, requested at, request IP, [Issue] [Reject] actions
- Issuing signs the JWT, sets status=`active`, emails JWT to requester

**`/admin/licensing/licenses`**
- Table of all licenses (filterable by status, email, engagement, date range)
- Columns: email, hostname, engagement, status, issued, expires, days-left, [Revoke] [Resend] actions

**`/admin/licensing/usage`**
- Telemetry feed (filterable by email, engagement, target FQDN, date)
- Columns: started_at, license_email, doc_author, engagement, hostname, duration, target count + types, P1/P2/P3 counts, [Detail]
- CSV export

**`/admin/licensing/usage/[id]` (detail)**
- One run: full target list, full findings summary, report filename, source IP
- "Open run in customer-engagement detail" link

**`/` (root) and `/request` — public self-service form**
- The primary entry point at `License.AuthorityGate.com`. Anyone can land here, fill out a form, and get a license emailed.
- Fields:
  - Email (required, validated)
  - Machine fingerprint (required — copied from the tool's "Show my fingerprint" first-run screen)
  - Hostname (auto-filled if the tool POSTs on the user's behalf, otherwise manual)
  - Customer engagement code (free text — for invoicing / reporting attribution)
  - Doc author (free text — for the user's own attribution)
  - Company (free text)
- CAPTCHA-protected
- Rate-limited 1/min/email and 10/hour/IP
- On submit: row created with `status=pending`, downstream auto-approval logic decides whether to email immediately or queue for manual review

### 3.9 License.AuthorityGate.com API endpoints

| Method | Path | Auth | Purpose |
|---|---|---|---|
| `POST` | `/api/license/request` | none, rate-limited 1/min/email | Tool initiates license request |
| `GET`  | `/api/license/status?id=&fp=` | none | Tool polls request status while waiting for email |
| `POST` | `/api/usage` | Bearer = stored JWT | Tool submits run telemetry |
| `POST` | `/api/admin/license/issue` | admin session | Operator issues a license |
| `POST` | `/api/admin/license/revoke` | admin session | Operator revokes |
| `POST` | `/api/admin/license/resend` | admin session | Re-email JWT |
| `GET`  | `/api/admin/licenses` | admin session | Filter/list |
| `GET`  | `/api/admin/usage` | admin session | Filter/list |

Rate limits, IP allowlists, audit logging on every admin action.

### 3.10 Tool-side new module

`Modules/Licensing.psm1` — public functions:

| Function | Purpose |
|---|---|
| `Get-AGMachineFingerprint` | Return SHA-256 of MachineGuid |
| `Get-AGLicensePath` | Return `%LOCALAPPDATA%\AuthorityGate\HorizonHealthCheck\license.jwt` |
| `Read-AGLicense` | Read + parse JWT from disk |
| `Save-AGLicense` | Validate + persist JWT |
| `Test-AGLicense` | Verify sig (Ed25519), exp, machine fingerprint match. Returns `[ok=bool, reason]` |
| `Request-AGLicense` | POST `/api/license/request` |
| `Wait-AGLicenseApproval` | Poll `/api/license/status` until issued or timeout |
| `Submit-AGUsageEvent` | POST `/api/usage`. Queue locally on failure. |
| `Flush-AGUsageQueue` | Drain queue dir to dashboard |

Configurable endpoint via `$Global:AGLicenseBase` (default `https://license.authoritygate.com`) for staging/dev.

### 3.11 GUI integration

**License tab** (always-visible, leftmost tab):
- Status (Active / Expired / Not yet activated)
- Email, hostname, fingerprint (truncated for display)
- Engagement, expires at, days remaining
- Buttons: `Activate License...`, `Request New License...`, `Refresh`

**First-run wizard** (modal if no license file present): blocks the rest of the GUI until license is active.

**Pre-run check**: at click of "Run Health Check," validate the license. Soft-warn at <24h remaining, hard-stop at expired.

**Post-run telemetry**: after report generation, fire-and-forget POST to dashboard. Show a non-blocking toast: "Run reported to License.AuthorityGate.com" or "Run queued (dashboard unreachable; will retry next run)".

### 3.12 Failure modes & UX

| Scenario | Tool behavior |
|---|---|
| No license file present | First-run wizard. Cannot proceed. |
| License signature invalid (tampered file) | Hard-stop "License file corrupted; request a new one." |
| License expired | Hard-stop "Your 3-day license expired. Click Request New License." |
| License machine fingerprint mismatch | Hard-stop "This license is bound to a different machine." |
| License revoked (next call to /api/usage returns 403) | Soft-warn this run, hard-stop next |
| Dashboard unreachable at request time | Show error + offline-license-request form (manual email) |
| Dashboard unreachable at telemetry POST | Queue locally, flush on next run |
| Tool clock skewed | Show "Your system clock differs from server by X minutes; correct it then re-validate." |

### 3.13 Privacy / customer concerns

- Telemetry is metadata-only — no probe data, findings text, IPs of customer assets.
- Target FQDNs ARE included (per requirement). Customers must accept this in their PSO contract.
- HTTPS-only, TLS 1.2+, certificate pinning to `license.authoritygate.com`.
- Local queue at `%LOCALAPPDATA%\AuthorityGate\HorizonHealthCheck\usage-queue\` is operator-readable (no PII secrets — purely metadata).
- Document this clearly in `docs/PERMISSIONS.md` so customers see what leaves their environment before they sign.

---

## 4. Phased delivery

| Phase | Scope | Effort estimate |
|---|---|---|
| **1** | LICENSE rewrite + README update + `LICENSE_NOTICE.md` | 0.5d |
| **2** | Dashboard PostgreSQL schema + `/api/license/request` + `/api/license/status` + admin `/admin/licensing/requests` | 2d |
| **3** | Dashboard JWT signing + admin issue/revoke + email templates | 1d |
| **4** | Tool: `Modules/Licensing.psm1` + GUI License tab + first-run wizard + pre-run check | 2d |
| **5** | Tool: `/api/usage` + telemetry POST + local queue + flush | 1d |
| **6** | Dashboard `/admin/licensing/usage` page + CSV export | 1d |
| **7** | Production cutover: tag v1.x-final-mit, cut v2.0.0, announce | 0.5d |

Total: ~8d engineering for a complete cut.

---

## 5. Decisions to confirm before we build

These shape the implementation; please confirm or course-correct each:

1. **License re-license**: switch from MIT → AuthorityGate Source-Available License v1.0 with PSO carve-out. **Existing MIT-licensed copies stay MIT forever**; only new versions (`v2.0+`) carry the new terms. **Confirm?**

2. **3-day duration, machine-bound**: per your request. Renewal flow: same email + same machine + active engagement = single-click reissue (no full re-approval), or always full re-approval? **Recommend: single-click reissue if engagement is still open.**

3. **Telemetry payload**: list in §3.6 (email, time, hostname, target FQDNs, doc author, engagement, plugin counts, findings counts). Add anything? Redact anything? Specifically: **do we send target FQDNs as plain text, or hash them?** Plain-text is more useful for AuthorityGate but more sensitive for customers.

4. **Dashboard unreachable**:
   - At activation: hard-fail (cannot get license without dashboard) — **confirm**
   - At per-run check: license is offline-validated, so OK to proceed
   - At telemetry submit: soft-fail + queue + flush next run — **confirm**

5. **Approval automation**: every license request goes to a human at `Sales@authoritygate.com` for approval, OR auto-approve email domains on a known-PSO-customer allowlist (with manual approval for unknown domains)? **Recommend: allowlist auto-approve for PSO customers, manual for everyone else.**

6. **Public-facing language**: in README, do we want a clear "this tool is free for AuthorityGate PSO customers; everyone else, contact Sales" callout, or keep the messaging only inside the LICENSE file?

7. **What "production use" means**: does running a one-off assessment for a customer = production? My read of your intent: **yes — every customer engagement is production use, free for PSO clients, license-required for non-PSO**. Confirm?

8. **Telemetry of failed runs**: if the tool crashes mid-run, do we still post a partial telemetry event? **Recommend: yes, with `status: "failed"` so the dashboard sees both success and failure rates.**

9. **License revocation on device loss**: if a consultant's laptop is stolen, can AuthorityGate revoke that license remotely so the next run is hard-blocked? Note this only works if the tool can reach the dashboard — offline a stolen laptop with valid JWT can run until expiry.

10. **Public form vs always-by-email**: do we want a public web form at `license.authoritygate.com/licensing/request` (anyone can request a license), or is initiation always tool-side (the tool POSTs the request, dashboard never has a public form)?

---

## 6. Out of scope for v1

- Probe data exfiltration to dashboard (telemetry is metadata only)
- Real-time license push-revocation (requires dashboard polling — adds load)
- Multi-tenant licensing (one customer, many users on different machines — handle via multiple licenses)
- License transfer between machines (always issue new)
- Self-service license renewal portal (use email approval flow for v1)
- Per-plugin licensing (everything ships under one license)

---

## 7. Open implementation questions

- Where does the Ed25519 private key live? Recommend HSM-backed (AWS KMS, Azure Key Vault) so a database breach doesn't reveal it.
- Email sending infrastructure: existing transactional provider (SendGrid / SES / Postmark)? Or do we use the existing Sales@ inbox manually?
- Dashboard hosting: existing Next.js / Rails / etc. on License.AuthorityGate.com? What stack?
- Public key embedding in tool: hard-coded constant or fetched from a published `.well-known` URL at first run? Recommend hard-coded for offline-validation guarantee.
- Time-source for `iat` / `exp`: server's UTC clock at signing time. Tool uses local UTC clock at validation. Document the 5-minute clock-skew tolerance.
