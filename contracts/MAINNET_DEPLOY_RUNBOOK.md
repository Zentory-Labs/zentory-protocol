# Mainnet deploy runbook (M12)

The exact order + commands to deploy ZENTORY to HyperEVM **mainnet**, plus the
post-deploy safety gates. Most deploy scripts already exist and are hardened; the
mainnet-specific risks are (1) **Safe-as-admin on every contract** (no EOA holds a
privileged role), (2) **real underlying tokens** (no mock ERC20s), and (3)
**contract verification**. This runbook closes those.

> ⚠️ Do NOT run until the hard gates are met: **M2** external audit passed +
> remediated, **M4** legal sign-off, **M3** Gnosis Safe live with the 5 signers,
> and the real HyperEVM-mainnet underlying token addresses (WBTC/WETH/WSOL/WXRP or
> their mainnet equivalents) + sUSDC are confirmed.

## 0. Inputs to gather first (Edge / external)

| Input | Source |
|---|---|
| `SAFE` — Gnosis Safe address (3-of-5) | M3 (deploy the Safe on HyperEVM first; see MULTISIG_MIGRATION_PLAN.md) |
| Real underlying token addresses | HyperEVM mainnet (WBTC/WETH/WSOL/WXRP, sUSDC) |
| `EXPECTED_CHAIN_ID` | HyperEVM mainnet chain id (NOT 998) |
| Audit commit hash | the frozen `audit/...` branch that was reviewed |
| Funding amounts | TGE_STRUCTURE.md (liquidity, insurance, airdrop totals) |

## 1. Parameterization fixes required before mainnet

The following are testnet-pinned and MUST be parameterized (tracked here so they
aren't forgotten):

- `MigrateToMultisig.s.sol` — `CHAIN_ID = 998` hardcoded + pins the testnet hot
  wallet. Replace the chain literal with `requireChainFromEnv()` and read the
  hot wallet from env, OR cut a mainnet copy.
- `DeployPipeline.s.sol` — deploys **mock ERC20s** and grants roles to the
  **deployer**. For mainnet: take real underlying addresses via env, pass `SAFE`
  as every `_admin/_owner/_governor` constructor arg, and set a **dedicated
  `INSURANCE_FUND`** (deploy `DeployInsuranceFund.s.sol` first — do NOT default to
  treasury).
- All new scripts (`DeployInsuranceFund`, `DeployMerkleDistributor`,
  `RedeploySignalStack` pattern) already use `requireChainFromEnv()` — good.

## 2. Deploy order

```bash
export EXPECTED_CHAIN_ID=<mainnet-id>
export PRIVATE_KEY=<deployer>          # funds gas only; owns nothing at the end
export RPC=<mainnet-rpc>

# a. Token + vesting + treasury + buyback (if not already live)
# b. Staking + fees + model bonding   (DeployStaking.s.sol — GOVERNOR=$SAFE)
# c. Insurance fund                    (DeployInsuranceFund.s.sol — INSURANCE_GOVERNANCE=$SAFE)
# d. Vaults                            (MainnetDeployVaults.s.sol — real underlyings, admin=$SAFE)
# e. Signal stack                      (RedeploySignalStack pattern — keeper + $SAFE admin)
# f. Airdrop                           (DeployMerkleDistributor.s.sol — AIRDROP_ADMIN=$SAFE)
```

Every script that takes an admin/owner/governor MUST receive `$SAFE`, never the
deployer EOA. The vault seeding uses the deposit path only (MainnetDeployVaults
already enforces the share/asset invariant — prevents a repeat of the zSOL
100B over-seed).

## 3. Contract verification (no automation exists today — do this)

For each deployed contract, on the HyperEVM explorer (purrsec / sourcify):

```bash
forge verify-contract <ADDRESS> <src/Path.sol>:<Name> \
  --chain-id $EXPECTED_CHAIN_ID \
  --verifier sourcify --verifier-url <hyperevm-sourcify-url> \
  --constructor-args $(cast abi-encode "constructor(<types>)" <args>)
```

Capture each verification URL in `DEPLOYMENTS.md`.

## 4. Post-deploy safety gate — NO EOA holds a privileged role

After migration, assert every privileged-role holder is the Safe (a contract),
not an EOA. For each contract + role:

```bash
# DEFAULT_ADMIN_ROLE = 0x00..00
cast call <CONTRACT> "hasRole(bytes32,address)(bool)" 0x0000000000000000000000000000000000000000000000000000000000000000 $SAFE --rpc-url $RPC   # want true
cast code $SAFE --rpc-url $RPC | head -c 4   # want non-empty (Safe is a contract)
# And confirm the deployer holds NOTHING:
cast call <CONTRACT> "hasRole(bytes32,address)(bool)" 0x00..00 <DEPLOYER> --rpc-url $RPC   # want false
```

Roles to check per `MigrateToMultisig.s.sol._buildRegistry`: `DEFAULT_ADMIN_ROLE`,
`GOVERNOR_ROLE`, `RISK_COUNCIL_ROLE`, `GUARDIAN_ROLE` (leave `EPOCH_SETTLER`
[keeper] and `SCORING_ORACLE` [EpochScoring contract] as-is — intentional).

## 5. Post-deploy wiring checklist

- [ ] `INSURANCE_FUND` points at the dedicated InsuranceFund (not treasury); seed it.
- [ ] FeeDistributor insurance share routes to the InsuranceFund.
- [ ] MerkleDistributor funded with exactly the airdrop total; proofs published to `/claim`.
- [ ] dApp `lib/contracts.ts`, engine env, keeper env, `DEPLOYMENTS.md` repointed to mainnet addresses.
- [ ] Immunefi scope (IMMUNEFI_SETUP.md) assets table filled with mainnet addresses.
- [ ] Production RPC (`RPC_FALLBACK_URLS`) configured (see M6).
- [ ] All deployer-EOA roles revoked (§4 passes).
```

## 6. Spot stack (v1 canonical vault) — added 2026-06 re-scan

```bash
# g. NAV oracle    (DeployMedianOracle.s.sol — ORACLE_UPDATERS=3+ independent keys;
#                   script REQUIRES ORACLE_MIN_QUORUM >= 3 on chain 999)
# h. Spot stack    (DeploySpotStack.s.sol — ROUTER=real HyperSwap V3 SwapRouter,
#                   FEE_TIER=deepest WBTC/USDC pool, ORACLE=<g>, STRATEGY_EXECUTOR=<live>)
```

Mandatory after g+h (extends the §4 no-EOA gate to the new surface):
- [ ] `StrategyExecutor.setAuthorizedSigner(<GP engine signer>)` — until this runs, NO
      signals/rebalances are accepted (safe default), but it MUST be the engine key,
      never the deployer.
- [ ] Per-vault limits SET (skip = unlimited): `setMaxPositionSize`, `setMaxLeverageBPS`
      for every vault the executor can drive.
- [ ] MedianOracle: >= 3 independent updaters live and reporting on the keeper cadence;
      `minQuorum >= 3`; admin transferred to the Safe. (Rotation: addUpdater BEFORE
      removeUpdater — the contract enforces it.)
- [ ] Adapter + vault + oracle `DEFAULT_ADMIN_ROLE` → Safe; deployer renounced (§4 check
      re-run including MedianOracle + HyperSwapRouterAdapter + SpotVault).
- [ ] Engine env: `EXPECTED_CHAIN_ID=999` set on every writer (oracle_pusher,
      signal_submitter, executor) — they abort on mismatch.
- [ ] Key policy applied: `docs/KEY_MANAGEMENT.md` (inventory, rotation, compromise
      response) — authorizedSigner on KMS/hardware for mainnet.
- [ ] Seed each SpotVault with a first deposit (inflation-attack invariant) before
      opening deposits.
