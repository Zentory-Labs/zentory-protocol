# Contributing to ZENTORY

Thanks for your interest. Read this first — **we close unsolicited PRs from
first-time contributors on sight.** That's not unfriendly; it's our standard
defense against the wave of bot/farm PRs that targets crypto repos.

## TL;DR

1. **Open an issue first** describing what you want to change and why.
2. Wait for a maintainer to ack the issue.
3. *Then* a PR is welcome. Keep it small + focused.

## Hard "no"s

We immediately close + block-the-author for any of the following:

- A PR opened without a prior linked issue or maintainer ack.
- A PR from a first-time contributor whose username/profile looks bot-shaped
  (auto-generated handles, no real history, batch-spam pattern across many
  repos).
- A PR that touches `.github/workflows/*`, `foundry.toml`, `remappings.txt`,
  `package.json`/`package-lock.json`, deploy scripts, the `keeper/`
  configuration, or any secrets-adjacent file — except from a maintainer.
- A PR that pulls in a new dependency without a maintainer-acked design
  discussion. This is the supply-chain attack vector.
- A PR with `vm.ffi(...)`, `vm.broadcast(...)` writes outside scripts,
  curl-piped install steps, or postinstall scripts in any added deps.

## Security disclosures

**Do NOT open a public PR or issue for a vulnerability.** See `SECURITY.md`
for responsible disclosure. We run an Immunefi bounty (or will, post-audit
— see `docs/IMMUNEFI_SETUP.md`).

## Reviewing & merging

- All PRs require an approval from the code owner (`.github/CODEOWNERS`)
  before merge — enforced by branch protection.
- All status checks must pass (Foundry tests, Slither advisory).
- Maintainers may rebase/squash on merge.
- Signed commits required for protected branches (`git commit -S`).

## What we welcome

- Documentation fixes (typos, clarifications) — open a small PR, fine.
- Issue reports with reproduction steps for bugs.
- Discussion in issues about strategy/design improvements.
- Audit/security observations via the disclosure path in `SECURITY.md`.

## What we don't accept

- Refactors with no behavior change ("cleanup PRs" from non-maintainers).
- New tests that don't reproduce a real bug or extend an existing suite
  for a deliberate reason.
- Dependency bumps without justification.
- Style/lint-only PRs.

If you're unsure, **open an issue first.** Saves everyone time.
