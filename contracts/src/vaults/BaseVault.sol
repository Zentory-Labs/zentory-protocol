// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IVault} from "./IVault.sol";
import {IFeeDistributor} from "../interfaces/IFeeDistributor.sol";
import {IZENTStaking} from "../interfaces/IZENTStaking.sol";

/// @title BaseVault
/// @notice ERC-4626 benchmark-denominated vault. Depositors receive vault shares (e.g. zBTC)
///         representing proportional ownership of the vault's underlying asset.
///         Performance fee is charged only on alpha above the HODL baseline (NAV > high-water mark).
///         All risk rails are immutable constants — adjustable only via DAO governance.
contract BaseVault is ERC4626, AccessControl, IVault {
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

    // ─── ERC4626 Overrides ─────────────────────────────────────────────────

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
    function totalAssets() public view override(ERC4626, IVault) returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) - performanceFeeAccrued;
    }

    /// @inheritdoc IVault
    function getNavPerShare() public view returns (uint256) {
        uint256 supply = totalSupply();
        // slither-disable-next-line incorrect-equality
        if (supply == 0) return lastNavPerShare;
        uint256 assetUnit = 10 ** IERC20Metadata(asset()).decimals();
        return (totalAssets() * assetUnit) / supply;
    }

    // ─── Performance Fee ───────────────────────────────────────────────────

    function evaluateFees() external {
        uint256 nav = getNavPerShare();
        uint256 hwm = highWaterMark;

        if (nav <= hwm) {
            lastNavPerShare = nav;
            return;
        }

        uint256 alpha = nav - hwm;
        uint256 assetUnit = 10 ** IERC20Metadata(asset()).decimals();
        uint256 fee = (alpha * totalSupply() * performanceFee) / (assetUnit * 10000);

        if (fee > 0) {
            performanceFeeAccrued += fee;
            emit PerformanceFeeAccrued(fee, lastNavPerShare, nav);
        }

        highWaterMark = nav;
        lastNavPerShare = nav;
    }

    function claimFees() external returns (uint256 claimed) {
        claimed = performanceFeeAccrued;
        require(claimed > 0, "No fees to claim");
        performanceFeeAccrued = 0;

        address recipient = feeRecipient;
        if (recipient.code.length > 0) {
            IERC20(asset()).forceApprove(recipient, claimed);
            IFeeDistributor(recipient).accumulate(address(this), claimed);
        } else {
            IERC20(asset()).safeTransfer(recipient, claimed);
        }
    }

    function setFeeRecipient(address newRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRecipient != address(0), "BaseVault: zero fee recipient");
        feeRecipient = newRecipient;
    }

    function setStaking(address staking_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(staking_ != address(0), "BaseVault: zero staking");
        require(address(staking) == address(0), "BaseVault: staking already set");
        staking = IZENTStaking(staking_);
    }

    // ─── Keeper: Trade Execution ───────────────────────────────────────────

    function recordTrade(int8 direction, uint256 size, uint256 entryPrice) external onlyRole(KEEPER_ROLE) {
        require(direction == int8(1) || direction == int8(-1) || direction == int8(0), "Invalid direction");
        require(entryPrice > 0, "Invalid entry price");
        require(!isCircuitBreakerActive, "Circuit breaker active");

        uint256 tvl = totalAssets();
        if (tvl > 0) {
            uint256 maxSize = (tvl * maxPositionSizeBPS) / 10000;
            require(size <= maxSize, "Position size exceeds limit");
        }

        currentDirection = direction;
        currentPositionSize = size;
        currentEntryPrice = entryPrice;

        tradeHistory.push(
            Trade({direction: direction, size: size, entryPrice: entryPrice, timestamp: block.timestamp, closed: false})
        );

        emit TradeExecuted(direction, size, entryPrice, block.timestamp);
    }

    function closePosition() external onlyRole(KEEPER_ROLE) {
        currentDirection = int8(0);
        currentPositionSize = 0;
        currentEntryPrice = 0;
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

    /// @inheritdoc IVault
    function isKeeper(address caller) external view returns (bool) {
        return hasRole(KEEPER_ROLE, caller);
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IVault).interfaceId;
    }
}
