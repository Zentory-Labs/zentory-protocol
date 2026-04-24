// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IVault} from "./IVault.sol";

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
    uint256 public override maxLeverage;
    uint256 public maxPositionSizeBPS;
    uint256 public circuitBreakerDrawdownBPS;
    uint256 public rebalanceThresholdBPS;

    // ─── State ──────────────────────────────────────────────────────────────
    uint256 public override highWaterMark;
    uint256 public override lastNavPerShare;
    uint256 public override performanceFee;
    /// @inheritdoc IVault
    address public override feeRecipient;
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
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _maxLeverage,
        uint256 _maxPositionSizeBPS,
        uint256 _circuitBreakerDrawdownBPS,
        uint256 _rebalanceThresholdBPS,
        uint256 _performanceFeeBPS,
        address _feeRecipient,
        address _admin
    )
        ERC20(_name, _symbol)
        ERC4626(IERC20(
                _validateConstructorConfig(
                    _asset,
                    _maxPositionSizeBPS,
                    _circuitBreakerDrawdownBPS,
                    _rebalanceThresholdBPS,
                    _performanceFeeBPS,
                    _feeRecipient,
                    _admin
                )
            ))
        AccessControl()
    {
        maxLeverage = _maxLeverage;
        maxPositionSizeBPS = _maxPositionSizeBPS;
        circuitBreakerDrawdownBPS = _circuitBreakerDrawdownBPS;
        rebalanceThresholdBPS = _rebalanceThresholdBPS;
        performanceFee = _performanceFeeBPS;
        feeRecipient = _feeRecipient;

        uint256 assetUnit = 10 ** IERC20Metadata(_asset).decimals();
        lastNavPerShare = assetUnit;
        highWaterMark = assetUnit;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    function _validateConstructorConfig(
        address _asset,
        uint256 _maxPositionSizeBPS,
        uint256 _circuitBreakerDrawdownBPS,
        uint256 _rebalanceThresholdBPS,
        uint256 _performanceFeeBPS,
        address _feeRecipient,
        address _admin
    ) private pure returns (address) {
        require(_asset != address(0), "BaseVault: zero asset");
        require(_feeRecipient != address(0), "BaseVault: zero fee recipient");
        require(_admin != address(0), "BaseVault: zero admin");
        require(_maxPositionSizeBPS <= 10000, "BaseVault: invalid position limit");
        require(_circuitBreakerDrawdownBPS <= 10000, "BaseVault: invalid drawdown");
        require(_rebalanceThresholdBPS <= 10000, "BaseVault: invalid rebalance threshold");
        require(_performanceFeeBPS <= 10000, "BaseVault: invalid performance fee");
        return _asset;
    }

    // ─── ERC4626 Overrides ─────────────────────────────────────────────────

    function deposit(uint256 assets, address receiver)
        public
        override
        onlyWhenCircuitBreakerInactive
        returns (uint256)
    {
        uint256 balanceBefore = IERC20(asset()).balanceOf(address(this));
        uint256 shares = super.deposit(assets, receiver);
        require(IERC20(asset()).balanceOf(address(this)) - balanceBefore == assets, "BaseVault: unsupported asset");
        return shares;
    }

    function mint(uint256 shares, address receiver) public override onlyWhenCircuitBreakerInactive returns (uint256) {
        uint256 balanceBefore = IERC20(asset()).balanceOf(address(this));
        uint256 assets = previewMint(shares);
        uint256 mintedShares = super.mint(shares, receiver);
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
        IERC20(asset()).safeTransfer(feeRecipient, claimed);
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
