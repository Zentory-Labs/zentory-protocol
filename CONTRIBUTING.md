# Contributing to ZENTORY

Thank you for your interest in contributing to ZENTORY Protocol. This document tells you what we accept, how to set up the repo, how to land a PR, and how we handle security.

The high-level "what is this project" answer lives in [`README.md`](README.md), [`STRATEGY.md`](STRATEGY.md), and [`docs/whitepaper.md`](docs/whitepaper.md). Read those first.

---

## Ground rules

1. **Security disclosures do not go in public issues.** Email `security@zentorylabs.com` or use the Immunefi program (when live). See [`SECURITY.md`](SECURITY.md).
2. **Smart-contract changes require tests.** New behavior needs unit tests; risky behavior needs fuzz or invariant tests in [`contracts/test/`](contracts/test). PRs that change `.sol` without expanding `test/` will be asked to revise.
3. **No emojis in code or commit messages.** Plain text only.
4. **No `console.log` / `console.error` in shipped TypeScript.** Use the existing logger or `@sentry/nextjs` where applicable.
5. **Do not commit secrets.** `.env` files are in `.gitignore`; rotate any key that ends up in a diff.

---

## Repository setup

### Prerequisites

- Node 20+
- Python 3.11+
- Foundry (`foundryup`)
- Supabase CLI (only if working on `supabase/`)

### Smart contracts

```
cd contracts
forge install            # pulls submodules (forge-std, OZ, OZ-upgradeable)
forge build
forge test -vv
forge test --match-path "test/fuzz/**"
forge test --match-path "test/invariants/**"
```

The cross-language EIP-712 test (`test/crosslanguage/DigestParity.t.sol`) uses `vm.ffi` and requires the Python engine to be installed first:

```
cd ../engine
pip install -e ".[dev]"
```

### Python engine

```
cd engine
pip install -e ".[dev]"
pytest
ruff check src tests
mypy src
```

### Frontend dApp

```
cd frontend
npm ci
cp .env.example .env.local   # fill in Supabase, RPC, WalletConnect IDs
npm run dev
```

### Marketing site

The marketing site lives in a separate repo (`zentorylabs.com`) and is deployed independently. PRs that touch marketing copy go there.

---

## Workflow

1. **Discuss before building.** For non-trivial work, open an issue or comment on an existing one to align on scope. We will not merge a 500-line PR that nobody knew was coming.
2. **Branch from `main`.** Branch names should be lowercase, dash-separated, and prefixed by intent: `feat/`, `fix/`, `chore/`, `docs/`, `test/`. Example: `feat/ghost-portfolio-indexer`.
3. **Commit messages.** Conventional Commits style is preferred (`feat: ...`, `fix: ...`, `docs: ...`). Imperative voice. No emojis.
4. **PR description.** Must answer: (a) what changed, (b) why, (c) how it was tested, (d) any tradeoffs or follow-ups. PRs without (c) and (d) will be sent back.
5. **CI must be green.** See [`.github/workflows/ci.yml`](.github/workflows/ci.yml) for the gates: contracts (Foundry build/test/invariants + FFI signer), Slither, engine pytest, frontend build + Playwright + Vercel preview.
6. **Review.** At least one core-team approval for `contracts/` changes; two for changes that touch `keeper/`, `governance/`, `staking/`, or `signals/`. UI changes require a Vercel preview link in the PR.

---

## Areas open for contribution

| Track | What we want | Where to look |
|---|---|---|
| **Smart contracts** | Additional fuzz / invariant suites; gas optimization with proof; new vault wrappers | [`contracts/src/`](contracts/src), [`contracts/test/`](contracts/test) |
| **Signal supply** | Quant strategies (Lumibot-compatible) with backtested track record | [`engine/src/strategy/`](engine/src/strategy), [`engine/src/genetic_programming/`](engine/src/genetic_programming) |
| **Indexer & analytics** | Better Ghost Portfolio reconstruction; Hyperliquid fills mapping accuracy | [`engine/scripts/`](engine/scripts) |
| **dApp** | Ghost Portfolio dashboard, conviction leaderboard polish, auto-follow UX | [`frontend/app/`](frontend/app) |
| **Docs** | Improvements to whitepaper, runbooks, deployment guides | [`docs/`](docs) |

---

## Code style

- **Solidity:** `solc 0.8.28`, OpenZeppelin patterns, custom errors over `require(msg)`. Storage layout changes need explicit migration notes. Public/external functions need NatSpec.
- **TypeScript:** strict TS; prefer named exports; no `any` without justification in comment.
- **Python:** Ruff + mypy clean. Type hints on all public functions in `engine/src/`.
- **Tests:** descriptive `test_` names; cover happy path, edge case, and at least one adversarial case.
- **Comments:** explain *why*, not *what*. Skip obvious comments.

---

## Issue templates

The repository ships with templates under [`.github/ISSUE_TEMPLATE/`](.github/ISSUE_TEMPLATE):

- **Monitoring alert** — when a production monitor fires; routes to security/ops.

Open a regular issue for everything else: bugs, feature requests, documentation gaps. Tag with `area:contracts`, `area:engine`, `area:frontend`, `area:docs`, or `area:supabase` if you can.

---

## License & contribution licensing

Unless explicitly noted otherwise, contributions are accepted under the same license as the file being modified. If the file has no license header yet, default to the repository LICENSE file. Significant contributions require a CLA-equivalent statement in the PR description that you have the right to submit the work and grant ZENTORY Labs a license to use it.

---

## Where to ask

- **Bugs / features:** GitHub Issues.
- **Security:** `security@zentorylabs.com`.
- **Business / partnerships:** `contact@zentorylabs.io`.
- **General community:** [@ZENTORYLabs on X](https://twitter.com/ZENTORYLabs).
