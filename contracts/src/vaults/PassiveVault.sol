// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseVault} from "./BaseVault.sol";

/// @title PassiveVault
/// @notice Future-only benchmark-denominated vault wrapper with zero performance
///         fee and zero max leverage. Solves the Q11 audit finding #7 (legacy
///         zBTC/zETH/zSOL/zXRP charged a 20% performance fee and advertised
///         3x leverage while running no active strategy).
///
/// @dev    This contract is the **future pattern** for any new benchmark wrapper
///         deployment. It is **NOT** deployed by this PR — the legacy z-vaults
///         retain their immutable risk rails and are paused via the existing
///         `BaseVault.activateCircuitBreaker(reason)` path under the
///         RISK_COUNCIL_ROLE (see `script/PauseZVaults.s.sol`).
///
///         The five risk rails are hard-coded to PASSIVE values:
///
///           - `performanceFee = 0`          — no performance fee is ever charged.
///             The audit's charge-perf-fee-for-no-strategy contradiction cannot
///             recur for any vault deployed via this class.
///           - `maxLeverage = 0`             — no leverage cap is enforced
///             because the contract does not run a strategy at all (any
///             `recordTrade()` will revert via `// (none here)`-style invariant:
///             the BaseVault `recordTrade` path reads `currentDirection` and
///             `currentPositionSize` which are never set; the
///             `tvl * maxLeverage / 10000` check in `BaseVault.recordTrade`
///             means a trade of any size with `maxLeverage == 0` reverts).
///           - `maxPositionSizeBPS = 10000`  — single-side position ceiling at
///             100% TVL (the max the BaseVault invariant can express without
///             enabling leverage).
///           - `circuitBreakerDrawdownBPS = 2000` — same 20% drawdown rail as
///             the legacy z-vaults for symmetry with the rest of the suite.
///           - `rebalanceThresholdBPS = 10000` — 100% NAV drift threshold,
///             effectively disabling automatic rebalances (a passive wrapper
///             has no strategy to rebalance *to*).
///
///         Together these close finding #7 at the *source* rather than at
///         any specific deployed address: a future deployer who picks this
///         subclass literally cannot wire in a strategy that charges a perf
///         fee for not running, regardless of the constructor params they
///         pass in, because the only constructor params they pass in are
///         the asset / name / symbol / feeRecipient / admin — the risk rails
///         are baked in.
///
///         Per `docs/decisions/2026-08-21-q11-zvaults-deprecate.md`, no on-chain
///         deployment of `PassiveVault` is part of this PR. A follow-up
///         migration script (`script/MigrateLegacyZVaults.s.sol`, out of
///         scope for this PR) will deploy fresh `PassiveVault` instances
///         under the legacy names if the founder approves a balance
///         migration off the immutable-fee legacy addresses.
// slither-disable-next-line naming-convention
contract PassiveVault is BaseVault {
    // Hard-coded PASSIVE risk rails. `internal` visibility would let subclasses
    // mutate them; `private` here documents the intent that no subclass of
    // PassiveVault can re-enable a fee or a leverage cap without rewriting
    // the constructor (which the auditor will see and sign off).
    uint256 private constant PASSIVE_PERFORMANCE_FEE_BPS = 0; // 0%
    uint256 private constant PASSIVE_MAX_LEVERAGE = 0; // no leverage
    uint256 private constant PASSIVE_MAX_POSITION_SIZE_BPS = 10000; // 100% TVL (no-strategy ceiling)
    uint256 private constant PASSIVE_CIRCUIT_BREAKER_BPS = 2000; // 20% drawdown
    uint256 private constant PASSIVE_REBALANCE_THRESHOLD_BPS = 10000; // 100% drift (effectively disabled)

    constructor(address asset_, string memory name_, string memory symbol_, address feeRecipient_, address admin_)
        BaseVault(
            asset_,
            name_,
            symbol_,
            PASSIVE_MAX_LEVERAGE,
            PASSIVE_MAX_POSITION_SIZE_BPS,
            PASSIVE_CIRCUIT_BREAKER_BPS,
            PASSIVE_REBALANCE_THRESHOLD_BPS,
            PASSIVE_PERFORMANCE_FEE_BPS,
            feeRecipient_,
            admin_
        )
    {}
}
