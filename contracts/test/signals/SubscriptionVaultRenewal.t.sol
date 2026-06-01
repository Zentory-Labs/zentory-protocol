// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SubscriptionVault} from "../../src/signals/SubscriptionVault.sol";
import {ZENT} from "../../src/ZENT.sol";

/// @notice Spec-conformance audit, finding #1 (Critical): renewSubscription must
///         charge the subscription's OWN stored tier price, not always ELITE.
///
///         The bug: renewal reverse-mapped the stored asset-class bitmap through
///         _getTierForBitmap, which tested bitwise OVERLAP. ELITE's bitmap (0x1F)
///         overlaps every tier's bitmap, so the ELITE branch always won — BASIC
///         renewals were billed 2000 ZENT/mo (20x) and PRO 2000 (4x), and any
///         subscriber who had only approved their real price was DoS'd at the
///         transferFrom.
contract SubscriptionVaultRenewalTest is Test {
    SubscriptionVault vault;
    ZENT zent;

    address treasury = makeAddr("treasury");
    address user = makeAddr("user");

    uint256 constant BASIC_PRICE = 100e18;
    uint256 constant PRO_PRICE = 500e18;
    uint256 constant ELITE_PRICE = 2000e18;

    function setUp() public {
        zent = new ZENT(); // test contract holds the full 1B supply
        vault = new SubscriptionVault(address(zent), treasury);

        // Fund the user and approve the vault for spending.
        assertTrue(zent.transfer(user, 100_000e18));
        vm.prank(user);
        zent.approve(address(vault), type(uint256).max);
    }

    /// @dev Subscribe to `tierId` for one month, then renew one month, and
    ///      return the ZENT charged for the RENEWAL alone (treasury delta).
    function _renewalCost(uint256 tierId) internal returns (uint256 spent) {
        vm.prank(user);
        uint256 tokenId = vault.subscribe(tierId, 1);

        uint256 treasuryBefore = zent.balanceOf(treasury);
        vm.prank(user);
        vault.renewSubscription(tokenId, 1);
        spent = zent.balanceOf(treasury) - treasuryBefore;
    }

    function test_renewBasic_chargesBasicPrice_notElite() external {
        uint256 spent = _renewalCost(0);
        assertEq(spent, BASIC_PRICE, "BASIC renewal must cost 100 ZENT (pre-fix: 2000 / ELITE)");
    }

    function test_renewPro_chargesProPrice_notElite() external {
        uint256 spent = _renewalCost(1);
        assertEq(spent, PRO_PRICE, "PRO renewal must cost 500 ZENT (pre-fix: 2000 / ELITE)");
    }

    function test_renewElite_chargesElitePrice() external {
        uint256 spent = _renewalCost(2);
        assertEq(spent, ELITE_PRICE, "ELITE renewal correctly costs 2000 ZENT");
    }

    /// @notice A BASIC subscriber who approved only enough for the BASIC price
    ///         can renew (pre-fix this reverted because it tried to pull the
    ///         ELITE price).
    function test_renewBasic_succeedsWithBasicAllowanceOnly() external {
        address tight = makeAddr("tight");
        assertTrue(zent.transfer(tight, 1_000e18));

        vm.prank(tight);
        zent.approve(address(vault), BASIC_PRICE); // subscribe 1mo consumes exactly this
        vm.prank(tight);
        uint256 tokenId = vault.subscribe(0, 1);

        // Approve exactly one more month at the BASIC price and renew.
        vm.prank(tight);
        zent.approve(address(vault), BASIC_PRICE);
        vm.prank(tight);
        uint32 newExp = vault.renewSubscription(tokenId, 1);
        assertGt(newExp, 0, "renewal must succeed with a BASIC-sized allowance");
    }
}
