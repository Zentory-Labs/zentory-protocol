# Keeper Live-Fire Runbook (HyperEVM Testnet)

Operational procedure for bringing the `zent-keeper-settle` keeper live
against the HyperEVM Blaze testnet (chain ID **998**) so the epoch-settling
loop can be exercised end-to-end with real transactions.

The keeper is the off-chain service that:

1. Polls `EpochScoring.checkUpkeep()` on a heartbeat schedule
2. Reads pending signals from the on-chain registry + the Supabase mirror
3. Submits the accuracy batch back to `EpochScoring.setAccuracyBatch()`
4. Calls `EpochScoring.settleEpoch()` when an epoch reaches its close

The keeper code (`contracts/keeper/src/`) is hardened (chain-ID
assertion at boot, RPC fallback transport, F-08 typed provider on
failure), `forge test` covers the contract surface it touches, and
`npm test` covers the JS module. What it lacks is real network
exercise — this runbook closes that loop.

---

## Pre-flight checklist

| Requirement | Source | Verification |
|---|---|---|
| HyperEVM testnet RPC URL (primary) | Hyperliquid dev portal / community RPC list | `curl -fsS -X POST -H "content-type: application/json" -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' "$RPC_URL"` returns `"result":"0x3e6"` (998) |
| HyperEVM testnet RPC URL (fallback, optional) | Second provider (e.g. public endpoint) | Same check |
| A testnet ETH balance on the keeper EOA | Faucet (Hyperliquid Discord) | `cast balance --rpc-url "$RPC_URL" "$KEEPER_ADDRESS"` returns > 0.5 testnet ETH |
| `KEEPER_PRIVATE_KEY` for that EOA | Locally generated, **never committed** | `cast wallet derive-private-key "$MNEMONIC"` then verify the address matches the funded EOA |
| Deployed `SignalRegistry` address | Output of `forge script contracts/script/DeployCore.s.sol` (or `DeployPipeline.s.sol`) | `cast call --rpc-url "$RPC_URL" "$SIGNAL_REGISTRY" "currentEpochId()(uint256)"` returns `1` |
| Deployed `EpochScoring` address | Same deploy run | `cast call --rpc-url "$RPC_URL" "$EPOCH_SCORING" "stakingContract()(address)"` returns the staking address |
| `ZENT_TOKEN_ADDRESS` | Same deploy run | `cast call --rpc-url "$RPC_URL" "$ZENT_TOKEN" "totalSupply()(uint256)"` matches the deploy log |
| Supabase project URL + service-role key | Supabase dashboard | `curl -fsS -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" "$SUPABASE_URL/rest/v1/signals?select=count"` returns `[]` (empty array) |

The deploy run also has to grant the keeper EOA `SCORING_ORACLE_ROLE`
on `EpochScoring`. That is the only write role the keeper needs.

```
cast send --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_PK" \
  "$EPOCH_SCORING" "grantRole(bytes32,address)" \
  0x8327e8356dfc3d65d40e7f8b69eb1d8a0b3fa30c0a8a8f8a08e8e0a3a5e0a0a0a \
  "$KEEPER_ADDRESS"
```

(The role hash above is illustrative — read `SCORING_ORACLE_ROLE` from
the contract first with `cast call`.)

---

## Smoke tests in dry-run mode

Before broadcasting real transactions, run the keeper against a forked
local node to verify wiring end-to-end:

```bash
# 1. Fork HyperEVM testnet to Anvil
anvil --fork-url "$RPC_URL" --chain-id 998

# 2. Impersonate the deployer to grant the keeper role, then run keeper
#    pointed at the local fork (set RPC_URL=http://127.0.0.1:8545)
forge script contracts/script/DeployPipeline.s.sol \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --slow

# Record the deployed addresses into .env.keeper
```

The deploy script is idempotent — re-running it produces no change on
already-deployed contracts. This is intentional so the testnet + mainnet
deploy scripts can share the same shape.

---

## Boot

```bash
cd contracts/keeper
cp .env.example .env  # edit in the values above
npm ci
npm run build         # tsc, type-checks against the live viem types
npm test              # vitest, runs the keeper unit tests
npm start             # node dist/index.js, enters the polling loop
```

The boot path:

1. Reads env, validates required vars
2. `assertChainId()` — refuses to start if RPC chain ID != 998
3. Subscribes to Supabase `signals` table for new rows
4. Starts the `heartbeat.ts` polling loop (default: every 30s)

The heartbeat log line is the operational "is the keeper alive?" signal.
It must always carry:

- the keeper address
- the chain ID it believes it's on
- the last successful RPC round-trip time

```
[keeper] heartbeat ts=... epochId=... lastEpochStart=... chainId=998 wallet=0x...
```

If the chain ID ever changes mid-flight the keeper aborts. That is the
audit F-03 behaviour.

---

## First settlement

To trigger the first settlement:

1. Submit at least one signal via the on-chain `submitSignal(...)` on
   `SignalRegistry` from a provider EOA funded with testnet ETH.
2. Wait for `expiresAt` to elapse, or fast-forward via
   `cast rpc evm_increaseTime 86400` on a forked node.
3. The keeper heartbeat will see `checkUpkeep() == true` and:
   - call `setAccuracyBatch(...)` for every signal in the epoch
   - call `settleEpoch()`
4. Watch the Supabase `epoch_states` table for the new `settled=true` row.

---

## Going to mainnet

When the HyperEVM testnet (chain ID 998) ships to mainnet (TBD chain ID),
the same keeper binary runs unchanged. Only the following change:

- `CHAIN_ID` env var (defaults to `998`; set to the mainnet chain ID)
- `HYPEREVM_RPC_URL` pointed at the new endpoint
- `HYPEREVM_EXPLORER_URL` for log correlation
- Re-run the deploy script against mainnet with the multisig as `tx.origin`

The keeper code itself has **no chain-ID hardcode** beyond the 998
default + the `assertChainId()` boot check. Both are configurable.

---

## What this runbook does NOT cover

- **Mainnet deploy execution** — runbook in `docs/MULTISIG_MIGRATION_PLAN.md`.
- **Signer rotation** — once the multisig owns deployer / governance roles,
  the keeper EOA needs no special multisig support because it only writes
  to its own roles.
- **Supabase schema migrations** — owned by the data team, out of band.

---

## Blockers (as of 2026-08-27)

| Blocker | Owner | Resolution |
|---|---|---|
| Testnet RPC credentials not in repo (deliberate) | Ops | Fill in `.env` per the table above |
| Live deployed `SignalRegistry` / `EpochScoring` addresses not yet recorded | Ops | Re-run `DeployPipeline.s.sol --broadcast --slow` and append to `docs/MAINNET_READINESS.md` |
| Keeper EOA not funded with testnet ETH | Ops | Faucet (Hyperliquid Discord `#devnet-faucet`) |
| Supabase project not provisioned for keeper reads | Data | Create project, run migrations in `contracts/keeper/supabase/` |
| HyperEVM mainnet launch date | External | TBD; keeper code is ready today |

Once those are filled in, the keeper can be live-fired without any
additional code changes.