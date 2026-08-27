// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IVault} from "./IVault.sol";
import {IFeeDistributor} from "../interfaces/IFeeDistributor.sol";
import {IZENTStaking} from "../interfaces/IZENTStaking.sol";

/// @title BaseVault
/// @notice ERC-4626 benchmark-denominated vault. Depositors receive vault shares (e.g. zBTC)
///         representing proportional ownership of the vault's underlying asset.
///         Performance fee is charged only on alpha above the HODL baseline (NAV > high-water mark).
///         All risk rails are immutable constants — adjustable only via DAO governance.
contract BaseVault is ERC4626, AccessControl, ReentrancyGuard, IVault {
    using SafeERC20 for IERC20;

    // ─── Roles ───────────────────────────────────────────────────────────────
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant RISK_COUNCIL_ROLE = keccak256("RISK_COUNCIL_ROLE");

    // ─── Immutable Risk Rails ──────────────────────────────────────────────
    uint256 public immutable override maxLeverage;
    uint256 public immutable maxPositionSizeBPS;
    uint256 public immutable circuitBreakerDrawdownBPS;
    uint256 public immutable rebalanceThresholdBPS;

    // ─── State ──────────────────────────────────────────────────────────────
    uint256 public override highWaterMark;
    uint256 public override lastNavPerShare;
    uint256 public immutable override performanceFee;
    /// @inheritdoc IVault
    address public override feeRecipient;
    IZENTStaking public staking;
    uint256 public performanceFeeAccrued;
    bool public override isCircuitBreakerActive;
    int8 public override currentDirection;

    /// @notice Latest mark price (asset units, in the same decimals as the underlying)
    ///         reported by the keeper from the off-EVM venue (e.g. Hyperliquid order book).
    ///         `totalAssets()` values the open position against `currentMarkPrice` so NAV
    ///         reflects live PnL. Defaults to `currentEntryPrice` so a fresh, never-updated
    ///         vault reports 0 PnL rather than a fictitious mark.
    uint256 public currentMarkPrice;

    // ─── Events ───────────────────────────────────────────────────────────

    /// @notice Emitted when the circuit breaker is automatically triggered by checkCircuitBreaker().
    event CircuitBreakerAutoTriggered(uint256 drawdownBPS, uint256 thresholdBPS);

    /// @notice Emitted when a keeper closes the current vault position.
    event PositionClosed();

    /// @notice Emitted on every `redeemEmergency` call. Mirrors SpotVault's
    ///         event shape so off-chain monitoring can alert on any non-zero
    ///         `haircutAssets` (a stale-oracle / unsettled-PnL event in progress).
    event EmergencyRedeem(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 sharesBurned,
        uint256 paid,
        uint256 haircutAssets,
        uint256 haircutPerShare
    );

    /// @notice Reverted from `redeemEmergency` when the vault's circuit breaker
    ///         is active. Halt must halt EXITS too — the halt is explicit, not silent.
    error EmergencyBreakerActive();

    // ─── Trade Log ─────────────────────────────────────────────────────────
    struct Trade {
        int8 direction;
        uint256 size;
        uint256 entryPrice;
        uint256 timestamp;
        bool closed;
    }

    Trade[] public tradeHistory;
    uint256 public currentPositionSize;
    uint256 public currentEntryPrice;

    // ─── Constructor ───────────────────────────────────────────────────────
    constructor(
        address asset_,
        string memory name_,
        string memory symbol_,
        uint256 maxLeverage_,
        uint256 maxPositionSizeBPS_,
        uint256 circuitBreakerDrawdownBPS_,
        uint256 rebalanceThresholdBPS_,
        uint256 performanceFeeBPS_,
        address feeRecipient_,
        address admin_
    ) ERC20(name_, symbol_) ERC4626(IERC20(_validateAsset(asset_))) {
        require(feeRecipient_ != address(0), "BaseVault: zero fee recipient");
        require(admin_ != address(0), "BaseVault: zero admin");
        require(maxPositionSizeBPS_ <= 10000, "BaseVault: invalid position limit");
        require(circuitBreakerDrawdownBPS_ <= 10000, "BaseVault: invalid drawdown");
        require(rebalanceThresholdBPS_ <= 10000, "BaseVault: invalid rebalance threshold");
        require(performanceFeeBPS_ <= 10000, "BaseVault: invalid performance fee");

        maxLeverage = maxLeverage_;
        maxPositionSizeBPS = maxPositionSizeBPS_;
        circuitBreakerDrawdownBPS = circuitBreakerDrawdownBPS_;
        rebalanceThresholdBPS = rebalanceThresholdBPS_;
        performanceFee = performanceFeeBPS_;
        feeRecipient = feeRecipient_;

        uint256 assetUnit = 10 ** IERC20Metadata(asset_).decimals();
        lastNavPerShare = assetUnit;
        highWaterMark = assetUnit;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    function _validateAsset(address asset_) private pure returns (address) {
        require(asset_ != address(0), "BaseVault: zero asset");
        return asset_;
    }

    // ─── Inflation-Attack Mitigation ───────────────────────────────────────
    /// @notice Decimals offset between shares and underlying asset.
    /// @dev    OpenZeppelin's ERC4626 default of 0 leaves the first-depositor
    ///         "donation" inflation attack open. Returning 6 multiplies the
    ///         attacker's required donation by 10^6, making the attack
    ///         economically unviable on every supported underlying. Paired
    ///         with the seed-via-deposit() invariant in MainnetDeployVaults,
    ///         this closes the inflation-attack vector.
    ///         See https://docs.openzeppelin.com/contracts/5.x/erc4626#inflation-attack
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    // ─── ERC4626 Overrides ─────────────────────────────────────────────────

    /// @dev Mirror SpotVault's guard: refuse deposits when the vault is halted
    ///      (we already gate deposit itself with `onlyWhenCircuitBreakerInactive`)
    ///      or when existing shareholders' shares are unbacked (NAV = 0 with
    ///      supply > 0). Returning 0 here makes the ERC-4626 standard library's
    ///      `deposit`/`mint` paths revert cleanly with `ERC4626ExceededMaxDeposit`.
    ///      See SpotVault.maxDeposit docstring (audit CRITICAL-1 follow-up).
    function maxDeposit(address) public view override returns (uint256) {
        if (isCircuitBreakerActive) return 0;
        if (totalSupply() > 0 && totalAssets() == 0) return 0;
        return type(uint256).max;
    }

    function maxMint(address) public view override returns (uint256) {
        if (isCircuitBreakerActive) return 0;
        if (totalSupply() > 0 && totalAssets() == 0) return 0;
        return type(uint256).max;
    }

    function deposit(uint256 assets, address receiver)
        public
        override
        onlyWhenCircuitBreakerInactive
        returns (uint256)
    {
        IZENTStaking staking_ = staking;
        if (address(staking_) != address(0)) {
            require(staking_.hasAccess(receiver), "BaseVault: stake required");
        }
        uint256 balanceBefore = IERC20(asset()).balanceOf(address(this));
        uint256 shares = super.deposit(assets, receiver);
        // The vault intentionally rejects fee-on-transfer or rebasing assets.
        // slither-disable-next-line incorrect-equality
        require(IERC20(asset()).balanceOf(address(this)) - balanceBefore == assets, "BaseVault: unsupported asset");
        return shares;
    }

    function mint(uint256 shares, address receiver) public override onlyWhenCircuitBreakerInactive returns (uint256) {
        IZENTStaking staking_ = staking;
        if (address(staking_) != address(0)) {
            require(staking_.hasAccess(receiver), "BaseVault: stake required");
        }
        uint256 balanceBefore = IERC20(asset()).balanceOf(address(this));
        uint256 assets = previewMint(shares);
        uint256 mintedShares = super.mint(shares, receiver);
        // The vault intentionally rejects fee-on-transfer or rebasing assets.
        // slither-disable-next-line incorrect-equality
        require(IERC20(asset()).balanceOf(address(this)) - balanceBefore == assets, "BaseVault: unsupported asset");
        return mintedShares;
    }

    modifier onlyWhenCircuitBreakerInactive() {
        require(!isCircuitBreakerActive, "Circuit breaker active");
        _;
    }

    /// @inheritdoc IVault
    /// @dev    NAV (settle-able) = idle balance − accrued performance fees. The
    ///         off-EVM perp position's mark-to-market PnL is intentionally
    ///         EXCLUDED here. Audit Critical-1 fix: previously `totalAssets()`
    ///         valued the open position against `currentMarkPrice`, inflating
    ///         share value by unrealized PnL that the contract could never pay
    ///         out. That allowed honest depositors (no attacker required) to
    ///         withdraw more than the vault held — every profitable mark
    ///         silently drained the last redeemer's principal.
    ///
    ///         Mark-to-market is preserved as a *signal* via `_markToMarket()`
    ///         and `getNavPerShareViewOnly()`. The circuit breaker and keeper
    ///         risk views continue to react to live PnL (they MUST — otherwise
    ///         a -50% position would never trip the breaker), but no
    ///         ERC-4626 entrypoint that touches user funds ever sees it.
    ///         Only the IDLE balance is settle-able; only the idle balance is
    ///         real. SpotVault keeps its in-vault two-leg model and overrides
    ///         this hook implicitly via its own `totalAssets()`.
    function totalAssets() public view override(ERC4626, IVault) returns (uint256) {
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        return idle > performanceFeeAccrued ? idle - performanceFeeAccrued : 0;
    }

    /// @notice Mark-to-market NAV including off-EVM PnL. View-only — NOT used
    ///         by ERC-4626 math, withdraw, or redeem. Used by the circuit
    ///         breaker (`checkCircuitBreaker`) and keeper dashboards to see
    ///         live drawdowns. Returns 0 if the mark would be negative to
    ///         avoid wrapping signed-underflow in a `uint` return.
    function getNavPerShareViewOnly() public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 0;
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        int256 mtm = _markToMarket();
        int256 grossSigned = int256(idle) + mtm - int256(performanceFeeAccrued);
        uint256 gross = grossSigned > 0 ? uint256(grossSigned) : 0;
        return (gross * (10 ** decimals())) / supply;
    }

    /// @notice Signed mark-to-market of the open position in asset units (raw
    ///         decimals, same as the underlying). Positive when in-the-money,
    ///         negative when out-of-the-money, zero when flat or no mark set.
    /// @dev    Formula: `signed_size * (mark - entry) / mark`. `size` and price
    ///         are stored in different units (asset units vs. a price scale,
    ///         typically 10^8 USD). Converting USD PnL back to asset units
    ///         requires dividing by the price — using `mark` (not `entry`)
    ///         keeps the valuation current. The result is in asset units, so
    ///         it adds directly to the idle-balance NAV.
    ///         Subclasses may override; the default is safe to call at any
    ///         time and degrades gracefully when mark/entry haven't been set.
    function _markToMarket() internal view virtual returns (int256) {
        if (currentDirection == int8(0)) return int256(0);
        if (currentMarkPrice == 0 || currentEntryPrice == 0) return int256(0);
        if (currentPositionSize == 0) return int256(0);
        int256 size_ = int256(currentPositionSize);
        int256 entry = int256(currentEntryPrice);
        int256 mark = int256(currentMarkPrice);
        // pnl_asset = size * (mark - entry) / mark, signed by direction.
        // Multiplication is bounded by size * |mark - entry|; for any sane
        // position size and price delta this stays well within int256.
        int256 diff = mark - entry;
        return (size_ * diff) / mark * int256(currentDirection);
    }

    /// @notice Keeper pushes the latest off-EVM mark price. `totalAssets()`,
    ///         `getNavPerShare()`, and `checkCircuitBreaker()` will reflect the
    ///         updated PnL on the next view call.
    /// @param  markPrice  Latest mark in the same scale as `entryPrice` (asset
    ///         units, same decimals as the underlying). Must be > 0.
    function updateMarkPrice(uint256 markPrice) external onlyRole(KEEPER_ROLE) {
        require(markPrice > 0, "Invalid mark price");
        currentMarkPrice = markPrice;
    }

    /// @inheritdoc IVault
    /// @dev    NAV per share denominated in asset units, settle-able basis. With
    ///         `_decimalsOffset()` set to 6 (audit H-1 inflation-attack
    ///         mitigation), share decimals = asset decimals + 6. `shareUnit`
    ///         accounts for that offset so the "1 share" denominator matches the
    ///         actual ERC20 decimals of the share token, keeping NAV in asset-
    ///         unit terms exactly as before the offset was introduced.
    ///
    ///         IMPORTANT: this returns the SETTLE-ABLE NAV per share — i.e. the
    ///         amount of underlying each share is actually entitled to at this
    ///         instant, excluding off-EVM PnL. Use `getNavPerShareViewOnly()`
    ///         for live mark-to-market (circuit breaker / dashboards).
    function getNavPerShare() public view returns (uint256) {
        uint256 supply = totalSupply();
        // slither-disable-next-line incorrect-equality
        if (supply == 0) return lastNavPerShare;
        uint256 shareUnit = 10 ** decimals();
        return (totalAssets() * shareUnit) / supply;
    }

    // ─── Performance Fee ───────────────────────────────────────────────────

    function evaluateFees() external onlyRole(KEEPER_ROLE) {
        // HWM is tracked against the view-only (mark-to-market) NAV so fee
        // accrual captures alpha from off-EVM PnL once it materialises. Fee
        // math remains bounded by the SETTLE-ABLE totalAssets() so we never
        // accrue fees the vault cannot pay out (audit Critical-1 follow-up).
        uint256 nav = getNavPerShareViewOnly();
        if (nav == 0) nav = getNavPerShare();
        uint256 hwm = highWaterMark;

        if (nav <= hwm) {
            lastNavPerShare = nav;
            return;
        }

        uint256 alpha = nav - hwm;
        uint256 shareUnit = 10 ** decimals();
        uint256 fee = (alpha * totalSupply() * performanceFee) / (shareUnit * 10000);

        // Cap the accrual by what settle-able NAV can actually afford. Fees
        // the vault genuinely cannot pay (off-EVM PnL not yet settled) are
        // skipped rather than taken out of depositor principal. The HWM
        // still moves up — closing the future gap — so the protocol's
        // claim against future settled alpha is preserved.
        if (fee > 0) {
            uint256 room = totalAssets();
            if (fee > room) fee = room;
        }

        if (fee > 0) {
            performanceFeeAccrued += fee;
            emit PerformanceFeeAccrued(fee, lastNavPerShare, nav);
        }

        highWaterMark = nav;
        lastNavPerShare = nav;
    }

    function claimFees() external nonReentrant returns (uint256 claimed) {
        claimed = performanceFeeAccrued;
        require(claimed > 0, "No fees to claim");

        address recipient = feeRecipient;
        uint256 paid;

        // Compute the destination first; only zero `performanceFeeAccrued`
        // AFTER we know how the transfer succeeded. A failure mid-way (an
        // approve that reverts on a non-standard ERC20, a FeeDistributor
        // whose `accumulate` reverts) must not silently burn the accrued
        // fees — the next call would see `claimed = 0` and the protocol
        // would lose the revenue permanently.
        if (recipient.code.length > 0) {
            // Approval + accumulate may revert if `recipient` is not actually
            // an IFeeDistributor (e.g. setFeeRecipient was pointed at a
            // generic contract). In that case fall back to a direct ERC20
            // transfer so governance can fix the misconfiguration without
            // permanently burning the accrued fees.
            IERC20(asset()).forceApprove(recipient, claimed);
            try IFeeDistributor(recipient).accumulate(address(this), claimed) {
                paid = claimed;
            } catch {
                // Revoke the unused approval and pay the recipient directly.
                IERC20(asset()).forceApprove(recipient, 0);
                IERC20(asset()).safeTransfer(recipient, claimed);
                paid = claimed;
                emit FeeRecipientFallbackUsed(recipient, claimed);
            }
        } else {
            IERC20(asset()).safeTransfer(recipient, claimed);
            paid = claimed;
        }

        // Only zero the accounting after the transfer has settled.
        performanceFeeAccrued -= paid;
    }

    /// @notice Emitted when `claimFees` falls back to a direct ERC20 transfer
    ///         because the configured `feeRecipient` is a contract but is not
    ///         a working IFeeDistributor. Off-chain monitoring should alert
    ///         so governance can fix the misconfiguration (recipient was set
    ///         to a non-FeeDistributor contract address).
    event FeeRecipientFallbackUsed(address indexed recipient, uint256 amount);

    /// @notice Emitted when the performance-fee recipient is changed. Lets
    ///         off-chain monitoring alert on any admin/governance fee re-routing
    ///         (audit VAULT-4 observability gap).
    event FeeRecipientChanged(address indexed oldRecipient, address indexed newRecipient);

    function setFeeRecipient(address newRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRecipient != address(0), "BaseVault: zero fee recipient");
        emit FeeRecipientChanged(feeRecipient, newRecipient);
        feeRecipient = newRecipient;
    }

    function setStaking(address staking_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(staking_ != address(0), "BaseVault: zero staking");
        require(address(staking) == address(0), "BaseVault: staking already set");
        staking = IZENTStaking(staking_);
    }

    // ─── Keeper: Trade Execution ───────────────────────────────────────────

    function recordTrade(int8 direction, uint256 size, uint256 entryPrice)
        external
        onlyRole(KEEPER_ROLE)
        nonReentrant
    {
        require(direction == int8(1) || direction == int8(-1) || direction == int8(0), "Invalid direction");
        require(entryPrice > 0, "Invalid entry price");
        require(!isCircuitBreakerActive, "Circuit breaker active");

        uint256 tvl = totalAssets();
        if (tvl > 0) {
            uint256 maxSize = (tvl * maxPositionSizeBPS) / 10000;
            require(size <= maxSize, "Position size exceeds limit");
            // Leverage cap: a vault declared `maxLeverage = 3x` (30000 BPS)
            // must reject any recordTrade whose notional exceeds 3× NAV.
            // Previously `maxLeverage` was a dead immutable — exposed via the
            // IVault getter but never read in contract logic. Without this
            // check a keeper could open a 100x notional trade; the
            // StrategyExecutor's own `maxLeverageBPS` check does not catch
            // trades that go through the keeper-direct `recordTrade` path
            // (the executor's per-vault cap is per-keeper wiring, not a
            // vault-enforced invariant).
            uint256 maxNotional = (tvl * maxLeverage) / 10000;
            require(size <= maxNotional, "Leverage exceeds max");
        }

        currentDirection = direction;
        currentPositionSize = size;
        currentEntryPrice = entryPrice;
        // Mark defaults to entry until the keeper pushes the first off-EVM
        // mark — keeps the open leg's MTM at 0 instead of pinning to whatever
        // stale value happened to be left in storage.
        currentMarkPrice = entryPrice;

        tradeHistory.push(
            Trade({direction: direction, size: size, entryPrice: entryPrice, timestamp: block.timestamp, closed: false})
        );

        emit TradeExecuted(direction, size, entryPrice, block.timestamp);
    }

    function closePosition() external onlyRole(KEEPER_ROLE) nonReentrant {
        currentDirection = int8(0);
        currentPositionSize = 0;
        currentEntryPrice = 0;
        currentMarkPrice = 0;
        emit PositionClosed();
    }

    // ─── Risk Controls ─────────────────────────────────────────────────────

    function activateCircuitBreaker(string calldata reason) external onlyRole(RISK_COUNCIL_ROLE) {
        require(!isCircuitBreakerActive, "Already active");
        isCircuitBreakerActive = true;
        emit CircuitBreakerActivated(reason);
    }

    function deactivateCircuitBreaker() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isCircuitBreakerActive, "Not active");
        isCircuitBreakerActive = false;
    }

    /// @notice Automatically trigger the circuit breaker if the current NAV drawdown
    ///         from the high-water mark exceeds circuitBreakerDrawdownBPS.
    ///         Anyone can call this — it is not access-controlled — so keepers, keepers-of-last-resort,
    ///         or monitoring bots can trigger it without needing a role.
    /// @dev    Reads the VIEW-ONLY (mark-to-market) NAV so live off-EVM PnL
    ///         still trips the breaker. Settle-able NAV (used by withdraw)
    ///         cannot move the breaker — only signals can.
    function checkCircuitBreaker() external {
        if (isCircuitBreakerActive) return;

        uint256 hwm = highWaterMark;
        uint256 nav = getNavPerShareViewOnly();
        if (nav == 0) nav = getNavPerShare();
        if (nav >= hwm) return;

        uint256 drawdownBPS = ((hwm - nav) * 10000) / hwm;
        if (drawdownBPS >= circuitBreakerDrawdownBPS) {
            isCircuitBreakerActive = true;
            emit CircuitBreakerActivated("auto");
            emit CircuitBreakerAutoTriggered(drawdownBPS, circuitBreakerDrawdownBPS);
        }
    }

    /// @inheritdoc IVault
    function isKeeper(address caller) external view returns (bool) {
        return hasRole(KEEPER_ROLE, caller);
    }

    // ─── Emergency exit (stale-mark / unsettled-PnL recovery) ────────────

    /// @notice Opt-in emergency exit that pays whatever underlying the vault
    ///         currently holds, in proportion to shares, ignoring the off-EVM
    ///         position. Required because a stale-oracle / unsettled PnL state
    ///         can otherwise leave `totalAssets()` under-declared and honest
    ///         users locked in. Mirrors SpotVault.redeemEmergency — same
    ///         semantics, same haircut accounting.
    /// @dev    The haircut proportionally reduces `performanceFeeAccrued` so a
    ///         fee claim cannot later withdraw tokens that have already left
    ///         the vault via this path (audit H-1 hardening, see Berkay
    ///         Çarıkçıoğlu's SpotVault finding — same shape of bug, same
    ///         shape of fix).
    function redeemEmergency(uint256 shares, address receiver, address owner)
        external
        nonReentrant
        returns (uint256 paid)
    {
        if (isCircuitBreakerActive) revert EmergencyBreakerActive();
        require(shares > 0, "BaseVault: zero shares");
        require(receiver != address(0) && owner != address(0), "BaseVault: zero addr");

        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, shares);
        }

        uint256 supply = totalSupply();
        require(supply > 0, "BaseVault: empty vault");
        uint256 bal = IERC20(asset()).balanceOf(address(this));

        // What the depositor is owed under the documented share-supply rule,
        // minus the protocol's accrued fee share — both prorated to shares.
        uint256 grossOwed = (shares * bal) / supply;
        uint256 feeShare = (shares * performanceFeeAccrued) / supply;
        uint256 owed = grossOwed > feeShare ? grossOwed - feeShare : 0;

        _burn(owner, shares);
        // Clamp against rounding drift (see SpotVault.redeemEmergency — same
        // shape of fix). Solidity 0.8 would revert on underflow; dust stays
        // as protocol surplus.
        uint256 accrued = performanceFeeAccrued;
        if (feeShare > accrued) feeShare = accrued;
        performanceFeeAccrued = accrued - feeShare;
        paid = owed;
        if (paid > 0) IERC20(asset()).safeTransfer(receiver, paid);

        uint256 haircut = grossOwed > paid ? grossOwed - paid : 0;
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

    function supportsInterface(bytes4 interfaceId) public view override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IVault).interfaceId;
    }
}
