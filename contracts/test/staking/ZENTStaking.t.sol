// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ZENT} from "../../src/ZENT.sol";
import {ZENTStaking} from "../../src/staking/ZENTStaking.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract ZENTStakingTest is Test {
    ZENT internal zent;
    ZENTStaking internal staking;

    address internal governor = makeAddr("governor");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant MIN_STAKE = 1_000 ether;

    function setUp() external {
        zent = new ZENT();
        staking = new ZENTStaking(address(zent), governor, MIN_STAKE);

        assertTrue(zent.transfer(alice, 100_000 ether));
        assertTrue(zent.transfer(bob, 100_000 ether));
    }

    // ─── Constants & Config ────────────────────────────────────────────────

    function test_constantsExposedCorrectly() external view {
        assertEq(staking.MIN_LOCK(), 7 days);
        assertEq(staking.MAX_LOCK(), 730 days);
    }

    function test_constructorRejectsZeroToken() external {
        vm.expectRevert(bytes("ZENTStaking: zero token"));
        new ZENTStaking(address(0), governor, MIN_STAKE);
    }

    function test_constructorRejectsZeroGovernor() external {
        vm.expectRevert(bytes("ZENTStaking: zero governor"));
        new ZENTStaking(address(zent), address(0), MIN_STAKE);
    }

    function test_governorHoldsRoles() external view {
        assertTrue(staking.hasRole(staking.DEFAULT_ADMIN_ROLE(), governor));
        assertTrue(staking.hasRole(staking.GOVERNOR_ROLE(), governor));
    }

    // ─── Stake ─────────────────────────────────────────────────────────────

    function test_stakeTransfersTokensAndSetsLock() external {
        uint256 amount = 5_000 ether;
        uint64 lockDuration = 365 days;

        vm.startPrank(alice);
        zent.approve(address(staking), amount);
        uint64 lockEnd = staking.stake(amount, lockDuration);
        vm.stopPrank();

        assertEq(zent.balanceOf(address(staking)), amount);
        assertEq(staking.stakedBalance(alice), amount);
        assertEq(lockEnd, uint64(block.timestamp) + lockDuration);
        assertEq(staking.totalStaked(), amount);
    }

    function test_stakeRejectsZeroAmount() external {
        vm.startPrank(alice);
        zent.approve(address(staking), 1_000 ether);
        vm.expectRevert(bytes("ZENTStaking: zero amount"));
        staking.stake(0, 30 days);
        vm.stopPrank();
    }

    function test_stakeRejectsLockBelowMin() external {
        vm.startPrank(alice);
        zent.approve(address(staking), 1_000 ether);
        vm.expectRevert(bytes("ZENTStaking: lock out of range"));
        staking.stake(1_000 ether, 1 days);
        vm.stopPrank();
    }

    function test_stakeRejectsLockAboveMax() external {
        vm.startPrank(alice);
        zent.approve(address(staking), 1_000 ether);
        vm.expectRevert(bytes("ZENTStaking: lock out of range"));
        staking.stake(1_000 ether, 731 days);
        vm.stopPrank();
    }

    function test_stakeRejectsExistingPosition() external {
        vm.startPrank(alice);
        zent.approve(address(staking), 2_000 ether);
        staking.stake(1_000 ether, 30 days);
        vm.expectRevert(bytes("ZENTStaking: position exists"));
        staking.stake(1_000 ether, 30 days);
        vm.stopPrank();
    }

    // ─── Increase ──────────────────────────────────────────────────────────

    function test_increaseAmountAddsToStake() external {
        vm.startPrank(alice);
        zent.approve(address(staking), 3_000 ether);
        staking.stake(1_000 ether, 30 days);
        staking.increaseAmount(2_000 ether);
        vm.stopPrank();

        assertEq(staking.stakedBalance(alice), 3_000 ether);
    }

    function test_increaseAmountRequiresExistingStake() external {
        vm.prank(alice);
        vm.expectRevert(bytes("ZENTStaking: no position"));
        staking.increaseAmount(1_000 ether);
    }

    function test_increaseAmountRejectedAfterLockEnd() external {
        vm.startPrank(alice);
        zent.approve(address(staking), 2_000 ether);
        staking.stake(1_000 ether, 30 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        vm.startPrank(alice);
        zent.approve(address(staking), 1_000 ether);
        vm.expectRevert(bytes("ZENTStaking: lock expired"));
        staking.increaseAmount(1_000 ether);
        vm.stopPrank();
    }

    // ─── Extend ────────────────────────────────────────────────────────────

    function test_extendLockPushesLockEndForward() external {
        vm.startPrank(alice);
        zent.approve(address(staking), 1_000 ether);
        staking.stake(1_000 ether, 30 days);

        uint64 newEnd = staking.extendLock(180 days);
        vm.stopPrank();

        assertEq(newEnd, uint64(block.timestamp) + 180 days);
    }

    function test_extendLockRejectsShorterEnd() external {
        vm.startPrank(alice);
        zent.approve(address(staking), 1_000 ether);
        staking.stake(1_000 ether, 180 days);

        vm.expectRevert(bytes("ZENTStaking: not extending"));
        staking.extendLock(30 days);
        vm.stopPrank();
    }

    // ─── veBalance ─────────────────────────────────────────────────────────

    function test_veBalanceMaxAtFullLock() external {
        uint256 amount = 10_000 ether;

        vm.startPrank(alice);
        zent.approve(address(staking), amount);
        staking.stake(amount, 730 days);
        vm.stopPrank();

        assertApproxEqAbs(staking.veBalance(alice), amount, 1);
    }

    function test_veBalanceHalfAtHalfLock() external {
        uint256 amount = 10_000 ether;

        vm.startPrank(alice);
        zent.approve(address(staking), amount);
        staking.stake(amount, 365 days);
        vm.stopPrank();

        assertApproxEqAbs(staking.veBalance(alice), amount / 2, 1);
    }

    function test_veBalanceDecaysLinearlyToZero() external {
        uint256 amount = 10_000 ether;

        vm.startPrank(alice);
        zent.approve(address(staking), amount);
        staking.stake(amount, 730 days);
        vm.stopPrank();

        uint256 initial = staking.veBalance(alice);

        vm.warp(block.timestamp + 365 days);
        uint256 midway = staking.veBalance(alice);
        assertApproxEqAbs(midway, initial / 2, initial / 1000); // 0.1% tolerance

        vm.warp(block.timestamp + 365 days);
        assertEq(staking.veBalance(alice), 0);
    }

    function test_veBalanceZeroWithoutStake() external view {
        assertEq(staking.veBalance(bob), 0);
    }

    // ─── Withdraw ──────────────────────────────────────────────────────────

    function test_withdrawRevertsBeforeLockEnd() external {
        vm.startPrank(alice);
        zent.approve(address(staking), 1_000 ether);
        staking.stake(1_000 ether, 30 days);
        vm.expectRevert(bytes("ZENTStaking: locked"));
        staking.withdraw();
        vm.stopPrank();
    }

    function test_withdrawReturnsTokens() external {
        uint256 amount = 5_000 ether;
        vm.startPrank(alice);
        zent.approve(address(staking), amount);
        staking.stake(amount, 30 days);
        vm.stopPrank();

        uint256 aliceBefore = zent.balanceOf(alice);
        vm.warp(block.timestamp + 31 days);

        vm.prank(alice);
        staking.withdraw();

        assertEq(zent.balanceOf(alice), aliceBefore + amount);
        assertEq(staking.stakedBalance(alice), 0);
        assertEq(staking.totalStaked(), 0);
    }

    function test_withdrawRevertsIfNoPosition() external {
        vm.prank(bob);
        vm.expectRevert(bytes("ZENTStaking: no position"));
        staking.withdraw();
    }

    // ─── Access Gating ────────────────────────────────────────────────────

    function test_hasAccessFalseBelowMinStake() external {
        vm.startPrank(alice);
        zent.approve(address(staking), 500 ether);
        staking.stake(500 ether, 30 days);
        vm.stopPrank();

        assertFalse(staking.hasAccess(alice));
    }

    function test_hasAccessTrueAtOrAboveMinStake() external {
        vm.startPrank(alice);
        zent.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE, 30 days);
        vm.stopPrank();

        assertTrue(staking.hasAccess(alice));
    }

    function test_hasAccessFalseAfterLockExpiry() external {
        vm.startPrank(alice);
        zent.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE, 30 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);
        assertFalse(staking.hasAccess(alice));
    }

    // ─── Governor-Only Config ─────────────────────────────────────────────

    function test_setMinStakeUpdatesValue() external {
        vm.prank(governor);
        staking.setMinStake(2_500 ether);
        assertEq(staking.minStake(), 2_500 ether);
    }

    function test_setMinStakeRejectedFromNonGovernor() external {
        bytes32 role = staking.GOVERNOR_ROLE();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, role));
        staking.setMinStake(1 ether);
    }
}
