# Execution pivot — manual → Lumibot → safe automation

This updates the original “full GP automation” plan to the `goal.md` pivot: **manual execution now**, **Lumibot backtesting for proof**, **automation only after security gates**.

## Phase 0 (now): Manual mode (safe-by-default)

- **Two separate actions**:
  - **Log-only**: record a proposed trade signal for review/audit.
  - **Execute**: submit a signed signal to `StrategyExecutor` from a keeper address.
- **Hard rules**:
  - No private keys in the frontend.
  - “Execute” endpoints must require authn/authz + rate limiting + an append-only audit log.
  - Keeper execution is pausable (guardian + governance).

## Phase 1: Lumibot backtesting (evidence)

- Implement a Lumibot provider that outputs signals from strategies on known price series.
- Produce reproducible reports:
  - in-sample / out-of-sample splits
  - drawdown, Sharpe, hit rate, max adverse excursion
  - parameter + dataset hashes so reports are tamper-evident
- Publish summarized results to the marketing site and link to raw artifacts (IPFS optional).

## Phase 2: Safe automation (only after contract correctness gates)

Automation is allowed only after:
- keeper signature auth is bound to an authorized signer
- replay protection is proven (nonce monotonicity end-to-end)
- timelock execution is correct
- fee routing is end-to-end
- privileged operations are audited + monitored

## Canonical TradeSignal (single source-of-truth)

The on-chain contract is the canonical spec. Off-chain code must match it byte-for-byte.

### Solidity digest (authoritative)

`StrategyExecutor` verifies:

- `DOMAIN_SEPARATOR = keccak256(abi.encode(keccak256("EIP712Domain(uint256 chainId,address executor)"), chainId, executor))`
- `SIGNAL_TYPEHASH = keccak256("TradeSignal(address vault,uint8 direction,uint256 size,uint64 price,uint256 nonce,uint256 expiry)")`
- `structHash = keccak256(abi.encode(SIGNAL_TYPEHASH, vault, direction, size, price, nonce, expiry))`
- `digest = keccak256("\x19\x01" || DOMAIN_SEPARATOR || structHash)`
- `ecrecover(digest, sig) == authorizedSigner`

### JSON payload (transport)

```json
{
  "vault": "0x...",
  "direction": 1,
  "size": "1000000",
  "price": "6500000000",
  "nonce": "123",
  "expiry": "1710000000",
  "chainId": 998,
  "executor": "0x...",
  "signature": "0x..."
}
```

### Field semantics

- `vault`: vault contract being traded.
- `direction`: `1=long`, `0=short`, `2=close` (reduce-only).
- `size`: raw size units (must match adapter expectations).
- `price`: limit price in \(10^8\) units (USD * 1e8).
- `nonce`: strictly increasing per vault.
- `expiry`: unix timestamp; reject if `block.timestamp > expiry`.

## Key management policy (minimum bar)

- **Signal signer key** (`authorizedSigner`):
  - Stored in a KMS/HSM (or hardware wallet for early stages).
  - Rotatable via governance/admin operation.
  - Never co-located with the keeper execution key.
- **Keeper execution key** (calls `executeSignal`):
  - Holds `KEEPER_ROLE`.
  - Rate-limited, monitored, and quickly revocable.
- **Guardian key**:
  - Multisig if possible.
  - Has pause authority.

