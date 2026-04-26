---
date: 2026-04-26
topic: wallet-integration-strategy
---

# Wallet Integration Strategy for Zentory Protocol

## Problem Frame

Zentory Protocol is an AI-powered algorithmic trading vault system on HyperEVM, supporting multiple asset vaults (zBTC, zETH, zXRP, zSOL) with ZENT staking, veZENT governance, and keeper-based strategy execution. The current wallet integration is directly embedded in page components with no abstraction layer, limited to a single injected connector and Coinbase Wallet — leaving three strategic gaps:

1. **Onboarding gap**: Mainstream users without existing crypto wallets have no path to access the protocol. The current wallet-required model excludes the largest potential user base.
2. **Trust gap**: No transaction simulation, no audit transparency, no gasless UX — all features that DeFi power users and institutional participants expect as baseline in 2026.
3. **Extensibility gap**: A single-chain, single-connector implementation has no foundation for multi-wallet, multi-chain, or smart-account expansion without significant rework.

The wallet integration strategy must serve three distinct user segments simultaneously: mainstream users needing frictionless onboarding, crypto-native DeFi power users needing transparency and depth, and institutional users needing Safe{Wallet} multisig security. These segments are not mutually exclusive — the same product must support all three without bifurcation.

---

## Actors

- A1. **Mainstream user**: Has no existing crypto wallet. Needs email or social login, wallet created automatically, gasless first transactions, and clear risk explanations. Primary outcome: participate in DeFi without crypto expertise.
- A2. **Crypto-native DeFi power user**: Has Rabby, Phantom, or MetaMask. Wants transaction simulation, batch approvals, chain switching, and full control. Primary outcome: execute strategies efficiently with maximum transparency.
- A3. **Institutional user**: Uses Safe{Wallet} for organizational treasury or governance participation. Needs multisig, timelock, and role-segregated permissions. Primary outcome: participate with institutional-grade security and auditability.
- A4. **Keeper/operator**: Authorized wallet for `StrategyExecutor` actions. Executes vault rebalancing and strategy calls via HyperCoreAdapter. Must be clearly distinguished from governance wallets in the UI.
- A5. **Agent/system**: Programmatic access for automated strategies, 봅 intelligence, or third-party integrations via WalletConnect session keys.

---

## Key Flows

- F1. **Mainstream onboarding**
  - **Trigger:** User visits protocol without a connected wallet
  - **Actors:** A1 (user), A1 (embedded wallet)
  - **Steps:**
    1. Landing page shows "Sign in with email" and "Connect wallet" side by side
    2. User enters email → embedded MPC wallet created automatically via Privy or Dynamic
    3. Wallet address shown as "Your wallet" with a brief explanation
    4. First deposit flow: user selects vault → amount → gas sponsorship confirmed → transaction submitted → success state
  - **Outcome:** User has deposited into a vault without installing any wallet or owning gas token
  - **Covered by:** R1, R4, R7, R10

- F2. **Power user multi-wallet connection**
  - **Trigger:** User clicks "Connect wallet" with existing Rabby/MetaMask/Phantom
  - **Actors:** A2 (user)
  - **Steps:**
    1. Wallet selector modal shows supported wallets with logos (MetaMask, Rabby, Phantom, Trust, WalletConnect)
    2. User selects wallet → wallet-specific connection flow (extension popup or deep link)
    3. On connect: address shown with ENS resolution where available, full address on hover
    4. Chain selector defaults to HyperEVM, shows supported chain chips
    5. Dashboard loads with vault balances, ZENT stake position, governance votes
  - **Outcome:** Connected wallet state persists across page reloads; user can switch between multiple connected wallets
  - **Covered by:** R2, R3, R5, R8, R11

- F3. **Transaction signing with simulation**
  - **Trigger:** User initiates a vault deposit, ZENT stake, or governance vote
  - **Actors:** A2 (user)
  - **Steps:**
    1. User fills action form (amount, vault selection) and clicks "Confirm"
    2. Pre-sign panel appears showing: tokens out, gas estimate, destination contract, risk summary, approval scope
    3. User reviews simulation output → clicks "Sign" → wallet popup appears
    4. On wallet sign confirm: transaction submitted → pending state with block explorer link
    5. On receipt: success state with position update; on failure: error state with specific reason
  - **Outcome:** User sees exactly what the transaction will do before signing; no blind approvals
  - **Covered by:** R6, R9, R12

- F4. **Keeper wallet session authorization**
  - **Trigger:** Keeper operator connects wallet for the first time
  - **Actors:** A4 (keeper), A4 (authorized wallet)
  - **Steps:**
    1. Keeper connects wallet → protocol detects `STRATEGY_EXECUTOR_ROLE` authorization
    2. UI surfaces distinct "Keeper" badge and role label next to the connected address
    3. Keeper actions (rebalance, harvest, parameter update) are visually distinguished from governance actions
    4. Keeper transactions show `StrategyExecutor` contract address, not user-facing vault addresses
  - **Outcome:** Keeper and governance wallet roles are unambiguously distinguished; no risk of operator confusion with user funds
  - **Covered by:** R13

---

## Requirements

**Wallet connectivity**

- R1. The protocol must support two parallel onboarding paths: (a) external wallet connection for users who already have one, and (b) embedded wallet creation for users who do not. Both paths must reach the same vault interaction functionality.
- R2. Supported external wallets must include MetaMask, Rabby (DeFi power users), Phantom (Solana-exposed users), Trust Wallet, Ledger, and WalletConnect v2 (covering 700+ additional wallets). Wallet logos and names must be displayed using EIP-6963 detection where available.
- R3. The wallet connection modal must surface trust signals at the moment of connection: audit status ("Audited by Certik + Trail of Bits"), protocol TVL, and a one-line risk statement. These appear inside the modal, not in documentation or footers.
- R4. RainbowKit (or ConnectKit) must be the wallet connection UI layer. It must be configured to support HyperEVM as a custom chain, with chain-aware address resolution and block explorer links.
- R5. Multiple wallets must be supported simultaneously. A user who connects wallet A, then connects wallet B, must have both connections retained. The UI must show a wallet switcher when multiple wallets are connected, with a clear indicator of which wallet is currently signing transactions.

**Smart account and gasless UX**

- R6. The protocol must implement ERC-4337 smart account infrastructure via ZeroDev Kernel and Biconomy Nexus, enabling gasless transactions for users who opt into smart account mode. Gas sponsorship must be available for first-transaction users without requiring them to hold the native gas token.
- R7. EIP-7702 delegation must be supported, allowing existing MetaMask EOAs to temporarily gain smart account features (batching, gas sponsorship) without migrating to a new wallet address. This is the primary mechanism for onboarding existing MetaMask users into gasless UX.
- R8. Safe{Wallet} integration must be supported as an optional smart account layer. Users with Safe wallets must be able to interact with the protocol using their Safe's multisig security model. Safe modules must be compatible with the ERC-7579 plugin standard used by ZeroDev and Biconomy.
- R9. Transaction simulation must be displayed before every write transaction (deposit, withdrawal, stake, governance vote). Simulation must show: token amounts changed, destination address, gas estimate, and any approval scope with expiry. Rabby's simulation output is the reference standard.

**Multi-chain**

- R10. Chain support must be structured for extensibility. The address resolution layer must be chain-aware from day one (even if only HyperEVM is active at launch). The chain configuration must support adding HyperEVM mainnet, Solana via HyperEVM bridge, and EVM L2s (Base, Arbitrum, Polygon) without re-architecting the wallet layer.
- R11. Chain switching must show a distinct error state when the user is on an unsupported chain. The error must be non-dismissable until the user selects a supported chain. Error codes 4902, 4001, and -32002 must be handled with specific recovery actions documented in code.

**Session and identity**

- R12. Wallet connection state must persist across page reloads via wagmi's localStorage persister. The reconnection flow must show a "reconnecting" state rather than silently dropping the connection.
- R13. Keeper wallet roles must be visually distinguished from governance wallets throughout the UI. A "Keeper" badge and role label must appear in the connected wallet display and all transaction confirmation panels. Keeper transactions must show the `StrategyExecutor` contract address, not user-facing vault addresses.

**Trust and transparency**

- R14. Full wallet addresses must be visible on hover or expand, even when ENS names are resolved. Truncated addresses must never be the only address display in any security-relevant context.
- R15. Audit report links must appear at the point of first deposit or stake action, not in footers. Format: "[Protocol] has been audited by [Firm] ([Report] • [Date])". Audit information must be specific — firm names and dates, not generic "audited" claims.

---

## Acceptance Examples

- AE1. **Covers R1, R4.** Given a user with no crypto wallet visits `/stake`, when they enter their email and click "Continue", then a wallet address is created and shown as "Your wallet" without requiring any wallet extension or seed phrase. The user can then deposit ZENT into staking immediately.

- AE2. **Covers R2, R5.** Given a user connects MetaMask, then connects Rabby, when they return to the site after closing the browser, both wallets appear in the wallet switcher. When they select Rabby, transactions are signed with the Rabby address; when they select MetaMask, transactions use the MetaMask address.

- AE3. **Covers R6, R7.** Given a MetaMask user on HyperEVM with no gas token balance, when they attempt to deposit into a vault, the gas is sponsored by the protocol's paymaster and the transaction succeeds without the user needing to acquire the native gas token.

- AE4. **Covers R9.** Given a user initiates a zBTC vault deposit, when they reach the confirmation step, a simulation panel shows: "You will send 0.5 BTC → receive 0.5 zBTC (estimated), pay ~$2.40 gas, and approve zBTCVault to spend your BTC (this approval can be revoked anytime)." The user sees this before the wallet popup appears.

- AE5. **Covers R13.** Given a keeper wallet is connected, when the keeper initiates a rebalance, the transaction confirmation panel shows a "Keeper" badge, the `StrategyExecutor` contract address, and the rebalance parameters — visually distinct from a regular user deposit confirmation.

---

## Success Criteria

- Mainstream users can complete a first vault deposit without installing a wallet, owning gas, or seeing a seed phrase.
- Crypto-native users can connect Rabby, Phantom, MetaMask, Trust, Ledger, or any WalletConnect-compatible wallet within two clicks.
- Every write transaction shows a simulation preview before the wallet signing popup appears.
- A user with Safe{Wallet} can interact with the protocol using their multisig without any special configuration.
- Chain switching shows specific, actionable error messages for each error code; no raw error codes are shown to users.
- Wallet connection state reconnects automatically on page reload with a visible "reconnecting" state.
- Keeper and governance wallet roles are visually distinct throughout the UI with explicit role labels.

---

## Scope Boundaries

### Deferred for later

- Bitcoin-native wallet support (Xverse, Leather) — depends on Bitcoin bridge or wrapped asset integration beyond initial HyperEVM scope
- Hardware wallet derivation path support beyond Ledger — Trezor and other devices deferred until demand is confirmed
- WalletConnect Pay integration (stablecoin checkout, fiat onramp) — downstream of wallet connectivity; depends on payment infrastructure decision
- Cross-chain vault interactions (deposit BTC, mint on HyperEVM) — requires bridge infrastructure decision
- AI agent wallet session keys — A5 use case; depends on keeper/operator system hardening first
- Programmatic EOA access for third-party bots — depends on API key / session key infrastructure

### Outside this product's identity

- A centralized exchange or brokerage — Zentory is a non-custodial DeFi protocol; the wallet strategy supports self-custody, not exchange-style order matching
- Privacy-preserving transactions (Tornado Cash-style) — incompatible with DeFi lending's compliance requirements and auditability expectations
- A mobile-only or wallet-less native application — the protocol is web-first; mobile wallets connect via WalletConnect deep links, not a custom mobile app

---

## Key Decisions

- **Smart account backbone is multi-provider, not single-provider**: ZeroDev Kernel and Biconomy Nexus are used for gasless UX and session keys. Safe{Wallet} is used for institutional multisig. The protocol supports all three — the user's wallet choice determines which applies, not the protocol.
- **Embedded wallet for mainstream onboarding via Privy**: Privy (Stripe-acquired) provides email/social login with embedded MPC wallets. It is the recommended integration for users who do not arrive with an existing wallet. This is not a custom auth system — it uses Privy's SDK and is consistent with industry-standard DeFi onboarding.
- **WalletConnect v2 as the connectivity protocol, not a specific wallet**: WalletConnect v2 covers 700+ wallets including Trust, OKX, Bitget, and emerging wallets. Supporting WalletConnect v2 means supporting the entire WalletConnect ecosystem without per-wallet integration work.
- **Transaction simulation via Alchemy or Tenderly (or Rabby SDK)**: Simulation is a trust-critical feature, not optional. The implementation uses an existing simulation service rather than building custom simulation infrastructure.
- **wagmi/viem as the contract interaction base with an abstraction layer on top**: Page components must not call wagmi hooks directly. A `lib/wallet/` and `lib/contracts/` abstraction layer is the structural prerequisite for all other requirements.
- **HyperEVM is the primary chain; multi-chain is structured but not yet active**: The architecture supports chain-aware address resolution from day one, but only HyperEVM testnet (chain ID 998) is active at v1 launch. Chain expansion is a planned phase, not an architectural change.

---

## Dependencies / Assumptions

- D1. HyperEVM mainnet launch timeline is assumed to be within the implementation window; chain IDs and RPC endpoints will be updated at mainnet deployment.
- D2. The Privy SDK pricing (free to 499 MAU, then $500/month) is acceptable for the anticipated user scale at v1 launch.
- D3. ZeroDev Kernel and Biconomy Nexus ERC-7579 compatibility is assumed to be stable; the ERC-7579 standard is sufficiently mature as of 2026 Q1 for production use.
- D4. WalletConnect v2 project ID is available from cloud.walletconnect.com at no cost; registration is a one-time setup step.
- D5. Simulation infrastructure (Alchemy or Tenderly) has a free tier sufficient for v1; costs at scale will be evaluated in the phase 2 planning.
- D6. Supabase auth session is already configured for the frontend; EIP-4361 "Sign in with Ethereum" wallet sessions are a future-phase enhancement, not a v1 dependency.

---

## Outstanding Questions

### Resolve Before Planning

- **[Affects R1, R4][User decision]** Privy vs. Dynamic for embedded wallet: Both are viable. Privy has deeper DeFi adoption; Dynamic has Fireblocks enterprise backing and broader non-EVM chain support. Which is preferred, or should both be supported?
- **[Affects R6, R7][User decision]** Protocol-funded gas sponsorship (paymaster): Who pays for gas on first transactions — the protocol treasury, a specific sponsor, or the user after their first free transaction? This affects economics and UX.

### Deferred to Planning

- **[Affects R9][Technical]** Which simulation provider (Alchemy, Tenderly, or Rabby SDK) to use — depends on pricing research and API capability comparison at planning time.
- **[Affects R10][Technical]** HyperEVM mainnet chain ID and RPC endpoints — confirmed at DEPLOYMENT.md but needs formal integration into the chain config.
- **[Affects R2][Needs research]** WalletConnect v2 project ID registration — straightforward but must be done before Phase 1 begins.
- **[Affects R13][Technical]** Safe{Wallet} module authorization pattern for keeper role — need to verify `STRATEGY_EXECUTOR_ROLE` assignment works with Safe's module system vs. direct role assignment.
- **[Affects R7][Needs research]** EIP-7702 support timeline — depends on whether the Ethereum Pectra hard fork has shipped and MetaMask's EIP-7702 support status at implementation time.

---

## Next Steps

-> /ce-plan with this document as the primary input. The plan should use the three-phase structure implied by the requirements (Phase 1: foundation and connectivity, Phase 2: smart accounts and gasless, Phase 3: institutional and simulation hardening) as its implementation units.
