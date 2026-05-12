# Zentory Protocol — Master Deployment Guide

## Repository Structure

As of May 2026 the monorepo has been split into four repositories under the `Zentory-Labs` GitHub organization:

```
Zentory-Labs/zentory-protocol     ← This repo (BSL 1.1, public)
├── contracts/                      Solidity smart contracts (Foundry)
├── docs/                           Plans, roadmaps, security findings
└── whitepaper/                     Whitepaper source content

Zentory-Labs/zentory-app          ← Next.js dApp (AGPL-3.0, public)
                                    Deployed at app.zentorylabs.com

Zentory-Labs/zentory-engine       ← Research engine (Proprietary, private)
                                    Off-chain signer; binds to on-chain
                                    SignalRegistry via EIP-712 only.

Zentory-Labs/zentorylabs.com      ← Marketing website (MIT, private repo)
```

---

## Prerequisites

- Node.js 20+
- Python 3.11+
- [Foundry](https://getfoundry.sh)
- [Supabase CLI](https://supabase.com/docs/guides/cli)
- Git

---

## Step 1 — Supabase Setup

### Create a Supabase project

1. Go to [supabase.com](https://supabase.com) → New project
2. Save the **Project URL** and **anon/public key** from Settings → API
3. Save the **service role key** (keep server-side only)

### Run the schema

In the Supabase SQL Editor, paste and run the contents of:

```
frontend/supabase/schema.sql
```

This creates:
- `signals` — trade signal history
- `profiles` — wallet → email mapping
- `proposals` — governance proposal mirror
- `keeper_audit` — keeper execution log

### Enable Row Level Security

All tables have RLS enabled. The schema includes policies:
- Anyone can read signals and proposals
- Only service role can insert/update signals and audit logs

### Environment variables (frontend)

```bash
# frontend/.env.local
NEXT_PUBLIC_SUPABASE_URL=https://your-project-id.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key
```

---

## Step 2 — Deploy Smart Contracts

### Testnet (HyperEVM Testnet)

```bash
cd contracts

# Initialize submodules (first time only)
git submodule update --init --recursive

# Copy and fill env
cp .env.example .env
# Edit .env with your deployer private key and RPC URL

# Full pipeline deploy
forge script script/DeployPipeline.s.sol \
  --rpc-url $HYPEREVM_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvv

# Run tests
forge test

# Run Slither (requires Python + slither-analyzer)
slither . --solc-remaps '@openzeppelin=node_modules/@openzeppelin'
```

### Update frontend contract addresses

After deployment, update `frontend/lib/contracts.ts` with the deployed contract addresses from `deployments.json`.

---

## Step 3 — Frontend Setup

```bash
cd frontend

# Install dependencies
npm install

# Copy env
cp .env.example .env.local
# Fill in all variables (see .env.example comments)

# Run dev server
npm run dev

# Build for production
npm run build
```

### Key environment variables (frontend)

| Variable | Purpose |
|---|---|
| `NEXT_PUBLIC_HYPEREVM_RPC` | HyperEVM testnet/mainnet RPC |
| `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` | WalletConnect cloud project ID |
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase anon key |
| `KEEPER_PRIVATE_KEY` | **Server-side only.** Private key for keeper wallet that executes trades. Never expose to browser. |

### Production deploy (Vercel)

```bash
npm run build
vercel --prod
```

Add all `NEXT_PUBLIC_*` and `KEEPER_PRIVATE_KEY` to Vercel environment variables. Mark `KEEPER_PRIVATE_KEY` as sensitive.

---

## Step 4 — Marketing Site

```bash
cd zentorylabs.com

npm install
npm run build
vercel --prod
```

The marketing site is fully static (SSG) except for `/api/backtest-chart`.

### Environment variables (zentorylabs.com)

Currently none required — the site is fully static.
(Historically: `ALPACA_API_KEY`, `ALPACA_API_SECRET` for live portfolio — these are deprecated.)

---

## Step 5 — Engine Setup

```bash
cd engine

# Install (Python 3.11+)
pip install -e .

# Run tests
pytest

# Lint
ruff check src
ruff check src --fix
```

### Key engine modules

| Module | Purpose |
|---|---|
| `src/genetic_programming/` | GP primitives, chromosome, population |
| `src/strategy/` | Signal generation, trend follower |
| `src/signals/` | EIP-712 signing, signal router |
| `src/execution/` | Hyperliquid executor, Lumibot broker |

---

## Testnet Deployment Checklist

Before any mainnet deployment, clear these gates from `docs/plans/2026-04-25-001-verification-master-plan.md`:

- [ ] G1: All 200 Foundry tests pass
- [ ] G2: Invariant tests pass
- [ ] G3: Slither finds no HIGH/CRITICAL issues
- [ ] G4: Python/Solidity digest parity test passes
- [ ] G5: Playwright smoke tests pass on testnet
- [ ] G6: Privileged API auth + rate limiting verified
- [ ] G7: Pentest: 0 CRITICAL, ≤2 HIGH findings
- [ ] G8: Governance timelock lifecycle test passes
- [ ] G9: Monitoring alerts fire correctly
- [ ] G10: Incident response runbook tested

---

## Links

| Service | URL |
|---|---|
| Marketing site | https://zentorylabs.com |
| DApp | https://app.zentorylabs.com |
| DApp GitHub | [`Zentory-Labs/zentory-app`](https://github.com/Zentory-Labs/zentory-app) |
| HyperEVM Testnet RPC | https://rpc.hyperliquid-testnet.xyz/evm |
| HyperEVM Explorer | https://hypurrscan.io |
| Supabase Dashboard | https://supabase.com/dashboard |
