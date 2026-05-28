// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISpotSwapAdapter, AggregatorV3Interface} from "../vaults/SpotVault.sol";

/// @title ShadowSpotAdapter
/// @notice TESTNET-ONLY swap venue that fills at the oracle price minus a
///         configurable slippage. Holds reserves of the asset + cash and serves
///         the SpotVault so the full loop (deposit -> signal-driven rebalance ->
///         NAV moves with PnL -> redeem) runs end-to-end on testnet without a
///         real Hyperliquid spot integration. Drops out the moment the
///         production CoreWriter spot adapter is ready and audited.
///
/// ============================================================================
/// !!! NOT FOR MAINNET. The production adapter must route to Hyperliquid spot
/// !!! via CoreWriter, handle async fills, real slippage, and be audited. This
/// !!! contract just simulates fills at oracle price for demo purposes.
/// ============================================================================
contract ShadowSpotAdapter is AccessControl, ISpotSwapAdapter {
    using SafeERC20 for IERC20;

    /// @notice Only authorized vaults can swap (otherwise anyone could drain
    ///         the reserves). Granted to the SpotVault at deploy.
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    IERC20 public immutable asset;
    IERC20 public immutable cash;
    AggregatorV3Interface public immutable oracle;
    uint16 public immutable simulatedSlippageBps;   // shaves the fill (set 0 for ideal)
    uint8 internal immutable _assetDec;
    uint8 internal immutable _cashDec;
    uint8 internal immutable _priceDec;

    event Swapped(address indexed caller, address tokenIn, address tokenOut,
                  uint256 amountIn, uint256 amountOut, int256 oraclePrice);

    error UnsupportedPair(address tokenIn, address tokenOut);
    error InsufficientReserves(address token, uint256 needed, uint256 have);
    error SlippageExceeded(uint256 amountOut, uint256 minOut);
    error BadOraclePrice(int256 answer);

    constructor(
        address asset_,
        address cash_,
        address oracle_,
        uint16 simulatedSlippageBps_,
        address admin
    ) {
        require(asset_ != address(0) && cash_ != address(0) && oracle_ != address(0), "zero addr");
        require(admin != address(0), "zero admin");
        require(simulatedSlippageBps_ <= 10000, "bad bps");
        asset = IERC20(asset_);
        cash = IERC20(cash_);
        oracle = AggregatorV3Interface(oracle_);
        simulatedSlippageBps = simulatedSlippageBps_;
        _assetDec = IERC20Metadata(asset_).decimals();
        _cashDec = IERC20Metadata(cash_).decimals();
        _priceDec = AggregatorV3Interface(oracle_).decimals();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc ISpotSwapAdapter
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut)
        external
        onlyRole(VAULT_ROLE)
        returns (uint256 amountOut)
    {
        if (!(tokenIn == address(asset) && tokenOut == address(cash))
            && !(tokenIn == address(cash) && tokenOut == address(asset))) {
            revert UnsupportedPair(tokenIn, tokenOut);
        }
        (, int256 ans, , , ) = oracle.latestRoundData();
        if (ans <= 0) revert BadOraclePrice(ans);
        uint256 p = uint256(ans);

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Ideal fill at oracle price; same decimal math as SpotVault helpers.
        uint256 ideal;
        if (tokenIn == address(asset)) {
            ideal = (amountIn * (10 ** _cashDec) * p) / ((10 ** _assetDec) * (10 ** _priceDec));
        } else {
            ideal = (amountIn * (10 ** _assetDec) * (10 ** _priceDec)) / ((10 ** _cashDec) * p);
        }
        amountOut = (ideal * (10000 - simulatedSlippageBps)) / 10000;
        if (amountOut < minOut) revert SlippageExceeded(amountOut, minOut);

        uint256 have = IERC20(tokenOut).balanceOf(address(this));
        if (amountOut > have) revert InsufficientReserves(tokenOut, amountOut, have);
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        emit Swapped(msg.sender, tokenIn, tokenOut, amountIn, amountOut, ans);
    }

    /// @notice Admin can withdraw reserves (testnet management).
    function sweep(address token, uint256 amount, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).safeTransfer(to, amount);
    }
}
