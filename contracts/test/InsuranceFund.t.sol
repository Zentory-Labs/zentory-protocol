// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MCK") {
        _mint(msg.sender, 1_000_000e18);
    }
}

contract InsuranceFundTest is Test {
    InsuranceFund fund;
    MockToken token;
    address gov = makeAddr("gov");
    address vault = makeAddr("vault");

    function setUp() public {
        fund = new InsuranceFund(gov);
        token = new MockToken();
        // Reserves arrive by plain ERC20 transfer (FeeDistributor share / slashed bonds).
        token.transfer(address(fund), 100_000e18);
    }

    function test_constructor_setsGovernanceOwner() external view {
        assertEq(fund.owner(), gov, "owner must be governance");
    }

    function test_constructor_rejectsZeroGovernance() external {
        // Ownable rejects a zero owner with its typed error.
        vm.expectRevert(abi.encodeWithSignature("OwnableInvalidOwner(address)", address(0)));
        new InsuranceFund(address(0));
    }

    function test_reserveOf_reportsBalance() external view {
        assertEq(fund.reserveOf(address(token)), 100_000e18, "reserves auditable on-chain");
    }

    function test_payout_onlyOwner_transfersAndDecrementsReserves() external {
        vm.prank(gov);
        fund.payout(address(token), vault, 40_000e18, "zBTC bad debt 2026-Q4");
        assertEq(token.balanceOf(vault), 40_000e18, "recipient received payout");
        assertEq(fund.reserveOf(address(token)), 60_000e18, "reserves decremented");
    }

    function test_payout_revertsForNonOwner() external {
        vm.prank(vault);
        vm.expectRevert(); // Ownable: caller is not the owner
        fund.payout(address(token), vault, 1, "unauthorized");
    }

    function test_payout_rejectsZeroRecipientAndAmount() external {
        vm.startPrank(gov);
        vm.expectRevert("InsuranceFund: zero recipient");
        fund.payout(address(token), address(0), 1, "x");
        vm.expectRevert("InsuranceFund: zero amount");
        fund.payout(address(token), vault, 0, "x");
        vm.stopPrank();
    }
}
