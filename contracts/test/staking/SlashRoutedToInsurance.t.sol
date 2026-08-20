// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ZENT} from "../../src/ZENT.sol";
import {ZENTStaking} from "../../src/staking/ZENTStaking.sol";
import {InsuranceFund} from "../../src/InsuranceFund.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @notice Tier-0 audit finding [0.C.3]: slashed ZENT was unrecoverable because
///         `ZENTStaking.slash()` never routed the slashed ZENT anywhere — the
///         original implementation sent it to `msg.sender` (EpochScoring) where
///         it got stuck, while the protocol-wide insurance fund never received
///         its share of slashing revenue. This suite covers the fix shape
///         described in `docs/security/TIER_0_FIX_QUEUE.md` (Q2):
///         (1) with `insuranceFund` set, slashed ZENT flows to that recipient;
///         (2) with `insuranceFund == address(0)` (legacy default), slashed
///             ZENT is retained in the staking contract as a bounded buffer;
///         (3) `setInsuranceFund` is admin-only and rejects the zero address.
contract SlashRoutedToInsuranceTest is Test {
    ZENT internal zent;
    ZENTStaking internal staking;
    InsuranceFund internal insurance;

    address internal admin = makeAddr("admin");
    address internal provider = makeAddr("provider");
    address internal alice = makeAddr("alice");

    uint256 internal constant STAKE_AMOUNT = 5_000 ether;
    uint256 internal constant SLASH_AMOUNT = 1_500 ether;

    function setUp() external {
        zent = new ZENT();
        // Use the real InsuranceFund contract as the mock receiver: it's the
        // production recipient, it has a working `Ownable2Step`, and the
        // `receive()` fallback plus its constructor-side state are exactly
        // what mainnet will be wired to. Deploying the real contract (vs a
        // bare receive-only stub) catches any incompatibility between the
        // two contracts' interfaces and ensures the deployment sequence
        // (ZENTStaking -> InsuranceFund -> setInsuranceFund) is realistic.
        insurance = new InsuranceFund(admin);
        staking = new ZENTStaking(address(zent), admin, 1_000 ether);

        assertTrue(zent.transfer(provider, 100_000 ether));
    }

    // ─── Test 1: slashed ZENT flows to the configured InsuranceFund ─────────

    /// @notice Tier-0 [0.C.3] fix (configured case): after the deploy runbook
    ///         wires the real `InsuranceFund` address via `setInsuranceFund`,
    ///         a slash must route the slashed ZENT to the insurance fund —
    ///         not leave it in the staking contract as an internal buffer,
    ///         and definitely not leak it back to the slasher.
    function test_slashRoutesZentToConfiguredInsuranceFund() external {
        vm.prank(admin);
        staking.setInsuranceFund(address(insurance));

        vm.startPrank(provider);
        zent.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT, 365 days);
        vm.stopPrank();

        uint256 stakingBefore = zent.balanceOf(address(staking));
        uint256 insuranceBefore = zent.balanceOf(address(insurance));
        assertEq(stakingBefore, STAKE_AMOUNT, "precondition: staking holds full stake");
        assertEq(insuranceBefore, 0, "precondition: insurance fund starts empty");

        vm.prank(admin);
        staking.slash(provider, SLASH_AMOUNT);

        // Insurance fund receives exactly the slashed amount.
        assertEq(
            zent.balanceOf(address(insurance)),
            insuranceBefore + SLASH_AMOUNT,
            "insurance fund must receive exactly the slashed ZENT"
        );
        // Staking contract does NOT additionally receive the slashed ZENT —
        // the funding comes out of the staking balance. The staking contract
        // holds STAKE_AMOUNT - SLASH_AMOUNT after the slash.
        assertEq(
            zent.balanceOf(address(staking)),
            stakingBefore - SLASH_AMOUNT,
            "staking balance must drop by exactly the slashed amount"
        );
        // Internal accounting tracks the reduction.
        assertEq(staking.totalStaked(), STAKE_AMOUNT - SLASH_AMOUNT);
        assertEq(staking.stakedBalance(provider), STAKE_AMOUNT - SLASH_AMOUNT);
    }

    // ─── Test 2: address(0) insuranceFund = legacy buffer behaviour ─────────

    /// @notice Tier-0 [0.C.3] (legacy case): until governance wires a real
    ///         recipient, `insuranceFund` defaults to `address(0)` and slashed
    ///         ZENT must stay inside the staking contract as a bounded buffer
    ///         rather than being sent to the zero address (silent burn) or to
    ///         `msg.sender` (legacy leak to EpochScoring). This preserves the
    ///         "no funds lost on day 0" invariant the deploy runbook relies on
    ///         between `ZENTStaking.deploy()` and the post-deploy config tx.
    function test_slashRetainsZentInStakingWhenInsuranceFundUnset() external {
        // Confirm constructor default is address(0) — if someone changes the
        // constructor default to something else, this test fails loud and the
        // docstring/deploy-runbook comment must be revisited together.
        assertEq(staking.insuranceFund(), address(0), "constructor default must be address(0)");

        vm.startPrank(provider);
        zent.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT, 365 days);
        vm.stopPrank();

        vm.prank(admin);
        staking.slash(provider, SLASH_AMOUNT);

        // Slashed ZENT is retained in the staking contract — not burned, not
        // transferred elsewhere.
        assertEq(
            zent.balanceOf(address(staking)),
            STAKE_AMOUNT,
            "with insuranceFund == 0, full original stake remains in staking contract"
        );
        // …but totalStaked still decreases, so withdraw accounting stays
        // consistent: a user who locked 5_000 ether can only withdraw 3_500.
        assertEq(staking.totalStaked(), STAKE_AMOUNT - SLASH_AMOUNT);
        assertEq(staking.stakedBalance(provider), STAKE_AMOUNT - SLASH_AMOUNT);
    }

    // ─── Test 3: setInsuranceFund is admin-only and rejects address(0) ──────

    /// @notice `setInsuranceFund` must be callable only by the admin (DEFAULT_ADMIN_ROLE),
    ///         and must reject `address(0)` so a mis-entry can never silently
    ///         route slashed ZENT into the void.
    function test_setInsuranceFundRevertsForNonAdmin() external {
        bytes32 adminRole = staking.DEFAULT_ADMIN_ROLE();
        address notAdmin = alice; // has no role on the staking contract
        vm.prank(notAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, notAdmin, adminRole)
        );
        staking.setInsuranceFund(address(insurance));
    }

    function test_setInsuranceFundRejectsZeroAddress() external {
        vm.prank(admin);
        vm.expectRevert(ZENTStaking.ZeroInsuranceFund.selector);
        staking.setInsuranceFund(address(0));
    }
}