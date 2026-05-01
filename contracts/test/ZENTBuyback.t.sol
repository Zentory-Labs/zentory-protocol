// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ZENTBuyback} from "../src/ZENTBuyback.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ZENTBuybackTest is Test {
    MockERC20 public zent;
    MockERC20 public usdc;
    ZENTBuyback public buyback;

    address public owner = makeAddr("owner");
    address public caller = makeAddr("caller");
    address public stranger = makeAddr("stranger");

    uint256 constant MIN_THRESHOLD = 1000e6; // 1000 USDC (6 decimals)

    function setUp() external {
        zent = new MockERC20("Zentory Token", "ZENT");
        usdc = new MockERC20("USD Coin", "USDC");
        buyback = new ZENTBuyback(address(zent), address(usdc), MIN_THRESHOLD);
        buyback.transferOwnership(owner);

        vm.label(address(zent), "ZENT");
        vm.label(address(usdc), "USDC");
        vm.label(address(buyback), "ZENTBuyback");
    }

    // ─── Constructor ───────────────────────────────────────────────────────

    function test_constructorRejectsZeroZent() external {
        vm.expectRevert(bytes("ZENTBuyback: zero ZENT address"));
        new ZENTBuyback(address(0), address(usdc), MIN_THRESHOLD);
    }

    function test_constructorRejectsZeroUsdc() external {
        vm.expectRevert(bytes("ZENTBuyback: zero USDC address"));
        new ZENTBuyback(address(zent), address(0), MIN_THRESHOLD);
    }

    function test_immutablesSet() external view {
        assertEq(address(buyback.zent()), address(zent));
        assertEq(address(buyback.usdc()), address(usdc));
        assertEq(buyback.minBuybackThreshold(), MIN_THRESHOLD);
        assertEq(buyback.deadAddress(), 0x000000000000000000000000000000000000dEaD);
    }

    // ─── setThreshold ──────────────────────────────────────────────────────

    function test_setThresholdOnlyOwner() external {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", stranger));
        buyback.setThreshold(2000e6);
    }

    function test_setThresholdEmitsEvent() external {
        vm.prank(owner);
        vm.expectEmit();
        emit ZENTBuyback.ThresholdUpdated(MIN_THRESHOLD, 2000e6);
        buyback.setThreshold(2000e6);
        assertEq(buyback.minBuybackThreshold(), 2000e6);
    }

    // ─── execute ──────────────────────────────────────────────────────────

    function test_executeRevertsBelowThreshold() external {
        // Mint small USDC amount (below threshold)
        usdc.mint(caller, 500e6);
        vm.prank(caller);
        usdc.approve(address(buyback), type(uint256).max);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ZENTBuyback.BelowThreshold.selector, 500e6));
        buyback.execute();
    }

    function test_executeRevertsWhenNoUsdcReceived() external {
        // Caller has USDC but no approval
        usdc.mint(caller, 1000e6);

        vm.prank(caller);
        vm.expectRevert();
        buyback.execute();
    }

    function test_executeSucceedsAboveThresholdAndBurnsZENT() external {
        // Mint USDC to caller and pre-mint ZENT to buyback contract for burn
        usdc.mint(caller, 5000e6);
        zent.mint(address(buyback), 1000e18);

        vm.prank(caller);
        usdc.approve(address(buyback), type(uint256).max);

        uint256 deadZentBefore = zent.balanceOf(0x000000000000000000000000000000000000dEaD);

        vm.prank(caller);
        buyback.execute();

        assertEq(usdc.balanceOf(address(buyback)), 5000e6);
        assertEq(zent.balanceOf(0x000000000000000000000000000000000000dEaD), deadZentBefore + 1000e18);
    }

    function test_executeTransfersUsdcFromCaller() external {
        usdc.mint(caller, 2000e6);
        zent.mint(address(buyback), 100e18);

        vm.prank(caller);
        usdc.approve(address(buyback), type(uint256).max);

        uint256 callerUsdcBefore = usdc.balanceOf(caller);
        uint256 contractUsdcBefore = usdc.balanceOf(address(buyback));

        vm.prank(caller);
        buyback.execute();

        assertEq(usdc.balanceOf(caller), callerUsdcBefore - 2000e6);
        assertEq(usdc.balanceOf(address(buyback)), contractUsdcBefore + 2000e6);
    }

    function test_executeNoZENTToBurn() external {
        // Caller sends USDC but no ZENT in contract — should not revert
        usdc.mint(caller, 2000e6);

        vm.prank(caller);
        usdc.approve(address(buyback), type(uint256).max);

        vm.prank(caller);
        buyback.execute(); // should not revert

        assertEq(usdc.balanceOf(address(buyback)), 2000e6);
        assertEq(zent.balanceOf(0x000000000000000000000000000000000000dEaD), 0);
    }

    // ─── rescueToken ───────────────────────────────────────────────────────

    function test_rescueTokenOnlyOwner() external {
        usdc.mint(address(buyback), 500e6);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", stranger));
        buyback.rescueToken(address(usdc), 500e6);
    }

    function test_rescueTokenCannotRescueZENTOrUSDC() external {
        vm.prank(owner);
        vm.expectRevert(bytes("ZENTBuyback: cannot rescue zent or usdc"));
        buyback.rescueToken(address(zent), 1e18);

        vm.prank(owner);
        vm.expectRevert(bytes("ZENTBuyback: cannot rescue zent or usdc"));
        buyback.rescueToken(address(usdc), 1e6);
    }

    function test_rescueTokenSucceedsForOtherToken() external {
        MockERC20 other = new MockERC20("Other Token", "OTHER");
        other.mint(address(buyback), 300e18);

        vm.prank(owner);
        buyback.rescueToken(address(other), 300e18);

        assertEq(other.balanceOf(owner), 300e18);
        assertEq(other.balanceOf(address(buyback)), 0);
    }
}
