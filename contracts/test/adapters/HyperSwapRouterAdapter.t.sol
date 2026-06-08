// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {HyperSwapRouterAdapter, ISwapRouterV3} from "../../src/adapters/HyperSwapRouterAdapter.sol";
import {MockERC20} from "../invariants/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Minimal Uniswap-V3-style router mock: pulls `amountIn` from the caller and
///      pays a configured `outAmount` of `tokenOut` to `recipient`. `enforceMin`
///      toggles whether it honors amountOutMinimum (real UniV3 routers do).
contract MockSwapRouterV3 is ISwapRouterV3 {
    uint256 public outAmount;
    bool public enforceMin = true;

    function setOut(uint256 o) external { outAmount = o; }
    function setEnforceMin(bool e) external { enforceMin = e; }

    function exactInputSingle(ExactInputSingleParams calldata p)
        external
        payable
        override
        returns (uint256)
    {
        IERC20(p.tokenIn).transferFrom(msg.sender, address(this), p.amountIn);
        if (enforceMin) require(outAmount >= p.amountOutMinimum, "Too little received");
        IERC20(p.tokenOut).transfer(p.recipient, outAmount);
        return outAmount;
    }
}

contract HyperSwapRouterAdapterTest is Test {
    HyperSwapRouterAdapter adapter;
    MockSwapRouterV3 router;
    MockERC20 wbtc; // asset, 8 dec
    MockERC20 usdc; // cash, 6 dec

    address vaultLike = address(this); // this contract acts as the vault (VAULT_ROLE)

    function setUp() public {
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        router = new MockSwapRouterV3();
        adapter = new HyperSwapRouterAdapter(address(router), address(wbtc), address(usdc), 500, address(this));
        adapter.grantRole(adapter.VAULT_ROLE(), vaultLike);

        // Fund the router with both legs so it can pay out.
        wbtc.mint(address(router), 1_000 * 1e8);
        usdc.mint(address(router), 100_000_000 * 1e6);
    }

    function test_swapAssetToCash() public {
        uint256 amountIn = 1e8;          // 1 WBTC
        uint256 out = 50_000 * 1e6;      // 50k USDC
        router.setOut(out);
        wbtc.mint(vaultLike, amountIn);
        wbtc.approve(address(adapter), amountIn);

        uint256 cashBefore = usdc.balanceOf(vaultLike);
        uint256 got = adapter.swap(address(wbtc), address(usdc), amountIn, 49_000 * 1e6);

        assertEq(got, out, "returns router output");
        assertEq(usdc.balanceOf(vaultLike) - cashBefore, out, "vault received cash");
        assertEq(wbtc.balanceOf(address(adapter)), 0, "adapter holds no asset");
        assertEq(wbtc.allowance(address(adapter), address(router)), 0, "approval cleared");
    }

    function test_swapCashToAsset() public {
        uint256 amountIn = 50_000 * 1e6;
        uint256 out = 1e8;
        router.setOut(out);
        usdc.mint(vaultLike, amountIn);
        usdc.approve(address(adapter), amountIn);

        uint256 assetBefore = wbtc.balanceOf(vaultLike);
        uint256 got = adapter.swap(address(usdc), address(wbtc), amountIn, 0.99e8);
        assertEq(got, out);
        assertEq(wbtc.balanceOf(vaultLike) - assetBefore, out);
    }

    function test_unsupportedPairReverts() public {
        MockERC20 weth = new MockERC20("Wrapped ETH", "WETH", 18);
        weth.mint(vaultLike, 1e18);
        weth.approve(address(adapter), 1e18);
        vm.expectRevert(
            abi.encodeWithSelector(HyperSwapRouterAdapter.UnsupportedPair.selector, address(weth), address(usdc))
        );
        adapter.swap(address(weth), address(usdc), 1e18, 0);
    }

    function test_routerEnforcesMinOut() public {
        // Standard UniV3 router reverts internally if output < amountOutMinimum.
        router.setOut(40_000 * 1e6);
        router.setEnforceMin(true);
        wbtc.mint(vaultLike, 1e8);
        wbtc.approve(address(adapter), 1e8);
        vm.expectRevert(bytes("Too little received"));
        adapter.swap(address(wbtc), address(usdc), 1e8, 49_000 * 1e6);
    }

    function test_adapterSlippageGuard() public {
        // A non-standard router that ignores the minimum → the adapter's own guard catches it.
        router.setOut(40_000 * 1e6);
        router.setEnforceMin(false);
        wbtc.mint(vaultLike, 1e8);
        wbtc.approve(address(adapter), 1e8);
        vm.expectRevert(
            abi.encodeWithSelector(HyperSwapRouterAdapter.SlippageExceeded.selector, 40_000 * 1e6, 49_000 * 1e6)
        );
        adapter.swap(address(wbtc), address(usdc), 1e8, 49_000 * 1e6);
    }

    function test_nonVaultRoleReverts() public {
        router.setOut(50_000 * 1e6);
        wbtc.mint(address(0xBEEF), 1e8);
        vm.startPrank(address(0xBEEF));
        wbtc.approve(address(adapter), 1e8);
        vm.expectRevert(); // AccessControlUnauthorizedAccount — modifier reverts before any transfer
        adapter.swap(address(wbtc), address(usdc), 1e8, 0);
        vm.stopPrank();
    }

    function test_setDeadlineWindow() public {
        adapter.setDeadlineWindow(600);
        assertEq(adapter.swapDeadlineWindow(), 600);
        vm.expectRevert(bytes("bad window"));
        adapter.setDeadlineWindow(0);
        vm.expectRevert(bytes("bad window"));
        adapter.setDeadlineWindow(2 hours);
    }

    function test_constructorRejectsZeroAndEqual() public {
        vm.expectRevert(bytes("zero addr"));
        new HyperSwapRouterAdapter(address(0), address(wbtc), address(usdc), 500, address(this));
        vm.expectRevert(bytes("asset == cash"));
        new HyperSwapRouterAdapter(address(router), address(wbtc), address(wbtc), 500, address(this));
    }
}
