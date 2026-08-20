# Postmortem Template

Copy this file to `docs/postmortems/YYYY-MM-DD-<short-slug>.md` and fill in every section. Sections marked **(required)** must not be left as TBD; if the information is unknown at publication time, write what is known and what remains under investigation.

This template is the canonical format. Any postmortem that deviates structurally needs IC sign-off before publication.

---

## 1. Header **(required)**

| Field | Value |
|---|---|
| **Incident date(s)** | YYYY-MM-DD → YYYY-MM-DD (UTC) |
| **Severity** | SEV0 / SEV1 / SEV2 |
| **Incident Commander** | Name |
| **Author** | Name |
| **Status** | draft / review / published |
| **Detected** | YYYY-MM-DD HH:MM UTC — how |
| **Contained** | YYYY-MM-DD HH:MM UTC |
| **Resolved** | YYYY-MM-DD HH:MM UTC |
| **Published** | YYYY-MM-DD |

> If the incident was active across multiple days, the **Duration** field below is the time from detection to resolution, not the calendar span.

| Field | Value |
|---|---|
| **Duration** | Xh Ym (detection → resolution) |
| **User-facing impact window** | YYYY-MM-DD HH:MM UTC → YYYY-MM-DD HH:MM UTC |
| **Related PRs** | #N (sha), #N (sha), … |

---

## 2. Summary **(required)**

One paragraph. Lead with the user-visible impact. No jargon. This is what an investor or a journalist should be able to read and understand.

> **Template:** Between \<start\> and \<end\>, \<what users saw\>. Root cause: \<plain-language cause\>. Impact: \<numbers — users affected, funds at risk, funds lost, data integrity window\>. Resolved by: \<what fixed it, in plain language\>.

Limit to 4–6 sentences. Link out for detail.

---

## 3. Timeline **(required)**

All events in UTC. List every decision and every action, not just the obvious ones. The IC's decision log is the source of truth for this section.

| UTC timestamp | Event | Source / actor |
|---|---|---|
| YYYY-MM-DD HH:MM | First signal of the issue (alert, user report, internal observation) | source |
| YYYY-MM-DD HH:MM | IC assigned | IC name |
| YYYY-MM-DD HH:MM | Severity set to SEV-X | IC |
| YYYY-MM-DD HH:MM | \<first containment action\> | Protocol Engineer |
| YYYY-MM-DD HH:MM | \<root cause identified\> | Security Engineer |
| YYYY-MM-DD HH:MM | \<fix shipped / deployed\> | PR #N |
| YYYY-MM-DD HH:MM | Incident resolved | IC |

If the timeline spans multiple days, group by day with sub-headers. Keep entries short — one line each. The detail goes in §5 (Root cause) and §6 (Resolution).

---

## 4. Root Cause **(required)**

Use 5 Whys, fault-tree, or a written causal paragraph — pick the one that fits the incident. The goal is to identify the **systemic** cause, not the proximate trigger.

### 4.1 Proximate trigger

The thing that directly caused the user-visible symptom. Be specific.

### 4.2 Systemic cause

The thing that allowed the proximate trigger to exist. This is what the action items in §9 will address. If the systemic cause is "we didn't have a process for X," the action item is to create that process. If it is "the process existed but wasn't followed," the action item is the enforcement.

### 4.3 5 Whys (or chosen method)

```
1. Why did <symptom> happen?
   → Because <proximate cause>.
2. Why did <proximate cause> happen?
   → Because <next layer>.
3. ...
```

---

## 5. Detection **(required)**

Two fields:

- **How did we find out?** Alert? User report? Routine audit? Internal observation? Anomalous on-chain behaviour noticed by a third party?
- **How long did it last before detection?** Time from the incident start (the first divergence from correct behaviour) to detection. If this number is embarrassing, that is a feature, not a bug — the whole point of this section is to make it visible.

If detection was delayed, this is where the postmortem is honest about it. Do not paper over a slow detection with reassuring language.

---

## 6. Resolution **(required)**

What stopped the bleed. List every concrete action that contained or resolved the incident, in order:

1. **Immediate containment** (pause, role revoke, key rotation, RLS re-lock).
2. **Root-cause fix** (the code change, the config change, the policy change).
3. **Verification** (the test or on-chain check that proved the fix worked).
4. **Cleanup** (de-pause, restore normal operations, communicate closure).

Each step gets a PR / tx hash / doc link. Vague claims ("we patched it") are not acceptable.

---

## 7. Impact **(required)**

Concrete numbers. If a number is zero, write `0`. Do not write "none."

| Dimension | Impact |
|---|---|
| **Users affected** | count (or wallet count if on-chain) |
| **Funds at risk** | amount + asset |
| **Funds lost** | amount + asset (should equal zero for a successful incident response) |
| **Data integrity window** | the time window during which data could have been tampered, even if no evidence of tampering exists |
| **Brand / reputation** | qualitative: did this make it to public channels, was it covered externally, did it appear in the next investor update |
| **Operational cost** | engineering hours, vendor hours, gas spent on remediation txs |

For SEV0/SEV1, also include:

- **Audit-relevant findings** — did this incident surface a new class of vulnerability that the next audit should explicitly cover?
- **Off-chain impact** — Supabase rows touched, alerts fired, third-party services affected.

---

## 8. What Worked / What Didn't **(required)**

Two lists. Be specific. "We responded quickly" is not acceptable — *why* did the response work?

### What worked

- Concrete things, with the evidence for why they worked.

### What didn't

- Concrete things, including the *near misses*. A near miss is more valuable to write down than a clean recovery, because the next time the same situation appears, the near miss is the early warning.

---

## 9. Action Items **(required)**

Table. Every action item gets an owner, a due date, a status, and a link to the tracker (the canonical home for these is `MAINNET_READINESS.md` tiers, or whatever successor tracker exists).

| ID | Action | Owner | Due | Status | Tracker link |
|---|---|---|---|---|---|
| AI-1 | <description> | F / E / X / L | YYYY-MM-DD | pending / in-progress / done | MAINNET_READINESS.md Tier X #N |
| AI-2 | <description> | E | YYYY-MM-DD | pending | PR #N |
| ... | | | | | |

Naming convention: `AI-N` within the postmortem, then cross-reference from the tracker by `postmortem:<file>#AI-N`. Owners use the legend from `MAINNET_READINESS.md` (F / E / X / L).

A postmortem is not closed until every action item has an owner and a due date, and has been added to the tracker. **Action items not in the tracker are not action items — they are intentions.**

---

## 10. Lessons Learned **(required)**

Two to five bullets. These are the things a future engineer should be able to read in 30 seconds and learn the right instinct. Not the same as the action items — the action items are the work; the lessons are the *judgment*.

> **Template:** "A healthy \<X\> is one a \<Y\> reads every \<Z\>." / "Silent failures are the most expensive failures because they train everyone to ignore the alert channel." / "The cheapest reliable prevention for \<class\> is \<specific action\>."

If the lessons could apply to any DeFi protocol, they are too generic. Make them specific to ZENTORY.

---

## Appendix A — Evidence Package Index **(required for SEV0/SEV1)**

A list of every artifact stored alongside the postmortem:

- Tx hashes + block explorer links (per chain).
- Role-change event log exports.
- Keeper audit log export (incident window).
- Alert timestamps + screenshots.
- Off-chain state snapshots (Railway volume, Supabase row counts, GitHub PAT validity, deployed commit SHAs).
- Decision log (who decided what, when).
- Communications archive (internal + external).

The Security Engineer owns the evidence package. The IC confirms it is complete before the postmortem is published.

---

## Appendix B — Disclosure Notes

Only for incidents where the public postmortem differs from the internal one.

- What was redacted and why.
- Coordinated disclosure timeline (if an audit firm or third party was involved).
- Any legal-counsel-approved language substitutions.

---

*Template version: 1.0 | Last updated: 2026-08-20 | Tracked under Phase D of the go-to-market checklist.*
