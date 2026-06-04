# Deployments

*Canonical record of ZENTORY Protocol contract deployments. Updated alongside every protocol deployment script run.*

> **Status:** testnet only. Mainnet addresses will be published in this file after the external audit + Q4 2026 mainnet gate (see [`STRATEGY.md`](STRATEGY.md) and [`docs/plans/2026-04-25-001-verification-master-plan.md`](docs/plans/2026-04-25-001-verification-master-plan.md)).
>
> **Nothing on this page is a token sale, an investment offer, or a recommendation.** These addresses are testnet artifacts published for verifiability. See [`SECURITY.md`](SECURITY.md) for disclosure, and the [Legal section of the README](README.md#legal) for the full disclaimer.

---

## Networks

| Network | Chain ID | Status | Notes |
|---|---|---|---|
| **HyperEVM testnet** | `998` | **Live — all addresses below** | Testnet only, no real economic value. Used for protocol gates G1-G10. |
| **HyperEVM mainnet** | `999` | Pending audit | Target Q4 2026, addresses TBA |

Block explorer for HyperEVM testnet: [testnet.purrsec.com](https://testnet.purrsec.com/) (or any HyperEVM-compatible block explorer with chain ID 998).

To verify any address below, navigate to `https://testnet.purrsec.com/address/<address>` — the bytecode, transaction history, and verified source can be inspected by anyone.

---

## Token

| Contract | Address | Source |
|---|---|---|
| `ZENT` (ERC-20, 1B fixed supply) | [`0x271cd48c1297caccd810c7b1bcd904f459df7117`](https://testnet.purrsec.com/address/0x271cd48c1297caccd810c7b1bcd904f459df7117) | [`contracts/src/ZENT.sol`](contracts/src/ZENT.sol) |
| `ZENTVesting` | [`0xf7c45f45768d790f388215a44d6e01f6f2568774`](https://testnet.purrsec.com/address/0xf7c45f45768d790f388215a44d6e01f6f2568774) | [`contracts/src/ZENTVesting.sol`](contracts/src/ZENTVesting.sol) |

## Alpha Vaults (ERC-4626)

Each vault is non-custodial: shares are minted to the depositor and redeemable on demand. The underlying asset for each vault on testnet is a `MockERC20` for safe testing; mainnet will use the real wrapped asset.

| Vault | Address | Source | Underlying (testnet mock) |
|---|---|---|---|
| `zBTCVault` | [`0x93669dac07321ff397cf5734ae8364ea24addf45`](https://testnet.purrsec.com/address/0x93669dac07321ff397cf5734ae8364ea24addf45) | [`contracts/src/vaults/zBTCVault.sol`](contracts/src/vaults/zBTCVault.sol) | [`0x80f727af3f7932718feb25fc28818ad103040bd2`](https://testnet.purrsec.com/address/0x80f727af3f7932718feb25fc28818ad103040bd2) |
| `zETHVault` | [`0xbe8a9d22560a1b126554b70aaca2d763b2e70c4e`](https://testnet.purrsec.com/address/0xbe8a9d22560a1b126554b70aaca2d763b2e70c4e) | [`contracts/src/vaults/zETHVault.sol`](contracts/src/vaults/zETHVault.sol) | [`0x08890a5b7d6d157da65c04c19150ff7d124eae40`](https://testnet.purrsec.com/address/0x08890a5b7d6d157da65c04c19150ff7d124eae40) |
| `zSOLVault` | [`0xb62ba9d0a14ac9f9601891179b3da52be71ce052`](https://testnet.purrsec.com/address/0xb62ba9d0a14ac9f9601891179b3da52be71ce052) | [`contracts/src/vaults/zSOLVault.sol`](contracts/src/vaults/zSOLVault.sol) | [`0xe1fe75622bd5d962c72c1d0a621e5fa6656a4371`](https://testnet.purrsec.com/address/0xe1fe75622bd5d962c72c1d0a621e5fa6656a4371) |
| `zXRPVault` | [`0x8b15204d88a9bb155be6798522983a3b5f7d7cb0`](https://testnet.purrsec.com/address/0x8b15204d88a9bb155be6798522983a3b5f7d7cb0) | [`contracts/src/vaults/zXRPVault.sol`](contracts/src/vaults/zXRPVault.sol) | [`0x2b9d5bbd8c5fefc71e985d993c13db2770469972`](https://testnet.purrsec.com/address/0x2b9d5bbd8c5fefc71e985d993c13db2770469972) |
| `zHYPEVault` | _not deployed (post-audit)_ | [`contracts/src/vaults/`](contracts/src/vaults) | _native HYPE_ |

> `BaseVault.sol` is an abstract base contract and is not deployed directly.

## Staking & Bonding

| Contract | Address | Source |
|---|---|---|
| `ZENTStaking` (veZENT) | [`0x93A14D1c60e054038980965CF3CAa50CEB848de9`](https://testnet.purrsec.com/address/0x93A14D1c60e054038980965CF3CAa50CEB848de9) | [`contracts/src/staking/ZENTStaking.sol`](contracts/src/staking/ZENTStaking.sol) |
| `ModelBonding` | [`0x15f6c4bf4000747e0fdd85b33998a36f5bdf5007`](https://testnet.purrsec.com/address/0x15f6c4bf4000747e0fdd85b33998a36f5bdf5007) | [`contracts/src/staking/ModelBonding.sol`](contracts/src/staking/ModelBonding.sol) |

## Fee Distribution

One `FeeDistributor` instance per vault. Each distributes the 15% performance fee per the [§6.4 whitepaper split](docs/whitepaper.md): 50% buyback + 25% treasury + 15% insurance + 10% ops.

| Distributor for | Address | Source |
|---|---|---|
| zBTCVault | [`0x8fb48f84aa69e89e0360e6d2d26c447aa57dcf73`](https://testnet.purrsec.com/address/0x8fb48f84aa69e89e0360e6d2d26c447aa57dcf73) | [`contracts/src/fees/FeeDistributor.sol`](contracts/src/fees/FeeDistributor.sol) |
| zETHVault | [`0x403e8c79653b1cb7a5c0eaa313ec0c7d0cac7e2c`](https://testnet.purrsec.com/address/0x403e8c79653b1cb7a5c0eaa313ec0c7d0cac7e2c) | [`contracts/src/fees/FeeDistributor.sol`](contracts/src/fees/FeeDistributor.sol) |
| zSOLVault | [`0xc69f8a8014b4d17ee2e7457109ff1db33c0c7d7f`](https://testnet.purrsec.com/address/0xc69f8a8014b4d17ee2e7457109ff1db33c0c7d7f) | [`contracts/src/fees/FeeDistributor.sol`](contracts/src/fees/FeeDistributor.sol) |
| zXRPVault | [`0xe990bfbc5c1e5779cb54cb95150edbbb2c2800d0`](https://testnet.purrsec.com/address/0xe990bfbc5c1e5779cb54cb95150edbbb2c2800d0) | [`contracts/src/fees/FeeDistributor.sol`](contracts/src/fees/FeeDistributor.sol) |

## Governance

| Contract | Address | Source |
|---|---|---|
| `Timelock` | [`0x1504ca3c050c88ccca67696d642f634fc381fd03`](https://testnet.purrsec.com/address/0x1504ca3c050c88ccca67696d642f634fc381fd03) | [`contracts/src/governance/Timelock.sol`](contracts/src/governance/Timelock.sol) |
| `Zentroller` | [`0x24f9401284ce16cfe61e40c1f9e3fb37d15b878e`](https://testnet.purrsec.com/address/0x24f9401284ce16cfe61e40c1f9e3fb37d15b878e) | [`contracts/src/governance/Zentroller.sol`](contracts/src/governance/Zentroller.sol) |
| `ZentGovernor` | [`0x21ba1f7c028b1adc78e75ac187b08b1bdd567118`](https://testnet.purrsec.com/address/0x21ba1f7c028b1adc78e75ac187b08b1bdd567118) | [`contracts/src/governance/ZentGovernor.sol`](contracts/src/governance/ZentGovernor.sol) |

## Strategy Execution

| Contract | Address | Source |
|---|---|---|
| `HyperCoreAdapter` | [`0xdad9175f6d2da1709ba3f73711e69022538d21a7`](https://testnet.purrsec.com/address/0xdad9175f6d2da1709ba3f73711e69022538d21a7) | [`contracts/src/keeper/HyperCoreAdapter.sol`](contracts/src/keeper/HyperCoreAdapter.sol) |
| `StrategyExecutor` | [`0xacd862ef134d772b0ca53a97f53ccdd00abc05cf`](https://testnet.purrsec.com/address/0xacd862ef134d772b0ca53a97f53ccdd00abc05cf) | [`contracts/src/keeper/StrategyExecutor.sol`](contracts/src/keeper/StrategyExecutor.sol) |

> `HyperCoreAdapter` and `StrategyExecutor` were re-deployed in Phase 5 of the testnet pipeline to apply hardening fixes from the internal pentest ([`docs/reports/pentest-2026-04-26.md`](docs/reports/pentest-2026-04-26.md)). Older addresses from earlier `DeployPipeline.s.sol` broadcasts are deprecated.

## Signal Arena

| Contract | Address | Source |
|---|---|---|
| `SignalRegistry` (EIP-712 signed signals) | [`0xA71cfdA74fc0BB7bE3f95aB806197286549e82e7`](https://testnet.purrsec.com/address/0xA71cfdA74fc0BB7bE3f95aB806197286549e82e7) | [`contracts/src/signals/SignalRegistry.sol`](contracts/src/signals/SignalRegistry.sol) |
| `EpochScoring` (4-hour epochs) | [`0x659569A6f195698745779E59fef88e3B5Fe0484A`](https://testnet.purrsec.com/address/0x659569A6f195698745779E59fef88e3B5Fe0484A) | [`contracts/src/signals/EpochScoring.sol`](contracts/src/signals/EpochScoring.sol) |
| `SubscriptionVault` (ZENT-paid signal subs) | [`0xb053b9a1A82D57B2BEa7cC4a472924Fb6926933E`](https://testnet.purrsec.com/address/0xb053b9a1A82D57B2BEa7cC4a472924Fb6926933E) | [`contracts/src/signals/SubscriptionVault.sol`](contracts/src/signals/SubscriptionVault.sol) |

## Shadow Stack — SpotVault research vault (testnet only)

Oracle-valued ERC-4626 vault that rebalances long ⇄ flat on signed signals, with a self-contained testnet swap venue so the full loop (deposit → signal rebalance → NAV moves with PnL → redeem) runs end-to-end without a real Hyperliquid spot integration. **None of these ship to mainnet** — production uses real USDC + a CoreWriter spot adapter behind an external audit.

| Contract | Address | Source |
|---|---|---|
| `SpotVault` (BTC long/flat, 20% perf fee) | [`0x504E998B32D165cfd6470a8a0000235550C33cBc`](https://testnet.purrsec.com/address/0x504E998B32D165cfd6470a8a0000235550C33cBc) | [`contracts/src/vaults/SpotVault.sol`](contracts/src/vaults/SpotVault.sol) |
| `ShadowSpotAdapter` (oracle-price fills) | [`0x385Ba1f9A9d74A28974C8F6c03762D03B0e4a00c`](https://testnet.purrsec.com/address/0x385Ba1f9A9d74A28974C8F6c03762D03B0e4a00c) | [`contracts/src/shadow/ShadowSpotAdapter.sol`](contracts/src/shadow/ShadowSpotAdapter.sol) |
| `ShadowPriceOracle` (BTC/USD, push-updated) | [`0x46a7c01424229CB5B2C9FF069e6b0eab07490Fd4`](https://testnet.purrsec.com/address/0x46a7c01424229CB5B2C9FF069e6b0eab07490Fd4) | [`contracts/src/shadow/ShadowPriceOracle.sol`](contracts/src/shadow/ShadowPriceOracle.sol) |
| `ShadowUSDC` (sUSDC cash leg, 6 dec, open mint) | [`0x2DF6A937da1430B4B593fE3EB2C9AB986cC3AF9e`](https://testnet.purrsec.com/address/0x2DF6A937da1430B4B593fE3EB2C9AB986cC3AF9e) | [`contracts/src/shadow/ShadowUSDC.sol`](contracts/src/shadow/ShadowUSDC.sol) |

> Vault asset = the testnet WBTC mock `0x08890A5B7D6D157Da65C04C19150fF7d124eaE40` (8 dec). Deploy via `deploy-shadow-stack.ps1` → `deploy-spot-vault.ps1` — **the deploy self-finalizes** (grants `VAULT_ROLE` to the vault, funds both adapter reserve legs with 50M sUSDC + 1,000 WBTC, seeds a 0.01 WBTC first deposit). `finalize-spot-vault.ps1` is an **idempotent reserve top-up / repair** tool: re-run it to refill the adapter legs as rebalances consume them (a no-op on a fresh deploy). The oracle must be kept fresh by `oracle_pusher.py` (≤ `MAX_ORACLE_STALENESS`, 24h on testnet) or deposits/NAV reads revert on staleness. **Verified live 2026-06-02:** `getNavPerShare()` = 1.00, keeper holds `KEEPER_ROLE`, `rebalanceTo()` executes (oracle-priced swap loop works).

---

## How to verify these are the canonical deployments

The source of truth is the Foundry broadcast log, which is checked into this repo. To regenerate this table yourself:

```bash
cd contracts
# inspect the latest deployment broadcasts (per script, per chain id)
ls broadcast/DeployPipeline.s.sol/998/
ls broadcast/Phase5Only.s.sol/998/
ls broadcast/ResumeDeployment.s.sol/998/
ls broadcast/deploy_signal_network.s.sol/998/
```

Each `run-*.json` contains the full transaction log, including every `CREATE` / `CREATE2` with the deployed contract name and address. The broadcast logs are committed alongside the source, so the chain of custody is auditable from this repo to the chain.

For independent verification:

1. Pull the contract address from the table above.
2. Look it up on a HyperEVM testnet block explorer (e.g. [testnet.purrsec.com](https://testnet.purrsec.com/)).
3. Compare the on-chain bytecode hash to the one produced by `forge inspect <Contract> bytecode` in this repo.
4. The bytecode hashes must match. If they do not, please open an issue.

---

## Update policy

This file is updated whenever:

- A new deployment script is run successfully against testnet (`forge script ... --broadcast`).
- A contract is re-deployed after a hardening fix (with the old address marked deprecated and a link to the pentest finding).
- The mainnet deployment goes live (a new "HyperEVM mainnet" section is added).

The intent is that this page can always be diffed against the latest `contracts/broadcast/**/run-latest.json` and the two stay in sync.

---

*If anything on this page is out of date with the broadcast logs, that is a docs bug — please open an issue or email `security@zentorylabs.com`.*
