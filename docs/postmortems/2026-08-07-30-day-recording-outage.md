# Postmortem — 30-Day Forward Ledger Recording Outage

> Severity: SEV2 (degraded observability with reputational risk; no user funds lost). The reputational risk is why we are publishing this and why the action items are tracked in `MAINNET_READINESS.md` Tier 0.5 alongside code defects.

---

## 1. Header

| Field | Value |
|---|---|
| **Incident date(s)** | 2026-07-08 → 2026-08-07 (UTC) |
| **Severity** | SEV2 |
| **Incident Commander** | Edge (founder-on-call) |
| **Author** | Edge |
| **Status** | published |
| **Detected** | 2026-08-07 — routine forward-ledger integrity check |
| **Contained** | 2026-08-15 — engine PR #15 (`dc85d03`) makes the failure loud |
| **Resolved** | 2026-08-15 — engine PR #18 (`1016ecf`) re-attaches the volume + adds RPC failover |
| **Published** | 2026-08-20 |

| Field | Value |
|---|---|
| **Duration** | ~38 days (last successful entry → fix shipped) |
| **User-facing impact window** | 2026-07-08 → 2026-08-07 (the public forward track record showed stale data through this window) |
| **Related PRs** | zentory-engine PR #15 (`dc85d03`), zentory-engine PR #18 (`1016ecf`) |

---

## 2. Summary

Between 2026-07-08 and 2026-08-07, the public forward track record on the ZENTORY recorder froze for **30 days**. The last successful forward ledger entry landed on 2026-07-08. For the next 30 days, the recorder cron continued to run on schedule, retried every four hours, and failed silently each time. Root causes: an expired `GITHUB_TOKEN` on the Zent Recorder service, a Railway volume (`zent-recorder-volume`) that had been deleted in a housekeeping pass, and a Discord-based alerting channel that no human monitored daily. The outage was discovered on 2026-08-07 during a routine forward-ledger integrity check. The fix shipped on 2026-08-15 across two engine PRs (#15 makes the failure loud; #18 re-attaches the volume and adds RPC failover). No user funds were lost. The forward record's value — that it was committed at the time — was preserved by **not backfilling** the gap.

---

## 3. Timeline

All times UTC.

| Timestamp | Event | Source / actor |
|---|---|---|
| 2026-06-08 | Forward ledger clock started (~30-day track record requirement per Tier 4 #16) | Edge |
| 2026-07-08 (≈16:00) | **Last successful forward ledger entry.** Subsequent cron runs return non-zero and fail silently. | Recorder cron |
| 2026-07-12 (≈) | **`GITHUB_TOKEN` on Zent Recorder expires.** Token had no rotation calendar; expiry was silent (no email, no Discord webhook from GitHub). | GitHub (expiry) |
| 2026-07-15 (≈) | **Railway volume `zent-recorder-volume` deleted in a housekeeping pass.** Volume held unpublished bars as a retryable backlog; its loss is what blocked recovery once the token was rotated. | Railway housekeeping |
| 2026-07-08 → 2026-08-07 | **Recorder cron retries every 4h, fails silently.** Failures log to a Discord channel that no human reads daily. Benign NAV flapping from unrelated sources trains the channel's readers to ignore it. | Recorder cron |
| 2026-08-07 (≈14:00) | **Outage discovered during a routine forward-ledger integrity check.** "Recording live — day N" widget on the dApp continues to display an inflated day count because the staleness check compares first/last ledger bar only, not last bar vs now. | Edge |
| 2026-08-07 | Discord-channel alert finally surfaced to a human; SEV2 opened; IC assigned (Edge). | Edge |
| 2026-08-15 | **zentory-engine PR #15 (`dc85d03`) merges.** Failures now log loudly with structured error context (token expiry vs volume missing vs RPC failure are distinguishable). | Engineering |
| 2026-08-15 | **zentory-engine PR #18 (`1016ecf`) merges.** Railway volume re-attached, RPC failover layer added (viem fallback transport — also closes MAINNET_READINESS Tier 0 #6 indirectly). | Engineering |
| 2026-08-15 | Recorder resumes successful ledger entries. Forward track record clock restarts on the fixed system. | Recorder cron |
| 2026-08-20 | Postmortem published. | Edge |

---

## 4. Root Cause

### 4.1 Proximate trigger

The recorder cron's publish step failed (because the GitHub PAT was expired), and the retry-backlog could not absorb the failure (because the Railway volume that held unpublished bars had been deleted).

### 4.2 Systemic cause

Three independent systemic gaps, each of which would have been sufficient on its own and which compounded:

1. **A single GitHub PAT for the recorder service, with no rotation calendar.** When the token expired, no human was notified. The expiry was silent because GitHub only emits a webhook if one is configured, and we had not configured one for service-account PAT expiries.
2. **A Railway volume deleted during housekeeping with no audit log.** The volume was not in a "do-not-delete" tag, the housekeeping script had no allowlist of protected resources, and the deletion was not logged in a way that would have surfaced to a human before the next cron retry.
3. **A critical-alert channel with no human-on-the-end.** Discord is a notification sink, not an escalation path. With no email / SMS / push bridge, and no on-call rotation that reads that specific channel daily, the channel became a write-only log. Benign NAV flapping from unrelated sources actively trained the channel's readers (when there were any) to ignore it.

### 4.3 5 Whys

```
1. Why did the forward track record freeze?
   → The recorder cron could not publish entries.
2. Why couldn't the cron publish entries?
   → The GitHub PAT was expired.
3. Why was an expired PAT a hard stop rather than a recoverable failure?
   → There was no retry-backlog — the Railway volume that held
     unpublished bars was gone.
4. Why was the Railway volume gone?
   → A housekeeping pass deleted it; the script had no protected-resource allowlist.
5. Why didn't we notice for 30 days?
   → The alert channel was Discord-only, no human read it daily, and the
     "Recording live — day N" widget on the dApp computed the day count
     from first/last ledger bar only — it never compared last bar vs now.
```

The 30-day duration is a system-design failure, not an operational one. No individual person failed; the system had no path that a single human failure could not have caused.

---

## 5. Detection

- **How did we find out?** Routine forward-ledger integrity check during a Tier 0 review session. The check (manual at the time, now automated per PR #15) cross-referenced the recorder's "last successful entry" timestamp against `now` and flagged a 30-day gap. This is the same class of check that should have been automated and was not.
- **How long did it last before detection?** **30 days** (2026-07-08 → 2026-08-07). The recorder cron retried every 4 hours — roughly 180 retry attempts produced 0 alerts that reached a human.

Detection delay is the worst part of this incident. The system had the data to detect the failure in real time; it had the alerting infrastructure to surface it; what it did not have was a path from "alert fired" to "human reads alert." That gap is fixed by the action items below.

---

## 6. Resolution

What stopped the bleed:

1. **Immediate containment** (2026-08-07): paused public-facing "Recording live — day N" claim on the dApp until the record resumed. Honest framing: "Recording paused — last entry 2026-07-08." Per Tier 0.5 #6 of `MAINNET_READINESS.md`, **no backfill was performed**. A forward record's value is that it was committed at the time; a bulk backfill is detectable and reads as fabrication.
2. **Root-cause fix #1 — token rotation.** Rotated `GITHUB_TOKEN` (new PAT with contents+PR write on `zentory-app`). Action item AI-1. Done post-incident.
3. **Root-cause fix #2 — failure loud.** Engine PR #15 (`dc85d03`) restructured the recorder's error logging so that token-expiry, volume-missing, and RPC-failure are distinguishable in the logs. A failure now shouts, not whispers.
4. **Root-cause fix #3 — volume re-attached + RPC failover.** Engine PR #18 (`1016ecf`) re-attached the Railway volume (`zent-recorder-volume` → `/app/forward`) and added the viem fallback transport for RPC failover. The volume now holds unpublished bars as a retryable backlog, so a future single-leg failure does not lose data.
5. **Verification.** Recorder resumed successful entries on 2026-08-15. Integrity check re-run; "Recording live — day N" widget re-enabled only after a verified contiguous chain of new entries.
6. **Cleanup.** No further action needed; the gap is disclosed in this postmortem and remains in the public forward record as a documented gap, not a hidden one.

---

## 7. Impact

| Dimension | Impact |
|---|---|
| **Users affected** | 0 directly (no funds at risk; the forward record is observational, not user-balance-bearing) |
| **Funds at risk** | $0 |
| **Funds lost** | $0 |
| **Data integrity window** | 2026-07-08 → 2026-08-07 — the public forward record showed stale data through this window. The on-chain state was not affected; the Ghost Portfolio and signal-economy data planes were unaffected (those run on the Supabase `execution_attempts` and `hl_user_fills` tables, separate from the recorder's forward ledger). |
| **Brand / reputation** | Moderate. The forward record is the protocol's most-cited proof point; a 30-day gap is the kind of finding that ends an investor diligence if left unexplained. Mitigated by disclosure (this postmortem) and by the action items below. |
| **Operational cost** | ~3 engineering days (PR #15 + PR #18 + verification), ~1 founder day (IC + postmortem). No vendor spend. |

**Audit-relevant findings:** none new — this is an operational / observability failure, not a code vulnerability. The fixes land in the engine (off-chain) layer; the smart contracts are not affected.

**Off-chain impact:** Supabase rows were not touched; the data plane was not breached; the alert channel received the failures but no human read them.

---

## 8. What Worked / What Didn't

### What worked

- **Engine cron retry behaviour.** The cron correctly retried every 4 hours throughout the window. The retry path existed and ran; it just had nothing to retry against once the volume was gone.
- **Vault circuit breakers correctly halted keeper actions on the stale ledger.** Because the recorder's failure produced no new ledger entries, the keeper's freshness check correctly refused to act on stale data. The on-chain safety property held: **no action was taken on stale data.**
- **Integrity check during a routine review.** The fact that we *did* catch it on 2026-08-07 — even manually — meant the blast radius was bounded at 30 days, not indefinite. Tier 0 review is the right venue for this class of check.
- **PR #18's RPC failover.** The viem fallback transport added in PR #18 is independently useful and addresses Tier 0 #6 (`MAINNET_READINESS.md`) — the recorder is more resilient than it was before this incident, on dimensions unrelated to the original trigger.

### What didn't

- **Silent failures.** The recorder failed 180 times across 30 days and produced zero alerts that reached a human. Every one of those failures was a missed chance to catch the issue at day 1.
- **Discord-only alerting for critical paths.** Discord is a chat tool, not an escalation path. With no on-call rotation, no email/SMS/push bridge, and benign NAV flapping training readers to mute the channel, the alert channel was effectively write-only for the duration of the incident.
- **No expiry calendar on credentials.** The `GITHUB_TOKEN` expiry was silent because no calendar tracked it. The credential-expiry inventory (`MAINNET_READINESS.md` Tier 0.5 #7) was partial at the time of the incident.
- **Stale "Recording live — day N" widget.** The dApp computed day count from first/last ledger bar only; it never compared last bar vs `now`. This is exactly the bug Tier 0 #6 of the audit flagged. The fix (zentory-app PR #276 staleness gate) was merged in parallel; the lesson is the same: a "live" indicator that does not check freshness is not a liveness indicator.

---

## 9. Action Items

| ID | Action | Owner | Due | Status | Tracker link |
|---|---|---|---|---|---|
| AI-1 [O.1] | Rotate `GITHUB_TOKEN` (contents+PR write on `zentory-app`). Do not paste it in chat. | F | 2026-08-15 | **done** post-incident | `MAINNET_READINESS.md` Tier 0.5 #1 |
| AI-2 [O.5] | Route critical alerts to a channel a human actually reads (email/SMS/push). Alert on state change + escalate on duration, not every 30 min. Discord alone is not an escalation path. | F | open | **pending** | `MAINNET_READINESS.md` Tier 0.5 #5 |
| AI-3 [O.7] | Credential-expiry calendar: every credential with an expiry gets an owner, a rotation date, and an alert at T-7 days. | F+E | open | **pending** | `MAINNET_READINESS.md` Tier 0.5 #7 |
| AI-4 | Re-attach Railway volume `zent-recorder-volume` → `/app/forward` so unpublished bars survive as a retryable backlog. | E | 2026-08-15 | **done** (zentory-engine PR #18, `1016ecf`) | `MAINNET_READINESS.md` Tier 0.5 #2 |
| AI-5 | RPC failover layer (viem fallback transport) so a single-RPC outage does not compound with other failures. | E | 2026-08-15 | **done** (zentory-engine PR #18, `1016ecf`) | `MAINNET_READINESS.md` Tier 0.5 #3 |
| AI-6 | Failure-loud logging: distinguish token-expiry / volume-missing / RPC-failure in the recorder's error logs. | E | 2026-08-15 | **done** (zentory-engine PR #15, `dc85d03`) | `MAINNET_READINESS.md` Tier 0.5 #4 |
| AI-7 | Staleness gate on the dApp: "Recording live — day N" compares last-bar vs `now`, not first-bar vs last-bar. | E | 2026-08-15 | **done** (zentory-app PR #276) | `MAINNET_READINESS.md` Tier 0.5 #8 |
| AI-8 | Disclose the 30-day gap publicly (this postmortem). Do **not** backfill the forward record. | F | 2026-08-20 | **done** | `MAINNET_READINESS.md` Tier 0.5 #6 |

Naming: AI-1 through AI-8 within this postmortem; the bracketed `[O.x]` references are the corresponding items in `MAINNET_READINESS.md` Tier 0.5. Owners use the legend from `MAINNET_READINESS.md` (F=founder, E=engineering, X=external, L=legal).

**Pending items at publication: AI-2 and AI-3.** Both are founder-led and remain open. Until AI-2 lands, this class of failure can recur.

---

## 10. Lessons Learned

- **A healthy alert channel is one a human reads every day.** Discord alone failed for 30 days. An alert channel that is technically live but socially quiet is the same as no alert channel at all.
- **Silent failures are the most expensive failures because they train everyone to ignore the alert channel.** Benign NAV flapping taught the Discord channel's readers to mute it; when the real failure came, no one noticed because the channel had already been muted.
- **A "live" indicator that does not check freshness is not a liveness indicator.** Computing day count from first/last bar is a vanity metric; computing it from last-bar vs `now` is the actual safety property.
- **The cheapest reliable prevention for this class of failure is a credential-expiry calendar with an alert at T-7 days.** A spreadsheet, a recurring calendar entry, and one human reading it would have caught the `GITHUB_TOKEN` expiry at day 7, not day 30.
- **A forward record's value is that it was committed at the time.** The temptation to backfill the 30-day gap was real; resisting it is the right call. A backfilled record is detectable (the gap, the timestamps, the absence of contemporaneous social signal) and reads as fabrication. The disclosed gap is a smaller reputational hit than a detected fabrication.

---

## Appendix A — Evidence Package Index

Stored alongside this postmortem in the private evidence bundle:

- Recorder cron logs from 2026-07-08 → 2026-08-15 (showing ~180 failed attempts).
- GitHub PAT validity state (expiry timestamp, last successful auth, first failed auth).
- Railway volume deletion audit log (housekeeping script run, resources deleted, no allowlist present).
- Discord channel export for `#recorder-alerts` covering the incident window (180 alerts, zero reactions, zero replies).
- Engine PR #15 (`dc85d03`) and PR #18 (`1016ecf`) — diffs, review trail, merge commits.
- Founder decision record on disclosure-vs-backfill (the choice that defined the postmortem's framing).

---

*Postmortem version: 1.0 | Last updated: 2026-08-20 | Tracked under Phase D of the go-to-market checklist.*
