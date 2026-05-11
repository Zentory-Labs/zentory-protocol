# Re-rate Trigger Checklist

*The final pre-flight before clicking "Re-rate" on the rating platform that issued our 56/100 score. Owner: whoever holds the rating-platform login. Last updated: May 2026.*

This is the **re-rate trigger** track. The earlier tracks produced the public surfaces (`README`, `STRATEGY`, `COMPETITORS`, `/why` page, JSON-LD, social, founder verification). This document tells you when and how to trigger the re-rate so the rater's scraper sees the new content on the first pass.

**Note on second-pass fixes (May 2026).** A coherence + product-lens review surfaced a small batch of wording bugs (custody language in `layout.tsx` FAQ JSON-LD and `page.tsx`, "wallet" vs "vault contract", README cross-reference `§5` → `§7.2`, SOCIAL_LAUNCH cross-reference `§3` → `§4.3`, capability-matrix `Yes` → `Partial` on Ghost dashboard rows, Hyperliquid fill-pipeline status). Those have been applied. Make sure those commits are part of the final push before re-rating.

---

## Pre-flight: must be true before clicking re-rate

Every item below has to be a hard "Yes" before re-rating, or the re-rate will not move the score meaningfully.

### Track A — GitHub org + repo split (new — May 2026)

The old `edgeza/ZentoryToken` monorepo has been split into `Zentory-Labs`. Confirm these four repos exist and are in the right state:

- [ ] `Zentory-Labs/zentory-protocol` — **public**, has rewritten README, BSL 1.1 LICENSE, topics + description set, social preview uploaded, discussions enabled with 3 seed threads.
- [ ] `Zentory-Labs/zentory-app` — public, AGPL-3.0 LICENSE, topics set.
- [ ] `Zentory-Labs/zentorylabs.com` — public, MIT, topics set.
- [ ] `Zentory-Labs/zentory-engine` — **private** (confirm this has NOT been made public).
- [ ] `https://github.com/edgeza/ZentoryToken` redirects to `https://github.com/Zentory-Labs/zentory-protocol` (GitHub handles this automatically after a transfer).
- [ ] Secrets audit clean: `git grep` for embedded keys returns zero in `zentory-protocol` and `zentory-app`.
- [ ] The local `zentory-protocol/` folder's README now has the "Open Source Policy" section and the new repo-layout table pointing to the other three repos.

### Track B — Marketing site

- [ ] `zentorylabs.com/app/page.tsx` new metadata + `problemPoints` deployed.
- [ ] `zentorylabs.com/app/why/page.tsx` deployed and reachable at `https://zentorylabs.com/why`.
- [ ] `zentorylabs.com/app/layout.tsx` JSON-LD blocks and `twitter:site` meta deployed.
- [ ] `zentorylabs.com/app/sitemap.ts` deployed; verify `https://www.zentorylabs.com/sitemap.xml` resolves and includes `/why`.
- [ ] `zentorylabs.com/app/robots.ts` deployed; verify `https://www.zentorylabs.com/robots.txt` resolves and explicitly allows GPTBot / ClaudeBot / PerplexityBot.
- [ ] `zentorylabs.com/components/Header.tsx` shows GitHub link pointing to `https://github.com/Zentory-Labs/zentory-protocol` (updated from the old `edgeza/ZentoryToken` URL).
- [ ] `zentorylabs.com/components/Footer.tsx` and `zentorylabs.com/app/layout.tsx` JSON-LD `sameAs` links all updated to the new `Zentory-Labs/` URLs.
- [ ] `zentorylabs.com/components/Footer.tsx` shows X / GitHub / dApp / Why ZENTORY / Whitepaper links.
- [ ] `zentorylabs.com/data/team.json` has `links` object populated with real handles (per Founder Verification doc).
- [ ] `zentorylabs.com/app/team/[slug]/page.tsx` renders the new `Verifiable handles` block.

### Track C — Social

- [ ] `@ZENTORYLabs` bio updated per [`SOCIAL_LAUNCH.md`](SOCIAL_LAUNCH.md) C1.
- [ ] Avatar and header image set.
- [ ] C2 thread posted and pinned. Each tweet in the thread is live.
- [ ] At least 3 of the C3 cornerstone posts have been published (1/week cadence has started).
- [ ] At least 5 ecosystem reply interactions per weekday for the past 2 weeks.
- [ ] Both founders following the handle.
- [ ] Project handle verified on the rating platform per [`SOCIAL_LAUNCH.md`](SOCIAL_LAUNCH.md) C1 step 4.

### Track D — Founders

- [ ] Edge's GitHub profile updated per [`FOUNDER_VERIFICATION.md`](FOUNDER_VERIFICATION.md) D2.
- [ ] Shaman's GitHub profile updated per same.
- [ ] Both founder X profiles updated.
- [ ] Founder LinkedIn profiles updated (optional but recommended).
- [ ] Founder verification submitted on rating platform per D3.
- [ ] Rating platform shows Founders dimension as "Verified" (or platform's equivalent).

### Track E — Quality gate

- [ ] `ce-doc-review` (coherence + product-lens) has been run on the new docs and any Critical / Important findings have been resolved.
- [ ] Internal sanity read: a non-team member can read the README and tell you in one sentence what ZENTORY is.

---

## Propagation wait times

After the last item above is true, wait for the following before clicking re-rate:

| Surface | Typical propagation | Why wait |
|---|---|---|
| GitHub topic indexing | 2–4 hours | Topics need to appear in GitHub's search index for the rater to use them as a signal |
| Vercel deployment | 2–5 minutes | Marketing site changes need to be live |
| Cloudflare / CDN cache (if used in front of zentorylabs.com) | up to 1 hour | Old metadata cached at edge |
| Twitter follower / impression metrics | 24–48 hours | Rater sees a snapshot; let activity register |
| Founder verification on rating platform | 1–3 business days | Platform-side processing |
| Sitemap submission to Google Search Console (optional) | 1–7 days | Useful for AI scrapers that piggy-back on Google index |

**Minimum total wait:** ~24 hours after the last item is checked.
**Recommended total wait:** **3 weeks** after the C2 thread is posted, so social signals have history depth.

---

## How to trigger the re-rate

1. Log into the rating platform with the account that owns the project record.
2. Navigate to the project page for `Zentory-Labs/zentory-protocol` (the rating platform may have auto-detected the new URL after the transfer; if it still shows `edgeza/ZentoryToken`, use the old URL and update it to `Zentory-Labs/zentory-protocol`).
3. **Verify the platform is reading the public repo, not a cached private snapshot.** If it still says "Unverified" or shows the old description, click "Refresh / Re-fetch" first.
4. Click "Re-rate" / "Refresh score" / "Submit for re-evaluation" (label varies).
5. Confirm the new content (description, topics, README excerpt, BSL LICENSE) is reflected in the platform's preview before submitting.
6. Submit.

The platform will queue the re-rate. Wait 5–30 minutes for the new score.

---

## What we expect to see

If everything in this checklist is true, the new score should land in this range:

| Dimension | Before | Expected after |
|---|---|---|
| **Uniqueness** | 40 | **75–85** |
| — Problem Novelty | 40 | 75–85 |
| — Ecosystem Saturation | 40 | 70–80 |
| — Solution Differentiation | 40 | 80–90 |
| **Social Presence** | 20 | **40–60** |
| — Content Relevance | 20 | 50–70 |
| — Engagement Quality | 20 | 30–50 |
| — Audience Authenticity | 20 | 40–55 |
| **Founders** | 0 | **Verified / 60–80** |
| **Investment Thesis** | 83 | **83–88** |
| **Overall** | **56** | **75–82** |

If the new score is below 70 overall after all of the above, something is broken in how the platform is reading our surfaces — open a support ticket with screenshots showing the public README, deployed `/why` page, and verified handle.

---

## What we do if the score does not move

Diagnostic order:

1. **Did the rater see the new README?** Check the platform's project preview pane. If it still shows the empty / old description, the platform is using a cache. Force-refresh.
2. **Did the rater see the marketing site?** Check the platform's site preview. If it shows the OLD copy ("Earn Systematic Yield"), the platform has a Cloudflare or its own cache. Wait 24h and retry.
3. **Is the repo actually public?** `gh repo view Zentory-Labs/zentory-protocol --json isPrivate` should return `false`.
4. **Are topics actually attached?** `gh repo view Zentory-Labs/zentory-protocol --json repositoryTopics` should return a non-null array.
5. **Did founder verification go through?** Check the project page for the Founders dimension status.

If 1–5 are all green and the score still hasn't moved, the rater is likely batching re-evaluations weekly. Wait 7 days, then retry.

---

## Post-rate actions

Within 24 hours of the new score landing:

- Screenshot the new score for the investor deck and `STRATEGY.md` §9.
- Post a brief thread from @ZENTORYLabs noting the rating improvement (don't be cringe about it — frame it as "the public docs are finally where they should be, here's what changed").
- Update [`docs/INVESTOR_ONE_PAGER.md`](../INVESTOR_ONE_PAGER.md) to reference the rating if it's now in the top tier.

---

## Beyond this round

The next ceiling on the score is **Social Presence** (cap at ~60 in this round because content history is still shallow). To break 80 overall in 60–90 days:

- Maintain the C4 cadence in [`SOCIAL_LAUNCH.md`](SOCIAL_LAUNCH.md).
- Land an ecosystem partnership announcement (Hyperliquid integration, audit firm engagement, named-quant onboarding).
- Ship the Ghost Portfolio public dashboard (Track B / 2 in [`STRATEGY.md`](../../STRATEGY.md)).
- Trigger another re-rate at month 3.

Beyond that, the score is constrained by real protocol milestones (mainnet, audit, TVL), which is exactly how it should be.
