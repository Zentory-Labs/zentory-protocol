// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {BaseVault} from "../../src/vaults/BaseVault.sol";

contract ERC20DecimalsMock is ERC20 {
    uint8 private tokenDecimals;

    constructor(uint8 decimals_) ERC20("Mock Asset", "MOCK") {
        tokenDecimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title BaseVaultTest
contract BaseVaultTest is Test {
    BaseVault public vault;
    ERC20Mock public asset;
    address public admin = makeAddr("admin");
    address public keeper = makeAddr("keeper");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public feeRecipient = makeAddr("feeRecipient");

    // MockERC20 uses 18 decimals (OZ default)
    uint256 constant ASSET_UNIT = 10 ** 18;

    function setUp() public {
        asset = new ERC20Mock();
        asset.mint(address(this), type(uint256).max);

        // Deploy vault with this test contract as admin
        vault = new BaseVault(
            address(asset), // _asset
            "zBTC Share", // _name
            "zBTC", // _symbol
            30000, // _maxLeverage (3x)
            10000, // _maxPositionSizeBPS (100% TVL)
            2000, // _circuitBreakerDrawdownBPS (20%)
            500, // _rebalanceThresholdBPS (5%)
            2000, // _performanceFeeBPS (20%)
            feeRecipient, // _feeRecipient
            address(this) // _admin — test contract is admin
        );

        vm.label(address(asset), "WBTC");
        vm.label(address(vault), "zBTCVault");
        vm.label(admin, "admin");
        vm.label(keeper, "keeper");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(feeRecipient, "feeRecipient");

        // Grant keeper role to keeper address
        vault.grantRole(vault.KEEPER_ROLE(), keeper);

        // Grant risk council role to this test contract (admin) for circuit breaker tests
        vault.grantRole(vault.RISK_COUNCIL_ROLE(), address(this));

        // Give some assets to alice for tests
        asset.transfer(alice, 1000 * ASSET_UNIT);
    }

    // ─── Initial State ───────────────────────────────────────────────────────

    function test_initialNavIsOneToOne() external view {
        assertEq(vault.getNavPerShare(), ASSET_UNIT);
        assertEq(vault.highWaterMark(), ASSET_UNIT);
        assertEq(vault.lastNavPerShare(), ASSET_UNIT);
    }

    function test_initialTotalAssetsIsZero() external view {
        assertEq(vault.totalAssets(), 0);
    }

    function test_initialTotalSupplyIsZero() external view {
        assertEq(vault.totalSupply(), 0);
    }

    // ─── Deposit ─────────────────────────────────────────────────────────────

    function test_firstDepositorGetsOneToOneShares() external {
        uint256 depositAmount = 10 * ASSET_UNIT;
        asset.transfer(alice, depositAmount);

        vm.prank(alice);
        asset.approve(address(vault), depositAmount);

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        assertEq(shares, depositAmount);
        assertEq(vault.balanceOf(alice), depositAmount);
        assertEq(vault.totalAssets(), depositAmount);
    }

    function test_secondDepositorGetsProportionalShares() external {
        // Alice deposits first
        uint256 aliceDeposit = 10 * ASSET_UNIT;
        asset.transfer(alice, aliceDeposit);
        vm.prank(alice);
        asset.approve(address(vault), aliceDeposit);
        vm.prank(alice);
        vault.deposit(aliceDeposit, alice);

        // Simulate yield: transfer more asset to vault
        asset.transfer(address(vault), 5 * ASSET_UNIT);
        // totalAssets = 15, totalShares = 10, nav = 1.5

        uint256 bobDeposit = 15 * ASSET_UNIT;
        asset.transfer(bob, bobDeposit);
        vm.prank(bob);
        asset.approve(address(vault), bobDeposit);
        vm.prank(bob);
        uint256 bobShares = vault.deposit(bobDeposit, bob);

        // NAV=1.5, bob deposits 15 assets → gets 10 shares
        assertLt(bobShares, bobDeposit);
        assertEq(bobShares, 10 * ASSET_UNIT);
    }

    // ─── High-Water Mark & Performance Fee ─────────────────────────────────

    function test_noFeeWhenNavBelowHwm() external {
        uint256 deposit = 10 * ASSET_UNIT;
        asset.transfer(alice, deposit);
        vm.prank(alice);
        asset.approve(address(vault), deposit);
        vm.prank(alice);
        vault.deposit(deposit, alice);

        // No yield — NAV stays at HWM. Fee evaluation should not charge anything.
        vault.evaluateFees();
        assertEq(vault.highWaterMark(), ASSET_UNIT);
    }

    function test_feeChargedOnAlphaAboveHwm() external {
        uint256 deposit = 100 * ASSET_UNIT;
        asset.transfer(alice, deposit);
        vm.prank(alice);
        asset.approve(address(vault), deposit);
        vm.prank(alice);
        vault.deposit(deposit, alice);

        // Simulate alpha: vault grows to 120 (20% gain)
        asset.transfer(address(vault), 20 * ASSET_UNIT);

        uint256 hwmBefore = vault.highWaterMark();
        vault.evaluateFees();

        assertGt(vault.highWaterMark(), hwmBefore);
        assertGt(vault.performanceFeeAccrued(), 0);
    }

    function test_feeMathUsesUnderlyingAssetDecimals() external {
        ERC20DecimalsMock asset8 = new ERC20DecimalsMock(8);
        uint256 asset8Unit = 10 ** 8;
        BaseVault vault8 = new BaseVault(
            address(asset8), "zBTC Share", "zBTC", 30000, 10000, 2000, 500, 2000, feeRecipient, address(this)
        );

        uint256 deposit = 100 * asset8Unit;
        asset8.mint(alice, deposit);

        vm.prank(alice);
        asset8.approve(address(vault8), deposit);
        vm.prank(alice);
        vault8.deposit(deposit, alice);

        asset8.mint(address(vault8), 20 * asset8Unit);
        vault8.evaluateFees();

        assertEq(vault8.performanceFeeAccrued(), 4 * asset8Unit);
    }

    function test_constructorRejectsZeroFeeRecipient() external {
        vm.expectRevert("BaseVault: zero fee recipient");
        new BaseVault(address(asset), "zBTC Share", "zBTC", 30000, 10000, 2000, 500, 2000, address(0), address(this));
    }

    function test_constructorRejectsExcessivePerformanceFee() external {
        vm.expectRevert("BaseVault: invalid performance fee");
        new BaseVault(address(asset), "zBTC Share", "zBTC", 30000, 10000, 2000, 500, 10001, feeRecipient, address(this));
    }

    function test_hwmNotUpdatedWhenNavBelowHwm() external {
        uint256 deposit = 100 * ASSET_UNIT;
        asset.transfer(alice, deposit);
        vm.prank(alice);
        asset.approve(address(vault), deposit);
        vm.prank(alice);
        vault.deposit(deposit, alice);

        // Simulate loss — NAV drops below HWM
        vm.prank(address(vault));
        IERC20(asset).transfer(address(1), 20 * ASSET_UNIT);

        uint256 hwmBefore = vault.highWaterMark();
        vault.evaluateFees();
        assertEq(vault.highWaterMark(), hwmBefore);
    }

    // ─── Keeper ────────────────────────────────────────────────────────────

    function test_onlyKeeperCanRecordTrade() external {
        vm.prank(alice);
        vm.expectRevert();
        vault.recordTrade(int8(1), 1e8, 50000e8);
    }

    function test_keeperCanRecordTrade() external {
        vm.prank(keeper);
        vault.recordTrade(int8(1), 5 * ASSET_UNIT, 50000e8);

        assertEq(uint8(vault.currentDirection()), 1);
        assertEq(vault.currentPositionSize(), 5 * ASSET_UNIT);
    }

    function test_invalidDirectionReverts() external {
        vm.prank(keeper);
        vm.expectRevert("Invalid direction");
        vault.recordTrade(int8(2), 1e8, 50000e8);
    }

    // ─── Circuit Breaker ────────────────────────────────────────────────────

    function test_circuitBreakerBlocksDeposit() external {
        vault.activateCircuitBreaker("Risk council");

        asset.transfer(alice, 10 * ASSET_UNIT);
        vm.prank(alice);
        asset.approve(address(vault), 10 * ASSET_UNIT);

        vm.prank(alice);
        vm.expectRevert("Circuit breaker active");
        vault.deposit(10 * ASSET_UNIT, alice);
    }

    function test_circuitBreakerBlocksMint() external {
        vault.activateCircuitBreaker("Risk council");

        asset.transfer(alice, 10 * ASSET_UNIT);
        vm.prank(alice);
        asset.approve(address(vault), 10 * ASSET_UNIT);

        vm.prank(alice);
        vm.expectRevert("Circuit breaker active");
        vault.mint(10 * ASSET_UNIT, alice);
    }

    function test_onlyAdminCanDeactivateCircuitBreaker() external {
        vault.activateCircuitBreaker("Risk council");

        vm.prank(alice);
        vm.expectRevert();
        vault.deactivateCircuitBreaker();

        vault.deactivateCircuitBreaker();
        assertFalse(vault.isCircuitBreakerActive());
    }

    // ─── Withdrawals ───────────────────────────────────────────────────────

    function test_withdrawReturnsAssets() external {
        uint256 deposit = 10 * ASSET_UNIT;
        asset.transfer(alice, deposit);
        vm.prank(alice);
        asset.approve(address(vault), deposit);
        vm.prank(alice);
        vault.deposit(deposit, alice);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 aliceBalBefore = asset.balanceOf(alice);

        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(asset.balanceOf(alice), aliceBalBefore + deposit);
    }

    // ─── Claim Fees ───────────────────────────────────────────────────────

    function test_claimFeesTransfersToFeeRecipient() external {
        uint256 deposit = 100 * ASSET_UNIT;
        asset.transfer(alice, deposit);
        vm.prank(alice);
        asset.approve(address(vault), deposit);
        vm.prank(alice);
        vault.deposit(deposit, alice);

        asset.transfer(address(vault), 20 * ASSET_UNIT);
        vault.evaluateFees();

        uint256 feeBalBefore = asset.balanceOf(feeRecipient);
        vault.claimFees();
        assertGt(asset.balanceOf(feeRecipient), feeBalBefore);
    }

    function test_claimFeesRevertsWhenZero() external {
        vm.expectRevert("No fees to claim");
        vault.claimFees();
    }

    // ─── Trade History ────────────────────────────────────────────────────

    function test_tradeHistoryRecorded() external {
        vm.prank(keeper);
        vault.recordTrade(int8(1), 5 * ASSET_UNIT, 50000e8);

        (int8 direction, uint256 size,,, bool closed) = vault.tradeHistory(0);

        assertEq(int8(direction), 1);
        assertEq(size, 5 * ASSET_UNIT);
        assertFalse(closed);
    }

    // ─── Access Control ───────────────────────────────────────────────────

    function test_keeperRoleAssigned() external view {
        assertFalse(vault.hasRole(vault.KEEPER_ROLE(), alice));
        assertTrue(vault.hasRole(vault.KEEPER_ROLE(), keeper));
    }

    function test_defaultAdminIsAdmin() external view {
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), address(this)));
    }
}
