# ZENTORY Protocol — Incident Response

> For step-by-step procedures see `docs/runbooks/incident-response.md`. This document is the policy + reference.

This document defines how ZENTORY Labs responds to incidents on the protocol (vaults, signal economy, governance, off-chain indexers, and the recorder / Ghost Portfolio pipeline). It is the **policy and reference** — the canonical command sequence lives in the runbook. Both must agree; if they disagree, the runbook wins on tactical steps and this document wins on policy decisions.

---

## 1. Scope

In scope:

- On-chain incidents: vault loss events, privileged key compromise, governance misuse, malicious or buggy contract behaviour.
- Off-chain incidents affecting user-facing guarantees: indexer outages, recorder stalls, RPC failures that prevent withdrawals, RLS regressions that let an anon key rewrite the track record.
- Operational incidents with credible material impact: alert-channel outages, expired credentials on critical services, deleted Railway volumes, lost admin keys.

Out of scope (escalate to the appropriate owner):

- Marketing/PR incidents without a technical root cause → Comms.
- Legal-only incidents (jurisdictional inquiry without a security dimension) → Legal Counsel.
- Pure user-error reports on the dApp (wrong asset deposited, wrong address) → Support.

---

## 2. Severity Definitions

Severity is assigned by the **Incident Commander (IC)** within 15 minutes of detection. It is re-evaluated every hour and may be downgraded or upgraded as facts emerge. The definition is **impact + reversibility**, not effort.

### SEV0 — Active loss or key compromise

Active, in-progress loss of user funds or protocol control. Examples:

- Active exploit draining a vault right now.
- Admin / signer / keeper private key confirmed compromised, used, or credibly about to be used.
- Governance proposal in timelock that would brick the protocol (e.g., quorum manipulation, fee routing to attacker).
- Forward ledger / Ghost Portfolio data plane has been silently rewritten by an attacker (RLS regression exploited).

**Response posture:** drop everything. All-hands. Comms cadence every 30 minutes minimum. Public disclosure within 24 hours if user funds are at risk.

### SEV1 — Severe bug with credible exploitation path

A vulnerability has been verified that *could* cause material loss or material user harm, but no exploitation is currently in progress. Examples:

- Audit finding rated Critical or High with a public PoC.
- Off-chain service (recorder, indexer, signer) showing signs of compromise that has not yet affected user funds.
- Vault circuit breaker stuck or not activating when it should.

**Response posture:** engineering on-call is full-time on the issue. Comms cadence every 1–2 hours. Public disclosure after a fix ships or after 7 days, whichever is sooner, per responsible-disclosure norms.

### SEV2 — Degraded functionality, no active exploit

Functionality is degraded but no funds are at risk and no attack vector is currently being exploited. Examples:

- Forward ledger frozen (recorder stale) with no evidence of tampering.
- RPC failover degraded, withdrawals slower than usual.
- dApp UI broken for a non-critical feature; deposits and withdrawals still work.

**Response posture:** normal on-call cadence. Fix in the next normal release window. Comms internally; external only if a customer-facing impact persists beyond 48 hours.

---

## 3. Role Roster

Roles are filled by named individuals on the team roster at `docs/operations/team-roster.md` (TBD). A role may be filled by the same person across multiple incidents sequentially, but **never concurrently** — one IC per active incident.

| Role | Responsibility | Authority |
|---|---|---|
| **Incident Commander (IC)** | Owns the response end-to-end: severity, decisions, comms, escalation, closure. | Final say on tactical priorities and external messaging during the incident. |
| **Protocol Engineer** | Contract and operator actions: pause, role changes, signer rotation, on-chain verification. | Can authorize any contract call the Safe or admin role permits; cannot unilaterally change policy. |
| **Security Engineer** | Threat assessment, forensic capture, key rotation, off-chain evidence. | Custodian of credentials, audit logs, and incident evidence package. |
| **Comms** | Internal updates, investor updates, public disclosure. | Owns all outbound text and timing; no one else publishes without their sign-off. |

Adjacent roles pulled in as needed:

- **External Auditor / Audit Firm Contact** (SEV0 / SEV1 only) — coordinate if active incident intersects a known audit finding.
- **Legal Counsel** (SEV0 only) — coordinate disclosure if jurisdictional exposure is in play.
- **Hyperliquid / RPC provider support** (off-chain infrastructure incidents) — coordinate if a vendor-side fault is suspected.

---

## 4. Immediate-Action Checklists

These are the *policy* level actions — the runbook has the exact click path and command sequence.

### 4.1 SEV0 — within 30 minutes

- [ ] IC assigned and announced in `#incident-active` (or the on-call channel).
- [ ] **Freeze execution:** pause `StrategyExecutor` (and any active vault keepable) via guardian/governor action. Verify new `executeSignal` calls revert.
- [ ] **Freeze deposits** on any affected vault (vault circuit breaker / deposit pause).
- [ ] **Preserve evidence:** capture tx hashes, block numbers, role-change events, keeper audit logs, Discord/alert timestamps into the evidence package.
- [ ] **Rotate keys** if compromise is in scope (see §5).
- [ ] **First internal update** within 30 minutes; first **public** update within 24 hours if user funds are at risk.
- [ ] Open a postmortem doc using `docs/POSTMORTEM_TEMPLATE.md` immediately, even if all facts are not yet known.

### 4.2 SEV1 — within 2 hours

- [ ] IC assigned.
- [ ] Investigation underway: blast radius, root cause, exploit reproducibility.
- [ ] **If exploit is reproducible:** brief on what a safe-mitigation path is (pause, role change, redeploy + migration).
- [ ] Preserve evidence as above.
- [ ] First internal update within 2 hours.
- [ ] Postmortem opened.

### 4.3 SEV2 — within 24 hours

- [ ] Ticket opened and assigned.
- [ ] Investigate during normal on-call.
- [ ] Decide: fix in this release, fix in next release, or accept.
- [ ] Postmortem only if the issue recurred, had near-miss characteristics, or the user impact exceeded 48 hours.

---

## 5. Investigation + Evidence Preservation

The investigation must produce, at minimum:

1. **What changed.** Recent governance proposals / timelock executions, role grants and revokes, signer changes, deployer-key usage, off-chain config edits.
2. **Blast radius.** Which vaults affected, how much moved, which user funds exposed, which subsystems degraded (Ghost Portfolio, signal economy, governance).
3. **Root cause.** Key compromise vs contract bug vs operator error vs off-chain failure. For SEV0/SEV1, distinguish between *exploit* and *vulnerability available* — they trigger different disclosure paths.
4. **Reversibility.** What can be rolled back vs what requires a redeploy + migration (see `contracts/scripts/audit/self_audit_findings.md` I-1: protocol primitives are immutable).

### Evidence package

Stored in the incident folder (private repo / access-controlled) with the postmortem. Required artifacts:

- Transaction hashes + block numbers (links to a block explorer for each chain involved).
- Role-change events (`RoleGranted`/`RoleRevoked`) with timestamps.
- Keeper audit logs around the incident window.
- Alert timestamps + alert-channel screenshots (Discord, email, SMS, PagerDuty — whatever fired).
- Off-chain state at the moment of incident: Railway volume snapshot, Supabase row snapshots, GitHub PAT validity state, deployed commit SHAs.
- Decision log: who decided what, when, with what justification.

The Security Engineer owns the evidence package. Nothing leaves the package without IC sign-off.

---

## 6. Communications Cadence

| Severity | Internal cadence | External cadence | Disclosure deadline |
|---|---|---|---|
| SEV0 | Every 30 minutes | Every 1–2 hours; public update within 24h | 24 hours from confirmation |
| SEV1 | Every 1–2 hours | After fix or 7 days, whichever sooner | 7 days from confirmation |
| SEV2 | Daily during on-call | Only if user-facing >48h | n/a |

### Internal updates

Short, factual, structured:

```
[SEV-X | HH:MM UTC | IC name]
Status: contained | investigating | recovering | resolved
What we know: ...
What we don't know yet: ...
What we need next: ...
```

Post in the active incident channel. Pin the most recent.

### External updates

Comms owns the wording. Every external message must include:

- What happened (plain language).
- What was paused / contained.
- What user funds are affected (if any), with concrete numbers.
- When the next update will land.
- A pointer to the eventual postmortem.

External channels, in order: status page, then Twitter/X, then Telegram, then email to investor list (SEV0 only). The order matters — do not skip the status page; investors monitor it.

---

## 7. Recovery

Recovery does not start until:

- Regression tests are green on the fix branch.
- Signer-parity test (if a key rotation is involved) is green.
- Invariant test suite is green.
- Slither / static analysis re-run on the patched code, report captured.
- For SEV0: a second engineer has reviewed and signed off on the recovery plan.

Recovery sequencing for the common cases:

- **Vault exploit paused:** redeploy only after migration plan is signed off by IC + Protocol Engineer + Security Engineer. See `contracts/scripts/audit/self_audit_findings.md` I-1: primitives are immutable; fix is deploy-new + migrate-state, not upgrade-in-place.
- **Key compromise:** new keys generated on hardware, old keys revoked via governance, all dependent services rotated (Vercel env, Railway env, GitHub secrets). Verification step: old key rejects immediately after new key is in place.
- **Off-chain tampering (RLS regression, indexer rewrite):** restore from the last known-good Supabase snapshot, then re-apply the lockdown migration. Public disclosure required because the "verifiable track record" claim was violated during the window.

---

## 8. Postmortem

Mandatory for every SEV0 and SEV1; optional but recommended for SEV2.

The postmortem is authored from `docs/POSTMORTEM_TEMPLATE.md`. It is published within 14 days of incident closure for SEV0 (and within 30 days for SEV1). SEV0 postmortems are public by default; SEV1 postmortems are public unless a specific reason (active exploit, coordinated disclosure with an audit firm) requires a delay.

### What we publish

- A redacted version of the postmortem (anything that would re-enable the exploit is removed).
- The action-item table with owners and due dates.
- A link to the relevant PRs.

### What we keep private

- Specific exploit code beyond what the published PoC requires.
- Personal information about users or staff.
- Vendor-side information protected by NDA.

---

## 9. Postmortem → Preventive Work

Every postmortem action item is tracked in the same place as `MAINNET_READINESS.md` items (Tier 0/0.5/1). The IC's job is not done until the action items have owners and due dates and have been added to that tracker.

The single most common failure mode of incident response is treating the postmortem as the deliverable. **The postmortem is the documentation; the preventive work is the deliverable.** The audit that found Tier 0 began with a postmortem of the 30-day outage (`docs/postmortems/2026-08-07-30-day-recording-outage.md`); the items that became Tier 0.5 of `MAINNET_READINESS.md` came from that postmortem's action items.

---

## 10. What This Document Does Not Cover

- Step-by-step command sequences → `docs/runbooks/incident-response.md`.
- Monitoring thresholds and alert routing → `docs/runbooks/monitoring-plan.md`, `docs/MONITORING.md`.
- Key custody and rotation procedure → `docs/KEY_MANAGEMENT.md`, `docs/MULTISIG_MIGRATION_PLAN.md`.
- Public disclosure templates and pre-drafted statements → `docs/comms/` (TBD).

If the runbook and this document disagree on a *policy* question (severity, role, cadence), this document wins. If they disagree on a *tactical* command, the runbook wins and the discrepancy is filed as a doc bug.

---

*Last updated: 2026-08-20. Tracked under Phase D of the go-to-market checklist.*
