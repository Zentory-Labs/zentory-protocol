// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ZENT} from "../../src/ZENT.sol";
import {ModelBonding} from "../../src/staking/ModelBonding.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract ModelBondingTest is Test {
    ZENT internal zent;
    ModelBonding internal bonding;

    address internal governor = makeAddr("governor");
    address internal council = makeAddr("council");
    address internal insurance = makeAddr("insurance");
    address internal provider = makeAddr("provider");
    address internal outsider = makeAddr("outsider");

    uint64 internal constant COOLDOWN = 14 days;

    function setUp() external {
        zent = new ZENT();
        bonding = new ModelBonding(address(zent), governor, council, insurance, COOLDOWN);

        assertTrue(zent.transfer(provider, 100_000 ether));
    }

    // ─── Constructor ───────────────────────────────────────────────────────

    function test_constructorRejectsZeroToken() external {
        vm.expectRevert(bytes("ModelBonding: zero token"));
        new ModelBonding(address(0), governor, council, insurance, COOLDOWN);
    }

    function test_constructorRejectsZeroGovernor() external {
        vm.expectRevert(bytes("ModelBonding: zero governor"));
        new ModelBonding(address(zent), address(0), council, insurance, COOLDOWN);
    }

    function test_constructorRejectsZeroCouncil() external {
        vm.expectRevert(bytes("ModelBonding: zero council"));
        new ModelBonding(address(zent), governor, address(0), insurance, COOLDOWN);
    }

    function test_constructorRejectsZeroInsurance() external {
        vm.expectRevert(bytes("ModelBonding: zero insurance"));
        new ModelBonding(address(zent), governor, council, address(0), COOLDOWN);
    }

    function test_rolesGrantedCorrectly() external view {
        assertTrue(bonding.hasRole(bonding.DEFAULT_ADMIN_ROLE(), governor));
        assertTrue(bonding.hasRole(bonding.GOVERNOR_ROLE(), governor));
        assertTrue(bonding.hasRole(bonding.RISK_COUNCIL_ROLE(), council));
    }

    // ─── Bond ──────────────────────────────────────────────────────────────

    function test_bondTransfersTokensAndIncreasesBalance() external {
        uint256 amount = 10_000 ether;
        vm.startPrank(provider);
        zent.approve(address(bonding), amount);
        bonding.bond(amount);
        vm.stopPrank();

        assertEq(zent.balanceOf(address(bonding)), amount);
        assertEq(bonding.bondOf(provider), amount);
        assertEq(bonding.totalBonded(), amount);
    }

    function test_bondRejectsZeroAmount() external {
        vm.prank(provider);
        vm.expectRevert(bytes("ModelBonding: zero amount"));
        bonding.bond(0);
    }

    function test_bondAddsToExistingBond() external {
        vm.startPrank(provider);
        zent.approve(address(bonding), 15_000 ether);
        bonding.bond(10_000 ether);
        bonding.bond(5_000 ether);
        vm.stopPrank();

        assertEq(bonding.bondOf(provider), 15_000 ether);
    }

    // ─── Unbond Request / Cooldown / Claim ────────────────────────────────

    function test_requestUnbondStartsCooldown() external {
        vm.startPrank(provider);
        zent.approve(address(bonding), 10_000 ether);
        bonding.bond(10_000 ether);
        bonding.requestUnbond(4_000 ether);
        vm.stopPrank();

        (uint256 pending, uint64 readyAt) = bonding.pendingUnbond(provider);
        assertEq(pending, 4_000 ether);
        assertEq(readyAt, uint64(block.timestamp) + COOLDOWN);
    }

    function test_requestUnbondRevertsOnZeroAmount() external {
        vm.startPrank(provider);
        zent.approve(address(bonding), 10_000 ether);
        bonding.bond(10_000 ether);
        vm.expectRevert(bytes("ModelBonding: zero amount"));
        bonding.requestUnbond(0);
        vm.stopPrank();
    }

    function test_requestUnbondRejectsExceedingBalance() external {
        vm.startPrank(provider);
        zent.approve(address(bonding), 10_000 ether);
        bonding.bond(10_000 ether);
        vm.expectRevert(bytes("ModelBonding: exceeds bond"));
        bonding.requestUnbond(20_000 ether);
        vm.stopPrank();
    }

    function test_requestUnbondRejectsWhileRequestPending() external {
        vm.startPrank(provider);
        zent.approve(address(bonding), 10_000 ether);
        bonding.bond(10_000 ether);
        bonding.requestUnbond(4_000 ether);
        vm.expectRevert(bytes("ModelBonding: request pending"));
        bonding.requestUnbond(1_000 ether);
        vm.stopPrank();
    }

    function test_claimUnbondRevertsBeforeCooldown() external {
        vm.startPrank(provider);
        zent.approve(address(bonding), 10_000 ether);
        bonding.bond(10_000 ether);
        bonding.requestUnbond(4_000 ether);
        vm.warp(block.timestamp + COOLDOWN - 1);
        vm.expectRevert(bytes("ModelBonding: cooldown active"));
        bonding.claimUnbond();
        vm.stopPrank();
    }

    function test_claimUnbondTransfersTokensAndClearsRequest() external {
        vm.startPrank(provider);
        zent.approve(address(bonding), 10_000 ether);
        bonding.bond(10_000 ether);
        bonding.requestUnbond(4_000 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + COOLDOWN);
        uint256 before = zent.balanceOf(provider);

        vm.prank(provider);
        bonding.claimUnbond();

        assertEq(zent.balanceOf(provider), before + 4_000 ether);
        assertEq(bonding.bondOf(provider), 6_000 ether);
        (uint256 pending,) = bonding.pendingUnbond(provider);
        assertEq(pending, 0);
        assertEq(bonding.totalBonded(), 6_000 ether);
    }

    function test_cancelUnbondClearsRequestAndKeepsBond() external {
        vm.startPrank(provider);
        zent.approve(address(bonding), 10_000 ether);
        bonding.bond(10_000 ether);
        bonding.requestUnbond(4_000 ether);
        bonding.cancelUnbond();
        vm.stopPrank();

        (uint256 pending,) = bonding.pendingUnbond(provider);
        assertEq(pending, 0);
        assertEq(bonding.bondOf(provider), 10_000 ether);
    }

    // ─── Slashing ──────────────────────────────────────────────────────────

    function test_slashSendsToInsuranceAndReducesBond() external {
        vm.startPrank(provider);
        zent.approve(address(bonding), 10_000 ether);
        bonding.bond(10_000 ether);
        vm.stopPrank();

        vm.prank(council);
        bonding.slash(provider, 3_000 ether, "NAV below HODL 5 epochs");

        assertEq(bonding.bondOf(provider), 7_000 ether);
        assertEq(zent.balanceOf(insurance), 3_000 ether);
        assertEq(bonding.totalBonded(), 7_000 ether);
    }

    function test_slashCapsPendingUnbondIfNeeded() external {
        vm.startPrank(provider);
        zent.approve(address(bonding), 10_000 ether);
        bonding.bond(10_000 ether);
        bonding.requestUnbond(8_000 ether);
        vm.stopPrank();

        vm.prank(council);
        bonding.slash(provider, 5_000 ether, "catastrophic drawdown");

        (uint256 pending,) = bonding.pendingUnbond(provider);
        assertEq(bonding.bondOf(provider), 5_000 ether);
        assertEq(pending, 5_000 ether);
    }

    function test_slashRejectsZero() external {
        vm.startPrank(provider);
        zent.approve(address(bonding), 10_000 ether);
        bonding.bond(10_000 ether);
        vm.stopPrank();

        vm.prank(council);
        vm.expectRevert(bytes("ModelBonding: invalid amount"));
        bonding.slash(provider, 0, "reason");
    }

    function test_slashRejectsExceedingBond() external {
        vm.startPrank(provider);
        zent.approve(address(bonding), 10_000 ether);
        bonding.bond(10_000 ether);
        vm.stopPrank();

        vm.prank(council);
        vm.expectRevert(bytes("ModelBonding: invalid amount"));
        bonding.slash(provider, 20_000 ether, "reason");
    }

    function test_slashRejectsFromNonCouncil() external {
        vm.startPrank(provider);
        zent.approve(address(bonding), 10_000 ether);
        bonding.bond(10_000 ether);
        vm.stopPrank();

        bytes32 role = bonding.RISK_COUNCIL_ROLE();
        vm.prank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, role)
        );
        bonding.slash(provider, 1_000 ether, "nope");
    }

    // ─── Governor-Only Configuration ──────────────────────────────────────

    function test_setInsuranceFundUpdatesAddress() external {
        address newFund = makeAddr("newFund");
        vm.prank(governor);
        bonding.setInsuranceFund(newFund);
        assertEq(bonding.insuranceFund(), newFund);
    }

    function test_setInsuranceFundRejectsZero() external {
        vm.prank(governor);
        vm.expectRevert(bytes("ModelBonding: zero insurance"));
        bonding.setInsuranceFund(address(0));
    }

    function test_setUnbondCooldownUpdatesValue() external {
        vm.prank(governor);
        bonding.setUnbondCooldown(30 days);
        assertEq(bonding.unbondCooldown(), 30 days);
    }

    function test_setUnbondCooldownRejectsFromNonGovernor() external {
        bytes32 role = bonding.GOVERNOR_ROLE();
        vm.prank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, role)
        );
        bonding.setUnbondCooldown(30 days);
    }
}
