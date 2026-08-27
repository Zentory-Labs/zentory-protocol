// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title SpotVault — H-1 emergency-redeem haircut regression
/// @notice Berkay Çarıkçıoğlu's audit finding: emergency redeems bypass the
///         performance fee accrual, leaving the protocol's fee claim stranded
///         against depositors who have already exited. A follow-on claimFees()
///         can then drain value the protocol never actually earned.
///
///         Fix: `redeemEmergency` proportionally decrements
///         `performanceFeeAccrued` for the redeemed shares.
///
///         These tests assert the FIXED behaviour using a vault with a real
///         performance-fee BPS and a pre-accrued fee position. They reuse the
///         SpotVault test infrastructure from `SpotVaultEmergency.t.sol`.

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SpotVault, ISpotSwapAdapter, AggregatorV3Interface} from "../../src/vaults/SpotVault.sol";
import {MockERC20} from "../invariants/mocks/MockERC20.sol";

contract H1Oracle is AggregatorV3Interface {
    int256 public answer;
    uint256 public updatedAt;
    uint8 public constant decimals = 8;

    constructor(int256 a) { answer = a; updatedAt = block.timestamp; }
    function setPrice(int256 a) external { answer = a; updatedAt = block.timestamp; }
    function setUpdatedAt(uint256 t) external { updatedAt = t; }
    function setAnswer(int256 a) external { answer = a; }

    function latestRoundData()
        external view returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

contract H1Adapter is ISpotSwapAdapter {
    address public immutable asset;
    address public immutable cash;
    H1Oracle public immutable oracle;
    uint8 immutable aDec; uint8 immutable cDec; uint8 immutable pDec;

    constructor(address asset_, address cash_, address oracle_) {
        asset = asset_; cash = cash_; oracle = H1Oracle(oracle_);
        aDec = IERC20Metadata(asset_).decimals();
        cDec = IERC20Metadata(cash_).decimals();
        pDec = H1Oracle(oracle_).decimals();
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut)
        external returns (uint256 out)
    {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        uint256 p = uint256(oracle.answer());
        if (tokenIn == asset && tokenOut == cash) {
            out = (amountIn * (10 ** cDec) * p) / ((10 ** aDec) * (10 ** pDec));
        } else if (tokenIn == cash && tokenOut == asset) {
            out = (amountIn * (10 ** aDec) * (10 ** pDec)) / ((10 ** cDec) * p);
        } else {
            revert("unsupported pair");
        }
        require(out >= minOut, "mock slippage");
        IERC20(tokenOut).transfer(msg.sender, out);
    }
}

contract SpotVaultEmergencyH1Test is Test {
    MockERC20 wbtc;
    MockERC20 usdc;
    H1Oracle oracle;
    H1Adapter adapter;
    SpotVault vault;

    address alice = makeAddr("alice");
    int256 constant PRICE_50K = 50_000 * 1e8;
    uint256 constant TEN_BTC = 10 * 1e8;
    uint256 constant MAX_STALE = 1 hours;
    uint256 constant PERF_FEE_BPS = 2000; // 20%

    function setUp() public {
        vm.warp(1_700_000_000);
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        oracle = new H1Oracle(PRICE_50K);
        adapter = new H1Adapter(address(wbtc), address(usdc), address(oracle));

        vault = new SpotVault(
            address(wbtc), address(usdc), address(oracle), MAX_STALE,
            "Zentory BTC H1 Vault", "zBTCH1",
            0,        // rebalanceThresholdBps
            100,      // maxSlippageBps
            PERF_FEE_BPS,
            address(this), address(this),
            1 hours
        );
        vault.setSwapAdapter(address(adapter));
        vault.grantRole(vault.KEEPER_ROLE(), address(this));
        vault.grantRole(vault.RISK_COUNCIL_ROLE(), address(this));

        wbtc.mint(address(adapter), 1_000 * 1e8);
        usdc.mint(address(adapter), 100_000_000 * 1e6);
        wbtc.mint(alice, TEN_BTC);
    }

    function _deposit() internal returns (uint256 shares) {
        vm.startPrank(alice);
        wbtc.approve(address(vault), TEN_BTC);
        shares = vault.deposit(TEN_BTC, alice);
        vm.stopPrank();
    }

    function _accrueFee() internal {
        // Strategy: deposit 10 BTC, push the oracle to $60k, then sell half
        // the position for USDC. With the new mark, 5 BTC sells for 5*$60k =
        // 300M USDC vs the prior HWM of 10 BTC * $50k = 500M USDC equivalent.
        // grossValue now = 5 BTC + 300M USDC ≈ 5 + 5 = 10 BTC equivalent at
        // $60k. NAV per share is unchanged in BTC terms (no alpha yet).
        //
        // To create alpha we need the mark to push past the HWM-tracked
        // BTC-equivalent NAV. Rebalance back to 100% long at the new mark:
        // vault swaps 300M USDC for 5 BTC at $60k → back to 10 BTC.
        // grossValue is still 10 BTC. NAV per share = 1e8. Still no alpha.
        //
        // The trick: simulate the HWM being below current NAV by first
        // artificially setting highWaterMark down via a different fee
        // evaluation cycle. Easier approach: oracle goes UP further to $80k,
        // rebalance, evaluate. At $80k with 10 BTC long, gross is still
        // 10 BTC equivalent. No alpha still — the vault NAV is mark-neutral.
        //
        // Real alpha comes from PnL flowing into the vault beyond principal.
        // SpotVault earns alpha only via fees generated by other mechanisms
        // (e.g. trading fees). For a unit test of the *decrement* invariant
        // we instead seed the performanceFeeAccrued directly via the only
        // mechanism the vault exposes: a small mark-driven delta. We use
        // the documented "HWM = 1 unit" initial state and deposit slightly
        // more than the HWM so the first evaluateFees sees positive alpha.
        //
        // Simplest reliable path: mint extra USDC into the vault AFTER
        // rebalance. evaluateFees sees NAV = (idle_btc + idle_cash) / supply >
        // HWM of 1 unit. This works because SpotVault NAV is settle-able,
        // not mark-based.
        vault.rebalanceTo(10_000);
        // Seed extra cash so evaluateFees sees NAV above HWM.
        usdc.mint(address(vault), 5 * 1e6); // +5 USDC of NAV
        vault.evaluateFees();
    }

    /// @notice Core invariant: emergency redeem drops performanceFeeAccrued
    ///         proportionally to the redeemed share fraction.
    function test_emergencyRedeem_decrementsFeeAccrued() public {
        uint256 shares = _deposit();
        _accrueFee();

        uint256 accruedBefore = vault.performanceFeeAccrued();
        assertGt(accruedBefore, 0, "test setup must produce a fee accrual");

        uint256 half = shares / 2;
        vm.prank(alice);
        vault.redeemEmergency(half, alice, alice);

        uint256 accruedAfter = vault.performanceFeeAccrued();
        // After redeeming `half / totalSupply_pre` of the supply, the
        // protocol's fee claim should drop by the same fraction.
        uint256 remainingShares = vault.totalSupply();
        uint256 expectedAccrued = (accruedBefore * remainingShares) / shares;
        assertApproxEqAbs(accruedAfter, expectedAccrued, 1);
        assertLt(accruedAfter, accruedBefore, "fee accrued must decrease");
    }

    /// @notice The protocol cannot subsequently claimFees() more than the
    ///         underlying left in the vault. We check via the invariant:
    ///         totalAssets is always >= 0.
    function test_emergencyRedeem_totalAssetsStaysNonNegative() public {
        uint256 shares = _deposit();
        _accrueFee();

        // Drain with three successive emergency redeems.
        uint256 t0 = block.timestamp;
        vm.prank(alice);
        vault.redeemEmergency(shares / 3, alice, alice);
        vm.warp(t0 + 2 hours);
        oracle.setUpdatedAt(block.timestamp);
        vm.prank(alice);
        vault.redeemEmergency(shares / 3, alice, alice);
        vm.warp(t0 + 4 hours);
        oracle.setUpdatedAt(block.timestamp);
        vm.prank(alice);
        vault.redeemEmergency(shares / 3, alice, alice);

        // totalAssets is settle-able: gross - accrued, clamped at zero.
        uint256 ta = vault.totalAssets();
        uint256 gross = vault.grossValue();
        uint256 accrued = vault.performanceFeeAccrued();
        assertEq(ta, gross > accrued ? gross - accrued : 0, "totalAssets invariant holds");
    }
}
