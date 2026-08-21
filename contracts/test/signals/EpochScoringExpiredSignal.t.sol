// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {EpochScoring} from "../../src/signals/EpochScoring.sol";
import {SignalTypes} from "../../src/signals/SignalTypes.sol";

/// @notice Registry mock that tracks `submittedAt` per signal id so the
///         `claimExpiredSignal` recovery path can compute age correctly.
///         `setSignal(id, provider, submittedAt)` is the test-only write API;
///         production uses `SignalRegistry.submitSignal` which sets
///         `submittedAt = block.timestamp` and is out of scope for these
///         unit tests (the integration path is exercised by
///         `test/signals/SignalRegistry.t.sol`).
contract ExpiredSignalMockRegistry {
    mapping(bytes32 => SignalTypes.Signal) internal _signals;
    mapping(bytes32 => bool) internal _exists;

    function setSignal(bytes32 id, address provider, uint256 submittedAt) external {
        _signals[id] = SignalTypes.Signal({
            signalId: id,
            provider: provider,
            assetClass: SignalTypes.AssetClass.CRYPTO_SPOT,
            assetId: bytes32(0),
            direction: 0,
            confidence: 0,
            submittedAt: submittedAt,
            expiresAt: submittedAt + 7 days,
            signature: hex"",
            status: SignalTypes.SignalStatus.Active
        });
        _exists[id] = true;
    }

    function getSignal(bytes32 id) external view returns (SignalTypes.Signal memory s) {
        require(_exists[id], "MockRegistry: signal not found");
        return _signals[id];
    }

    // Stubs for the rest of the surface EpochScoring may touch.
    function getSignalCount() external pure returns (uint256) {
        return 0;
    }
    function advanceEpoch() external {}

    function getEpochSignalCount(uint256) external pure returns (uint256) {
        return 0;
    }

    function getEpochSignalProvider(uint256, uint256) external pure returns (address) {
        return address(0);
    }

    function getEpochSignalReturn(uint256, uint256) external pure returns (int256) {
        return 0;
    }
}

/// @notice Staking mock that returns a fixed stake for everyone and records
///         slash/reward calls. Tests below assert the staking contract is
///         NEVER touched by `claimExpiredSignal` — the recovery path returns
///         the signal to the off-chain queue without moving any ZENT.
contract ExpiredSignalMockStaking {
    uint256 public immutable stakeAmount;
    uint256 public slashCalls;
    uint256 public rewardCalls;
    uint256 public totalSlashed;
    uint256 public totalRewarded;

    constructor(uint256 stakeAmount_) {
        stakeAmount = stakeAmount_;
    }

    function getProviderStake(address) external view returns (uint256) {
        return stakeAmount;
    }

    function getStakeAtEpoch(address, uint256) external pure returns (uint256) {
        return 0;
    }

    function slash(address, uint256 amt) external {
        slashCalls++;
        totalSlashed += amt;
    }

    function reward(address, uint256 amt) external {
        rewardCalls++;
        totalRewarded += amt;
    }
}

/// @title EpochScoringExpiredSignalTest
/// @notice Tier 0 audit Q6 — `accuracyCache` default-0 ≡ max-slash + dead-oracle recovery path.
///
///         Background:
///         - HIGH: An unscored signal reads `accuracyCache[id] == 0` (the default),
///           which is the MAXIMUM-slash input on the payout curve. A stalled
///           scoring oracle silently burns every provider's stake on the next
///           `applyPayout`. The sentinel guard (`accuracyScored[id] == true`)
///           already reverts this case with `SignalNotScored`.
///         - The recovery path added in this PR (`claimExpiredSignal(signalId)`)
///           lets the keeper mark a permanently-unscored, old signal as
///           "released without slash" so off-chain observers can reconcile it
///           and the protocol can clear stale entries from the queue.
///
///         These tests pin the recovery-path invariants:
///         1. Recovery returns stake untouched (no slash, no reward — the
///            signal was never scored, so there was never a payout to settle).
///         2. Recovery is only available for signals old enough that the
///            scoring oracle has had a real chance to recover (MAX_SIGNAL_AGE).
///         3. Recovery is gated by EPOCH_SETTLER (only the keeper / governance
///            can release signals).
///         4. Recovery is idempotent (a signal can only be claimed once).
///         5. Recovery rejects already-scored / already-payout-applied signals
///            so it cannot be used to launder an intended slash.
///         6. `applyPayout` continues to revert after recovery (defense in
///            depth — the recovery flag is informational only, not a way to
///            "approve" the payout).
contract EpochScoringExpiredSignalTest is Test {
    EpochScoring scoring;
    ExpiredSignalMockRegistry registry;
    ExpiredSignalMockStaking staking;

    address constant PROVIDER = address(0x9A11);
    address constant ZENT_TOKEN = address(0x271c);
    address constant KEEPER = address(0x2251); // scoringOracle + EPOCH_SETTLER
    address constant ATTACKER = address(0xBADD);
    uint256 constant STAKE = 1000e18; // > MIN_STAKE

    event ExpiredSignalClaimed(bytes32 indexed signalId, address indexed provider, uint256 ageSeconds);

    function setUp() public {
        registry = new ExpiredSignalMockRegistry();
        staking = new ExpiredSignalMockStaking(STAKE);
        scoring = new EpochScoring(
            address(registry),
            address(staking),
            ZENT_TOKEN,
            KEEPER, // scoringOracle
            KEEPER // keeper (EPOCH_SETTLER)
        );
    }

    // ─── Core invariant: recovery returns stake untouched ────────────────

    /// @notice A signal older than MAX_SIGNAL_AGE that was never scored can
    ///         be claimed via `claimExpiredSignal`. The provider's stake
    ///         must be unchanged (no slash, no reward) because the signal
    ///         was never paid out — the recovery path is informational, not
    ///         a payout event.
    function test_claimExpiredSignal_returnsStakeUnchanged() external {
        bytes32 id = bytes32(uint256(1));
        registry.setSignal(id, PROVIDER, block.timestamp);

        // Warp past MAX_SIGNAL_AGE (7 days + 1 second for the strict `<` guard).
        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(KEEPER);
        scoring.claimExpiredSignal(id);

        // The staking contract must NOT have been touched — no slash, no reward.
        assertEq(staking.slashCalls(), 0, "recovery path must not slash");
        assertEq(staking.rewardCalls(), 0, "recovery path must not reward");
        assertEq(staking.totalSlashed(), 0, "no stake destroyed");
        assertEq(staking.totalRewarded(), 0, "no stake created");

        // The expiredClaimed flag must be observable off-chain.
        assertTrue(scoring.expiredClaimed(id), "expiredClaimed flag set");
    }

    /// @notice Recovery emits the documented `ExpiredSignalClaimed` event
    ///         with the correct provider + age so keepers and indexers can
    ///         reconcile the cleared signal against their off-chain lists.
    function test_claimExpiredSignal_emitsEvent() external {
        bytes32 id = bytes32(uint256(2));
        uint256 startTs = block.timestamp;
        registry.setSignal(id, PROVIDER, startTs);

        vm.warp(startTs + 7 days + 1);

        vm.expectEmit(true, true, false, true);
        emit ExpiredSignalClaimed(id, PROVIDER, 7 days + 1);

        vm.prank(KEEPER);
        scoring.claimExpiredSignal(id);
    }

    /// @notice MAX_SIGNAL_AGE is a contract constant and exposed publicly so
    ///         keepers can pre-filter their reconciliation lists without
    ///         reading from the registry event log.
    function test_maxSignalAgeIsPubliclyReadable() external {
        assertEq(scoring.MAX_SIGNAL_AGE(), 7 days, "MAX_SIGNAL_AGE = 7 days");
    }

    // ─── Age guard: signals still within MAX_SIGNAL_AGE cannot be claimed ──

    /// @notice A fresh signal cannot be claimed. The grace period gives the
    ///         scoring oracle time to recover from routine keeper outages
    ///         before the recovery path kicks in.
    function test_claimExpiredSignal_revertsWhenStillFresh() external {
        bytes32 id = bytes32(uint256(3));
        registry.setSignal(id, PROVIDER, block.timestamp);

        // One second shy of MAX_SIGNAL_AGE — still inside the grace window.
        vm.warp(block.timestamp + 7 days - 1);

        vm.prank(KEEPER);
        vm.expectRevert(abi.encodeWithSelector(EpochScoring.SignalStillFresh.selector, 7 days - 1, 7 days));
        scoring.claimExpiredSignal(id);
    }

    /// @notice Right at the boundary — `age == MAX_SIGNAL_AGE` IS claimable
    ///         (the guard uses strict `<`, not `<=`). A signal exactly 7 days
    ///         old can be released.
    function test_claimExpiredSignal_succeedsAtBoundary() external {
        bytes32 id = bytes32(uint256(4));
        registry.setSignal(id, PROVIDER, block.timestamp);

        vm.warp(block.timestamp + 7 days);

        vm.prank(KEEPER);
        scoring.claimExpiredSignal(id);
        assertTrue(scoring.expiredClaimed(id), "released exactly at MAX_SIGNAL_AGE");
    }

    // ─── Mutually exclusive with the payout path ──────────────────────────

    /// @notice An already-scored signal MUST be settled via `applyPayout`,
    ///         not released via `claimExpiredSignal`. The recovery path
    ///         cannot be used to skip an intended slash — once the oracle
    ///         has scored the signal, the economics have to play out.
    function test_claimExpiredSignal_revertsWhenAlreadyScored() external {
        bytes32 id = bytes32(uint256(5));
        registry.setSignal(id, PROVIDER, block.timestamp);

        vm.prank(KEEPER);
        scoring.setAccuracy(id, 0); // maximally wrong, but still "scored"

        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(KEEPER);
        vm.expectRevert(abi.encodeWithSelector(EpochScoring.SignalAlreadyScored.selector, id));
        scoring.claimExpiredSignal(id);
    }

    /// @notice An already-payout-applied signal cannot be re-released. The
    ///         settlement has happened; releasing it is meaningless and we
    ///         block it explicitly so an off-chain bug doesn't double-handle.
    /// @dev    The first guard that fires is `SignalAlreadyScored` (a
    ///         payout-applied signal was necessarily scored first), so we
    ///         expect that selector. Either guard alone is sufficient to
    ///         block the release.
    function test_claimExpiredSignal_revertsWhenPayoutApplied() external {
        bytes32 id = bytes32(uint256(6));
        registry.setSignal(id, PROVIDER, block.timestamp);

        vm.prank(KEEPER);
        scoring.setAccuracy(id, 0);
        vm.prank(KEEPER);
        scoring.applyPayout(id); // payoutApplied[id] = true, slashCalls == 1

        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(KEEPER);
        vm.expectRevert(abi.encodeWithSelector(EpochScoring.SignalAlreadyScored.selector, id));
        scoring.claimExpiredSignal(id);

        // Sanity: the original slash is unchanged.
        assertEq(staking.slashCalls(), 1, "the legitimate slash is still on the books");
    }

    /// @notice Defense in depth: even after `claimExpiredSignal`, a follow-up
    ///         `applyPayout(id)` still reverts with `SignalNotScored` because
    ///         the recovery flag is purely informational — it does NOT mark
    ///         the signal as scored. This pins the property that the recovery
    ///         path cannot be weaponized to retroactively approve a payout
    ///         that should have happened.
    function test_applyPayoutStillRevertsAfterExpiredClaim() external {
        bytes32 id = bytes32(uint256(7));
        registry.setSignal(id, PROVIDER, block.timestamp);

        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(KEEPER);
        scoring.claimExpiredSignal(id);

        vm.prank(KEEPER);
        vm.expectRevert(abi.encodeWithSelector(EpochScoring.SignalNotScored.selector, id));
        scoring.applyPayout(id);
    }

    // ─── Idempotency ──────────────────────────────────────────────────────

    /// @notice `expiredClaimed` is a one-shot — calling claim twice on the
    ///         same signal reverts. This pins the invariant that the
    ///         recovery event is fired exactly once per released signal
    ///         (keepers / indexers must be able to dedupe off the event log).
    function test_claimExpiredSignal_isIdempotent() external {
        bytes32 id = bytes32(uint256(8));
        registry.setSignal(id, PROVIDER, block.timestamp);

        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(KEEPER);
        scoring.claimExpiredSignal(id);
        assertTrue(scoring.expiredClaimed(id), "released");

        vm.prank(KEEPER);
        vm.expectRevert(abi.encodeWithSelector(EpochScoring.ExpiredAlreadyClaimed.selector, id));
        scoring.claimExpiredSignal(id);
    }

    /// @notice Multiple distinct signals can each be released independently.
    ///         The flag is per-signal; one release does not lock others.
    function test_claimExpiredSignal_distinctSignals() external {
        bytes32 idA = bytes32(uint256(9));
        bytes32 idB = bytes32(uint256(10));
        registry.setSignal(idA, PROVIDER, block.timestamp);
        registry.setSignal(idB, PROVIDER, block.timestamp);

        vm.warp(block.timestamp + 7 days + 1);

        vm.startPrank(KEEPER);
        scoring.claimExpiredSignal(idA);
        scoring.claimExpiredSignal(idB);
        vm.stopPrank();

        assertTrue(scoring.expiredClaimed(idA), "A released");
        assertTrue(scoring.expiredClaimed(idB), "B released");
    }

    // ─── Role gating ──────────────────────────────────────────────────────

    /// @notice `claimExpiredSignal` is gated by EPOCH_SETTLER. A non-keeper
    ///         caller (including the deployer EOA without the role) reverts
    ///         with the standard AccessControl revert. This pins the
    ///         invariant that an unprivileged actor cannot release signals.
    function test_claimExpiredSignal_revertsForNonKeeper() external {
        bytes32 id = bytes32(uint256(11));
        registry.setSignal(id, PROVIDER, block.timestamp);

        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(ATTACKER);
        vm.expectRevert();
        scoring.claimExpiredSignal(id);

        // Sanity: the flag is still false (no state change from the revert).
        assertFalse(scoring.expiredClaimed(id), "unauthorized call must not flip the flag");
    }

    /// @notice The contract's DEFAULT_ADMIN_ROLE can grant EPOCH_SETTLER to
    ///         a new key (governance rotation). After grant, the new key
    ///         can release signals. This mirrors the `transferAdmin` /
    ///         `setScoringOracle` governance path documented elsewhere.
    function test_claimExpiredSignal_adminCanGrantRole() external {
        bytes32 id = bytes32(uint256(12));
        registry.setSignal(id, PROVIDER, block.timestamp);

        vm.warp(block.timestamp + 7 days + 1);

        // KEEPER is admin in this test (set in constructor as msg.sender =
        // address(this)). Grant EPOCH_SETTLER to ATTACKER.
        scoring.grantRole(scoring.EPOCH_SETTLER(), ATTACKER);

        vm.prank(ATTACKER);
        scoring.claimExpiredSignal(id);
        assertTrue(scoring.expiredClaimed(id), "newly-granted keeper can release");
    }
}
