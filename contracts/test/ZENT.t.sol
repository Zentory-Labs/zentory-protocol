// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ZENT} from "../src/ZENT.sol";

contract ZENTTest is Test {
    ZENT public zent;

    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    function setUp() public {
        zent = new ZENT();
    }

    // ─── Basic Properties ──────────────────────────────────────────────────────

    function test_totalSupply() external view {
        assertEq(zent.totalSupply(), TOTAL_SUPPLY);
        assertEq(zent.CAP(), TOTAL_SUPPLY);
    }

    function test_decimals() external view {
        assertEq(zent.decimals(), 18);
    }

    function test_nameAndSymbol() external view {
        assertEq(zent.name(), "Zentory Token");
        assertEq(zent.symbol(), "ZENT");
    }

    function test_initialDeployerBalance() external view {
        assertEq(zent.balanceOf(address(this)), TOTAL_SUPPLY);
    }

    // ─── No Mint ───────────────────────────────────────────────────────────────

    function test_mintSelectorNotInBytecode() external {
        (bool success,) = address(zent).call(abi.encodeWithSignature("mint(address,uint256)", address(0xBEEF), 1e18));
        assertFalse(success, "mint should not be callable");
    }

    // ─── Transfers ────────────────────────────────────────────────────────────

    function test_transfer() external {
        address alice = makeAddr("alice");
        uint256 amount = 1000e18;
        zent.transfer(alice, amount);
        assertEq(zent.balanceOf(alice), amount);
        assertEq(zent.balanceOf(address(this)), TOTAL_SUPPLY - amount);
    }

    function test_transferToZeroReverts() external {
        vm.expectRevert();
        zent.transfer(address(0), 1000e18);
    }

    function test_transferFrom() external {
        address alice = makeAddr("alice");
        uint256 amount = 500e18;
        zent.approve(alice, amount);
        vm.prank(alice);
        zent.transferFrom(address(this), alice, amount);
        assertEq(zent.balanceOf(alice), amount);
    }

    // ─── Burn ─────────────────────────────────────────────────────────────────

    function test_burn() external {
        uint256 amount = 100e18;
        uint256 balBefore = zent.balanceOf(address(this));
        zent.burn(amount);
        assertEq(zent.balanceOf(address(this)), balBefore - amount);
        assertEq(zent.totalSupply(), TOTAL_SUPPLY - amount);
    }

    function test_burnFrom() external {
        address alice = makeAddr("alice");
        uint256 amount = 200e18;
        zent.transfer(alice, amount);
        vm.prank(alice);
        zent.approve(address(this), amount);
        zent.burnFrom(alice, amount);
        assertEq(zent.balanceOf(alice), 0);
        assertEq(zent.totalSupply(), TOTAL_SUPPLY - amount);
    }

    // ─── No Cosmetic Admin Surface ─────────────────────────────────────────────

    function test_noOwnershipSurface() external {
        (bool renounceSuccess,) = address(zent).call(abi.encodeWithSignature("renounceOwnership()"));
        (bool deployerSuccess,) = address(zent).call(abi.encodeWithSignature("deployer()"));
        (bool isRenouncedSuccess,) = address(zent).call(abi.encodeWithSignature("isRenounced()"));

        assertFalse(renounceSuccess, "renounceOwnership should not exist");
        assertFalse(deployerSuccess, "deployer should not exist");
        assertFalse(isRenouncedSuccess, "isRenounced should not exist");
    }

    function test_transferWithVestingSelectorNotInBytecode() external {
        (bool success,) = address(zent)
            .call(abi.encodeWithSignature("transferWithVesting(address,uint256,uint8)", address(0xBEEF), 1e18, 0));
        assertFalse(success, "transferWithVesting should not exist");
    }

    // ─── Vote / Delegation ───────────────────────────────────────────────────

    function test_delegate() external {
        address voter = makeAddr("voter");
        zent.transfer(voter, 1000e18);
        vm.prank(voter);
        zent.delegate(voter);
        assertEq(zent.getVotes(voter), 1000e18);
    }

    function test_delegationTransfersCheckpoint() external {
        address from = makeAddr("from");
        address to = makeAddr("to");
        zent.transfer(from, 500e18);
        vm.prank(from);
        zent.delegate(to);
        assertEq(zent.getVotes(to), 500e18);
    }

    // ─── Cap invariant ────────────────────────────────────────────────────────

    function test_totalSupplyNeverExceedsCap() external {
        zent.burn(1);
        assertLe(zent.totalSupply(), zent.CAP());
    }
}
