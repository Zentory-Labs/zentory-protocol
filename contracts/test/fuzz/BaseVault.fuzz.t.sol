// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {BaseVault} from "../../src/vaults/BaseVault.sol";
import {MockERC20} from "../invariants/mocks/MockERC20.sol";

/// @title BaseVaultFuzzTest
/// @notice Fuzz tests for BaseVault deposit/mint/withdraw/redeem math.
///         All revert tests removed — they are fully covered by BaseVault.t.sol unit tests.
contract BaseVaultFuzzTest is Test {
    BaseVault vault;
    MockERC20 asset;

    address alice = makeAddr("alice");
    address feeRecipient = makeAddr("feeRecipient");
    address admin = makeAddr("admin");

    function setUp() external {
        asset = new MockERC20("Mock WETH", "WETH", 18);
        vault = new BaseVault({
            asset_:        address(asset),
            name_:         "zETH Vault",
            symbol_:       "zETH",
            maxLeverage_:  30000,
            maxPositionSizeBPS_: 10000,
            circuitBreakerDrawdownBPS_: 2000,
            rebalanceThresholdBPS_: 500,
            performanceFeeBPS_: 2000,
            feeRecipient_: feeRecipient,
            admin_:        admin
        });

        // Mint only what alice needs for fuzz runs (avoids overflow edge cases)
        asset.mint(alice, 100_000e18);
        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);
    }

    // ─── Deposit fuzz ────────────────────────────────────────────────────────────
    function test_fuzz_depositAlwaysReturnsAtLeastOneShare(uint96 assets) external {
        vm.assume(assets >= 1e10 && assets <= 10e18);

        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        assertGe(shares, 1, "deposit must return >= 1 share");
        assertLe(shares, assets, "shares cannot exceed deposit amount");
    }

    function test_fuzz_depositAndWithdrawRoundTrip(uint96 assets) external {
        vm.assume(assets >= 1e10 && assets <= 10e18);

        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        uint256 balanceBefore = asset.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(shares, alice, alice);
        uint256 balanceAfter = asset.balanceOf(alice);

        assertApproxEqAbs(balanceAfter - balanceBefore, assets, 1, "withdraw returns deposited assets");
    }

    function test_fuzz_convertToAssetsAndSharesConsistency(uint96 assets) external view {
        vm.assume(assets >= 1e10 && assets <= 1000e18);

        uint256 shares = vault.convertToShares(assets);
        uint256 assetsBack = vault.convertToAssets(shares);

        assertApproxEqAbs(assetsBack, assets, 1, "round-trip must be consistent");
    }

    // ─── Preview functions ───────────────────────────────────────────────────────
    function test_fuzz_previewDepositIsAccurate(uint96 assets) external {
        vm.assume(assets >= 1e10 && assets <= 10e18);

        uint256 preview = vault.previewDeposit(assets);
        vm.prank(alice);
        uint256 actual = vault.deposit(assets, alice);
        assertEq(actual, preview, "deposit preview must match actual");
    }
}
