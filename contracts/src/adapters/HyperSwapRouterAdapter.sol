// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISpotSwapAdapter} from "../vaults/SpotVault.sol";

/// @notice Minimal Uniswap-V3-style SwapRouter interface. HyperSwap V3 (and the
///         other major HyperEVM concentrated-liquidity DEXs) are Uniswap-V3 forks
///         exposing this exact `exactInputSingle` shape.
interface ISwapRouterV3 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

/// @title HyperSwapRouterAdapter
/// @notice Production `ISpotSwapAdapter` (v1) that executes SpotVault's asset<->cash
///         rebalances ATOMICALLY through a HyperEVM Uniswap-V3-style DEX router
///         (HyperSwap V3). Single-hop on a configured fee tier; `minOut` is enforced
///         in-transaction, so — unlike the native HyperCore CoreWriter spot path —
///         there is no async fill, no eventual-consistency accounting, and no
///         non-reverting silent failure. AUM is bounded by SpotVault's per-rebalance
///         slippage guard (`maxSlippageBps`), which is appropriate for the low-turnover
///         long/flat strategy on thinner on-DEX liquidity.
///
/// @dev    Drop-in for ShadowSpotAdapter: same `ISpotSwapAdapter.swap` signature,
///         same VAULT_ROLE gate, output routed straight to the vault (msg.sender).
///         Swappable for a CoreWriter spot adapter (v2, deeper native liquidity) via
///         SpotVault.setSwapAdapter WITHOUT redeploying the vault. The router address
///         and fee tier are constructor params — set the real mainnet HyperSwap V3
///         SwapRouter + the deepest pool's fee tier at deploy.
contract HyperSwapRouterAdapter is AccessControl, ISpotSwapAdapter {
    using SafeERC20 for IERC20;

    /// @notice Only the SpotVault may swap (granted at deploy). Prevents arbitrary
    ///         callers from routing through this adapter / abusing its approvals.
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    ISwapRouterV3 public immutable router;
    address public immutable asset; // the vault underlying (e.g. WBTC)
    address public immutable cash; // the vault cash leg (e.g. USDC)
    uint24 public immutable feeTier; // pool fee, e.g. 500 = 0.05%, 3000 = 0.30%

    /// @notice Seconds added to block.timestamp for the swap deadline. Admin-tunable.
    uint256 public swapDeadlineWindow = 300; // 5 minutes

    event Swapped(address indexed caller, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event DeadlineWindowSet(uint256 window);

    error UnsupportedPair(address tokenIn, address tokenOut);
    error SlippageExceeded(uint256 amountOut, uint256 minOut);

    constructor(address router_, address asset_, address cash_, uint24 feeTier_, address admin_) {
        require(
            router_ != address(0) && asset_ != address(0) && cash_ != address(0) && admin_ != address(0), "zero addr"
        );
        require(asset_ != cash_, "asset == cash");
        router = ISwapRouterV3(router_);
        asset = asset_;
        cash = cash_;
        feeTier = feeTier_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    /// @inheritdoc ISpotSwapAdapter
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut)
        external
        onlyRole(VAULT_ROLE)
        returns (uint256 amountOut)
    {
        if (!((tokenIn == asset && tokenOut == cash) || (tokenIn == cash && tokenOut == asset))) {
            revert UnsupportedPair(tokenIn, tokenOut);
        }

        // Pull the input from the vault and approve exactly amountIn to the router.
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).forceApprove(address(router), amountIn);

        // Route output straight back to the vault (msg.sender). The router enforces
        // amountOutMinimum (reverts the whole tx on shortfall) — atomic by construction.
        amountOut = router.exactInputSingle(
            ISwapRouterV3.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: feeTier,
                recipient: msg.sender,
                deadline: block.timestamp + swapDeadlineWindow,
                amountIn: amountIn,
                amountOutMinimum: minOut,
                sqrtPriceLimitX96: 0
            })
        );

        // Defense-in-depth: assert the router honored the minimum even if a
        // non-standard router implementation failed to.
        if (amountOut < minOut) revert SlippageExceeded(amountOut, minOut);

        // An exact-input swap must consume the entire pulled amount. If any tokenIn
        // remains, the input token took a transfer fee / the router under-pulled
        // (fee-on-transfer / non-standard router) — revert rather than silently
        // strand vault funds in the adapter (pre-audit review HSA-001/HSA-007).
        require(IERC20(tokenIn).balanceOf(address(this)) == 0, "HyperSwapRouterAdapter: residual tokenIn");

        // Clear any residual allowance (should be 0 after an exact-in swap, but
        // a non-standard router could leave dust approved).
        IERC20(tokenIn).forceApprove(address(router), 0);

        emit Swapped(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @notice Tune the swap deadline window (admin only).
    function setDeadlineWindow(uint256 window) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(window > 0 && window <= 1 hours, "bad window");
        swapDeadlineWindow = window;
        emit DeadlineWindowSet(window);
    }
}
