// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ZENT} from "../src/ZENT.sol";
import {ZENTVesting} from "../src/ZENTVesting.sol";

contract ZENTVestingTest is Test {
    ZENT internal zent;
    ZENTVesting internal vesting;

    address internal beneficiary = makeAddr("beneficiary");
    address internal otherBeneficiary = makeAddr("otherBeneficiary");

    function setUp() public {
        zent = new ZENT();
        vesting = new ZENTVesting(address(zent));
    }

    function test_fundRejectsDuplicateBeneficiaryInBatch() external {
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary;
        beneficiaries[1] = beneficiary;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e18;
        amounts[1] = 50e18;

        uint64[] memory cliffs = new uint64[](2);
        cliffs[0] = 10 days;
        cliffs[1] = 10 days;

        uint64[] memory durations = new uint64[](2);
        durations[0] = 100 days;
        durations[1] = 100 days;

        bool[] memory revocable = new bool[](2);
        revocable[0] = true;
        revocable[1] = true;

        zent.approve(address(vesting), 150e18);

        vm.expectRevert("ZENTVesting: duplicate beneficiary");
        vesting.fund(beneficiaries, amounts, cliffs, durations, revocable, uint64(block.timestamp));
    }

    function test_fundRejectsOverwritingExistingSchedule() external {
        _fundSingle(beneficiary, 100e18, 10 days, 100 days, true);

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 50e18;

        uint64[] memory cliffs = new uint64[](1);
        cliffs[0] = 10 days;

        uint64[] memory durations = new uint64[](1);
        durations[0] = 100 days;

        bool[] memory revocable = new bool[](1);
        revocable[0] = true;

        zent.approve(address(vesting), 50e18);

        vm.expectRevert("ZENTVesting: schedule exists");
        vesting.fund(beneficiaries, amounts, cliffs, durations, revocable, uint64(block.timestamp));
    }

    function test_revokePreservesVestedButUnclaimedTokens() external {
        uint64 start = uint64(block.timestamp);
        // cliff 10d + vest 90d = 100d total. Linear-from-start (finding #5):
        // at start+60d, vested = 100e18 * 60/100 = 60e18.
        _fundSingle(beneficiary, 100e18, 10 days, 90 days, true);

        vm.warp(start + 60 days);
        assertEq(vesting.vestedAmount(beneficiary), 60e18);

        uint256 deployerBalanceBefore = zent.balanceOf(address(this));
        vesting.revoke(beneficiary);

        // Unvested (40e18) returns to the deployer; vested (60e18) is preserved.
        assertEq(zent.balanceOf(address(this)), deployerBalanceBefore + 40e18);
        assertEq(vesting.vestedAmount(beneficiary), 60e18);

        vm.prank(beneficiary);
        vesting.claim();

        assertEq(zent.balanceOf(beneficiary), 60e18);
        assertEq(vesting.vestedAmount(beneficiary), 0);
    }

    /// @notice Spec-conformance audit finding #5: a cliff must produce a lump
    ///         unlock. Linear-from-start over (cliff + vest) means at the cliff
    ///         the accrued portion (cliff / total) unlocks at once. Pre-fix the
    ///         curve re-anchored at the cliff end, so the documented cliff
    ///         release vested 0.
    function test_lumpUnlocksAtCliff() external {
        uint64 start = uint64(block.timestamp);
        // cliff 25d + vest 75d = 100d total -> 25% unlocks at the cliff.
        _fundSingle(beneficiary, 100e18, 25 days, 75 days, false);

        // Just before the cliff: nothing is claimable.
        vm.warp(start + 25 days - 1);
        assertEq(vesting.vestedAmount(beneficiary), 0, "nothing vests before the cliff");

        // At the cliff: the 25% lump unlocks at once (pre-fix this was 0).
        vm.warp(start + 25 days);
        assertEq(vesting.vestedAmount(beneficiary), 25e18, "25% lump unlocks at the cliff");

        // Partway through: linear from start (75/100 at 75 days).
        vm.warp(start + 75 days);
        assertEq(vesting.vestedAmount(beneficiary), 75e18, "linear from start after the cliff");

        // At the end: fully vested.
        vm.warp(start + 100 days);
        assertEq(vesting.vestedAmount(beneficiary), 100e18, "fully vested at the end");
    }

    function test_fundRejectsZeroDuration() external {
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        uint64[] memory cliffs = new uint64[](1);
        cliffs[0] = 10 days;

        uint64[] memory durations = new uint64[](1);
        durations[0] = 0;

        bool[] memory revocable = new bool[](1);
        revocable[0] = true;

        zent.approve(address(vesting), 100e18);

        vm.expectRevert("ZENTVesting: zero duration");
        vesting.fund(beneficiaries, amounts, cliffs, durations, revocable, uint64(block.timestamp));
    }

    function _fundSingle(address account, uint256 amount, uint64 cliff, uint64 duration, bool revocable) internal {
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = account;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        uint64[] memory cliffs = new uint64[](1);
        cliffs[0] = cliff;

        uint64[] memory durations = new uint64[](1);
        durations[0] = duration;

        bool[] memory revocables = new bool[](1);
        revocables[0] = revocable;

        zent.approve(address(vesting), amount);
        vesting.fund(beneficiaries, amounts, cliffs, durations, revocables, uint64(block.timestamp));
    }
}
