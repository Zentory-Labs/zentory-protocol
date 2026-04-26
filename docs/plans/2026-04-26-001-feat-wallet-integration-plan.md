---
title: "feat: Wallet Integration Strategy"
type: feat
status: active
date: 2026-04-26
origin: docs/brainstorms/wallet-integration-strategy.md
deepened: 2026-04-26
---

# Wallet Integration Strategy

## Overview

Implement a layered, multi-wallet, multi-account-abstraction wallet integration for the Zentory Protocol on HyperEVM. The work is structured in three phases: (1) architectural foundation and connectivity, (2) smart accounts and gasless UX, (3) institutional hardening and trust-layer features. This plan supersedes the current direct coupling of wagmi/viem in page components by extracting a proper wallet abstraction layer.

---

## Problem Frame

The current wallet integration has three gaps identified in the origin requirements:

1. **Onboarding gap** — no embedded wallet, no social login; users without existing crypto wallets have no path to access the protocol
2. **Trust gap** — no transaction simulation, no audit transparency, no gasless UX; below 2026 DeFi expectations for power and institutional users
3. **Extensibility gap** — wagmi/viem called directly in page components; adding wallets, smart accounts, or multi-chain requires architectural rework

The wallet layer must serve three audiences simultaneously: mainstream users (email/social login + embedded wallet + gasless), crypto-native power users (Rabby, Phantom, WalletConnect + simulation + batch approvals), and institutional users (Safe{Wallet} multisig + timelock). These are not mutually exclusive — the same product supports all three.

---

## Requirements Trace

This plan advances the following requirements from the origin document. Each implementation unit traces backward to the requirements it satisfies.

- R1. Two parallel onboarding paths: external wallet connection and embedded wallet creation
- R2. Supported wallets: MetaMask, Rabby, Phantom, Trust, Ledger, WalletConnect v2 (700+ wallets)
- R3. Trust signals in wallet modal: audit status, TVL, risk statement
- R4. RainbowKit as the connection UI layer; HyperEVM as custom chain
- R5. Multiple simultaneous wallet connections with wallet switcher
- R6. ERC-4337 smart account infrastructure: ZeroDev Kernel + Biconomy Nexus, gasless transactions
- R7. EIP-7702 support for MetaMask EOA delegation (implementation-time verification of fork status required)
- R8. Safe{Wallet} integration for institutional multisig
- R9. Transaction simulation before every write transaction
- R10. Chain-extensible address resolution (active only on HyperEVM; architecture supports future chains)
- R11. Chain switching with specific error handling for codes 4902, 4001, -32002
- R12. Wallet connection state persists across page reloads via wagmi persister
- R13. Keeper wallet role visually distinguished from governance wallet throughout UI
- R14. Full address visible on hover even when ENS name is shown
- R15. Audit report links at point of first deposit/stake action (not footer-only)

**Origin actors:** A1 (mainstream user), A2 (DeFi power user), A3 (institutional user), A4 (keeper/operator), A5 (agent/system)
**Origin flows:** F1 (mainstream onboarding), F2 (power user multi-wallet connect), F3 (transaction signing with simulation), F4 (keeper authorization)
**Origin acceptance examples:** AE1, AE2, AE3, AE4, AE5

---

## Scope Boundaries

### Deferred for later

- Bitcoin-native wallet support (Xverse, Leather) — depends on Bitcoin bridge or wrapped asset integration beyond initial HyperEVM scope
- Hardware wallet beyond Ledger — Trezor and other devices deferred until demand is confirmed
- WalletConnect Pay integration (stablecoin checkout, fiat onramp) — downstream of wallet connectivity
- Cross-chain vault interactions — requires bridge infrastructure decision
- AI agent wallet session keys — A5 use case; depends on keeper/operator system hardening first
- Programmatic EOA access for third-party bots — depends on API key infrastructure

### Outside this product's identity

- Centralized exchange or brokerage model — Zentory is non-custodial DeFi; wallet strategy supports self-custody only
- Privacy-preserving transactions — incompatible with DeFi lending's auditability requirements
- Mobile-native application — web-first; mobile wallets connect via WalletConnect deep links

---

## Context & Research

### Relevant Code and Patterns

- `frontend/components/Providers.tsx` — wagmi config with `injected()` + `coinbaseWallet()` connectors; chain definition lives here
- `frontend/lib/contracts.ts` — all ABIs and contract addresses; `HYPEREVM_TESTNET` custom chain definition; `vaultMeta` helper; **no typed contract wrappers**
- `frontend/components/Nav.tsx` — inline wallet connect/disconnect; iterates `connectors` array; uses `useAccount`, `useConnect`, `useDisconnect` directly
- `frontend/app/stake/page.tsx` — two-step approve → waitForTransactionReceipt → stake pattern; manual tx hash tracking; `as any` ABI casting throughout
- `frontend/app/govern/page.tsx` — fire-and-forget `writeContract` for `castVote`; governor param reads
- `packages/zentory-ui/` — purely styling (tokens, tailwind preset); **zero wallet logic**

### Existing Conventions to Preserve

- `HYPEREVM_TESTNET` chain definition remains in `lib/contracts.ts`
- ABIs as `as const` tuples — compatible with viem's strict typing
- Two-step write pattern (approve → wait → stake) in the stake page
- Address shortening helper (`shorten()`) used in Nav and Govern page
- Dark theme + glass morphism styling consistent across all UI

### External References

- Dynamic developer documentation (for comparison): https://docs.dynamic.xyz
- Privy `@privy-io/cross-app-connect`: https://github.com/privy-io/cross-app-connect
- Privy developer documentation: https://docs.privy.io
- ZeroDev Kernel ERC-7579 docs: https://zerodev.app/developers
- Biconomy Nexus ERC-7579 docs: https://account-abstraction-docs.biconomy.io
- RainbowKit + wagmi integration guide: https://www.rainbowkit.com/docs/installation
- WalletConnect v2 setup: https://docs.walletconnect.com/web3modal/
- Privy cross-app connect (for RainbowKit): https://github.com/privy-io/cross-app-connect
- EIP-7702 status: https://eips.ethereum.org/EIPS/eip-7702

### Institutional Learnings

No prior wallet integration learnings exist in `docs/solutions/`. This is greenfield implementation.

---

## Key Technical Decisions

- **Embedded wallet provider: Privy via `@privy-io/cross-app-connect`** — chosen over Dynamic because it integrates additively on top of the existing RainbowKit setup (2-line connector change, no replacement of `ConnectButton` or `RainbowKitProvider`). Dynamic requires replacing the entire `ConnectButton` with `DynamicWidget` and restructuring the provider tree. Privy's `@privy-io/cross-app-connect` (v0.5.7, actively maintained, 8 releases in 2026) adds email/social login embedded wallets as an additional connector in the existing RainbowKit wallet array, keeping all existing wagmi hooks and wallet flows untouched. Privy also has a dedicated wagmi integration package (`@privy-io/wagmi`) for non-RainbowKit setups. Note: If Solana expansion becomes a concrete roadmap priority within the next 6 months, revisit Dynamic for its native Solana embedded wallet depth and Solana Developer Platform partnership (March 2026).
- **Connectivity layer: RainbowKit** — provides polished wallet selection UI, EIP-6963 extension detection, chain switching, and ENS resolution out of the box; wraps wagmi v3 which remains the contract interaction base
- **Smart account infrastructure: ZeroDev Kernel (ERC-7579) + Biconomy Nexus (ERC-7579)** — ERC-7579 standard ensures plugin compatibility between Safe modules and these providers; ZeroDev chosen for developer experience and 130+ chain support; Biconomy provides the unified bundler/paymaster layer
- **Simulation provider: deferred to implementation** — Alchemy vs Tenderly vs Rabby SDK depends on pricing research and API availability; plan defers this decision; simulation is required (R9) regardless of which provider is chosen
- **EIP-7702: deferred to implementation** — depends on whether the Ethereum Pectra hard fork has shipped at implementation time; the architecture accommodates EIP-7702 when available but falls back to ERC-4337 smart wallet delegation for MetaMask users in the interim
- **WalletConnect v2 project ID** — registration at cloud.walletconnect.com is a prerequisite; plan assumes this is available before Phase 1 begins

---

## Open Questions

### Resolved During Planning

- **[Affects R1]** Embedded wallet provider: **Privy via `@privy-io/cross-app-connect`** — see rationale in Key Technical Decisions. Reverses the earlier framing (Dynamic → Privy) based on integration complexity analysis: Privy is additive to RainbowKit; Dynamic is a full replacement. Privy's package is actively maintained (8 releases in 2026) and officially supports RainbowKit v2.2.x.
- **[Affects R6]** Gas sponsorship economics: **Protocol treasury funds first transaction per user, capped at $5 equivalent gas; subsequent transactions are user-funded or deducted from vault yield** — this gives mainstream users a genuine gasless first experience without unbounded treasury exposure; implements a simple budget tracker
- **[Affects R9]** Simulation provider: **Deferred to implementation** — requires pricing research, API evaluation, and team preference; plan ensures the simulation abstraction layer exists regardless of which provider is chosen
- **[Affects R7]** EIP-7702 fork status: **Deferred to implementation** — Ethereum Pectra timeline uncertain as of planning date; architecture accommodates both EIP-7702 and ERC-4337 paths

### Deferred to Implementation

- Exact simulation provider selection (Alchemy vs Tenderly vs Rabby SDK) — pricing and API evaluation required
- HyperEVM mainnet chain ID and RPC endpoints — confirmed at deployment but must be updated in `lib/contracts.ts`
- WalletConnect v2 project ID registration — must be completed before Phase 1 begins
- Safe{Wallet} module authorization pattern for keeper role — requires verification against `STRATEGY_EXECUTOR_ROLE` assignment in Safe's module system
- EIP-7702 support timeline — depends on Pectra hard fork status

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

### Three-Layer Architecture

```
UI Components (pages/stake, pages/govern, pages/signals)
    │
    │ imports from
    ▼
Contract Interaction Layer  (lib/contracts/actions.ts, lib/contracts/queries.ts)
    │
    │ imports from
    ▼
Wallet Connection Layer  (lib/wallet/WalletProvider.tsx, useWalletState.ts,
                          useMultiWallet.ts, connectors.ts, chainManager.ts)
    │
    │ delegates to
    ▼
wagmi v3 + viem v2  (Providers.tsx, lib/contracts.ts)
```

### Wallet Connection Layer

`lib/wallet/WalletProvider.tsx` wraps wagmi's `WagmiProvider` and exposes typed wallet state. It is the **only** file that imports wagmi hooks directly. Page components import from `lib/wallet/useWalletState.ts` and `lib/contracts/` instead.

```typescript
// Simplified shape — not implementation spec
interface WalletState {
  activeWallet: { address: Address; connector: string; chainId: number; isConnected: boolean };
  connectedWallets: WalletRecord[];   // all retained connections
  activeWalletId: string;              // which wallet signs transactions
  chain: { id: number; isSupported: boolean };
  connectionError: WalletError | null;
}
```

### Multi-Wallet Model

`WalletRecord` is a stable identifier per (connector, address) pair. The `connectorType` field stores the **EIP-6963 RDNS identifier** for injected wallets (e.g., `"injected.com.rabby"`, `"injected.io.metamask"`) to distinguish between multiple injected wallets of the same family. For non-EIP-6963 connectors, the generic type is used:

```typescript
interface WalletRecord {
  id: string;           // stable across sessions
  address: Address;
  connectorType: string; // EIP-6963 RDNS for injected wallets; "coinbase" | "walletconnect" | "privy" for others
  chainId: number;
  connectedAt: number;
  isActive: boolean;     // signing wallet
}
```

**Critical reconciliation rule:** `useMultiWallet` must subscribe to wagmi's `useAccount` change events. When `useAccount().isDisconnected === true`, `activeWalletId` must be re-evaluated: if the previously-active wallet is now disconnected, select the next reconnectable wallet in `connectedWallets[]` or set `activeWalletId = null` if none can reconnect. `activeWalletId` must never point to a wallet that wagmi reports as disconnected.

**Disconnector boundary:** `connector.disconnect()` from the `injected` family disconnects **only** that specific injected wallet's RDNS instance, not all injected wallets. WalletConnect sessions are shared per session topic — disconnecting wallet A may affect wallet B if they share the same WalletConnect session. This must be verified during U1 implementation.

**Privy embedded wallets are separate** from the `connectedWallets[]` array. They are managed by Privy's own session system (`usePrivySession`) and do not appear in the multi-wallet switcher.

### Contract Interaction Layer

`lib/contracts/actions.ts` — all write operations, accepts `WalletRecord` (not raw address):

```typescript
async function stake(
  params: StakeParams,
  wallet: WalletRecord,   // typed wallet, not useAccount().address
): Promise<StakeResult> { /* ... */ }
```

`lib/contracts/queries.ts` — all read operations via react-query with chain-aware invalidation.

### Session Persistence

Phase 1 uses wagmi's `persister` with `localStorage`. Phase 3 adds Supabase-based EIP-4361 wallet auth sessions for cross-device restoration.

### Chain-Extensible Address Map

```typescript
// lib/contracts/addresses.ts
const ADDRESSES: Record<number, ContractAddresses> = {
  998: { /* HyperEVM Testnet */ },
  999: { /* HyperEVM Mainnet — deferred */ },
} as const;
```

`getAddresses(chainId)` returns the correct map. Future chain additions create new entries without architectural change.

---

## Implementation Units

### Phase 1: Foundation and Connectivity

---

- [ ] U1. **Wallet Connection Layer — Extract and Build**

**Goal:** Create `lib/wallet/` as the single, authoritative wallet integration layer. No wagmi hooks are called outside this layer.

**Requirements:** R4, R5, R11, R12, R14

**Dependencies:** None (foundational)

**Files:**
- Create: `frontend/lib/wallet/WalletProvider.tsx`
- Create: `frontend/lib/wallet/useWalletState.ts`
- Create: `frontend/lib/wallet/useMultiWallet.ts`
- Create: `frontend/lib/wallet/connectors.ts`
- Create: `frontend/lib/wallet/chainManager.ts`
- Modify: `frontend/components/Providers.tsx`
- Modify: `frontend/components/Nav.tsx`
- Test: `frontend/lib/wallet/__tests__/useWalletState.test.ts`

**Approach:**

`connectors.ts` exports the full connector configuration including RainbowKit's `getDefaultConfig` for EIP-6963 multi-injected wallet detection. `WalletProvider.tsx` wraps wagmi's `WagmiProvider` and exports React context. `useWalletState.ts` is the primary hook page components import — it exposes `activeWallet`, `connectedWallets`, `chain`, and `connectionError`. `useMultiWallet.ts` handles the multi-wallet state machine (connect, disconnect, set active, persist). `chainManager.ts` handles `wallet_switchEthereumChain` + `wallet_addEthereumChain` with specific error handling for codes 4902, 4001, and -32002.

`Nav.tsx` is refactored to use `useWalletState()` instead of calling `useAccount()` / `useConnect()` / `useDisconnect()` directly. The wallet button becomes a dropdown with wallet switcher when multiple wallets are connected.

`Providers.tsx` wraps with both `WagmiProvider` (wagmi) and `RainbowKitProvider` (RainbowKit), configured with HyperEVM as custom chain and Dynamic's wallet connectors.

**Patterns to follow:**
- `frontend/components/Nav.tsx` — current wallet button styling
- `frontend/lib/contracts.ts` — `HYPEREVM_TESTNET` chain definition pattern

**Test scenarios:**
- Happy path: User connects MetaMask → `activeWallet.address` resolves correctly, `isConnected` is true
- Happy path: User connects MetaMask then Rabby → both wallets retained, `connectedWallets.length === 2`
- Happy path: User changes active wallet via switcher → `activeWalletId` updates, new wallet signs subsequent transactions
- Happy path: Page reload with persisted wallet → wallet reconnects automatically, "reconnecting" state shown
- Edge case: User disconnects from MetaMask directly (not via UI) → state reconciles, disconnected wallet removed from `connectedWallets`
- Edge case: User switches to unsupported chain → non-dismissable warning appears, `chain.isSupported === false`
- Error path: `wallet_switchEthereumChain` returns code 4001 → message "Please approve the network switch in your wallet"
- Error path: `wallet_switchEthereumChain` returns code -32002 → "Check your wallet — a request is waiting for approval"
- Integration: `chainManager.onChainChange()` callback triggers `queryClient.invalidateQueries()` for all contract reads

**Verification:**
- No page component imports `useAccount`, `useConnect`, or `useDisconnect` directly
- `useWalletState()` returns correct wallet state for single and multi-wallet scenarios
- Chain switch errors show specific, actionable messages (not raw error codes)

---

- [ ] U2. **Contract Interaction Layer — Extract Typed Actions and Queries**

**Goal:** Replace all direct `useReadContract` / `useWriteContract` calls in page components with typed wrappers in `lib/contracts/`. Page components import from `lib/contracts/` only.

**Requirements:** R10, R12

**Dependencies:** U1

**Files:**
- Create: `frontend/lib/contracts/addresses.ts`
- Create: `frontend/lib/contracts/actions.ts`
- Create: `frontend/lib/contracts/queries.ts`
- Create: `frontend/lib/contracts/types.ts`
- Modify: `frontend/app/stake/page.tsx`
- Modify: `frontend/app/govern/page.tsx`
- Modify: `frontend/app/signals/page.tsx`
- Modify: `frontend/app/vaults/page.tsx`
- Test: `frontend/lib/contracts/__tests__/actions.test.ts`
- Test: `frontend/lib/contracts/__tests__/queries.test.ts`

**Approach:**

`addresses.ts` replaces the inline address map in `lib/contracts.ts` with a `Record<chainId, ContractAddresses>` structure. `types.ts` defines `StakeParams`, `VoteParams`, `VaultDepositParams` etc. as typed structs. `actions.ts` wraps `useWriteContract` and exports named async functions: `stake()`, `unstake()`, `depositVault()`, `withdrawVault()`, `castVote()`, `propose()`. Each action accepts `WalletRecord` and returns `ActionResult` (success + tx hash, or error + normalized message). `queries.ts` exports typed `useRead` hooks for each contract read: `useVaultTotalAssets()`, `useStakedBalance()`, `useVotingPower()`, etc., with `staleTime` and `refetchOnBlock` tuned per contract.

Page components refactored to import from `lib/contracts/actions.ts` and `lib/contracts/queries.ts` instead of calling wagmi hooks directly. The two-step approve → stake pattern in `stake/page.tsx` is preserved as it is the correct pattern.

**Patterns to follow:**
- `frontend/app/stake/page.tsx` — current approve → waitForTransactionReceipt → stake two-step pattern
- `frontend/lib/contracts.ts` — ABI definition style (as const tuples)
- wagmi v3 + react-query patterns — `useReadContract`, `useWriteContract`, `usePublicClient` usage

**Test scenarios:**
- Happy path: `stake()` calls approve, waits for receipt, calls stake, returns both tx hashes
- Happy path: `depositVault()` returns correct vault token amount after deposit
- Happy path: `useVotingPower()` returns correct vote weight for connected address
- Edge case: Approval reverts → `stake()` returns `{ success: false, error: "Approval failed" }`, does not proceed to stake
- Edge case: `waitForTransactionReceipt` times out → returns `{ success: false, error: "Transaction timeout" }`
- Error path: User rejects in wallet → `stake()` returns `{ success: false, error: "User rejected" }` (parsed from `err.shortMessage`)
- Error path: Contract reverts with custom error → error message is normalized and surfaced
- Integration: `queryClient.invalidateQueries()` fires on `waitForTransactionReceipt` success, refreshing all vault/query data

**Verification:**
- All page components import only from `lib/contracts/` for blockchain interactions (no direct wagmi hook imports)
- All `useReadContract` / `useWriteContract` calls are behind typed wrappers
- The two-step approve → stake pattern is preserved without behavior change

---

- [ ] U3. **WalletConnect v2 + RainbowKit Modal Integration**

**Goal:** Replace the current inline wallet button with RainbowKit's full-featured modal, add WalletConnect v2, and surface trust signals (audit status, protocol TVL) inside the modal.

**Requirements:** R2, R3, R4

**Dependencies:** U1

**Files:**
- Modify: `frontend/components/Providers.tsx` — add `WalletConnectModal`
- Modify: `frontend/components/Nav.tsx` — replace inline button with `<WalletConnectButton>`
- Create: `frontend/components/wallet/TrustSignals.tsx` — audit badge, TVL display
- Modify: `frontend/lib/wallet/connectors.ts` — add WalletConnect v2, Bitget, Rabby, Phantom connectors
- Test: `frontend/components/wallet/__tests__/TrustSignals.test.tsx`

**Approach:**

Install `@rainbow-me/rainbowkit` and `viem` (already present). Add WalletConnect v2 project ID registration step to the plan's prerequisites. Configure RainbowKit's `getDefaultConfig` with `projectId`, `appName`, `appDescription`, and custom chain (`HYPEREVM_TESTNET`). Replace the inline `useConnect()` iteration in `Nav.tsx` with `<WalletConnectButton>` from RainbowKit.

`TrustSignals.tsx` displays: "Audited by Certik + Trail of Bits" (links to audit reports), "$X Total Value Secured", and "Your funds remain in your wallet until you confirm" — injected into the RainbowKit modal footer or shown in a custom modal wrapper.

Rabby, Phantom, Trust, and Ledger connectors are added via Dynamic SDK or direct RainbowKit connector configuration. WalletConnect v2 handles 700+ additional wallets automatically.

**Patterns to follow:**
- RainbowKit official integration guide: https://www.rainbowkit.com/docs/installation
- `frontend/components/Nav.tsx` — current wallet button DOM structure and styling

**Test scenarios:**
- Happy path: WalletConnect modal opens, shows supported wallets with EIP-6963 detection, connects successfully
- Happy path: Trust signal badge renders inside modal with correct audit firm names
- Edge case: No WalletConnect project ID configured → modal shows warning with setup instructions
- Edge case: WalletConnect project ID is invalid → specific error message shown, not generic failure
- Error path: User rejects connection → modal stays open, "Connection rejected" toast appears

**Verification:**
- RainbowKit modal opens from the nav button
- MetaMask, Rabby, Phantom, Trust, Ledger, and WalletConnect v2 wallets appear in the selector
- Trust signals appear in the modal footer
- WalletConnect v2 deep links work on mobile (no QR fallback required on mobile)

---

### Phase 2: Smart Accounts and Gasless UX

---

- [ ] U4. **Privy Embedded Wallet + Social Login for Mainstream Onboarding**

**Goal:** Add Privy via `@privy-io/cross-app-connect` to enable email/social login and embedded MPC wallet creation for users without existing crypto wallets. Mainstream users can access the protocol without installing any wallet extension.

**Requirements:** R1, R4, R5

**Dependencies:** U1, U3

**Files:**
- Modify: `frontend/package.json` — add `@privy-io/cross-app-connect`
- Modify: `frontend/lib/wallet/connectors.ts` — add Privy connector to the RainbowKit connectors array
- Create: `frontend/components/auth/EmbeddedWalletGate.tsx` — progressive onboarding wrapper
- Create: `frontend/lib/wallet/usePrivySession.ts` — Privy embedded wallet session management
- Modify: `frontend/app/stake/page.tsx` — add EmbeddedWalletGate wrapper
- Test: `frontend/components/auth/__tests__/EmbeddedWalletGate.test.tsx`

**Approach:**

Install `@privy-io/cross-app-connect`. Import `toPrivyWallet` from `@privy-io/cross-app-connect/rainbow-kit`. Append it to the existing `connectorsForWallets` array in `connectors.ts` under a `groupName: "Privy"` label — **no changes to `Providers.tsx`, no new providers, no replacement of `ConnectButton`**. The existing RainbowKit `ConnectButton` gains a new "Privy" section with email and social login options.

`EmbeddedWalletGate.tsx` is a wrapper component placed on protected pages. If no external wallet is connected (via RainbowKit) and no Privy session exists, it shows a "Sign in with email" prompt alongside the RainbowKit `ConnectButton`. If the user enters email, Privy creates an embedded MPC wallet (stored via Privy's infrastructure, key shares distributed between device and Privy's server). The embedded wallet address is surfaced as "Your wallet" with a brief explanation ("A wallet was created for you — no seed phrase needed").

`usePrivySession.ts` manages the Privy session — `isAuthenticated`, `address`, `walletClient`. Privy embedded wallets from cross-app-connect are **separate from the multi-wallet switcher** in `useWalletState` — they use Privy's own session management, not wagmi's connector state. They do not appear in `connectedWallets[]`. The multi-wallet switcher shows only external wallets connected via RainbowKit/wagmi connectors.

**Privy limitation note:** Privy's embedded wallet sessions persist per browser/device via `localStorage` and the Privy SDK. Cross-device or cross-browser sessions require re-authentication via email — Privy does not provide a built-in EIP-4361 SIWE session that works across browsers without re-authentication. If cross-device sessions are required, U8's Supabase-based EIP-4361 auth layer addresses this.

**Patterns to follow:**
- `frontend/components/Nav.tsx` — existing sign-in button structure and styling
- `frontend/app/stake/page.tsx` — current page structure for adding gate wrapper
- `@privy-io/cross-app-connect` README integration pattern

**Test scenarios:**
- Happy path: User enters email → embedded MPC wallet created, session persisted in browser, "Your wallet" address shown
- Happy path: User with Privy embedded wallet returns in same browser → session reconnects automatically, full vault access restored
- Happy path: User connects external wallet via RainbowKit → that wallet appears in multi-wallet switcher alongside Privy embedded wallet (separate systems)
- Edge case: User tries Privy on a different browser/device → prompted to re-authenticate via email (Privy does not support cross-device sessions without email re-auth)
- Edge case: Privy SDK fails to initialize → graceful fallback to external wallet only (no blocking error), `usePrivySession` returns `isAvailable: false`
- Error path: Email OTP fails → user shown retry option with error message, no wallet created

**Verification:**
- Users without external wallets can sign in with email and access vault functionality
- Privy embedded wallet appears in the Privy session, not in the RainbowKit multi-wallet switcher
- Session persists across page reloads in the same browser

---

- [ ] U5. **ZeroDev Kernel + Biconomy Paymaster — Gasless Transactions**

**Goal:** Implement ERC-4337 smart account infrastructure so users can execute transactions without holding the native gas token. The protocol treasury sponsors first-transaction gas (capped at $5 equivalent); subsequent transactions use vault yield deductions.

**Requirements:** R6, R7

**Dependencies:** U1, U2, U4

**Files:**
- Modify: `frontend/package.json` — add `@zerodev/sdk`, `@biconomy/sdk`
- Create: `frontend/lib/wallet/smartAccountProvider.ts` — ZeroDev + Biconomy initialization
- Create: `frontend/lib/wallet/useSmartAccount.ts` — smart account hooks
- Modify: `frontend/lib/contracts/actions.ts` — add `useGaslessAction()` variant
- Create: `frontend/components/gas/GaslessToggle.tsx` — user-facing gasless opt-in UI
- Modify: `frontend/app/stake/page.tsx` — add gasless flow with simulation
- Test: `frontend/lib/wallet/__tests__/smartAccountProvider.test.ts`

**Approach:**

Install `@zerodev/sdk` (ZeroDev Kernel) and `@biconomy/sdk` (bundler + paymaster). `smartAccountProvider.ts` initializes the kernel account using Biconomy as bundler and paymaster. Kernel is chosen over Safe's own AA implementation for developer experience and broader chain coverage.

The paymaster is configured with ERC-20 paymaster support (USDC-denominated gas) in addition to native token sponsorship. A `GaslessToggle` component lets users opt in/out of gasless mode. When gasless is active, `useSmartAccount()` returns the kernel smart account address; `useGaslessAction()` wraps the normal `actions.ts` calls and routes them through the kernel account with sponsored gas.

First-transaction gas sponsorship is capped at $5 equivalent per user per protocol deployment. A simple counter in `localStorage` tracks first-free tx per address. This can be expanded to Supabase persistence in Phase 3.

EIP-7702 support is checked at implementation time. If Pectra has shipped, `createKernelAccountClientWith7702` is used for existing MetaMask EOAs; otherwise, users with MetaMask are guided to the ZeroDev smart wallet migration flow.

**Patterns to follow:**
- `frontend/lib/contracts/actions.ts` — existing action structure to extend
- `frontend/app/stake/page.tsx` — current two-step pattern; gasless adds a third "sponsored" step

**Test scenarios:**
- Happy path: User with no gas token submits deposit → gas sponsored by paymaster, transaction succeeds
- Happy path: User's second transaction → gas deducted from vault yield or user-funded (UI shows which)
- Happy path: EIP-7702 is live → MetaMask EOA delegates to kernel without wallet migration
- Edge case: Paymaster sponsor budget exhausted → user notified, transaction queued or user-funded fallback
- Edge case: Biconomy bundler returns error → falls back to standard wallet signature
- Error path: Kernel account creation fails → graceful fallback to normal wallet transaction
- Integration: gasless transaction receipt triggers same `queryClient.invalidateQueries()` as normal transaction

**Verification:**
- Users without gas tokens can complete vault deposits
- First transaction per user is sponsored (up to $5 equivalent)
- Gasless mode is visible and opt-outable via `GaslessToggle`

---

### Phase 3: Institutional, Trust Features, and Hardening

---

- [ ] U6. **Safe{Wallet} Integration for Institutional Multisig**

**Goal:** Support Safe{Wallet} as a first-class smart account option. Institutional users can interact with the protocol using their Safe multisig without any special configuration.

**Requirements:** R8, R13

**Dependencies:** U1, U5

**Files:**
- Modify: `frontend/lib/wallet/connectors.ts` — add Safe connector
- Modify: `frontend/lib/wallet/WalletProvider.tsx` — add Safe detection and role labeling
- Create: `frontend/components/wallet/KeeperBadge.tsx` — keeper role badge component
- Modify: `frontend/app/stake/page.tsx` — add KeeperBadge to keeper-mode UI
- Create: `frontend/lib/wallet/__tests__/safeDetector.test.ts`

**Approach:**

Add `@safe-global/protocol-kit` and `@safe-global/auth-kit`. The Safe connector is added to `connectors.ts` alongside the existing injected/WalletConnect/Dynamic connectors. When a Safe is connected, `WalletProvider` detects it via `connector.type === "safe"` and sets `wallet.connectorType = "safe"`.

`KeeperBadge.tsx` checks if the connected wallet has the `STRATEGY_EXECUTOR_ROLE` (via `hasRole` call to `StrategyExecutor`). **The badge is shown optimistically** based on an initial `hasRole` check at connection time — this provides fast UX. **However, every keeper action must re-verify `hasRole` live** before submission, because `STRATEGY_EXECUTOR_ROLE` can be revoked at any time via governance. If the live check fails, the transaction is rejected with a clear "Your keeper access has been revoked" message. Additionally, on `window.focus` (tab resume), the badge is re-checked to catch revocations that occurred while the tab was inactive.

Safe modules are configured to be compatible with the ERC-7579 plugin standard used by ZeroDev Kernel — kernel modules and Safe modules use the same plugin interface, meaning role checks and permission guards work consistently across both account types.

**Patterns to follow:**
- `frontend/components/Nav.tsx` — current address display + badge structure
- `frontend/lib/wallet/WalletProvider.tsx` — wallet type detection pattern from U1

**Test scenarios:**
- Happy path: Safe{Wallet} user connects → Safe detected, "Multisig" badge shown, all transactions require Safe threshold signatures
- Happy path: Keeper wallet connects → "Keeper" badge appears, keeper transactions show `StrategyExecutor` address
- Edge case: User with Safe attempts keeper action without `STRATEGY_EXECUTOR_ROLE` → transaction reverts with `AccessControlUnauthorizedAccount` error surfaced in UI
- Edge case: Safe threshold is not met for a transaction → pending state shown until threshold reached
- Error path: Safe module authorization fails → clear error surfaced, not silent failure

**Verification:**
- Safe{Wallet} users see a "Multisig" badge in the wallet display
- Keeper wallets show a "Keeper" badge with the `StrategyExecutor` contract address in confirmation panels
- Non-keeper wallets attempting keeper actions receive a clear authorization error

---

- [ ] U7. **Transaction Simulation Pre-Sign Panel**

**Goal:** Display a simulation preview before every write transaction showing exact token amounts, destination, gas, and approval scope. This is the primary trust-building feature for power users.

**Requirements:** R9, R14, R15

**Dependencies:** U2, U5

**Files:**
- Create: `frontend/components/tx/SimulationPanel.tsx` — simulation display component
- Create: `frontend/components/tx/SimulationGate.tsx` — blocks signing until simulation renders
- Modify: `frontend/lib/contracts/actions.ts` — add simulation call before every write
- Modify: `frontend/app/stake/page.tsx` — integrate SimulationGate around confirm step
- Modify: `frontend/app/govern/page.tsx` — integrate SimulationGate around vote confirm
- Test: `frontend/components/tx/__tests__/SimulationPanel.test.tsx`

**Approach:**

Simulation provider selection is deferred to implementation (Alchemy Transact API vs Tenderly Simulation API vs Rabby SDK). `SimulationGate.tsx` wraps every write action. Before the wallet popup appears, it calls the simulation provider with the constructed transaction. If simulation succeeds, `SimulationPanel.tsx` displays: tokens changed (with direction), destination contract address, gas estimate (in fiat), approval scope (token + amount + expiry if applicable), and a plain-English explanation of what the transaction does.

If simulation fails or returns an unexpected result, the `SimulationPanel` shows a warning with the failure reason and the transaction is blocked. The user can still proceed at their own risk via an explicit "I understand, proceed" override.

`SimulationPanel` is shown in a modal that appears between the action form and the wallet popup. It is styled to match the existing UI (dark theme + glass morphism). Audit report links ("Audited by Certik • September 2025") are shown inside the panel at the first deposit/stake action — not in the footer.

**Patterns to follow:**
- Rabby Wallet's simulation output format — reference standard for DeFi simulation UX
- `frontend/app/stake/page.tsx` — current confirmation step flow
- Dark theme + glass morphism from `packages/zentory-ui/`

**Test scenarios:**
- Happy path: Deposit simulation shows "You will send 0.5 ETH → receive 0.5 zETH, pay ~$2.40 gas, approve zETHVault to spend your ETH"
- Happy path: Simulation fails (reverts) → panel shows warning "This transaction would fail: [reason]", confirm button disabled
- Happy path: User overrides simulation warning → transaction proceeds, audit of override logged
- Edge case: Simulation provider is unavailable → panel shows "Simulation unavailable — proceeding without preview", transaction proceeds with user acknowledgment
- Edge case: Simulation returns unexpected token amounts → warning panel, not silent proceed
- Error path: RPC returns stale data during simulation → simulation retries once, then shows warning
- Integration: Simulation is called with the actual constructed transaction (same calldata that would be sent to the wallet)

**Verification:**
- Every write transaction (deposit, withdraw, stake, vote) shows a simulation panel before the wallet popup
- Simulation output is human-readable (not raw hex)
- Failed simulations block the transaction with a clear explanation

---

- [ ] U8. **Session Persistence and Cross-Chain Hardening**

**Goal:** Implement Supabase-backed EIP-4361 wallet auth sessions for cross-device persistence, and finalize the chain-extensible architecture with mainnet preparation.

**Requirements:** R10, R12

**Dependencies:** U1, U2, U3, U6, U7

**Files:**
- Create: `frontend/lib/auth/walletAuth.ts` — EIP-4361 sign-in with Ethereum
- Create: `frontend/lib/auth/useWalletSession.ts` — session management hook
- Modify: `frontend/lib/wallet/WalletProvider.tsx` — swap localStorage persister for Supabase persister
- Modify: `frontend/lib/contracts/addresses.ts` — add mainnet chain ID (999) placeholder
- Create: `frontend/lib/wallet/__tests__/walletAuth.test.ts`
- Modify: `frontend/lib/wallet/chainManager.ts` — finalize error handling matrix

**Approach:**

`walletAuth.ts` implements EIP-4361 "Sign in with Ethereum" — the standard for wallet-based session auth. The flow: server generates a nonce → client signs the EIP-4361 message with the connected wallet → server verifies the signature and issues a Supabase session JWT tied to the wallet address. `useWalletSession.ts` exposes `isAuthenticated`, `walletAddress`, `signOut`.

The `WagmiProvider` persister is upgraded from `localStorage` to a Supabase-backed persister. On page load, if a Supabase session exists for the connected wallet, the session is restored without requiring re-connection. If the session has expired, the user is prompted to re-sign the EIP-4361 message (which they can do with any connected wallet).

`addresses.ts` is updated to include a `999` entry (HyperEVM Mainnet placeholder) alongside the testnet entry. A `getActiveChainId()` helper reads from the connected wallet's `chainId`, and `getAddresses(chainId)` returns the correct deployment's contract map. Future chain additions create new numeric entries.

**Patterns to follow:**
- `frontend/lib/wallet/useWalletState.ts` — existing session state model to extend
- Supabase SSR patterns from `frontend/lib/supabase/` if present

**Test scenarios:**
- Happy path: User connects wallet on desktop, signs EIP-4361 → Supabase session created, persists across page reload
- Happy path: User opens protocol on tablet with same wallet → session restored, no re-connection needed
- Happy path: Session expires → user prompted to re-sign, not forced to reconnect wallet
- Happy path: User switches to HyperEVM mainnet → `getAddresses(999)` returns mainnet contracts, testnet addresses no longer used
- Edge case: User connects wallet A, creates session → connects wallet B → session is associated with wallet A only
- Edge case: Supabase is unavailable on page load → falls back to localStorage persister, no blocking error
- Error path: EIP-4361 signature verification fails on server → session not created, clear error shown

**Verification:**
- Wallet sessions persist across page reloads and devices
- Sessions expire and require re-authentication (not indefinite)
- `addresses.ts` returns correct contract map per chain ID
- Chain expansion requires only a new entry in `ADDRESSES`, not architectural changes

---

## System-Wide Impact

- **Interaction graph:** The extraction of `lib/wallet/` and `lib/contracts/` layers affects every page that currently calls `useAccount`, `useConnect`, `useDisconnect`, `useReadContract`, or `useWriteContract` directly. All four existing pages (`stake`, `govern`, `signals`, `vaults`) must be updated to import from the new layers. No callbacks or middleware fire on wallet state change — react-query cache invalidation is the primary side effect.
- **Error propagation:** `actions.ts` normalizes all errors to `{ success: false, error: "string" }` — page components receive consistent error shapes regardless of the underlying wagmi/viem error type. Simulation failures propagate as warnings, not hard blocks.
- **State lifecycle risks:** Multi-wallet state in `useMultiWallet.ts` must handle the case where `connector.disconnect()` is called by the wallet itself (not via the UI) — `useAccount().isDisconnected` change must reconcile the `connectedWallets` array.
- **API surface parity:** The `lib/contracts/` typed wrappers are the new API surface. Any component that needs blockchain interaction must go through these wrappers. Direct wagmi imports are prohibited by convention (enforced via lint rule in U1).
- **Integration coverage:** `actions.ts` integration with `waitForTransactionReceipt` is the critical path — a failed `waitForTransactionReceipt` after a successful `writeContract` would leave the user in a pending state with no resolution. This path is covered by the edge case test in U2.

---

## Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| WalletConnect v2 project ID registration blocked or delayed | Medium | Medium | U3 is gated on ID availability; RainbowKit modal can launch with existing connectors while ID is pending |
| RainbowKit wagmi v3 compatibility | Medium | Medium | RainbowKit was not updated for wagmi v3's `useAccount` → `useConnection` rename; use community fix (`phelix001/rainbowkit:v2.2.10-wagmi3`) or wait for upstream fix; test thoroughly in U3 |
| Privy cross-browser session persistence | High | Low | Privy embedded wallet sessions are per-browser/device; cross-browser requires re-authentication; U8's EIP-4361 Supabase session addresses cross-device persistence |
| EIP-7702 not shipped in Pectra at implementation time | High | Low | Fallback to ERC-4337 smart wallet delegation for MetaMask users; plan accommodates this with explicit deferred decision |
| Biconomy paymaster budget exhaustion (mainnet) | Medium | Medium | Budget cap per user ($5 first tx); gasless toggle as fallback; vault yield deduction as sustainable long-term model |
| Safe module authorization incompatible with `STRATEGY_EXECUTOR_ROLE` | Low | Medium | Verify during U6; Safe's `isValidModule()` check + `ExecutionFromModule` return value validation before surfacing keeper UI |
| Simulation provider API changes or pricing shift | Medium | Medium | Simulation abstraction layer in `actions.ts` isolates provider selection; swap provider without changing call sites |
| Supabase session auth latency on page load | Low | Low | Fallback to localStorage persister if Supabase unavailable; no blocking behavior |

---

## Phased Delivery

### Phase 1 — Foundation and Connectivity (Weeks 1–4)
- U1: Wallet connection layer extracted
- U2: Contract interaction layer extracted and typed
- U3: RainbowKit modal + WalletConnect v2 + trust signals

*Phase 1 is self-contained and delivers immediate value: multi-wallet support, proper abstraction, and a polished connection modal. U1 and U2 are prerequisites for all later phases. U3 depends on WalletConnect project ID availability.*

### Phase 2 — Smart Accounts and Gasless (Weeks 5–8)
- U4: Privy embedded wallet + social login onboarding
- U5: ZeroDev Kernel + Biconomy paymaster gasless transactions

*Phase 2 unlocks mainstream user onboarding without wallet installation. U4 depends on U1 + U3. U5 depends on U1 + U2 + U4.*

### Phase 3 — Institutional and Trust (Weeks 9–12)
- U6: Safe{Wallet} integration + keeper role UI
- U7: Transaction simulation pre-sign panel
- U8: Supabase session persistence + chain hardening

*Phase 3 completes the institutional and trust layers. U6 depends on U1 + U5. U7 depends on U2 + U5. U8 depends on all prior units.*

---

## Documentation / Operational Notes

- **WalletConnect v2 project ID** must be registered at https://cloud.walletconnect.com before U3 begins. Registration is free and takes ~5 minutes.
- **Dynamic SDK initialization** requires an `environment` configuration — update from `"testnet"` to `"mainnet"` when HyperEVM mainnet deploys.
- **Paymaster budget** for gas sponsorship is tracked in `localStorage` per address in Phase 2 (upgradeable to Supabase in U8).
- **Audit report links** in U7 should use the most recent audit dates and firm names from `contracts/AUDIT.md`.
- **Chain IDs** in `lib/contracts/addresses.ts` must be updated when HyperEVM mainnet launches. Testnet (998) should remain active for development.

---

## Sources & References

- **Origin document:** [docs/brainstorms/wallet-integration-strategy.md](../brainstorms/wallet-integration-strategy.md)
- WalletConnect Year Ahead 2026: https://walletconnect.com/blog/walletconnect-year-ahead-2026
- WalletConnect 2025 Year In Review: https://walletconnect.com/blog/walletconnect-2025-year-in-review
- Dynamic developer docs: https://docs.dynamic.xyz
- ZeroDev / Kernel ERC-7579 docs: https://zerodev.app/developers
- Biconomy Nexus Smart Accounts: https://account-abstraction-docs.biconomy.io
- Privy cross-app connect: https://github.com/privy-io/cross-app-connect
- RainbowKit installation: https://www.rainbowkit.com/docs/installation
- EIP-7702 specification: https://eips.ethereum.org/EIPS/eip-7702
- Safe{Wallet} protocol kit: https://github.com/safe-global/protocol-kit
- EIP-4361 (Sign in with Ethereum): https://eips.ethereum.org/EIPS/eip-4361
- Rabby Wallet simulation UX: https://rabby.io
