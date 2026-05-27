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

/// @notice Minimal Chainlink-style oracle: USD price of one whole underlying unit,
///         scaled to `decimals()` (typically 8). Cash asset is assumed ~= $1.
interface ISpotPriceOracle {
    function priceUsd() external view returns (uint256);
    function decimals() external view returns (uint8);
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

    IERC20 public immutable cashAsset;          // e.g. USDC
    ISpotPriceOracle public immutable oracle;   // underlying/USD
    ISpotSwapAdapter public swapAdapter;

    uint8 internal immutable _assetDec;
    uint8 internal immutable _cashDec;
    uint8 internal immutable _priceDec;

    uint16 public targetWeightBps;              // 0..10000 (last commanded exposure)
    uint16 public immutable rebalanceThresholdBps; // dust deadband
    uint16 public immutable maxSlippageBps;
    uint256 public immutable performanceFee;    // bps of alpha above HWM
    uint256 public highWaterMark;
    uint256 public performanceFeeAccrued;       // in underlying units
    address public feeRecipient;
    bool public isCircuitBreakerActive;

    event Rebalanced(uint16 targetBps, uint256 assetLeg, uint256 cashLeg, uint256 navPerShare);
    event PerformanceFeeAccrued(uint256 fee, uint256 navBefore, uint256 navAfter);
    event CircuitBreakerSet(bool active);

    error CircuitBreakerActive();
    error BadWeight();

    constructor(
        address asset_,
        address cashAsset_,
        address oracle_,
        string memory name_,
        string memory symbol_,
        uint16 rebalanceThresholdBps_,
        uint16 maxSlippageBps_,
        uint256 performanceFeeBps_,
        address feeRecipient_,
        address admin_
    ) ERC20(name_, symbol_) ERC4626(IERC20(asset_)) {
        require(asset_ != address(0) && cashAsset_ != address(0) && oracle_ != address(0), "zero addr");
        require(feeRecipient_ != address(0) && admin_ != address(0), "zero addr");
        require(rebalanceThresholdBps_ <= 10000 && maxSlippageBps_ <= 10000 && performanceFeeBps_ <= 10000, "bad bps");

        cashAsset = IERC20(cashAsset_);
        oracle = ISpotPriceOracle(oracle_);
        _assetDec = IERC20Metadata(asset_).decimals();
        _cashDec = IERC20Metadata(cashAsset_).decimals();
        _priceDec = ISpotPriceOracle(oracle_).decimals();

        rebalanceThresholdBps = rebalanceThresholdBps_;
        maxSlippageBps = maxSlippageBps_;
        performanceFee = performanceFeeBps_;
        feeRecipient = feeRecipient_;
        highWaterMark = 10 ** _assetDec; // 1.0 in underlying units

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    /// @dev Inflation-attack mitigation (audit H-1), same as BaseVault.
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    // ─── Oracle valuation helpers ──────────────────────────────────────────

    /// @notice Value `cashAmt` (raw cash units) in underlying units.
    function cashToAsset(uint256 cashAmt) public view returns (uint256) {
        uint256 p = oracle.priceUsd();
        require(p > 0, "oracle price 0");
        return (cashAmt * (10 ** _assetDec) * (10 ** _priceDec)) / ((10 ** _cashDec) * p);
    }

    /// @notice Value `assetAmt` (raw underlying units) in cash units.
    function assetToCash(uint256 assetAmt) public view returns (uint256) {
        uint256 p = oracle.priceUsd();
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
    }

    // ─── Performance fee (alpha above HWM, in underlying units) ──────────────

    function evaluateFees() external onlyRole(KEEPER_ROLE) {
        uint256 nav = getNavPerShare();
        if (nav <= highWaterMark) return;
        uint256 alpha = nav - highWaterMark;
        uint256 shareUnit = 10 ** decimals();
        uint256 fee = (alpha * totalSupply() * performanceFee) / (shareUnit * 10000);
        if (fee > 0) {
            performanceFeeAccrued += fee;
            emit PerformanceFeeAccrued(fee, highWaterMark, nav);
        }
        highWaterMark = nav;
    }

    // ─── Admin ───────────────────────────────────────────────────────────────

    function setSwapAdapter(address adapter_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(adapter_ != address(0), "zero adapter");
        swapAdapter = ISpotSwapAdapter(adapter_);
    }

    function setCircuitBreaker(bool active) external onlyRole(RISK_COUNCIL_ROLE) {
        isCircuitBreakerActive = active;
        emit CircuitBreakerSet(active);
    }
}
