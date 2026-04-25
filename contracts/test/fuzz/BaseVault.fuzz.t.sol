// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {BaseVault} from "../../src/vaults/BaseVault.sol";
import {MockERC20} from "../invariants/mocks/MockERC20.sol";

/// @title BaseVaultFuzzTest
/// @notice Fuzz tests for BaseVault deposit/mint/withdraw/redeem math.
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

        asset.mint(alice, 100_000_000e18);
        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);
    }

    // ─── Deposit fuzz ────────────────────────────────────────────────────────────
    function test_fuzz_depositAlwaysReturnsAtLeastOneShare(uint96 assets) external {
        vm.assume(assets >= 1e10); // dust threshold

        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        assertGe(shares, 1, "deposit must return >= 1 share");
        assertLe(shares, assets, "shares cannot exceed deposit amount");
    }

    function test_fuzz_depositAndWithdrawRoundTrip(uint96 assets) external {
        vm.assume(assets >= 1e10);
        vm.assume(assets <= 10_000e18); // cap to avoid huge numbers

        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        uint256 balanceBefore = asset.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(shares, alice, alice);
        uint256 balanceAfter = asset.balanceOf(alice);

        assertApproxEqAbs(balanceAfter - balanceBefore, assets, 1, "withdraw returns deposited assets");
    }

    function test_fuzz_mintAndRedeemRoundTrip(uint96 shares) external {
        vm.assume(shares >= 1e10);
        vm.assume(shares <= 10_000e18);

        vm.prank(alice);
        uint256 assets = vault.mint(shares, alice);

        uint256 balanceBefore = asset.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(shares, alice, alice);
        uint256 balanceAfter = asset.balanceOf(alice);

        assertApproxEqAbs(balanceBefore - balanceAfter, assets, 1);
    }

    function test_fuzz_convertToAssetsAndSharesConsistency(uint96 assets) external view {
        vm.assume(assets >= 1e10);

        uint256 shares = vault.convertToShares(assets);
        uint256 assetsBack = vault.convertToAssets(shares);

        assertApproxEqAbs(assetsBack, assets, 1, "round-trip must be consistent");
    }

    function test_fuzz_depositRejectsZero() external {
        vm.expectRevert("BaseVault: zero deposit");
        vault.deposit(0, alice);
    }

    function test_fuzz_mintRejectsZero() external {
        vm.expectRevert("BaseVault: zero mint");
        vault.mint(0, alice);
    }

    function test_fuzz_redeemRejectsZero() external {
        vm.expectRevert("BaseVault: zero redeem");
        vault.redeem(0, alice, alice);
    }

    function test_fuzz_redeemRejectsInsufficientBalance(uint256 shares) external {
        vm.assume(shares > 0 && shares > vault.balanceOf(alice));

        vm.expectRevert("ERC20: burn amount exceeds balance");
        vault.redeem(shares, alice, alice);
    }

    // ─── Preview functions ───────────────────────────────────────────────────────
    function test_fuzz_previewDepositIsAccurate(uint96 assets) external {
        vm.assume(assets >= 1e10);
        uint256 preview = vault.previewDeposit(assets);
        vm.prank(alice);
        uint256 actual = vault.deposit(assets, alice);
        assertEq(actual, preview, "deposit preview must match actual");
    }

    function test_fuzz_previewMintIsAccurate(uint96 shares) external {
        vm.assume(shares >= 1e10);
        uint256 preview = vault.previewMint(shares);
        vm.prank(alice);
        uint256 actual = vault.mint(shares, alice);
        assertEq(actual, preview, "mint preview must match actual");
    }

    // ─── Multiple depositors ─────────────────────────────────────────────────────
    function test_fuzz_secondDepositorGetsProportionalShares(uint96 aliceDeposit, uint96 bobDeposit) external {
        vm.assume(aliceDeposit >= 1e10 && bobDeposit >= 1e10);
        vm.assume(aliceDeposit <= 1000e18 && bobDeposit <= 1000e18);

        vm.prank(alice);
        uint256 aliceShares = vault.deposit(aliceDeposit, alice);

        asset.mint(makeAddr("bob"), bobDeposit);
        vm.prank(makeAddr("bob"));
        asset.approve(address(vault), type(uint256).max);
        vm.prank(makeAddr("bob"));
        uint256 bobShares = vault.deposit(bobDeposit, makeAddr("bob"));

        // Second depositor gets proportional shares
        uint256 totalAssets = vault.totalAssets();
        uint256 totalShares = vault.totalSupply();
        assertApproxEqRel(
            uint256(bobShares) * totalAssets,
            uint256(aliceShares) * totalShares,
            1e14, // 0.01% tolerance
            "second depositor shares must be proportional"
        );
    }
}
