// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SpotVault} from "../../src/vaults/SpotVault.sol";
import {ShadowPriceOracle} from "../../src/shadow/ShadowPriceOracle.sol";
import {ShadowSpotAdapter} from "../../src/shadow/ShadowSpotAdapter.sol";
import {MockERC20} from "../invariants/mocks/MockERC20.sol";

/// @notice End-to-end shadow-mode test using the REAL deployable shadow contracts
///         (not test-file mocks). Proves the testnet stack works as a depositor
///         experience: deposit -> signal-driven rebalance -> price moves -> NAV
///         in underlying rises -> redeem more underlying than HOLD.
contract ShadowStackTest is Test {
    MockERC20 wbtc;
    MockERC20 usdc;
    ShadowPriceOracle oracle;
    ShadowSpotAdapter adapter;
    SpotVault vault;

    address alice = makeAddr("alice");
    int256 constant PRICE_50K = 50_000 * 1e8;
    int256 constant PRICE_25K = 25_000 * 1e8;
    uint256 constant TEN_BTC = 10 * 1e8;
    uint256 constant MAX_STALE = 1 hours;

    function setUp() public {
        vm.warp(1_700_000_000);
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        usdc = new MockERC20("USD Coin", "USDC", 6);

        oracle = new ShadowPriceOracle(8, PRICE_50K, address(this));
        adapter = new ShadowSpotAdapter(address(wbtc), address(usdc), address(oracle),
                                        0 /*sim slippage bps*/, address(this));

        vault = new SpotVault(
            address(wbtc), address(usdc), address(oracle), MAX_STALE,
            "Zentory BTC Spot Vault", "zBTCs",
            0,      // rebalance threshold bps (always rebalance in test)
            100,    // max slippage bps (1%)
            0,      // perf fee
            address(this), address(this)
        );
        vault.setSwapAdapter(address(adapter));
        vault.grantRole(vault.KEEPER_ROLE(), address(this));
        adapter.grantRole(adapter.VAULT_ROLE(), address(vault));

        // Seed adapter reserves + alice's deposit.
        wbtc.mint(address(adapter), 1_000 * 1e8);
        usdc.mint(address(adapter), 100_000_000 * 1e6);
        wbtc.mint(alice, TEN_BTC);
    }

    function test_FullLoopOnShadowStack_BeatsHoldInUnderlying() public {
        // Deposit 10 BTC.
        vm.startPrank(alice);
        wbtc.approve(address(vault), TEN_BTC);
        uint256 shares = vault.deposit(TEN_BTC, alice);
        vm.stopPrank();
        assertApproxEqRel(vault.convertToAssets(shares), TEN_BTC, 1e12);

        // Signal: go FLAT before the drop (sell BTC for USDC at $50k).
        vault.rebalanceTo(0);
        assertEq(wbtc.balanceOf(address(vault)), 0, "flat");

        // Oracle pushes a 50% price drop (the keeper would call this every 4H).
        oracle.setPrice(PRICE_25K);

        // NAV in BTC ~doubles while the vault sits in USDC.
        assertApproxEqRel(vault.totalAssets(), 2 * TEN_BTC, 1e12);

        // Signal: go LONG again (rebuy BTC at $25k -> ~20 BTC held).
        vault.rebalanceTo(10000);
        assertApproxEqRel(wbtc.balanceOf(address(vault)), 2 * TEN_BTC, 1e12);

        // Alice redeems -> receives ~20 BTC. HOLDer would have 10.
        vm.prank(alice);
        uint256 received = vault.redeem(shares, alice, alice);
        assertApproxEqRel(received, 2 * TEN_BTC, 1e12, "depositor's BTC ~doubled");
        assertGt(received, TEN_BTC, "beats HOLD in underlying");
    }

    function test_Adapter_RejectsUnauthorizedCaller() public {
        wbtc.mint(address(this), 1e8);
        wbtc.approve(address(adapter), 1e8);
        vm.expectRevert();       // VAULT_ROLE check
        adapter.swap(address(wbtc), address(usdc), 1e8, 0);
    }

    function test_Adapter_RejectsUnsupportedPair() public {
        MockERC20 weth = new MockERC20("ETH", "ETH", 18);
        weth.mint(address(vault), 1e18);
        vm.startPrank(address(vault));
        weth.approve(address(adapter), 1e18);
        vm.expectRevert(abi.encodeWithSelector(
            ShadowSpotAdapter.UnsupportedPair.selector, address(weth), address(usdc)));
        adapter.swap(address(weth), address(usdc), 1e18, 0);
        vm.stopPrank();
    }

    function test_Oracle_StaleAfterMaxStaleness() public {
        // The vault must revert NAV reads when the shadow oracle is stale.
        vm.startPrank(alice);
        wbtc.approve(address(vault), TEN_BTC);
        vault.deposit(TEN_BTC, alice);
        vm.stopPrank();
        vault.rebalanceTo(0);
        vm.warp(block.timestamp + MAX_STALE + 1);
        vm.expectRevert();
        vault.totalAssets();
    }

    function test_Oracle_KeeperPriceUpdateRefreshesStaleness() public {
        vm.startPrank(alice);
        wbtc.approve(address(vault), TEN_BTC);
        vault.deposit(TEN_BTC, alice);
        vm.stopPrank();
        vault.rebalanceTo(0);
        vm.warp(block.timestamp + MAX_STALE + 1);
        oracle.setPrice(PRICE_50K);  // keeper push refreshes updatedAt
        // No longer reverts.
        assertGt(vault.totalAssets(), 0);
    }
}
