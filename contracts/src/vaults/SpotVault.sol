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

    IERC20 public immutable cashAsset;              // e.g. USDC
    AggregatorV3Interface public immutable oracle;  // underlying/USD
    uint256 public immutable maxOracleStaleness;    // seconds; reverts if feed older
    ISpotSwapAdapter public swapAdapter;

    uint8 internal immutable _assetDec;
    uint8 internal immutable _cashDec;
    uint8 internal immutable _priceDec;

    uint16 public targetWeightBps;              // 0..10000 (last commanded exposure)
    uint16 public immutable rebalanceThresholdBps; // dust deadband
    uint16 public immutable maxSlippageBps;
    uint256 public immutable performanceFee;    // bps of alpha above HWM
    uint256 public highWaterMark;
    /// @notice DEPRECATED under Tier 0 Q10 per-depositor HWM equalization
    ///         (audit finding #6). Performance fees are now captured as
    ///         fee-share dilution to the fee recipient, not as an
    ///         idle-balance deduction. The storage slot is retained so
    ///         existing off-chain indexers continue to compile / query the
    ///         field, but it is always zero in normal operation. New code
    ///         MUST NOT depend on it; use `feeRecipient`'s share balance
    ///         via `balanceOf(feeRecipient)` instead.
    uint256 public performanceFeeAccrued;
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

    error CircuitBreakerActive();
    error BadWeight();
    error StaleOracle(uint256 updatedAt, uint256 nowTs);
    error InvalidOraclePrice(int256 answer);
    error EmergencyBreakerActive();
    error EmergencyCooldownActive(uint256 nextAllowedAt);

    /// @param emergencyRedeemCooldown_ seconds between successive `redeemEmergency`
    ///        calls per `owner` address. Settable later via
    ///        `setEmergencyRedeemCooldown` (RISK_COUNCIL_ROLE). Recommended default
    ///        is 1 hour (3600) — long enough to deter MEV racing during a stale
    ///        oracle event, short enough that honest users are not inconvenienced
    ///        through a multi-hour outage.
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
        uint256 emergencyRedeemCooldown_
    ) ERC20(name_, symbol_) ERC4626(IERC20(asset_)) {
        require(asset_ != address(0) && cashAsset_ != address(0) && oracle_ != address(0), "zero addr");
        require(feeRecipient_ != address(0) && admin_ != address(0), "zero addr");
        require(rebalanceThresholdBps_ <= 10000 && maxSlippageBps_ <= 10000 && performanceFeeBps_ <= 10000, "bad bps");
        require(maxOracleStaleness_ > 0, "zero staleness");

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
    function _oraclePrice() internal view returns (uint256) {
        (uint80 roundId, int256 answer, , uint256 updatedAt, uint80 answeredInRound) =
            oracle.latestRoundData();
        if (answer <= 0) revert InvalidOraclePrice(answer);
        if (answeredInRound < roundId) revert StaleOracle(updatedAt, block.timestamp);
        if (updatedAt == 0 || block.timestamp - updatedAt > maxOracleStaleness) {
            revert StaleOracle(updatedAt, block.timestamp);
        }
        return uint256(answer);
    }

    /// @notice Value `cashAmt` (raw cash units) in underlying units.
    function cashToAsset(uint256 cashAmt) public view returns (uint256) {
        if (cashAmt == 0) return 0;   // fully-long vault needs no oracle
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
        // Tier 0 Q10 (per-depositor HWM equalization): the performance fee is
        // now captured as a SHARE DILUTION to the fee recipient, not as an
        // idle-balance deduction. Performance fees appear in the fee
        // recipient's share balance (`balanceOf(feeRecipient)`); subtracting
        // `performanceFeeAccrued` here would double-charge the dilution path
        // and break the per-depositor invariant.
        //
        // `grossValue()` already includes both legs (underlying + cash
        // valued through the oracle). The fee claim is wholly separate.
        return gross;
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
        if (tvl == 0) { targetWeightBps = targetBps; return; }

        uint256 desiredAsset = (tvl * targetBps) / 10000;
        uint256 curAsset = IERC20(asset()).balanceOf(address(this));

        uint256 diff = desiredAsset > curAsset ? desiredAsset - curAsset : curAsset - desiredAsset;
        // dust deadband: skip tiny rebalances
        if (diff * 10000 < uint256(rebalanceThresholdBps) * tvl) {
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

        targetWeightBps = targetBps;
        emit Rebalanced(targetBps, IERC20(asset()).balanceOf(address(this)),
                        cashAsset.balanceOf(address(this)), getNavPerShare());
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

    // ─── Deposit / Withdraw: capture fee atomically + ensure enough underlying ──

    /// @notice Tier 0 Q10: capture any accrued perf fee BEFORE the new depositor's
    ///         shares are minted, so the incoming depositor is not included in
    ///         the supply the fee is captured against.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        override
    {
        _captureFee();
        super._deposit(caller, receiver, assets, shares);
    }

    /// @notice Tier 0 Q10: capture any accrued perf fee BEFORE the outgoing
    ///         owner's shares are burned, so the just-burned supply is not
    ///         included in any subsequent fee calculation.
    /// @dev    The SpotVault-specific body (swap cash -> asset if the leg
    ///         has fallen short) is preserved unchanged beneath the fee call,
    ///         so the MTM math and the fee capture compose correctly: the
    ///         swap moves underlying INTO the vault from the cash leg if the
    ///         requested redemption would otherwise under-pay. With the
    ///         Q10 share-dilution fix, the swap no longer has to "add back"
    ///         performanceFeeAccrued - the fee claim lives in shares.
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        _captureFee();
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
    }

    // ─── Performance fee (alpha above HWM, Tier 0 Q10: per-depositor HWM) ────────

    /// @notice Emitted on every fee-share mint. Same shape as BaseVault's
    ///         FeeSharesMinted so off-chain monitors can correlate.
    event FeeSharesMinted(
        address indexed feeRecipient, uint256 feeShares, uint256 feeAssetEquivalent, uint256 navPerShare
    );

    /// @dev    Tier 0 Q10 (audit finding #6): the performance fee is captured
    ///         as a SHARE DILUTION to the fee recipient, not as a `grossValue`
    ///         deduction. Late depositors used to be charged retroactively on
    ///         gains earned before they joined because the fee was computed
    ///         against the full post-deposit supply and subtracted from the
    ///         gross balance. With share dilution:
    ///
    ///         - The fee mints fee shares worth exactly 20% of the alpha
    ///           captured by the supply-outstanding at fee-assessment time.
    ///         - `totalAssets()` returns the gross balance with no fee
    ///           subtraction (the fee lives in shares, not in the balance).
    ///         - `evaluateFees()` is `public` (dropped `KEEPER_ROLE`); the
    ///           auto-trigger on deposit/withdraw keeps the HWM never-stale
    ///           regardless of keeper liveness.
    function evaluateFees() public {
        _captureFee();
    }

    /// @notice Internal helper: capture any accrued performance fee as share
    ///         dilution. Called from `evaluateFees()` and `deposit()` / `mint()`
    ///         / `_withdraw()`. MUST be called BEFORE any new share mint so
    ///         the new depositor is never included in the fee calc.
    function _captureFee() internal {
        uint256 nav = getNavPerShare();
        if (nav <= highWaterMark) return;

        uint256 alpha = nav - highWaterMark;
        // Fee shares: see BaseVault._captureFee() for the full derivation.
        // Same formula applies here (asset-units cancel in shareUnit / nav).
        uint256 feeShares = (alpha * totalSupply() * performanceFee) / (nav * 10000);

        if (feeShares > 0) {
            _mint(feeRecipient, feeShares);

            // Diagnostic: how much the fee shares are worth at `nav`.
            uint256 shareUnit = 10 ** decimals();
            uint256 feeAsset = (feeShares * nav) / shareUnit;
            emit FeeSharesMinted(feeRecipient, feeShares, feeAsset, nav);
        }

        highWaterMark = nav;
    }

    /// @notice Redeem ALL of the fee recipient's accrued fee shares back to
    ///         underlying. Replaces the legacy `claimFees()` that paid out
    ///         the `performanceFeeAccrued` pool. Under the new design the
    ///         fee is in shares, so the natural way to "take the fee as cash"
    ///         is to redeem those shares.
    function claimFees()
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
        returns (uint256 paid)
    {
        uint256 feeShares = balanceOf(feeRecipient);
        require(feeShares > 0, "SpotVault: nothing accrued");

        // Compute redemption value out-of-band: burn shares first, then
        // pro-rate the underlying by the post-burn denominator. This
        // matches the OZ ERC4626 redemption math with rounding absorbed
        // by the protocol (depositors are not affected either way).
        uint256 supply = totalSupply();
        uint256 bal = IERC20(asset()).balanceOf(address(this));
        paid = supply == 0 ? 0 : (feeShares * bal) / supply;

        _burn(feeRecipient, feeShares);
        if (paid > 0) {
            IERC20(asset()).safeTransfer(feeRecipient, paid);
        }
        emit PerformanceFeeClaimed(feeRecipient, paid, balanceOf(feeRecipient));
    }

    /// @notice Forgive part of the fee recipient's fee shares, returning that
    ///         backing to depositors. Recovery lever for pinned-redeem
    ///         states (see `maxDeposit`). Under the new design, "writing
    ///         down" means burning that many of the fee recipient's
    ///         shares - strictly pro-depositor (it can only DECREASE the
    ///         protocol's fee claim and therefore only INCREASE
    ///         `totalAssets()` for the remaining holders).
    function writeDownAccruedFees(uint256 sharesToBurn)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 feeShares = balanceOf(feeRecipient);
        require(sharesToBurn > 0 && sharesToBurn <= feeShares, "SpotVault: bad write-down");
        _burn(feeRecipient, sharesToBurn);
        emit PerformanceFeeWrittenDown(sharesToBurn, balanceOf(feeRecipient));
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
            msg.sender,
            receiver,
            owner,
            shares,
            paid,
            haircut,
            shares > 0 ? haircut * supply / shares : 0
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
}
