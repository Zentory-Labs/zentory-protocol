// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FeeDistributor} from "../../src/fees/FeeDistributor.sol";
import {IFeeDistributor} from "../../src/interfaces/IFeeDistributor.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract FeeDistributorTest is Test {
    ERC20 internal wbtc;
    ERC20 internal zent;
    FeeDistributor internal distributor;

    address internal governor = makeAddr("governor");
    address internal gpEngine = makeAddr("gpEngine");
    address internal insurance = makeAddr("insurance");
    address internal treasury = makeAddr("treasury");
    address internal vault = makeAddr("vault");
    address internal stranger = makeAddr("stranger");

    function setUp() external {
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        zent = new MockERC20("Zentory Token", "ZENT", 18);
        distributor = new FeeDistributor(address(wbtc), address(zent), governor, gpEngine, insurance, treasury);

        // Mint WBTC to the vault so it can accumulate fees
        MockERC20(address(wbtc)).mint(vault, 1_000 ether);
    }

    // ─── Constructor ───────────────────────────────────────────────────────

    function test_constructorRejectsZeroAsset() external {
        vm.expectRevert(bytes("FeeDistributor: zero asset"));
        new FeeDistributor(address(0), address(zent), governor, gpEngine, insurance, treasury);
    }

    function test_constructorRejectsZeroZent() external {
        vm.expectRevert(bytes("FeeDistributor: zero zent"));
        new FeeDistributor(address(wbtc), address(0), governor, gpEngine, insurance, treasury);
    }

    function test_constructorRejectsZeroGovernor() external {
        vm.expectRevert(bytes("FeeDistributor: zero governor"));
        new FeeDistributor(address(wbtc), address(zent), address(0), gpEngine, insurance, treasury);
    }

    function test_rolesAssignedCorrectly() external view {
        assertTrue(distributor.hasRole(distributor.DEFAULT_ADMIN_ROLE(), governor));
        assertTrue(distributor.hasRole(distributor.GOVERNOR_ROLE(), governor));
    }

    // ─── Accumulate ───────────────────────────────────────────────────────

    function test_accumulateIncrementsPendingFees() external {
        vm.startPrank(vault);
        wbtc.approve(address(distributor), type(uint256).max);
        distributor.accumulate(vault, 1 ether);
        vm.stopPrank();

        assertEq(distributor.pendingFees(vault), 1 ether);
    }

    function test_accumulateFromMultipleVaults() external {
        address vault2 = makeAddr("vault2");
        MockERC20(address(wbtc)).mint(vault2, 500 ether);

        vm.startPrank(vault);
        wbtc.approve(address(distributor), type(uint256).max);
        distributor.accumulate(vault, 1 ether);
        vm.stopPrank();

        vm.startPrank(vault2);
        MockERC20(address(wbtc)).approve(address(distributor), type(uint256).max);
        distributor.accumulate(vault2, 2 ether);
        vm.stopPrank();

        assertEq(distributor.pendingFees(vault), 1 ether);
        assertEq(distributor.pendingFees(vault2), 2 ether);
    }

    function test_accumulateRejectsZeroAmount() external {
        vm.prank(vault);
        vm.expectRevert(bytes("FeeDistributor: zero amount"));
        distributor.accumulate(vault, 0);
    }

    function test_accumulateRejectsZeroVault() external {
        vm.expectRevert(bytes("FeeDistributor: zero vault"));
        distributor.accumulate(address(0), 1 ether);
    }

    // ─── Distribute ──────────────────────────────────────────────────────

    function test_distributeSplitsFees505251510() external {
        // Vault accumulates 10_000_000 sats (0.0001 BTC = 10M satoshis)
        uint256 fee = 10_000_000;
        vm.startPrank(vault);
        wbtc.approve(address(distributor), type(uint256).max);
        distributor.accumulate(vault, fee);
        vm.stopPrank();

        vm.prank(stranger);
        distributor.distribute(vault);

        // 50% buyback: 5_000_000 sats
        assertEq(wbtc.balanceOf(address(distributor)), fee - fee / 2);
        assertEq(wbtc.balanceOf(gpEngine), fee * 25 / 100); // 25% → 2_500_000
        assertEq(wbtc.balanceOf(insurance), fee * 15 / 100); // 15% → 1_500_000
        assertEq(wbtc.balanceOf(treasury), fee * 10 / 100); // 10% → 1_000_000

        assertEq(distributor.pendingFees(vault), 0);
    }

    function test_distributeEmitsEvent() external {
        uint256 fee = 10_000_000;
        vm.startPrank(vault);
        wbtc.approve(address(distributor), type(uint256).max);
        distributor.accumulate(vault, fee);
        vm.stopPrank();

        vm.prank(stranger);
        vm.expectEmit();
        emit IFeeDistributor.FeesDistributed(
            fee * 50 / 100, // buyback stays in distributor
            fee * 25 / 100, // gpEngine
            fee * 15 / 100, // insurance
            fee * 10 / 100 // treasury
        );
        distributor.distribute(vault);
    }

    function test_distributeRevertsWhenNothingAccumulated() external {
        vm.prank(stranger);
        vm.expectRevert(bytes("FeeDistributor: nothing to distribute"));
        distributor.distribute(vault);
    }

    function test_distributeRejectsZeroVault() external {
        vm.expectRevert(bytes("FeeDistributor: zero vault"));
        vm.prank(stranger);
        distributor.distribute(address(0));
    }

    // ─── Trigger Buyback ─────────────────────────────────────────────────

    function test_triggerBuybackBurnsZent() external {
        // Seed vault WBTC and accumulate → distribute to populate the buyback pool
        uint256 fee = 1 ether;
        vm.startPrank(vault);
        wbtc.approve(address(distributor), type(uint256).max);
        distributor.accumulate(vault, fee);
        vm.stopPrank();

        vm.prank(stranger);
        distributor.distribute(vault);

        // Seed distributor with ZENT so it has something to burn (production: DEX swap acquires ZENT)
        MockERC20(address(zent)).mint(address(distributor), 1000 ether);

        address[] memory path = new address[](2);
        path[0] = address(wbtc);
        path[1] = address(zent);

        uint256 zentBefore = zent.balanceOf(address(0xdead));
        vm.prank(governor);
        distributor.triggerBuyback(path);
        uint256 zentAfter = zent.balanceOf(address(0xdead));

        // ZENT was transferred to 0xdead (burn address)
        assertGt(zentAfter, zentBefore);
        assertEq(distributor.pools(0), 0); // buyback pool drained
    }

    function test_triggerBuybackRejectsNonGovernor() external {
        address[] memory path = new address[](2);
        path[0] = address(wbtc);
        path[1] = address(zent);

        bytes32 role = distributor.GOVERNOR_ROLE();
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, role)
        );
        distributor.triggerBuyback(path);
    }

    // ─── WithdrawTo ──────────────────────────────────────────────────────

    function test_withdrawToTransfersFromGpEnginePool() external {
        // Seed GP engine pool via distribute
        uint256 fee = 10_000_000;
        vm.startPrank(vault);
        wbtc.approve(address(distributor), type(uint256).max);
        distributor.accumulate(vault, fee);
        vm.stopPrank();

        vm.prank(stranger);
        distributor.distribute(vault);

        uint256 gpBalanceBefore = wbtc.balanceOf(gpEngine);
        vm.prank(governor);
        distributor.withdrawTo(gpEngine, 500_000, 1); // POOL_GP_ENGINE = 1

        assertEq(wbtc.balanceOf(gpEngine), gpBalanceBefore + 500_000);
    }

    function test_withdrawToTransfersFromTreasuryPool() external {
        uint256 fee = 10_000_000;
        vm.startPrank(vault);
        wbtc.approve(address(distributor), type(uint256).max);
        distributor.accumulate(vault, fee);
        vm.stopPrank();

        vm.prank(stranger);
        distributor.distribute(vault);

        uint256 treasuryBalanceBefore = wbtc.balanceOf(treasury);
        vm.prank(governor);
        distributor.withdrawTo(treasury, 200_000, 3); // POOL_TREASURY = 3

        assertEq(wbtc.balanceOf(treasury), treasuryBalanceBefore + 200_000);
    }

    function test_withdrawToRejectsFromBuybackPool() external {
        MockERC20(address(wbtc)).mint(address(distributor), 1 ether);

        vm.prank(governor);
        vm.expectRevert(bytes("FeeDistributor: not directly withdrawable"));
        distributor.withdrawTo(gpEngine, 100_000, 0); // POOL_BUYBACK = 0
    }

    function test_withdrawToRejectsFromInsurancePool() external {
        MockERC20(address(wbtc)).mint(address(distributor), 1 ether);

        vm.prank(governor);
        vm.expectRevert(bytes("FeeDistributor: not directly withdrawable"));
        distributor.withdrawTo(gpEngine, 100_000, 2); // POOL_INSURANCE = 2
    }

    function test_withdrawToRejectsFromNonGovernor() external {
        bytes32 role = distributor.GOVERNOR_ROLE();
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, role)
        );
        distributor.withdrawTo(gpEngine, 100_000, 1); // POOL_GP_ENGINE = 1
    }

    // ─── Governor Config ─────────────────────────────────────────────────

    function test_setGpEngineUpdatesAddress() external {
        address newGp = makeAddr("newGp");
        vm.prank(governor);
        distributor.setGpEngine(newGp);
        assertEq(distributor.gpEngine(), newGp);
    }

    function test_setGpEngineRejectsZero() external {
        vm.prank(governor);
        vm.expectRevert(bytes("FeeDistributor: zero gp engine"));
        distributor.setGpEngine(address(0));
    }

    function test_setInsuranceUpdatesAddress() external {
        address newInsurance = makeAddr("newInsurance");
        vm.prank(governor);
        distributor.setInsurance(newInsurance);
        assertEq(distributor.insurance(), newInsurance);
    }

    function test_setTreasuryUpdatesAddress() external {
        address newTreasury = makeAddr("newTreasury");
        vm.prank(governor);
        distributor.setTreasury(newTreasury);
        assertEq(distributor.treasury(), newTreasury);
    }

    function test_setGpEngineRejectedFromNonGovernor() external {
        bytes32 role = distributor.GOVERNOR_ROLE();
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, role)
        );
        distributor.setGpEngine(makeAddr("newGp"));
    }
}
