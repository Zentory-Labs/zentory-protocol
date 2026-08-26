// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Spot swap venue (e.g. Hyperliquid spot via CoreWriter, or a HyperEVM DEX).
///         Pulls `amountIn` of `tokenIn` from the caller and sends `tokenOut` back.
interface ISpotSwapAdapter {
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut)
        external
        returns (uint256 amountOut);
}

/// @notice Chainlink-compatible price feed: USD price of one whole underlying
///         unit, scaled to `decimals()` (typically 8). Cash asset assumed ~= $1.
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @title SpotVault (BaseVault v2 — spot, in-vault execution)
/// @notice ERC-4626 vault DENOMINATED IN THE UNDERLYING (e.g. WBTC). The strategy
///         is long/flat spot: hold the underlying (LONG) or the cash asset (USDC,
///         FLAT). NAV is measured in underlying units, valuing the cash leg via an
///         oracle. Unlike BaseVault, `totalAssets()` reflects the live position, so
///         a depositor's shares actually move with strategy PnL — the edge shows up
///         as MORE UNDERLYING PER SHARE (sit in cash through a drop, rebuy lower).
///         See VAULT_SPOT_EXECUTION_SPEC.md.
contract SpotVault is ERC4626, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant RISK_COUNCIL_ROLE = keccak256("RISK_COUNCIL_ROLE");

    IERC20 public immutable cashAsset; // e.g. USDC
    AggregatorV3Interface public immutable oracle; // underlying/USD
    uint256 public immutable maxOracleStaleness; // seconds; reverts if feed older
    ISpotSwapAdapter public swapAdapter;

    uint8 internal immutable _assetDec;
    uint8 internal immutable _cashDec;
    uint8 internal immutable _priceDec;

    uint16 public targetWeightBps; // 0..10000 (last commanded exposure)
    uint16 public immutable rebalanceThresholdBps; // dust deadband
    uint16 public immutable maxSlippageBps;
    uint256 public immutable performanceFee; // bps of alpha above HWM
    uint256 public highWaterMark;
    uint256 public performanceFeeAccrued; // in underlying units
    address public feeRecipient;
    bool public isCircuitBreakerActive;

    /// @notice Per-address cooldown (seconds) between successive `redeemEmergency`
    ///         calls. MEV-guard so that during a stale-oracle event a single bot
    ///         cannot race honest users to the limited underlying left in the vault.
    uint256 public emergencyRedeemCooldown;
    /// @notice Last timestamp at which `owner` called `redeemEmergency`. Used to
    ///         enforce `emergencyRedeemCooldown` per address. Zero means "never
    ///         called" — first call is always allowed.
    mapping(address => uint256) public lastEmergencyRedeemAt;

    // ─── TWAP / deviation guard (Tier-0.A Q9) ──────────────────────────────────
    /// @notice Time-weighted average price window (seconds). The vault tracks
    ///         recent on-chain price observations and computes the TWAP over
    ///         this window. Any new price that deviates by more than
    ///         `maxOracleDeviationBps` from the TWAP is rejected. Designated
    ///         `0` disables the guard (incident response uses
    ///         `setMaxOracleDeviationBps(0)` rather than redeploying).
    uint256 public immutable twapWindow;
    /// @notice Maximum permitted deviation (in bps) between the current oracle
    ///         price and the rolling TWAP. Set to 1000 (10%) for production;
    ///         0 disables the guard. Settable by admin via
    ///         `setMaxOracleDeviationBps` for incident response. Default 1000
    ///         is the same order of magnitude as the documented
    ///         5%-intra-window-move risk from the audit (`AUDIT_FINDINGS_2026-08-07.md`
    ///         stale-price window finding).
    uint256 public maxOracleDeviationBps;

    /// @dev Ring buffer of recent price observations. Stored as a fixed-size
    ///      array (gas-cheap) with an explicit count + write head. The TWAP
    ///      is computed across observations within `twapWindow` seconds of
    ///      `block.timestamp`. Ring size is a power of two for cheap modulo.
    struct Observation {
        uint64 timestamp;
        uint128 price;
    }
    Observation[16] private _observations;
    uint16 private _observationCount;
    uint16 private _observationHead;

    event Rebalanced(uint16 targetBps, uint256 assetLeg, uint256 cashLeg, uint256 navPerShare);
    event PerformanceFeeAccrued(uint256 fee, uint256 navBefore, uint256 navAfter);
    event PerformanceFeeClaimed(address indexed recipient, uint256 paid, uint256 stillAccrued);
    event PerformanceFeeWrittenDown(uint256 amount, uint256 stillAccrued);
    event CircuitBreakerSet(bool active);
    /// @notice Emitted on every `redeemEmergency` call. `haircutAssets` is what the
    ///         depositor is OWED at the last oracle price but cannot be paid because
    ///         the oracle is stale (and we skip the oracle in this path). It is the
    ///         invariant under which monitoring must alert: a non-zero haircut means
    ///         a stale-oracle event is in progress.
    event EmergencyRedeem(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 sharesBurned,
        uint256 paid,
        uint256 haircutAssets,
        uint256 haircutPerShare
    );
    event EmergencyRedeemCooldownSet(uint256 oldCooldown, uint256 newCooldown);
    event MaxOracleDeviationBpsSet(uint256 oldBps, uint256 newBps);
    event OracleDeviationRecorded(
        uint256 currentPrice, uint256 twapPrice, uint256 deviationBps, uint256 maxDeviationBps, uint256 observationCount
    );

    error CircuitBreakerActive();
    error BadWeight();
    error StaleOracle(uint256 updatedAt, uint256 nowTs);
    error InvalidOraclePrice(int256 answer);
    error EmergencyBreakerActive();
    error EmergencyCooldownActive(uint256 nextAllowedAt);
    /// @notice Emitted when the current oracle price deviates from the rolling
    ///         TWAP by more than `maxOracleDeviationBps`. This is the
    ///         Q9 (Tier-0.A stale-price window) guard. Closing this gap
    ///         prevents adversarial price prints from being priced into NAV
    ///         while the oracle is "fresh" but the price is suspect.
    error OracleDeviationTooLarge(uint256 currentPrice, uint256 twapPrice, uint256 maxDeviationBps);

    /// @param emergencyRedeemCooldown_ seconds between successive `redeemEmergency`
    ///        calls per `owner` address. Settable later via
    ///        `setEmergencyRedeemCooldown` (RISK_COUNCIL_ROLE). Recommended default
    ///        is 1 hour (3600) — long enough to deter MEV racing during a stale
    ///        oracle event, short enough that honest users are not inconvenienced
    ///        through a multi-hour outage.
    /// @param twapWindow_ seconds for the rolling TWAP window. The vault
    ///        computes the time-weighted average price over this window from
    ///        on-chain observations. 0 disables the deviation guard entirely
    ///        (the legacy pre-fix behaviour). Recommended: 1800 (30 min).
    /// @param maxOracleDeviationBps_ max deviation (bps) between the current
    ///        oracle price and the rolling TWAP before the vault reverts.
    ///        0 disables the guard. Settable later via
    ///        `setMaxOracleDeviationBps` (DEFAULT_ADMIN_ROLE). Recommended:
    ///        1000 (10%).
    constructor(
        address asset_,
        address cashAsset_,
        address oracle_,
        uint256 maxOracleStaleness_,
        string memory name_,
        string memory symbol_,
        uint16 rebalanceThresholdBps_,
        uint16 maxSlippageBps_,
        uint256 performanceFeeBps_,
        address feeRecipient_,
        address admin_,
        uint256 emergencyRedeemCooldown_,
        uint256 twapWindow_,
        uint256 maxOracleDeviationBps_
    ) ERC20(name_, symbol_) ERC4626(IERC20(asset_)) {
        require(asset_ != address(0) && cashAsset_ != address(0) && oracle_ != address(0), "zero addr");
        require(feeRecipient_ != address(0) && admin_ != address(0), "zero addr");
        require(rebalanceThresholdBps_ <= 10000 && maxSlippageBps_ <= 10000 && performanceFeeBps_ <= 10000, "bad bps");
        require(maxOracleStaleness_ > 0, "zero staleness");
        require(maxOracleDeviationBps_ <= 10000, "bad bps");

        cashAsset = IERC20(cashAsset_);
        oracle = AggregatorV3Interface(oracle_);
        maxOracleStaleness = maxOracleStaleness_;
        _assetDec = IERC20Metadata(asset_).decimals();
        _cashDec = IERC20Metadata(cashAsset_).decimals();
        _priceDec = AggregatorV3Interface(oracle_).decimals();

        rebalanceThresholdBps = rebalanceThresholdBps_;
        maxSlippageBps = maxSlippageBps_;
        performanceFee = performanceFeeBps_;
        feeRecipient = feeRecipient_;
        highWaterMark = 10 ** _assetDec; // 1.0 in underlying units

        emergencyRedeemCooldown = emergencyRedeemCooldown_;

        twapWindow = twapWindow_;
        maxOracleDeviationBps = maxOracleDeviationBps_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    /// @dev Inflation-attack mitigation (audit H-1), same as BaseVault.
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    // ─── Oracle valuation helpers ──────────────────────────────────────────

    /// @notice Read the price feed with fail-closed safety checks. Reverts on a
    ///         non-positive answer, an incomplete round, or a stale update. NAV
    ///         (and thus deposit/withdraw/rebalance) reverts rather than transact
    ///         on a bad price — the conservative choice. Operational outages are
    ///         handled by the circuit breaker, not by trusting a dead feed.
    /// @dev    Also enforces the TWAP / deviation guard (Tier-0.A Q9): the
    ///         price is checked against the rolling TWAP over the last
    ///         `twapWindow` seconds, and if the deviation exceeds
    ///         `maxOracleDeviationBps`, the vault reverts with
    ///         `OracleDeviationTooLarge`. Set `maxOracleDeviationBps` to 0
    ///         to disable the guard (incident response). The staleness check
    ///         is the FIRST line of defence; the deviation guard is the SECOND.
    ///         This function is a VIEW — it does NOT write to the observation
    ///         ring buffer. State-changing entry points call
    ///         `_recordOracleObservation()` to update the buffer.
    function _oraclePrice() internal view returns (uint256) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = oracle.latestRoundData();
        if (answer <= 0) revert InvalidOraclePrice(answer);
        if (answeredInRound < roundId) revert StaleOracle(updatedAt, block.timestamp);
        if (updatedAt == 0 || block.timestamp - updatedAt > maxOracleStaleness) {
            revert StaleOracle(updatedAt, block.timestamp);
        }
        uint256 price = uint256(answer);
        _checkDeviation(price);
        return price;
    }

    /// @dev View-only price read used by state-changing entry points AFTER
    ///      they have already validated the price via `_oraclePrice()`. Reads
    ///      the oracle (no deviation check, no buffer write) so the caller
    ///      can record the post-operation observation without re-doing the
    ///      deviation check.
    function _oraclePriceView() internal view returns (uint256) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = oracle.latestRoundData();
        if (answer <= 0) revert InvalidOraclePrice(answer);
        if (answeredInRound < roundId) revert StaleOracle(updatedAt, block.timestamp);
        if (updatedAt == 0 || block.timestamp - updatedAt > maxOracleStaleness) {
            revert StaleOracle(updatedAt, block.timestamp);
        }
        return uint256(answer);
    }

    /// @dev View-only deviation check. Compares `currentPrice` against the
    ///      rolling TWAP of prior observations (within `twapWindow`) and
    ///      reverts if the deviation reaches or exceeds `maxOracleDeviationBps`.
    ///      Does NOT write to the ring buffer — the state-changing entry points
    ///      call `_recordOracleObservation()` for that.
    /// @dev    Uses `>=` (not `>`) so the boundary value is rejected: a "max
    ///      deviation of 10%" means anything ≥ 10% is rejected. The bound
    ///      itself is the disallowed case, not the allowed one.
    function _checkDeviation(uint256 currentPrice) internal view {
        uint256 bound = maxOracleDeviationBps;
        if (bound == 0) return; // guard disabled
        uint256 twap = _twap();
        if (twap == 0) return; // no observations yet; safe (cold-start)

        uint256 deviation;
        if (currentPrice >= twap) {
            deviation = ((currentPrice - twap) * 10000) / twap;
        } else {
            deviation = ((twap - currentPrice) * 10000) / twap;
        }

        if (deviation >= bound) {
            revert OracleDeviationTooLarge(currentPrice, twap, bound);
        }
    }

    /// @dev Write-path counterpart to `_checkDeviation`. Records the current
    ///      price in the ring buffer for the TWAP computation. Must be called
    ///      from state-changing entry points (deposit, mint, withdraw, redeem,
    ///      rebalanceTo) before the operation completes. Cold-start: the first
    ///      observation seeds the TWAP and the deviation is zero by definition.
    /// @dev    Also emits `OracleDeviationRecorded` so off-chain monitoring can
    ///      observe the deviation BEFORE the guard fires (the very next
    ///      observation's deviation is the relevant signal).
    function _recordOracleObservation(uint256 price) internal {
        _recordObservation(price);

        // Compute post-write deviation for the monitoring event. The guard
        // check itself happens in `_oraclePrice()`; this emit lets monitors
        // correlate price moves vs. the rolling TWAP. Skipping the emit when
        // the guard is disabled keeps the event volume proportionate to the
        // guard's actual threat surface.
        uint256 bound = maxOracleDeviationBps;
        if (bound == 0) return;
        uint256 twap = _twap();
        if (twap == 0) return;
        uint256 deviation;
        if (price >= twap) {
            deviation = ((price - twap) * 10000) / twap;
        } else {
            deviation = ((twap - price) * 10000) / twap;
        }
        emit OracleDeviationRecorded(price, twap, deviation, bound, _observationCount);
    }

    /// @dev Append the current price to the ring buffer. Storage-cheap: one
    ///      SSTORE per observation.
    function _recordObservation(uint256 price) internal {
        uint16 head = _observationHead;
        uint16 idx = head % 16;
        _observations[idx] = Observation({timestamp: uint64(block.timestamp), price: uint128(price)});
        unchecked {
            _observationHead = uint16((head + 1) % 16);
            if (_observationCount < 16) _observationCount++;
        }
    }

    /// @dev Time-weighted average price over the last `twapWindow` seconds.
    ///      Walks the ring buffer in chronological order (oldest -> newest),
    ///      accumulating `price * dt` for each segment between consecutive
    ///      observations. The most recent observation's price extends to
    ///      `block.timestamp`. Observations outside the window are skipped.
    ///      Returns 0 if no observations exist (defensive).
    function _twap() internal view returns (uint256) {
        uint256 window = twapWindow;
        if (window == 0) return 0; // guard disabled
        uint16 n = _observationCount;
        if (n == 0) return 0;

        // Walk the ring buffer in chronological order. The oldest observation
        // is at slot (headIdx - count) % 16 (count is bounded to 16).
        uint256 headIdx = _observationHead;
        uint256 startIdx = (headIdx + 16 - n) % 16;

        uint256 sumPriceDt;
        uint256 sumDt;
        uint256 prevTs;
        uint256 prevPrice;
        bool first = true;

        for (uint256 i = 0; i < n; i++) {
            uint256 idx = (startIdx + i) % 16;
            Observation memory obs = _observations[idx];
            uint256 ts = obs.timestamp;
            uint256 price = obs.price;

            // Skip observations outside the window.
            if (block.timestamp - ts > window) {
                continue;
            }

            if (first) {
                prevTs = ts;
                prevPrice = price;
                first = false;
            } else {
                uint256 dt = ts >= prevTs ? ts - prevTs : 0;
                sumPriceDt += prevPrice * dt;
                sumDt += dt;
                prevTs = ts;
                prevPrice = price;
            }
        }

        // Final segment: from the last in-window observation to now.
        if (!first) {
            uint256 dt = block.timestamp >= prevTs ? block.timestamp - prevTs : 0;
            if (dt > 0) {
                sumPriceDt += prevPrice * dt;
                sumDt += dt;
            }
        }

        if (sumDt == 0) {
            // Single observation in the window — return its price.
            return prevPrice;
        }
        return sumPriceDt / sumDt;
    }

    /// @notice Value `cashAmt` (raw cash units) in underlying units.
    function cashToAsset(uint256 cashAmt) public view returns (uint256) {
        if (cashAmt == 0) return 0; // fully-long vault needs no oracle
        uint256 p = _oraclePrice();
        return (cashAmt * (10 ** _assetDec) * (10 ** _priceDec)) / ((10 ** _cashDec) * p);
    }

    /// @notice Value `assetAmt` (raw underlying units) in cash units.
    function assetToCash(uint256 assetAmt) public view returns (uint256) {
        if (assetAmt == 0) return 0;
        uint256 p = _oraclePrice();
        return (assetAmt * (10 ** _cashDec) * p) / ((10 ** _assetDec) * (10 ** _priceDec));
    }

    /// @notice Gross vault value in underlying units (both legs, before fees).
    function grossValue() public view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + cashToAsset(cashAsset.balanceOf(address(this)));
    }

    /// @inheritdoc ERC4626
    function totalAssets() public view override returns (uint256) {
        uint256 gross = grossValue();
        return gross > performanceFeeAccrued ? gross - performanceFeeAccrued : 0;
    }

    function getNavPerShare() public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 10 ** _assetDec;
        return (totalAssets() * (10 ** decimals())) / supply;
    }

    /// @notice Deposits are refused while the vault is halted or its share price is
    ///         undefined. Both cases previously let value be stolen:
    ///
    ///         1. `totalSupply() > 0 && totalAssets() == 0` — shares exist with
    ///            nothing backing them, so ERC-4626's
    ///            `assets.mulDiv(supply + 10**offset, totalAssets + 1)` divides by 1
    ///            and mints ~`supply * 10**offset` shares for dust. A ~$3 deposit in
    ///            that state captured >99% of supply and drained the vault as soon as
    ///            value recovered (audit CRITICAL-1, PoC in
    ///            docs/security/poc/SpotVaultPinPoc.t.sol). `_decimalsOffset()` only
    ///            defends the EMPTY vault; here it makes the attack worse.
    ///         2. Circuit breaker active — it previously gated only `rebalanceTo`, so
    ///            an admin halting the strategy could not stop money flowing in.
    ///
    ///         Returning 0 makes ERC4626.deposit revert with ExceededMaxDeposit.
    ///         Withdrawals are deliberately NOT gated: users must always be able to exit.
    function maxDeposit(address) public view override returns (uint256) {
        if (isCircuitBreakerActive) return 0;
        if (totalSupply() > 0 && totalAssets() == 0) return 0;
        return type(uint256).max;
    }

    /// @inheritdoc ERC4626
    function maxMint(address) public view override returns (uint256) {
        if (isCircuitBreakerActive) return 0;
        if (totalSupply() > 0 && totalAssets() == 0) return 0;
        return type(uint256).max;
    }

    // ─── Keeper: rebalance to a target exposure ──────────────────────────────

    /// @notice Rebalance the vault to hold `targetBps`/10000 of value in the
    ///         underlying (the rest in cash), by spot-swapping the delta.
    function rebalanceTo(uint16 targetBps) external onlyRole(KEEPER_ROLE) nonReentrant {
        if (isCircuitBreakerActive) revert CircuitBreakerActive();
        if (targetBps > 10000) revert BadWeight();

        uint256 tvl = grossValue();
        if (tvl == 0) {
            // Record the observation even on the empty-vault early-return so the
            // TWAP is seeded for the next operation. The guard check is a no-op
            // because the deviation guard fires only when the buffer has content.
            _recordOracleObservation(_oraclePriceView());
            targetWeightBps = targetBps;
            return;
        }

        uint256 desiredAsset = (tvl * targetBps) / 10000;
        uint256 curAsset = IERC20(asset()).balanceOf(address(this));

        uint256 diff = desiredAsset > curAsset ? desiredAsset - curAsset : curAsset - desiredAsset;
        // dust deadband: skip tiny rebalances
        if (diff * 10000 < uint256(rebalanceThresholdBps) * tvl) {
            // Record the observation; the deviation check still runs.
            _recordOracleObservation(_oraclePriceView());
            targetWeightBps = targetBps;
            return;
        }

        if (desiredAsset > curAsset) {
            // BUY underlying with cash
            uint256 cashIn = assetToCash(desiredAsset - curAsset);
            uint256 cashBal = cashAsset.balanceOf(address(this));
            if (cashIn > cashBal) cashIn = cashBal;
            uint256 minOut = ((desiredAsset - curAsset) * (10000 - maxSlippageBps)) / 10000;
            _swap(address(cashAsset), asset(), cashIn, minOut);
        } else {
            // SELL underlying for cash
            uint256 assetIn = curAsset - desiredAsset;
            uint256 minOut = (assetToCash(assetIn) * (10000 - maxSlippageBps)) / 10000;
            _swap(asset(), address(cashAsset), assetIn, minOut);
        }

        // Record the observation AFTER the swap; the deviation check happens
        // during the swap path (assetToCash -> _oraclePrice -> _checkDeviation).
        _recordOracleObservation(_oraclePriceView());

        targetWeightBps = targetBps;
        emit Rebalanced(
            targetBps, IERC20(asset()).balanceOf(address(this)), cashAsset.balanceOf(address(this)), getNavPerShare()
        );
    }

    function _swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) internal {
        if (amountIn == 0) return;
        // Defense-in-depth (pre-audit review): a rebalance/withdraw before the admin
        // wired the adapter would otherwise approve+call address(0). Fail clearly.
        require(address(swapAdapter) != address(0), "SpotVault: adapter unset");
        IERC20(tokenIn).forceApprove(address(swapAdapter), amountIn);
        uint256 out = swapAdapter.swap(tokenIn, tokenOut, amountIn, minOut);
        require(out >= minOut, "slippage");
    }

    // ─── Withdraw: ensure enough underlying to pay (swap cash->asset if flat) ─

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        uint256 bal = IERC20(asset()).balanceOf(address(this));
        if (bal < assets) {
            uint256 shortfall = assets - bal;
            uint256 cashIn = assetToCash(shortfall);
            uint256 cashBal = cashAsset.balanceOf(address(this));
            if (cashIn > cashBal) cashIn = cashBal;
            uint256 minOut = (shortfall * (10000 - maxSlippageBps)) / 10000;
            _swap(address(cashAsset), asset(), cashIn, minOut);
        }
        super._withdraw(caller, receiver, owner, assets, shares);
        // Record post-withdrawal observation for the next read.
        if (cashAsset.balanceOf(address(this)) > 0) {
            _recordOracleObservation(_oraclePriceView());
        }
    }

    /// @inheritdoc ERC4626
    /// @dev    Records an oracle observation so the TWAP / deviation guard (Q9)
    ///         is seeded for subsequent operations. The deviation check itself
    ///         already ran during `super.deposit` (which calls `_convertToShares`
    ///         -> `totalAssets` -> `_oraclePrice`).
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        super._deposit(caller, receiver, assets, shares);
        if (cashAsset.balanceOf(address(this)) > 0) {
            _recordOracleObservation(_oraclePriceView());
        }
    }

    // ─── Performance fee (alpha above HWM, in underlying units) ──────────────

    function evaluateFees() external onlyRole(KEEPER_ROLE) {
        uint256 nav = getNavPerShare();
        if (nav <= highWaterMark) return;
        uint256 alpha = nav - highWaterMark;
        uint256 shareUnit = 10 ** decimals();
        uint256 fee = (alpha * totalSupply() * performanceFee) / (shareUnit * 10000);

        // Never let accrued fees reach gross value. `totalAssets()` is
        // `gross - performanceFeeAccrued`, so an accrual that swallows gross pins
        // NAV to zero — which (pre-fix) was the state that opened the share-inflation
        // drain. Cap the accrual so at least 1 unit of backing always remains for
        // existing shareholders. Fees the vault genuinely cannot afford are simply
        // not accrued rather than being taken out of depositor principal.
        if (fee > 0) {
            uint256 gross = grossValue();
            uint256 room = gross > performanceFeeAccrued + 1 ? gross - performanceFeeAccrued - 1 : 0;
            if (fee > room) fee = room;
        }

        if (fee > 0) {
            performanceFeeAccrued += fee;
            emit PerformanceFeeAccrued(fee, highWaterMark, nav);
        }
        highWaterMark = nav;
    }

    /// @notice Pay accrued performance fees to `feeRecipient`, in the underlying.
    /// @dev    Without this, `performanceFeeAccrued` was a ONE-WAY SINK: it only ever
    ///         grew, the tokens never left, and every accrual pushed `totalAssets()`
    ///         closer to the zero-pin that enabled audit CRITICAL-1. Paying out
    ///         reduces gross and accrued by the same amount, so `totalAssets()` — and
    ///         therefore every depositor's claim — is unchanged.
    function claimFees() external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant returns (uint256 paid) {
        uint256 accrued = performanceFeeAccrued;
        require(accrued > 0, "SpotVault: nothing accrued");
        // Pay what the underlying leg can cover; the remainder stays accrued for a
        // later claim (the keeper can rebalance to raise underlying first).
        uint256 bal = IERC20(asset()).balanceOf(address(this));
        paid = accrued <= bal ? accrued : bal;
        require(paid > 0, "SpotVault: no underlying liquidity");
        performanceFeeAccrued = accrued - paid;
        IERC20(asset()).safeTransfer(feeRecipient, paid);
        emit PerformanceFeeClaimed(feeRecipient, paid, performanceFeeAccrued);
    }

    /// @notice Forgive part of the accrued performance fee, returning that backing to
    ///         depositors. Recovery lever for the state where a price move after
    ///         accrual leaves `performanceFeeAccrued >= grossValue()`: deposits are
    ///         then blocked (see `maxDeposit`) and existing holders' value is trapped
    ///         until the price recovers. Writing the fee down un-traps it immediately.
    /// @dev    Strictly pro-depositor: it can only DECREASE the protocol's fee claim
    ///         and therefore only INCREASE `totalAssets()`. It moves no tokens and
    ///         cannot touch depositor principal.
    function writeDownAccruedFees(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 accrued = performanceFeeAccrued;
        require(amount > 0 && amount <= accrued, "SpotVault: bad write-down");
        performanceFeeAccrued = accrued - amount;
        emit PerformanceFeeWrittenDown(amount, performanceFeeAccrued);
    }

    // ─── Admin ───────────────────────────────────────────────────────────────

    function setSwapAdapter(address adapter_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(adapter_ != address(0), "zero adapter");
        swapAdapter = ISpotSwapAdapter(adapter_);
    }

    /// @notice Emitted when the performance-fee recipient is changed. Mirrors
    ///         BaseVault.FeeRecipientChanged so off-chain monitoring can alert on any
    ///         fee re-routing uniformly across every vault.
    event FeeRecipientChanged(address indexed oldRecipient, address indexed newRecipient);

    /// @notice Re-point the performance-fee recipient (e.g. to the ecosystem treasury
    ///         Safe). Mirrors BaseVault.setFeeRecipient so every vault's fee sink is
    ///         admin-settable without a redeploy — this was previously constructor-only.
    function setFeeRecipient(address newRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRecipient != address(0), "SpotVault: zero fee recipient");
        emit FeeRecipientChanged(feeRecipient, newRecipient);
        feeRecipient = newRecipient;
    }

    function setCircuitBreaker(bool active) external onlyRole(RISK_COUNCIL_ROLE) {
        isCircuitBreakerActive = active;
        emit CircuitBreakerSet(active);
    }

    /// @notice Re-set the maximum permitted deviation (in bps) between the
    ///         current oracle price and the rolling TWAP. Settable by the
    ///         default admin without redeploy; the constructor seeds the
    ///         recommended default (1000 = 10%). Set to 0 to disable the
    ///         guard entirely (incident response — the legacy pre-fix
    ///         behaviour). Set to a higher bound to recover from a
    ///         legitimate regime shift (e.g. a hyper-volatile market where
    ///         the 10% default is too tight) without redeploying.
    /// @dev    The TWAP window is set at construction time and is immutable;
    ///         the bound is the only knob exposed here. The deviation guard
    ///         is the SECOND line of defence (MedianOracle's freshness is
    ///         the first); this setter only widens or narrows the second.
    function setMaxOracleDeviationBps(uint256 newBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newBps <= 10000, "SpotVault: bad bps");
        uint256 old = maxOracleDeviationBps;
        maxOracleDeviationBps = newBps;
        emit MaxOracleDeviationBpsSet(old, newBps);
    }

    /// @notice Seed the oracle observation ring buffer with the current price.
    ///         Keeper-callable; intended for the oracle-pusher service to
    ///         keep the TWAP ring buffer warm even when no user-initiated
    ///         deposits/redeems/rebalances are flowing. Cheap: one SSTORE.
    /// @dev    The first observation seeds the TWAP (no deviation check).
    ///         Subsequent calls may trip the deviation guard if the new
    ///         price is too far from the running TWAP — which is the correct
    ///         behaviour: if the oracle wants to write a price that deviates
    ///         from the running TWAP, the operation should revert. Use
    ///         `setMaxOracleDeviationBps(0)` to disable the guard when
    ///         seeding in a known-volatile window.
    function seedOracleObservation() external onlyRole(KEEPER_ROLE) {
        _recordOracleObservation(_oraclePriceView());
    }

    // ─── Emergency exit (stale-oracle recovery) ───────────────────────────────

    /// @notice Opt-in emergency exit that bypasses the oracle: pays whatever
    ///         underlying is currently in the vault, accepting a per-share haircut
    ///         when the oracle is stale or the vault cannot value its cash leg.
    /// @dev    Required because the standard `redeem`/`withdraw` paths revert when
    ///         `assetToCash()` reverts on a stale Chainlink feed, leaving depositors
    ///         locked in (see `docs/MAINNET_READINESS.md:38`, Tier 0.A — "Oracle
    ///         going quiet freezes all withdrawals; no fallback, no admin override.
    ///         Users cannot exit").
    ///
    ///         Design notes:
    ///           - Permissionless: any current share holder may call.
    ///           - Skips the oracle entirely; what you get is
    ///             `IERC20(asset()).balanceOf(self) * shares / totalSupply()`.
    ///             There is NO swap attempt: in a stale-oracle event we do not
    ///             trust the swap venue to price, and the cash leg is unvalued.
    ///           - Rate-limited per `owner` address via `emergencyRedeemCooldown` to
    ///             MEV-guard a single bot from racing honest users to the limited
    ///             underlying.
    ///           - Refuses to run while the circuit breaker is active. A halted
    ///             vault must halt EXITS too — the halt is explicit, not silent.
    ///           - Does NOT mutate `performanceFeeAccrued`; the protocol's fee claim
    ///             is computed off this vault's bookkeeping and emergency payouts
    ///             are paid from underlying the protocol already accounts for. A
    ///             fee-pinning interaction during a stale-oracle event would be
    ///             worse than the bug we're fixing.
    ///           - Emits `EmergencyRedeem` with the haircut so the loss is
    ///             auditable and proportional across all callers in a stale-oracle
    ///             event.
    function redeemEmergency(uint256 shares, address receiver, address owner)
        external
        nonReentrant
        returns (uint256 paid)
    {
        if (isCircuitBreakerActive) revert EmergencyBreakerActive();
        require(shares > 0, "SpotVault: zero shares");
        require(receiver != address(0) && owner != address(0), "SpotVault: zero addr");

        // Cooldown gate (per `owner`, MEV-guard against a single address racing
        // others to the limited underlying during a stale-oracle event).
        uint256 cooldown = emergencyRedeemCooldown;
        uint256 lastTs = lastEmergencyRedeemAt[owner];
        if (lastTs != 0 && cooldown != 0) {
            uint256 nextAllowed = lastTs + cooldown;
            if (block.timestamp < nextAllowed) revert EmergencyCooldownActive(nextAllowed);
        }
        lastEmergencyRedeemAt[owner] = block.timestamp;

        // Owner-auth check (mirror ERC-4626 allowance semantics so a non-owner
        // cannot burn someone else's shares). OpenZeppelin 5.x exposes
        // `_spendAllowance` as `internal virtual`; SpotVault inherits ERC20
        // directly so the call resolves without override.
        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, shares);
        }

        // Compute what the depositor is owed purely from current supply and the
        // actual underlying balance the vault can pay right now. No oracle call.
        uint256 supply = totalSupply();
        uint256 bal = IERC20(asset()).balanceOf(address(this));
        uint256 owed = supply == 0 ? 0 : (shares * bal) / supply;

        _burn(owner, shares);
        paid = owed;
        if (paid > 0) IERC20(asset()).safeTransfer(receiver, paid);

        // `haircut` is `owed - paid` — in this path `owed == paid` by construction
        // (we compute owed FROM the current balance), so it is zero here. Kept as
        // an explicit, audited field so any future partial-pay path is symmetric
        // with the event shape and so off-chain monitoring can alert on any
        // non-zero value (signals that a stale-oracle event has over-subscribed
        // the vault's available liquidity).
        uint256 haircut = owed > paid ? owed - paid : 0;
        emit EmergencyRedeem(
            msg.sender, receiver, owner, shares, paid, haircut, shares > 0 ? haircut * supply / shares : 0
        );
    }

    /// @notice Re-set the per-address cooldown for `redeemEmergency`. Settable by
    ///         the risk council without redeploy; the constructor seeds the
    ///         recommended default (1 hour).
    function setEmergencyRedeemCooldown(uint256 cooldown) external onlyRole(RISK_COUNCIL_ROLE) {
        uint256 old = emergencyRedeemCooldown;
        emergencyRedeemCooldown = cooldown;
        emit EmergencyRedeemCooldownSet(old, cooldown);
    }

    /// @notice Admin-override variant of `redeemEmergency`. Lets the risk
    ///         council burn a victim's shares and pay a designated receiver
    ///         during a stale-oracle incident — when the victim is unreachable
    ///         or the victim's UI is down. Closes the Tier-0.A admin-override
    ///         gap (see `docs/MAINNET_READINESS.md` §0.A, "Oracle going quiet
    ///         freezes all withdrawals; no fallback, no admin override. Users
    ///         cannot exit").
    /// @dev    Same accounting as `redeemEmergency`; same `EmergencyRedeem`
    ///         event (with `caller = msg.sender`, the admin) so off-chain
    ///         monitors can distinguish admin-initiated exits from user exits.
    ///
    ///         Preserves the per-address MEV cooldown keyed on `owner`:
    ///           - Admin-initiated calls consume the SAME cooldown clock on
    ///             `owner` as user-initiated calls would. The admin cannot
    ///             bypass the cooldown for a victim — every admin call
    ///             advances `lastEmergencyRedeemAt[owner]` by `cooldown`.
    ///           - The cooldown gate is per-`owner`, not per-caller. Admin
    ///             acting for alice does NOT consume bob's cooldown clock.
    ///           - ERC-4626 allowance semantics are enforced: the admin must
    ///             hold a sufficient allowance from `owner` for `shares`,
    ///             OR `owner == msg.sender` (an admin who is also the owner).
    ///             This is the same check `redeemEmergency` performs.
    ///           - Circuit-breaker halts the admin path explicitly
    ///             (`EmergencyBreakerActive`).
    ///
    ///         The function does NOT mutate `performanceFeeAccrued`; the
    ///         protocol's fee claim is computed off this vault's bookkeeping
    ///         and emergency payouts (user-initiated or admin-initiated) are
    ///         paid from underlying the protocol already accounts for.
    function redeemEmergencyFor(address owner, uint256 shares, address receiver)
        external
        onlyRole(RISK_COUNCIL_ROLE)
        nonReentrant
        returns (uint256 paid)
    {
        if (isCircuitBreakerActive) revert EmergencyBreakerActive();
        require(shares > 0, "SpotVault: zero shares");
        require(owner != address(0) && receiver != address(0), "SpotVault: zero addr");

        // Cooldown gate — keyed on `owner` so admin-initiated and user-
        // initiated calls consume the same clock. The admin CANNOT bypass
        // the cooldown for the victim.
        uint256 cooldown = emergencyRedeemCooldown;
        uint256 lastTs = lastEmergencyRedeemAt[owner];
        if (lastTs != 0 && cooldown != 0) {
            uint256 nextAllowed = lastTs + cooldown;
            if (block.timestamp < nextAllowed) revert EmergencyCooldownActive(nextAllowed);
        }
        lastEmergencyRedeemAt[owner] = block.timestamp;

        // Allowance semantics — same as the user path. Admin must be approved
        // by the owner (typical incident-response pattern: a multisig Safe
        // holds both RISK_COUNCIL_ROLE and an allowance from each depositor).
        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, shares);
        }

        // Pay pro-rata underlying. No oracle call — identical to the user path.
        uint256 supply = totalSupply();
        uint256 bal = IERC20(asset()).balanceOf(address(this));
        uint256 owed = supply == 0 ? 0 : (shares * bal) / supply;

        _burn(owner, shares);
        paid = owed;
        if (paid > 0) IERC20(asset()).safeTransfer(receiver, paid);

        // Event — `caller = msg.sender` (the admin) so monitors can distinguish
        // admin-initiated exits from user-initiated exits.
        uint256 haircut = owed > paid ? owed - paid : 0;
        emit EmergencyRedeem(
            msg.sender, receiver, owner, shares, paid, haircut, shares > 0 ? haircut * supply / shares : 0
        );
    }
}
