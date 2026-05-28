# Security Hardening Runbook (all public Zentory repos)

Concrete GitHub UI steps to lock down `zentory-protocol`, `zentory-app`, and
`zentorylabs.com`. The bot/farm PR pattern that hit us in May 2026 was the
trigger — these settings make the next one a non-event.

This is operational hygiene that institutional LPs / auditors check before
diligence. **Free, ~15 min total, recurring zero cost.**

> NOTE: GitHub UI settings can't be set from a config file. The CODEOWNERS
> + CONTRIBUTING + SECURITY.md changes are in the repo; the rest below must
> be flipped in the GitHub UI by a repo admin.

---

## 1. Branch protection — `main` (per repo)

Settings → Branches → **Add classic branch protection rule** for `main`:

- [x] **Require a pull request before merging**
- [x] Require approvals: **1** (will become 2 once you have 3+ maintainers)
- [x] **Dismiss stale pull request approvals when new commits are pushed**
- [x] **Require review from Code Owners** ← this is what makes CODEOWNERS enforced
- [x] **Require status checks to pass before merging**
   - Add the required checks (Foundry tests, build, etc.) once your CI is named
- [x] **Require branches to be up to date before merging**
- [x] **Require conversation resolution before merging**
- [x] **Require signed commits**
- [x] **Restrict who can push to matching branches** → only maintainers
- [x] **Do not allow bypassing the above settings** (no admin bypass)
- [x] **Restrict pushes that create matching branches** → off (you want to allow feature branches)
- [x] **Block force-pushes** (default; keep on)
- [x] **Block deletions** (default; keep on)

## 2. Actions — restrict workflow runs from forks (per repo)

Settings → Actions → General →

- **Actions permissions** → "Allow [Zentory-Labs] actions and reusable
  workflows" + "Allow actions created by GitHub" (don't open it up to
  "Allow all actions" — that's how supply-chain attacks land).
- **Fork pull request workflows from outside collaborators** →
  **"Require approval for all outside collaborators"** ← THIS IS WHY THE
  GTX BOT PR WAS BLOCKED. Keep it on; it's the system working.
- **Workflow permissions** → **"Read repository contents and packages
  permissions"** (the *default* token has read-only). Combined with
  per-job `permissions: contents: read` in the workflow file, this gives
  defense in depth.
- [x] **Allow GitHub Actions to create and approve pull requests** → OFF
  (a leaked Action token must not be able to merge things).

## 3. Code security & analysis (per repo)

Settings → Code security → enable:

- [x] **Dependabot alerts**
- [x] **Dependabot security updates** (PRs from Dependabot only — bypass
  the CODEOWNERS requirement for these is fine since they're scoped)
- [x] **Secret scanning**
- [x] **Push protection** (blocks commits that contain known-secret patterns
  *before* they leave your machine)
- [x] **Private vulnerability reporting** (gives researchers a private
  channel — pairs with `SECURITY.md`)

## 4. Moderation — block the bot author

Settings → Moderation → **Blocked users** → block the gtx-style bot
account (and any other bot-shaped names spamming PRs). Report as spam via
the `…` menu on the PR itself.

If they spammed multiple Zentory repos, repeat in each.

## 5. PRs & issues — auto-close stale/spam

Settings → General → Pull Requests → keep "Allow squash merging" + "Allow
auto-merge" (use sparingly, only for Dependabot). Disable "Allow merge
commits" + "Allow rebase merging" unless you actively use them.

Consider a stale-bot or GH-built-in: PRs untouched 14 days from non-
maintainers → auto-comment "please re-open after maintainer ack" → close.

## 6. Repo-level

- [x] Settings → General → "Require contributors to sign off on web-based
  commits" (DCO sign-off discourages low-effort drive-bys).
- [x] Disable "Wikis" if unused (one less surface).
- [x] Disable "Projects" / "Discussions" if unused.

## 7. Org-level (Zentory-Labs)

If you haven't already, at the org Settings → Member privileges:

- **Base permissions** → "Read" (not "Write") — outside collaborators get
  read by default.
- **Repository creation** → "Members can create only private repositories"
  (forces a conscious choice to make something public).
- **Repository invitations** → "Members are restricted" (only admins can
  add outside collaborators).

## 8. Add a `SECURITY.md` (already exists in `zentory-protocol`)

For the other repos that don't have one, copy from `zentory-protocol/SECURITY.md`
or write a one-liner that points there. Investors / auditors look for this.

---

## What to do RIGHT NOW (the bot PR)

1. Open the PR on GitHub.
2. Click **Files changed** and inspect the diff carefully. Red flags
   (close-on-sight): `.github/workflows/*`, `foundry.toml`, `remappings.txt`,
   `package.json`, scripts, `keeper/*`. A real-looking test that touches
   *only* `contracts/test/...` is technically lower risk — but still close
   it (you don't owe spammers a merge).
3. Click the author's username; check if they've spammed other repos with
   the same template. If yes → spam-bot confirmed.
4. **Close** the PR with the comment from `CONTRIBUTING.md`: "Closing —
   unsolicited PRs from first-time contributors aren't accepted; please
   open an issue first."
5. **Block** the user (Moderation → Blocked users).
6. **Report as spam** from the PR's `…` menu.
7. Check the other Zentory repos for the same bot author's open PRs.

The CI run was held precisely because §2 above is already on. Don't
approve it.

---

## Why this matters beyond bots

The same hardening list is what an auditor or institutional LP looks for
in pre-mainnet diligence:

- CODEOWNERS + branch protection = "no single dev can rug the contracts"
- Secret scanning + push protection = "no leaked keys" (we already had one)
- Required status checks = "all merges run the test suite"
- Signed commits = "we know who changed what"
- Restricted Actions = "supply chain doesn't run wild"

It is **free** and **takes 15 minutes**. Do it once and it pays compounding
dividends in trust signals for the rest of the project.
