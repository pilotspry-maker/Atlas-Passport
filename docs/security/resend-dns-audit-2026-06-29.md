# Atlas Passport — Resend Sender Domain DNS Audit

**Domain audited:** `atlaspassport.com`
**Reason for audit:** Pre-rotation deliverability check ahead of next `RESEND_API_KEY` rotation; verifies the "Verify Resend SPF + DKIM" item in CLAUDE.md §14.
**Audit date:** 2026-06-29 (UTC)
**Auditor:** Computer (Perplexity)
**Severity:** 🔴 **CRITICAL — production email is unauthenticated and almost certainly non-deliverable. Domain may not be under our control.**

---

## TL;DR

`atlaspassport.com` — the sender domain hard-coded as the default `FROM` in `src/lib/resend.ts` (`Kaelo <kaelo@atlaspassport.com>`) — **has zero email-authentication DNS records published**: no SPF, no DKIM, no DMARC, no MX, no Resend bounce subdomain. Worse, the apex `A` record points to an EC2 instance in `ap-southeast-2` serving a **domain-for-sale parking page** ("atlaspassport.com - GOLDPEPPER"). The authoritative nameservers (`ns1-5.globaldns.com`) all resolve to a single IP (`13.55.37.243`) — also AWS Sydney — consistent with a domain-broker parking nameserver, not a domain we administer.

**The next RESEND key rotation is not the blocker. The blocker is that we either (a) don't own this domain yet, or (b) own it but never pointed the nameservers at a DNS provider we can edit.** Until that's resolved, every production email Resend tries to send from `@atlaspassport.com` either bounces or lands in spam.

---

## 1. Audit results — actual DNS state

All queries run against Cloudflare 1.1.1.1 and Google 8.8.8.8 on 2026-06-29, and confirmed directly against the authoritative NS (`ns1.globaldns.com`, 13.55.37.243).

| Record needed for Resend                       | Expected at                    | Actual on `atlaspassport.com`         | Status        |
|-------------------------------------------------|--------------------------------|---------------------------------------|---------------|
| SPF — `TXT` with `include:amazonses.com` etc.   | `send.atlaspassport.com`       | _(no record)_                         | ❌ MISSING    |
| SPF bounce — `MX 10 feedback-smtp.<region>.amazonses.com` | `send.atlaspassport.com` | _(no record)_                         | ❌ MISSING    |
| DKIM — `TXT` with public key                    | `resend._domainkey.atlaspassport.com` | _(no record on `resend` or any of 10 common selectors probed)_ | ❌ MISSING    |
| DMARC — `TXT v=DMARC1; p=…`                     | `_dmarc.atlaspassport.com`     | _(no record)_                         | ❌ MISSING    |
| Receive MX (only if inbound enabled)            | `atlaspassport.com`            | _(no record)_                         | ⚠️ N/A (not used) |
| Apex `A`                                        | `atlaspassport.com`            | `54.252.89.206` (EC2 `ap-southeast-2`, **parking page**) | 🔴 SUSPICIOUS |
| Authoritative NS                                | `atlaspassport.com`            | `ns1-5.globaldns.com` (all → `13.55.37.243`) | 🔴 SUSPICIOUS |

Page served at the apex IP (Host: `atlaspassport.com`):

```
HTTP/1.1 200 OK
Server: Apache/2.4.68 OpenSSL/1.1.1zh PHP/5.4.16
<title>atlaspassport.com - GOLDPEPPER</title>
... "Buy with confidence", "Offer (Amount in USD)" ...
```

This is a domain-broker landing page (`GOLDPEPPER` is a known parked-domain monetizer). It is **not** a deploy of this Next.js app — `atlas-passport.vercel.app` is the live production host per CLAUDE.md §15.

---

## 2. What Resend currently requires (per current docs, 2026-06-29)

Pulled from [resend.com/docs](https://resend.com/docs/dashboard/domains/introduction), the [MX-conflict KB](https://resend.com/docs/knowledge-base/how-do-i-avoid-conflicting-with-my-mx-records), and the [DMARC guide](https://resend.com/docs/dashboard/domains/dmarc).

When you add `atlaspassport.com` (or a subdomain) in the Resend dashboard, Resend generates a record set unique to your account/region. The shape is always:

| # | Type  | Host                                    | Value (region `us-east-1` shown — verify in your dashboard)             | Priority | TTL  |
|---|-------|-----------------------------------------|--------------------------------------------------------------------------|----------|------|
| 1 | `MX`  | `send`                                  | `feedback-smtp.us-east-1.amazonses.com`                                  | `10`     | Auto |
| 2 | `TXT` | `send`                                  | `"v=spf1 include:amazonses.com ~all"` _(exact string from your dashboard)_ | —        | Auto |
| 3 | `TXT` | `resend._domainkey`                     | `"p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCB…"` _(account-specific public key)_  | —        | Auto |
| 4 | `TXT` | `_dmarc`                                | `"v=DMARC1; p=none; rua=mailto:dmarcreports@atlaspassport.com;"`         | —        | Auto |

Notes:

- **Region matters.** If the Resend domain is configured for `eu-west-1` or `ap-northeast-1`, the MX value changes (`feedback-smtp.<region>.amazonses.com`). Pull the literal values from `https://resend.com/domains/<id>` — copy/paste, do not transcribe.
- **DKIM is TXT, not CNAME.** Resend does not use CNAME-based DKIM today. The exact public key string is account-specific and only Resend can produce it.
- **Trailing dot trap.** Per Resend's verification KB, if your DNS provider auto-appends the zone, `feedback-smtp.us-east-1.amazonses.com` becomes `feedback-smtp.us-east-1.amazonses.com.atlaspassport.com` and silently fails. Add a literal trailing dot in the value field if your provider needs it.
- **DMARC starts at `p=none`.** Don't ship `p=quarantine` or `p=reject` on day one — observe for 1–2 weeks via `rua` reports first. Gmail/Yahoo bulk-sender rules (2024+) require *some* DMARC record to exist; `p=none` is sufficient to satisfy that.

---

## 3. Gap analysis — what's missing and why each matters

| Missing record                  | Production impact today                                                                                                 |
|---------------------------------|-------------------------------------------------------------------------------------------------------------------------|
| SPF (`TXT` on `send.`)          | Receivers can't verify Resend is authorized to send for us. Gmail/Yahoo will mark as spam or reject outright since Feb 2024 bulk-sender rules. |
| Bounce MX (`MX 10 feedback-smtp…`) | Resend can't receive bounce/complaint signals → your suppression list never updates → reputation degrades silently. Also blocks SPF alignment for DMARC. |
| DKIM (`TXT resend._domainkey`)  | No cryptographic signature on outbound mail. Combined with missing SPF, **every email fails both SPF and DKIM**, which means DMARC (when we add it) will fail too. |
| DMARC (`TXT _dmarc`)            | Required by Gmail/Yahoo for bulk senders since 2024. Without it, mail to those providers is throttled or rejected regardless of SPF/DKIM. |
| Apex pointing to parking page   | Anyone clicking `https://atlaspassport.com` (e.g. from email footers, support docs, or social) lands on a "buy this domain" page — direct brand and trust damage even before email auth. |

Bottom line: **`src/lib/email.ts` is calling `resend.emails.send(...)` against a `from:` domain that has no published authentication and isn't pointed at us.** Resend will accept the API call, but receivers will junk or reject it. The `RESEND_API_KEY` itself works — the *envelope* is broken.

---

## 4. Domain-ownership pre-check (must run before any DNS fix)

Before adding any records, confirm the domain is actually ours and that `globaldns.com` is the correct authoritative DNS host. This is the gating question — none of the fix steps in §5 work if the answer is "we don't own it" or "we own it but DNS is at a different provider."

Run locally:

```bash
# 1. WHOIS — who owns the registration?
whois atlaspassport.com | grep -iE "registrar|registrant|name server|expiry|status" | head -20

# 2. What's at globaldns.com? Is that a DNS provider we have an account with?
whois globaldns.com | grep -iE "registrar|organization|name server" | head -10

# 3. Cross-check: is the DNS host the same as the registrar, or split?
dig +short NS atlaspassport.com @1.1.1.1
```

Three possible outcomes:

| WHOIS says…                                              | Interpretation                                       | Next step                              |
|----------------------------------------------------------|------------------------------------------------------|----------------------------------------|
| We are the registrant; NS points to a host we control    | Domain is ours, DNS is at the right place             | Skip to §5                             |
| We are the registrant; NS points to `globaldns.com` (broker) | We own it but DNS is parked at a broker's nameservers | Change NS at the registrar to a DNS host we control (Cloudflare, Vercel DNS, Route53), then §5 |
| Someone else is registrant, or "REDACTED FOR PRIVACY" and we have no record of buying it | We don't own this domain                              | STOP. Either buy it from the broker (the page literally offers this) or pick a different sender domain. Do **not** rotate the Resend key against a domain we don't own. |

---

## 5. Fix instructions — to be run locally by the operator

> All commands assume the audit in §4 confirmed we own the domain and we have credentials for the DNS host. Replace placeholders in `<angle brackets>`.

### 5.1 Add the domain in Resend, capture exact values

1. Sign in at https://resend.com/domains
2. Click **Add Domain** → enter `atlaspassport.com`
3. Region: pick whichever is closest to the Vercel deployment region (US users → `us-east-1`; if unsure, leave the default and note it).
4. Resend now shows a **Records** table with 4 rows. Leave this tab open — every value (especially the DKIM public key and the SPF MX target) is account-specific. **Copy/paste from this tab into DNS, do not retype.**

### 5.2 Publish records at the authoritative DNS host

Pick the path that matches your DNS host:

**Cloudflare (recommended — proxy-off all email records)**

```text
Record 1 — Resend bounce MX
  Type:    MX
  Name:    send
  Mail server: feedback-smtp.us-east-1.amazonses.com
  Priority: 10
  Proxy:   DNS only (grey cloud)
  TTL:     Auto

Record 2 — SPF
  Type:    TXT
  Name:    send
  Content: v=spf1 include:amazonses.com ~all
  TTL:     Auto

Record 3 — DKIM (paste exact value from Resend dashboard)
  Type:    TXT
  Name:    resend._domainkey
  Content: <paste DKIM TXT from Resend — starts with "p=MIGfMA0..." style>
  TTL:     Auto

Record 4 — DMARC (starter)
  Type:    TXT
  Name:    _dmarc
  Content: v=DMARC1; p=none; rua=mailto:dmarcreports@atlaspassport.com;
  TTL:     Auto
```

**Vercel DNS** (if you migrate NS to Vercel) — same record set, equivalent UI under Project → Domains → DNS Records.

**Route53** — same record set; remember Route53 stores TXT values **with surrounding quotes** — `"v=spf1 include:amazonses.com ~all"`.

### 5.3 Trigger Resend verification

```bash
# Resend's UI: click "Verify DNS Records" on the domain detail page.
# Or via API:
curl -X POST "https://api.resend.com/domains/<domain_id>/verify" \
  -H "Authorization: Bearer $RESEND_API_KEY"
```

Propagation is usually <15 minutes but Resend allows up to 72 hours.

### 5.4 Verify from a workstation outside the DNS host

Don't trust the DNS host's own UI — query a public resolver:

```bash
DOMAIN=atlaspassport.com

# SPF + bounce MX (both must return)
dig +short TXT  send.$DOMAIN  @1.1.1.1
dig +short MX   send.$DOMAIN  @1.1.1.1

# DKIM
dig +short TXT  resend._domainkey.$DOMAIN  @1.1.1.1

# DMARC
dig +short TXT  _dmarc.$DOMAIN  @1.1.1.1
```

All four must return non-empty values matching what Resend showed.

Then check against an authoritative external tool:

- https://dns.email/atlaspassport.com  (Resend's own recommended checker)
- https://www.mail-tester.com (send a real test email to the generated address; aim for ≥ 9/10)

### 5.5 End-to-end production send check

Once Resend's dashboard shows the domain as **Verified** (green on all four rows):

```bash
# From the operator workstation, after the next deploy
curl -X POST https://atlas-passport.vercel.app/api/auth/test-email \
  -H "Content-Type: application/json" \
  -d '{"to":"<your-personal-inbox>"}'
```

Inspect the received message's full headers — look for:

```
spf=pass
dkim=pass
dmarc=pass (policy=none)
Return-Path: <bounces+...@send.atlaspassport.com>
```

If any of those three are not `pass`, do not proceed with the next `RESEND_API_KEY` rotation — fix the failing record first.

### 5.6 Fix the apex parking page (separate from email but blocks brand trust)

Even after email auth is fixed, `https://atlaspassport.com` still serves the "for sale" page until the apex `A` record is repointed:

- If marketing site lives at `atlas-passport.vercel.app`: in Vercel → Project → Domains → add `atlaspassport.com` + `www.atlaspassport.com`. Vercel will print the `A`/`CNAME` to publish. Replace the existing `A 54.252.89.206`.
- If there is no marketing site yet: at minimum publish an `A`/`CNAME` to a holding page we control (e.g. a Vercel 200 page) so customers don't see a broker page next to our transactional email.

---

## 6. Hardening (do these once the basics pass)

- **Upgrade DMARC to `p=quarantine; pct=100;`** after 1–2 weeks of clean `rua` reports.
- **Add `_dmarc` rua reporting recipient** that someone actually reads — `dmarcreports@atlaspassport.com` is only useful if mail to it goes somewhere (you have no inbound MX on the apex — send rua to a different domain we monitor, or to a DMARC analyzer like Postmark or Valimail).
- **Rotate to a dedicated sending subdomain** (e.g. `mail.atlaspassport.com`) per Resend's own guidance — protects apex reputation from transactional bounces, and matches what `src/lib/resend.ts` would use if `RESEND_FROM_EMAIL` were updated.
- **Add the `RESEND_FROM_EMAIL` Vercel env var to the next-rotation runbook** — currently it's set in Vercel (per `vercel env ls`) but if the sender domain changes, this is the only place the change shows up in code.

---

## 7. Checklist for the next operator (paste into a ticket)

```
[ ] §4 WHOIS confirms we own atlaspassport.com
[ ] §4 NS records point to a DNS host we administer
[ ] §5.1 Domain added in Resend, region recorded
[ ] §5.2 All four DNS records published with exact values from Resend dashboard
[ ] §5.3 Resend dashboard shows all four records as "Verified" (green)
[ ] §5.4 Public-resolver dig returns the expected values
[ ] §5.5 Production test email passes SPF, DKIM, and DMARC in headers
[ ] §5.6 Apex no longer serves the GOLDPEPPER parking page
[ ] CLAUDE.md §14 "Verify Resend SPF + DKIM" row marked done
[ ] docs/runbooks/resend-key-rotation.md §6.2 unblocked (was gated on this)
```

---

## References

- Resend — Managing Domains: https://resend.com/docs/dashboard/domains/introduction
- Resend — MX-conflict KB (exact `send` MX shape): https://resend.com/docs/knowledge-base/how-do-i-avoid-conflicting-with-my-mx-records
- Resend — DMARC implementation: https://resend.com/docs/dashboard/domains/dmarc
- Resend — Domain not verifying troubleshooting: https://resend.com/docs/knowledge-base/what-if-my-domain-is-not-verifying
- Resend — Custom return path changelog (2025-05-15): https://resend.com/changelog/custom-return-path
- Atlas Passport — CLAUDE.md §5 (env vars) and §14 (outstanding work)
- Atlas Passport — `docs/runbooks/resend-key-rotation.md` (companion runbook, PR #52)
