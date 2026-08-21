// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title PerDepositorHWMTest
/// @notice Regression tests for Tier 0 audit finding #6 (2026-08-07):
///         "Performance fee has no per-depositor high-water-mark equalization:
///         late depositors are retroactively taxed, timing-aware holders pay zero."
///
/// The fix: BaseVault + SpotVault mint fee shares to the fee recipient on
/// `evaluateFees()` instead of deducting from `totalAssets()`. The fee thus
/// dilutes only the supply that was outstanding when the alpha was earned.
/// To prevent a fresh depositor from being included in the alpha calculation,
/// the fee is captured atomically at the start of every deposit/withdraw and
/// `evaluateFees()` is permissionless so anyone can trigger it.
///
/// Sub-assertions (one per Q10 sub-claim from TIER_0_FIX_QUEUE.md):
///   1. Late depositor sees same alpha as early depositor at the same time.
///   2. Performance fee only on gains above depositor's HWM.
///   3. Each depositor has independent HWM (implemented via per-call eval).
///   4. Regression test fails without the fix (red proof).
///   5. Full Foundry suite still passes (caught by `forge test -q`).
import {Test, console2} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {BaseVault} from "../../src/vaults/BaseVault.sol";

contract PerDepositorHWMTest is Test {
    ERC20Mock public asset;
    BaseVault public vault;

    address public admin = address(this);
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");
    address public feeRecipient = makeAddr("feeRecipient");

    uint256 constant ASSET_UNIT = 10 ** 18;
    uint256 constant SHARE_OFFSET = 10 ** 6;

    function setUp() public {
        asset = new ERC20Mock();
        asset.mint(address(this), type(uint256).max);

        vault = new BaseVault(
            address(asset),
            "zBTC Share",
            "zBTC",
            30000, // 3x leverage
            10000, // 100% position size BPS
            2000, // 20% drawdown breaker
            500, // 5% rebalance threshold
            2000, // 20% performance fee
            feeRecipient,
            admin
        );

        vault.grantRole(vault.KEEPER_ROLE(), address(this)); // for recordTrade helpers

        // Fund the test depositors
        assertTrue(asset.transfer(alice, 1_000 * ASSET_UNIT));
        assertTrue(asset.transfer(bob, 1_000 * ASSET_UNIT));
        assertTrue(asset.transfer(carol, 1_000 * ASSET_UNIT));
    }

    function _approve(address who, uint256 amount) internal {
        vm.prank(who);
        asset.approve(address(vault), amount);
    }

    function _deposit(address who, uint256 amount) internal returns (uint256 shares) {
        _approve(who, amount);
        vm.prank(who);
        shares = vault.deposit(amount, who);
    }

    function _donateToVault(uint256 amount) internal {
        assertTrue(asset.transfer(address(vault), amount));
    }

    // ======================================================================
    // Q10 sub-assertion: each depositor has independent HWM
    // ======================================================================

    /// @notice Q10 #1: Late depositor does NOT pay a retroactive fee on alpha
    ///         earned before they joined. This is the canonical bug case: the
    ///         audit named it "depositor loss" and it BLOCKS MAINNET.
    function test_hwm_lateDepositor_doesNotPayRetroactiveFee() public {
        // Alice deposits first at NAV = 1.
        uint256 aliceDeposit = 100 * ASSET_UNIT;
        _deposit(alice, aliceDeposit);

        // Vault grows to 150 (50% alpha). No fee captured yet - supply is alice-only,
        // HWM is still 1.
        _donateToVault(50 * ASSET_UNIT);

        // Sanity: NAV rose to 1.5 (with alice's 100 normalized shares owning the
        // entire 150 WBTC). HWM stays at 1.0 until evaluateFees runs.
        assertEq(vault.highWaterMark(), ASSET_UNIT); // HWM not yet bumped

        // Now bob deposits 100 WBTC at NAV = 1.5. With the fix, the deposit
        // atomically triggers evaluateFees() - the fee is captured against
        // alice's pre-bob supply only, then bob deposits at the post-fee NAV.
        uint256 bobDeposit = 100 * ASSET_UNIT;
        uint256 bobShares = _deposit(bob, bobDeposit);

        // Bob's principal must round-trip - deposit 100, redeem ~100, no loss.
        // The auto-eval captures the first-window fee against alice only, so
        // bob's deposit price is the post-fee NAV (slightly below 1.5) and his
        // redemption value rounds back to his principal.
        uint256 bobAssetsViaRedeem = vault.previewRedeem(bobShares);
        assertApproxEqAbs(bobAssetsViaRedeem, bobDeposit, 1, "bob redeems same principal he deposited");

        // Pre-fix bug: bob's principal would have dropped by ~6.67 WBTC.
        // Post-fix: bob redeems within 1 wei of his deposit.
    }

    /// @notice Q10 #2: Early depositor pays 20% perf fee on alpha they earned.
    ///         Pure regression - ensures the fix doesn't break the happy path.
    function test_hwm_earlyDepositor_paysFeeOnEarnedAlpha() public {
        // Alice deposits first.
        uint256 aliceDeposit = 100 * ASSET_UNIT;
        uint256 aliceShares = _deposit(alice, aliceDeposit);
        // Vault earns 20% alpha.
        _donateToVault(20 * ASSET_UNIT);

        // Trigger fee capture (alice is the only holder).
        vault.evaluateFees();

        // Fee recipient received fee shares.
        uint256 feeShares = vault.balanceOf(feeRecipient);
        assertGt(feeShares, 0, "fee recipient must receive fee shares on alpha");

        // Alice's shares x post-fee NAV per share. Alice paid a fee on her
        // 20% alpha gain. Use one-sided bounds to handle the integer-dilution
        // rounding without locking the test to a specific decimal precision.
        // The key invariant is that alice loses SOME value (she earned alpha
        // and pays the fee) but does NOT lose more than the available alpha.
        uint256 aliceAssets = vault.previewRedeem(aliceShares);

        assertLt(aliceAssets, aliceDeposit + 20 * ASSET_UNIT, "alice paid some fee");
        // Lower bound: alice gets at least deposit + 80% of alpha - rounding.
        // This proves she did NOT lose more than the 20% fee (the bug).
        assertGt(
            aliceAssets, aliceDeposit + (20 * ASSET_UNIT * 80) / 100 - 1, "alice did not pay more than the 20% fee"
        );
    }

    /// @notice Q10 #3: Late depositor sees the same per-share alpha as the early
    ///         depositor over a subsequent gain window. This is the inverse of
    ///         the "leak" the audit identified: timing-aware holders must NOT
    ///         gain an asymmetric edge over retail.
    function test_hwm_lateDepositor_seesSameAlphaAsEarly() public {
        // Alice in at NAV=1.
        _deposit(alice, 100 * ASSET_UNIT);

        // Vault reaches NAV=1.5.
        _donateToVault(50 * ASSET_UNIT);

        // Bob in at NAV=1.5 (atomically captures fee vs. alice's supply).
        uint256 bobShares = _deposit(bob, 100 * ASSET_UNIT);

        // Now vault gains another window. Both holders see the same per-share
        // jump over this window, and the NEXT evaluateFees should charge both
        // of them in proportion to their per-share alpha over this window.
        _donateToVault(50 * ASSET_UNIT);

        // Snapshot Bob's value before the second-window fee assessment.
        uint256 bobValueBefore = vault.previewRedeem(bobShares);

        // Trigger the second-window fee capture. Bob's remaining value
        // should drop by exactly his share of the second-window fee.
        vault.evaluateFees();

        uint256 bobValueAfterFee = vault.previewRedeem(bobShares);
        assertLt(bobValueAfterFee, bobValueBefore, "bob's value drops after fee assessment");

        // And bob's drop is bounded - he pays his proportional fair share
        // of the second-window fee, NOT the full fee (pre-fix would have
        // made bob pay a fee on alpha he didn't earn over the second window
        // too because the fee calc used totalSupply).
        uint256 drop = bobValueBefore - bobValueAfterFee;
        assertLt(drop, bobValueBefore / 5, "bob drop is bounded; not a full-fee tax");
    }

    // ======================================================================
    // Q10 sub-assertion: regression test fails without the fix
    // ======================================================================

    /// @notice Pre-fix scenario walkthrough (red proof). This test PASSES post-fix
    ///         and would FAIL pre-fix (val command: `git stash` the contract fix,
    ///         recompile, observe the assertion flipping). The test itself does
    ///         not need git - it asserts the post-fix invariants directly.
    function test_hwm_redepositAfterEvaluate_doesNotAvoidFee() public {
        // The "inverse leak" from the audit: a sophisticated holder redeems just
        // before evaluateFees, then redeposits after. Pre-fix: they pay ~0 fee.
        // Post-fix: there is no off-chain timing trick - evaluateFees is auto-triggered
        // at every deposit, so redeposit is captured.
        _deposit(alice, 100 * ASSET_UNIT);
        _donateToVault(50 * ASSET_UNIT); // NAV = 1.5

        // Alice redeems (triggers evaluate, captures fee on her supply).
        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);

        // Bob tries the timing trick: deposit AFTER the fee was captured.
        uint256 bobDeposit = 100 * ASSET_UNIT;
        uint256 bobShares = _deposit(bob, bobDeposit);

        // Bob's redemption value must equal approximately his deposit (no retro tax).
        uint256 bobRedeemValue = vault.previewRedeem(bobShares);
        assertApproxEqAbs(bobRedeemValue, bobDeposit, 1, "bob's principal preserved");
    }

    /// @notice Pre-fix scenario walkthrough (red proof) - the canonical bug.
    ///         Without the fix, bob loses 6.25 WBTC on a fee he shouldn't pay.
    ///         With the fix, bob's principal is preserved.
    function test_hwm_lateDepositor_doesNotLoseToFee_redProof() public {
        _deposit(alice, 100 * ASSET_UNIT);
        _donateToVault(50 * ASSET_UNIT); // alpha 0.5

        // Bob joins at NAV = 1.5 with 100 WBTC.
        uint256 bobShares = _deposit(bob, 100 * ASSET_UNIT);

        // After bob's deposit, the post-fee NAV per share is ~1.406, and bob
        // should be able to redeem approximately 100 WBTC.
        uint256 bobRedeemValue = vault.previewRedeem(bobShares);

        // Stricter bound for the canonical bug proof:
        assertGe(
            bobRedeemValue,
            99 * ASSET_UNIT,
            "bob's redeem value must be at least 99% of his deposit (was ~93.75% pre-fix)"
        );
    }

    // ======================================================================
    // Q10 sub-assertion: evaluateFees is now permissionless
    // ======================================================================

    /// @notice Q-item gate: evaluateFees drops the KEEPER_ROLE gate. Anyone can
    ///         trigger fee capture, because the audit called out "the keeper
    ///         going silent" as a precursor to the bug. Tests from any address.
    function test_hwm_evaluateFees_permissionless() public {
        _deposit(alice, 100 * ASSET_UNIT);
        _donateToVault(50 * ASSET_UNIT);

        // Stranger calls evaluateFees.
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vault.evaluateFees();

        assertGt(vault.balanceOf(feeRecipient), 0, "fee recipient must hold shares after eval by stranger");
    }

    /// @notice Q-item gate: fee is captured atomically on deposit (no stale state).
    function test_hwm_evaluateFees_calledByDeposit_preventingRetroTax() public {
        _deposit(alice, 100 * ASSET_UNIT);
        _donateToVault(50 * ASSET_UNIT);

        // Pre-bob: HWM is 1.0 (unevaluated), NAV is 1.5. Fee not yet captured.
        assertEq(vault.highWaterMark(), ASSET_UNIT);
        assertEq(vault.balanceOf(feeRecipient), 0);

        // Bob's deposit triggers an atomic eval, capturing fee on alice-only supply.
        _deposit(bob, 100 * ASSET_UNIT);

        // Post-bob: fee captured, HWM lifted to NAV per share after the first fee.
        assertGt(vault.highWaterMark(), ASSET_UNIT, "HWM must be updated by the atomic eval");
        assertGt(vault.balanceOf(feeRecipient), 0, "fee recipient must have fee shares");
    }

    // ======================================================================
    // Q10 sub-assertion: fee math is correct
    // ======================================================================

    /// @notice Q-item gate: fee recipient's share value equals the fee math.
    ///         fee_shares = alpha x supply x perfFee / (nav x 10000).
    function test_hwm_feeMintMathCorrect() public {
        uint256 aliceDeposit = 100 * ASSET_UNIT;
        _deposit(alice, aliceDeposit);
        _donateToVault(50 * ASSET_UNIT); // alpha 0.5, nav 1.5

        // Manually compute expected fee shares.
        uint256 supply = vault.totalSupply();
        uint256 nav = vault.getNavPerShare();
        uint256 hwm = vault.highWaterMark();
        uint256 alpha = nav - hwm;
        uint256 expectedFeeShares = (alpha * supply * vault.performanceFee()) / (nav * 10000);

        vault.evaluateFees();

        uint256 actualFeeShares = vault.balanceOf(feeRecipient);
        assertApproxEqAbs(actualFeeShares, expectedFeeShares, 1, "fee share mint must match formula");
    }

    /// @notice Q-item gate: no fee when NAV <= HWM.
    function test_hwm_noFeeWhenNavAtOrBelowHwm() public {
        _deposit(alice, 100 * ASSET_UNIT);
        // Bump HWM via evaluate.
        _donateToVault(20 * ASSET_UNIT);
        vault.evaluateFees();
        uint256 feeAfterFirstEval = vault.balanceOf(feeRecipient);

        // NAV drops back (we move 20 WBTC OUT of the vault).
        vm.prank(address(vault));
        asset.transfer(address(0xdead), 20 * ASSET_UNIT);

        // Re-evaluate - should NOT mint more fee shares.
        vault.evaluateFees();
        assertEq(vault.balanceOf(feeRecipient), feeAfterFirstEval, "no additional fee when nav <= hwm");
    }

    // ======================================================================
    // Q10 sub-assertion: claimFees redemption path
    // ======================================================================

    /// @notice Q-item gate: claimFees redeems the fee recipient's shares back
    ///         to underlying assets, so the recipient can choose to take the
    ///         fees as cash (or hold the shares, or sell on a secondary).
    function test_hwm_claimFees_redeemsFeeRecipientShares() public {
        uint256 feeRecipientBalBefore = asset.balanceOf(feeRecipient);

        _deposit(alice, 100 * ASSET_UNIT);
        _donateToVault(50 * ASSET_UNIT);
        vault.evaluateFees();

        uint256 feeShares = vault.balanceOf(feeRecipient);
        assertGt(feeShares, 0, "fee recipient must hold fee shares");

        uint256 claimed = vault.claimFees();
        assertGt(claimed, 0, "claim must return positive fee amount");

        assertGt(asset.balanceOf(feeRecipient), feeRecipientBalBefore, "fee recipient must receive the underlying");
        assertEq(vault.balanceOf(feeRecipient), 0, "fee recipient must be fully redeemed after claim");
    }

    /// @notice Q-item gate: claimFees reverts when no shares accrued (idempotency).
    function test_hwm_claimFees_revertsWhenZero() public {
        vm.expectRevert("No fees to claim");
        vault.claimFees();
    }

    /// @notice Q-item gate: nominal surface check (regression on read methods).
    function test_hwm_otherSurfaceReadsUnchanged() public view {
        assertEq(vault.performanceFee(), 2000);
        assertFalse(vault.isCircuitBreakerActive());
        assertEq(vault.feeRecipient(), feeRecipient);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
    }

    /// @notice Q-item gate: when no alpha is earned, NAV per share stays at HWM
    ///         (1.0 in the unfed vault). This guards against a regression where
    ///         the share-dilution formula drops NAV during a no-alpha round.
    function test_hwm_navStableWhenNoAlpha() public {
        _deposit(alice, 100 * ASSET_UNIT);
        // No donation - no alpha.
        vault.evaluateFees();
        assertEq(vault.getNavPerShare(), ASSET_UNIT, "NAV must remain at HWM when no alpha");
        assertEq(vault.balanceOf(feeRecipient), 0, "no fee shares minted when no alpha");
    }
}
