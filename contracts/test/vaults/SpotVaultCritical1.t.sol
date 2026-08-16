// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// Regression tests for audit CRITICAL-1 (2026-08-07): a dust depositor could capture
/// the entire vault.
///
/// The bug: `totalAssets()` returns `gross - performanceFeeAccrued`, clamped to 0.
/// `performanceFeeAccrued` only ever grew (SpotVault had no claim path) and
/// `grossValue()` is underlying-denominated, so it FALLS when the underlying rallies
/// while the vault sits in cash. After any large exit plus a small adverse tick you
/// reach `totalSupply() > 0 && totalAssets() == 0`, where ERC-4626's
/// `assets.mulDiv(supply + 10**offset, totalAssets + 1)` divides by 1 and mints
/// ~`supply * 10**offset` shares for dust. Original PoC (asserts the BUG) is kept at
/// docs/security/poc/SpotVaultPinPoc.t.sol — these tests assert it is FIXED.
///
/// The exploit scenario is replayed verbatim; only the final assertions flip.

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SpotVault, ISpotSwapAdapter, AggregatorV3Interface} from "../../src/vaults/SpotVault.sol";
import {MockERC20} from "../invariants/mocks/MockERC20.sol";

contract PinOracle is AggregatorV3Interface {
    int256 public answer;
    uint256 public updatedAt;
    uint8 public constant decimals = 8;

    constructor(int256 a) {
        answer = a;
        updatedAt = block.timestamp;
    }

    function setPrice(int256 a) external {
        answer = a;
        updatedAt = block.timestamp;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

contract PinAdapter is ISpotSwapAdapter {
    address public immutable assetTok;
    address public immutable cashTok;
    PinOracle public immutable oracle;
    uint8 immutable aDec;
    uint8 immutable cDec;
    uint8 immutable pDec;

    constructor(address asset_, address cash_, address oracle_) {
        assetTok = asset_;
        cashTok = cash_;
        oracle = PinOracle(oracle_);
        aDec = IERC20Metadata(asset_).decimals();
        cDec = IERC20Metadata(cash_).decimals();
        pDec = PinOracle(oracle_).decimals();
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut)
        external
        returns (uint256 out)
    {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        uint256 p = uint256(oracle.answer());
        if (tokenIn == assetTok && tokenOut == cashTok) {
            out = (amountIn * (10 ** cDec) * p) / ((10 ** aDec) * (10 ** pDec));
        } else {
            out = (amountIn * (10 ** aDec) * (10 ** pDec)) / ((10 ** cDec) * p);
        }
        require(out >= minOut, "mock slippage");
        IERC20(tokenOut).transfer(msg.sender, out);
    }
}

contract SpotVaultCritical1Test is Test {
    MockERC20 wbtc;
    MockERC20 usdc;
    PinOracle oracle;
    PinAdapter adapter;
    SpotVault vault;

    address alice = makeAddr("alice");
    address attacker = makeAddr("attacker");

    function setUp() public {
        vm.warp(1_700_000_000);
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        oracle = new PinOracle(50_000 * 1e8);
        adapter = new PinAdapter(address(wbtc), address(usdc), address(oracle));
        vault = new SpotVault(
            address(wbtc), address(usdc), address(oracle), 1 hours,
            "Zentory BTC Spot Vault", "zBTCs",
            0, 100, 2000,                       // 20% perf fee = production default
            address(this), address(this),
            1 hours                            // emergencyRedeemCooldown (1h)
        );
        vault.setSwapAdapter(address(adapter));
        vault.grantRole(vault.KEEPER_ROLE(), address(this));
        wbtc.mint(address(adapter), 100_000 * 1e8);
        usdc.mint(address(adapter), 1_000_000_000 * 1e6);
        wbtc.mint(alice, 10 * 1e8);
        wbtc.mint(attacker, 1e8);
        wbtc.mint(address(this), 1e6);
    }

    /// Drives the vault into the pinned state exactly as the PoC does.
    function _pin() internal returns (uint256 seedShares) {
        wbtc.approve(address(vault), 1e6);
        seedShares = vault.deposit(1e6, address(this));          // 0.01 WBTC runbook seed

        vm.startPrank(alice);
        wbtc.approve(address(vault), 10 * 1e8);
        uint256 aliceShares = vault.deposit(10 * 1e8, alice);
        vm.stopPrank();

        vault.rebalanceTo(0);                 // flat at 50k
        oracle.setPrice(25_000 * 1e8);        // BTC halves while in cash
        vault.rebalanceTo(10000);             // rebuy low = real alpha
        vault.evaluateFees();                 // accrue the 20% perf fee

        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);   // the big LP exits

        vault.rebalanceTo(0);                 // flat again
        oracle.setPrice(27_500 * 1e8);        // +10% while in cash -> gross falls
    }

    /// THE FIX: in the pinned state a dust deposit must be impossible.
    function test_dustInflationDepositIsBlocked() public {
        _pin();
        // The pin itself can still occur (a price move after accrual is not
        // preventable) — what must NOT be possible is minting against it.
        if (vault.totalAssets() == 0 && vault.totalSupply() > 0) {
            assertEq(vault.maxDeposit(attacker), 0, "deposits must be closed while unbacked");
            assertEq(vault.maxMint(attacker), 0, "mints must be closed while unbacked");

            vm.startPrank(attacker);
            wbtc.approve(address(vault), 1e4);
            vm.expectRevert();               // ERC4626ExceededMaxDeposit
            vault.deposit(1e4, attacker);
            vm.stopPrank();
        }
    }

    /// Users must ALWAYS be able to exit — the fix must not trap anyone.
    function test_withdrawalsStayOpenWhilePinned() public {
        _pin();
        // Redeeming is still callable (value may be 0 while pinned, but it must not
        // revert or be gated) — gating exits would be a worse bug than the one fixed.
        uint256 shares = vault.balanceOf(address(this));
        assertGt(vault.maxRedeem(address(this)), 0, "exit path must stay open");
        vault.redeem(shares, address(this), address(this));
    }

    /// The recovery lever un-traps depositors without moving tokens.
    function test_writeDownRestoresBackingForDepositors() public {
        _pin();
        if (vault.totalAssets() == 0 && vault.totalSupply() > 0) {
            uint256 accrued = vault.performanceFeeAccrued();
            assertGt(accrued, 0);
            vault.writeDownAccruedFees(accrued);          // forgive the fee claim
            assertGt(vault.totalAssets(), 0, "depositor backing restored");
            assertGt(vault.maxDeposit(attacker), 0, "vault reopens once backed again");
        }
    }

    /// Claiming fees must never change what depositors are owed.
    function test_claimFeesDoesNotDiluteDepositors() public {
        wbtc.approve(address(vault), 1e6);
        vault.deposit(1e6, address(this));
        vm.startPrank(alice);
        wbtc.approve(address(vault), 10 * 1e8);
        vault.deposit(10 * 1e8, alice);
        vm.stopPrank();

        vault.rebalanceTo(0);
        oracle.setPrice(25_000 * 1e8);
        vault.rebalanceTo(10000);
        vault.evaluateFees();
        assertGt(vault.performanceFeeAccrued(), 0);

        uint256 assetsBefore = vault.totalAssets();
        uint256 paid = vault.claimFees();
        assertGt(paid, 0, "fees are actually claimable now (were a one-way sink)");
        assertApproxEqAbs(vault.totalAssets(), assetsBefore, 1, "depositor claim unchanged");
        assertEq(wbtc.balanceOf(address(this)) > 0, true, "recipient received the fee");
    }

    /// Accrual must never be able to swallow the whole vault.
    function test_accrualNeverExceedsGross() public {
        wbtc.approve(address(vault), 1e6);
        vault.deposit(1e6, address(this));
        vm.startPrank(alice);
        wbtc.approve(address(vault), 10 * 1e8);
        vault.deposit(10 * 1e8, alice);
        vm.stopPrank();

        for (uint256 i = 0; i < 6; i++) {
            vault.rebalanceTo(0);
            oracle.setPrice(int256(25_000 * 1e8 / int256(i + 1)));
            vault.rebalanceTo(10000);
            vault.evaluateFees();
            assertLt(vault.performanceFeeAccrued(), vault.grossValue(), "accrual capped below gross");
        }
    }

    /// The circuit breaker must actually stop money coming in.
    function test_circuitBreakerBlocksDeposits() public {
        wbtc.approve(address(vault), 1e6);
        vault.deposit(1e6, address(this));
        vault.grantRole(vault.RISK_COUNCIL_ROLE(), address(this));
        vault.setCircuitBreaker(true);
        assertEq(vault.maxDeposit(alice), 0, "halted vault must refuse deposits");
    }
}
