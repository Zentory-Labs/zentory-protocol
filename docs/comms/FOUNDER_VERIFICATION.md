# Founder Verification Checklist

*Owner: Edge & Shaman. To be executed in parallel by both co-founders. Last updated: May 2026.*

The rating report scored Founders **0/100**. The rating platform marks `@zentorylabs` as **Unverified** and lists no founder profiles. This is a binary flip — once the checklist below is complete, the score moves from 0 to "Verified" in the rater's model.

This is the bundled execution of the **founder verification** track (D2 + D3 in our internal plan). See [`GITHUB_SETTINGS.md`](../../GITHUB_SETTINGS.md) for the parallel repo-hygiene track and [`TEAM.md`](../../TEAM.md) for the canonical founder roster.

---

## Why founder verification matters

Three of the rater's signals depend on it:

1. **Founders dimension** itself (currently 0).
2. **Audience authenticity** under Social Presence — founders following the project handle is the lowest-cost authenticity signal.
3. **Repository verification** — rating platforms typically verify a repo by checking that one of the linked founder accounts has push access.

Doing this work after the README + STRATEGY + COMPETITORS land but **before** triggering the re-rate is the optimal sequence.

---

## D2 — Founder profile updates

Each co-founder runs through the same checklist on their own accounts.

### Edge

| Surface | Current | Target |
|---|---|---|
| GitHub `@edgeza` bio | TBA — verify | Mentions "Co-Founder, ZENTORY Labs — Head of Algo & Strategy." Links: `zentorylabs.com`, `github.com/edgeza/ZentoryToken`. |
| GitHub pinned repos | TBA — verify | `ZentoryToken` and `zentorylabs.com` are pinned. |
| GitHub profile README (`edgeza/edgeza` if it exists, otherwise create) | TBA | Short intro: who, what role at ZENTORY, what to read first (link the new README sections). |
| X profile (when set up) | None | Bio: "Co-Founder @ZENTORYLabs — Head of Algo & Strategy. Building the Signal Arena on HyperEVM." Header: ZENTORY brand. Pinned: link to the @ZENTORYLabs C2 thread. |
| LinkedIn (optional) | TBA | "Co-Founder, ZENTORY Labs" with link to zentorylabs.com. Helps the rater on Founders score. |
| Email signature | TBA | Title + zentorylabs.com link + GitHub handle. |

Once these are set, send the URLs to Shaman to plug into [`TEAM.md`](../../TEAM.md) and [`zentorylabs.com/data/team.json`](../../../zentorylabs.com/data/team.json) (the `links` object on each member entry).

### Shaman

| Surface | Current | Target |
|---|---|---|
| GitHub profile | TBA — create if needed | Bio mentions "Co-Founder, ZENTORY Labs — Head of Operations & PR." Link to zentorylabs.com. |
| GitHub pinned | TBA | `ZentoryToken` and `zentorylabs.com` (once you have collaborator visibility). |
| X profile (when set up) | None | Bio: "Co-Founder @ZENTORYLabs — Head of Ops & PR." Header: ZENTORY brand. Pinned: link to the @ZENTORYLabs C2 thread. |
| LinkedIn (optional) | TBA | "Co-Founder, ZENTORY Labs" with link to zentorylabs.com. |
| Email signature | TBA | Title + zentorylabs.com link. |

Send URLs to Edge for inclusion in `TEAM.md` and `team.json`.

### Cross-link cadence (both founders)

- Both founders **follow @ZENTORYLabs** on X.
- Both founders **like and quote-tweet** the C2 pinned thread the moment it goes live.
- Both founders **add `zentorylabs.com` to their X bio link** field.
- Both founders **list each other** in a brief "team" line in their bios where character count allows.

---

## D3 — Submit founder verification on the rating platform

Once D2 is complete and the new content has been pushed to GitHub + deployed to `zentorylabs.com`:

1. **Log into** the rating platform (whoever holds the credentials).
2. **Open** the project record for `edgeza/ZentoryToken`.
3. **Find** the Founders section. Most platforms ask for one or both of:
   - Public profile links (X, GitHub, LinkedIn) for each named founder.
   - Optional: KYC document upload to the platform itself (not publicly visible).
4. **Fill in** for each founder:
   - Name (pseudonymous handle is acceptable on most platforms; if not, use legal name with consent and the platform's privacy controls).
   - Role.
   - GitHub URL.
   - X URL.
   - LinkedIn URL (optional but helps).
   - Email (`edge@zentorylabs.io`, `shaman@zentorylabs.io`).
5. **Submit**. Verification typically takes 1–3 business days depending on platform.
6. **Confirm** the rating platform updates the Founders dimension from 0 to "Verified" or a positive numeric score.

### If the platform requires real identity

Some platforms (especially those tied to securities-grade ratings) will not verify pseudonymous founders. If that's the case here:

- Use the **legal entity** (ZENTORY Labs) plus the **operator-of-record** names that are already on file with audit/legal counsel.
- The rating platform usually has a private KYC channel — the names need not appear on the public site.
- Once verified, this becomes a one-time action.

### If you decide to keep founders pseudonymous publicly

This is a valid choice in crypto and many rating platforms accept it as long as:

- The handles are **stable** (no rotating identities).
- The handles are **reachable** (active GitHub + active X).
- The legal entity behind ZENTORY Labs is **registered and contactable** for compliance purposes (separate from public-facing founder identity).

Document this choice in `docs/regulatory-memo.md` so it's defensible later.

---

## Sequencing

```
1. Edge updates GitHub bio + pinned repos + profile README
2. Shaman updates GitHub bio + pinned repos
3. Edge + Shaman set up X profiles (if not already), bio, header, follow @ZENTORYLabs
4. Both LinkedIn (optional, recommended)
5. Send URLs back to whoever owns TEAM.md / team.json
6. TEAM.md and team.json are updated with the real URLs (filling the empty "x" fields in the JSON)
7. Commit + push (ZentoryToken/TEAM.md + zentorylabs.com/data/team.json)
8. Wait for marketing site redeploy (~2 minutes on Vercel)
9. Submit founder verification on rating platform
10. Re-trigger rate (after STEP 11 in GITHUB_SETTINGS.md)
```

Steps 1–5 are 30–60 minutes total per founder. Step 9 is a one-time platform submission. Step 10 closes the loop.

---

## Expected impact

| Score | Before | After D2 + D3 |
|---|---|---|
| Founders | 0 | Verified (binary in most platforms; numeric 60–80 in graded platforms) |
| Audience authenticity (Social sub-axis) | 20 | +10 to +20 from founder follows alone |
| Repository verification | Unverified | Verified once founder GitHub access is linked |
| Project handle verification | Unverified | Verified once @ZENTORYLabs is claimed |

This is the highest-leverage hour of work in the entire `improve-zentory-rating` plan.
