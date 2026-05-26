# Multisig migration plan (M3)

How to move admin control of the ZENTORY protocol from a single EOA
(currently `0xe56E7B7243C5820E1d59319937413C1462Ed5B5c` on testnet) to a
multisig that survives compromise of any one signer.

**This must be done before mainnet launch.** Holding a $XM protocol on a
single EOA is malpractice — one phishing email = the whole protocol gone.

---

## TL;DR — what we're going to do

1. Stand up a **Safe (Gnosis Safe) Smart Account** with **3-of-5** threshold
2. Test the Safe on testnet first by transferring `DEFAULT_ADMIN_ROLE` on
   `EpochScoring` and `Timelock.PROPOSER_ROLE` to the Safe
3. Verify a routine governance action (e.g. `setEpochReward(...)`) works
   end-to-end through the multisig
4. Repeat the exact same flow on mainnet at deploy time — every contract
   that has any privileged role starts with the Safe as the holder

## Why 3-of-5 (not 2-of-3 or 4-of-7)

| Threshold | Pros | Cons |
|---|---|---|
| 2-of-3 | Cheapest, fastest sigs | Single compromised signer + one careless click = quorum lost |
| **3-of-5** | Survives 2 compromises, still fast in practice | Slightly more coordination |
| 4-of-7 | More resilient | 4 sigs is slow when you need fast response |

**3-of-5 is the DeFi standard for protocols up to ~$100M TVL.** Aave, Uniswap,
Lido all started here. Move to 4-of-7 or council-elected signers later when
TVL justifies the extra coordination cost.

## Who should be signers

Pick **5 people you'd trust with the protocol**. They don't need to be
ZENTORY employees but should be:

- Reachable on short notice (you need 3 sigs within 24h for emergencies)
- Operationally competent with hardware wallets (Ledger or Trezor)
- Geographically distributed (don't put all 5 in the same country/timezone)
- Have at least one non-team member (signals decentralization to auditors)

**Suggested composition:**

| Slot | Profile | Why |
|---|---|---|
| 1 | Edge (founder) | Operational continuity |
| 2 | Co-founder / CTO | Operational continuity |
| 3 | Trusted technical advisor (external) | Demonstrates non-team checks |
| 4 | Trusted business advisor (external) | Independent perspective on governance proposals |
| 5 | Cold signer (rarely used, backup) | Insurance against losing 4 of 5 in a single event |

⚠️ **Each signer must use a hardware wallet** (Ledger Nano S Plus / X / Stax
or Trezor Safe 3). Browser MetaMask is not acceptable for multisig sigs —
phishing risk is too high.

## Where Safe is supported on HyperEVM

As of May 2026, **Safe does not have official deployments on HyperEVM**.
Options:

### Option A — Deploy Safe contracts ourselves (recommended)

Safe is open-source (GPL-3.0). Deploy the canonical Safe contracts to
HyperEVM mainnet using the same addresses they use on Ethereum mainnet
via CREATE2. Pros:

- Same auditable bytecode as the Safe everyone else uses
- Hot-path tools work (`safe-cli`, Safe Transaction Service when
  HyperEVM adds support)
- Can use a self-hosted Safe UI fork pointing at HyperEVM RPC

Cons: we maintain the deployment + the UI fork.

Approach:
1. Deploy `SafeProxyFactory` + `GnosisSafeL2` singleton via official deploy script
2. Stand up a self-hosted Safe Transaction Service (Postgres + Redis + Django) on Railway
3. Fork `safe-wallet-web` and point it at our backend + HyperEVM RPC
4. Document the procedure for signers so they can verify the singleton bytecode

### Option B — Use Squads (if Squads ships HyperEVM by mainnet)

Squads is the multisig of choice on Solana but they've been expanding to
EVM chains. Worth checking at deploy time. Less battle-tested than Safe
but native EVM support would save us deploy effort.

### Option C — Use a simple in-house multisig (NOT recommended)

OpenZeppelin's `Governor` or a custom multisig contract. **Don't do this.**
Safe's threat model has been audited 30+ times; ours hasn't. The marginal
saving in deploy effort is not worth the audit liability.

## Migration sequence on testnet (do this FIRST as a rehearsal)

1. Deploy Safe contracts to HyperEVM testnet (chain 998)
2. Each signer registers their hardware wallet address with the Safe
3. Verify the Safe address responds to `getOwners()` returning the 5 addresses
4. Verify `getThreshold()` returns `3`
5. From the current admin (deployer), call:
   ```solidity
   EpochScoring(0xB6b206...).grantRole(DEFAULT_ADMIN_ROLE, $SAFE_ADDRESS);
   EpochScoring(0xB6b206...).renounceRole(DEFAULT_ADMIN_ROLE, $DEPLOYER);
   Timelock(0x1504cA3C...).grantRole(PROPOSER_ROLE, $SAFE_ADDRESS);
   Timelock(0x1504cA3C...).grantRole(EXECUTOR_ROLE, $SAFE_ADDRESS);
   Timelock(0x1504cA3C...).revokeRole(PROPOSER_ROLE, $DEPLOYER);
   ```
6. Now propose a no-op governance action (e.g. `setEpochReward` to the
   same value). All 3 signers approve. Verify it executes through the
   Timelock after the 48h delay.
7. **If everything works on testnet for 1 full week, repeat on mainnet.**

## Migration sequence on mainnet (after audit passes)

1. Deploy contracts with the Safe address as the constructor arg for every
   `_admin` / `_owner` / `_governor` parameter — never the EOA
2. The deployer EOA only holds gas for the deploy itself; it gets zero
   privileges
3. After all contracts deploy, verify on the explorer that every privileged
   role is held by the Safe and not by any EOA
4. **Renounce / burn the deployer key** — `cast wallet new` style, send
   remaining ETH to the Safe, then never use that key again

## Why a Timelock is still required even with a multisig

A 3-of-5 can still be socially engineered, malicious-insider'd, or compromised
all at once (state actor scenario). The 48h Timelock means:

- Even with all 5 signers compromised, depositors have 48 hours to withdraw
  before any admin change takes effect
- Auditors and the bug bounty community have 48 hours to spot a malicious proposal

**Timelock + Multisig + Bug bounty is the defense-in-depth stack.** Skipping
any one of them is the protocol equivalent of dropping antibiotics halfway.

## Costs

| Item | Cost |
|---|---|
| Safe contract deploy on HyperEVM (one-time) | ~$5–20 in gas |
| Self-hosted Safe Transaction Service on Railway | $5–10/mo |
| Self-hosted Safe UI fork (Vercel) | $0 (free tier) |
| 5x hardware wallets if signers don't have one | $5x ~$80 = $400 |
| Signer time to verify + sign each proposal | non-trivial, plan for it |

**Total cash cost: ~$500 + $10/mo.** The expensive part is operational
discipline.

## What I need from you to start

1. **List of 5 signer addresses** — hardware wallets only. Send me the
   addresses (NOT the private keys) and which slot each represents (1–5
   per the table above).
2. **Confirm Safe deploy approach** — Option A (deploy Safe ourselves) or
   wait for Option B (Squads) status check at audit kickoff.
3. **Timeline** — testnet rehearsal needs to happen **before** mainnet,
   ideally during the audit window. Audit firms appreciate seeing the
   multisig path proven on testnet first.

---

*Last updated: 2026-05-25. Tracked as task #95 (M3).*
