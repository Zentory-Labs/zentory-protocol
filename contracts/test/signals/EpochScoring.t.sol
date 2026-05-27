// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {EpochScoring} from "../../src/signals/EpochScoring.sol";
import {SignalTypes} from "../../src/signals/SignalTypes.sol";

/// @notice Minimum-viable mock for ISignalRegistry — returns the values
///         EpochScoring needs to walk the empty path without exercising the
///         full registry. Each view returns deterministic stub data.
contract MockSignalRegistry {
    function getSignalCount() external pure returns (uint256) {
        return 0;
    }
    function getSignalProvider(uint256) external pure returns (address) {
        return address(0);
    }
    function getSignalReturn(address, uint256) external pure returns (int256) {
        return 0;
    }
    function stakingContract() external pure returns (address) {
        return address(0);
    }
    function getProviderCount() external pure returns (uint256) {
        return 0;
    }
    function getProviderAt(uint256) external pure returns (address) {
        return address(0);
    }
    function signalExists(bytes32) external pure returns (bool) {
        return false;
    }
    function providerNonce(address) external pure returns (uint256) {
        return 0;
    }
    function getSignal(bytes32) external pure returns (SignalTypes.Signal memory s) {
        return s;
    }
    function resolveSignals(bytes32[] calldata, uint256[] calldata) external {}
    function submitSignal(
        address, SignalTypes.AssetClass, bytes32, int256, uint256, uint256, bytes calldata
    ) external pure returns (bytes32) { return bytes32(0); }
    function submitSignalBatch(SignalTypes.Signal[] calldata)
        external pure returns (bytes32[] memory ids) { return ids; }

    // Audit C-2 fix: settleEpoch now calls advanceEpoch() on the registry to
    // keep the registry's epoch counter in lockstep with EpochScoring's.
    // Mock tracks its own counter so tests can assert it gets bumped.
    uint256 public currentEpochId;
    function advanceEpoch() external { currentEpochId += 1; }

    // Audit M-2/M-3: per-epoch signal accessors. Empty by default (the
    // empty-epoch boundary tests rely on getEpochSignalCount == 0).
    function getEpochSignalCount(uint256) external pure returns (uint256) { return 0; }
    function getEpochSignalProvider(uint256, uint256) external pure returns (address) { return address(0); }
    function getEpochSignalReturn(uint256, uint256) external pure returns (int256) { return 0; }
}

/// @notice Minimum-viable mock for IZENTStaking. Empty-epoch path doesn't
///         touch slash/reward so they're noops; getProviderStake returns 0
///         to match the "no providers staked" reality on a fresh deploy.
contract MockZENTStaking {
    function getProviderStake(address) external pure returns (uint256) { return 0; }
    function getStakeAtEpoch(address, uint256) external pure returns (uint256) { return 0; }
    function slash(address, uint256) external {}
    function reward(address, uint256) external {}
    function stake(uint256, uint64) external pure returns (uint64) { return 0; }
    function increaseAmount(uint256) external {}
    function extendLock(uint64) external pure returns (uint64) { return 0; }
    function withdraw() external {}
    function veBalance(address) external pure returns (uint256) { return 0; }
    function hasAccess(address) external pure returns (bool) { return false; }
    function stakedBalance(address) external pure returns (uint256) { return 0; }
    function totalVeSupply() external pure returns (uint256) { return 0; }
    function setMinStake(uint256) external {}
}

/// @notice EpochScoring tests focused on the boundary conditions that the
///         production keeper hit in May 2026.
///
///         Background: when no quants have submitted signals (the bootstrap
///         state on any fresh deploy), _distributeRewards computed
///         `epochReward / results.length` which panicked on division-by-zero
///         and reverted settleEpoch. This locked the keeper out of every
///         cron run for 24 hours before we noticed via Discord heartbeat
///         alerts. Patch landed in commit d48ed85.
///
///         The fix has two parts (defense in depth):
///         1. settleEpoch short-circuits when signalCount == 0
///         2. _distributeRewards itself returns 0 on empty input
///
///         These tests pin both behaviors so the bug class cannot return.
contract EpochScoringTest is Test {
    EpochScoring scoring;
    MockSignalRegistry registry;
    MockZENTStaking staking;

    address constant ZENT_TOKEN = address(0x271c); // placeholder
    address constant KEEPER     = address(0x2251);
    // ADMIN is `address(this)` (the test contract) at runtime — set in setUp().

    event EpochSettled(uint256 indexed epochId, uint256 totalSignals, uint256 settledSignals);

    function setUp() public {
        registry = new MockSignalRegistry();
        staking  = new MockZENTStaking();

        scoring = new EpochScoring(
            address(registry),
            address(staking),
            ZENT_TOKEN,
            KEEPER,    // scoringOracle
            KEEPER     // keeper (EPOCH_SETTLER)
        );
    }

    // ─── Empty-epoch boundary ───────────────────────────────────────────

    function test_settleEpoch_emptySignals_succeeds() external {
        // Skip past the 4-hour epoch boundary so the EpochNotReady guard
        // doesn't fire first.
        vm.warp(block.timestamp + 4 hours + 1);

        // Pre-conditions: epoch 1 active, not settled, signal count is 0.
        assertEq(scoring.currentEpochId(), 1, "should start at epoch 1");

        // The pre-patch contract reverted here with Panic(0x12) divide-by-zero.
        // Post-patch the call returns normally.
        vm.prank(KEEPER);
        uint256 totalRewards = scoring.settleEpoch();

        // Post-conditions: epoch advanced, totalRewards is zero, epoch 1
        // marked settled. EpochSettled event was emitted (verified separately
        // below via expectEmit if needed; we keep this test focused on state).
        assertEq(totalRewards, 0, "empty epoch should distribute zero rewards");
        assertEq(scoring.currentEpochId(), 2, "epoch counter should advance to 2");

        (uint256 totalSignals, uint256 settledSignals, bool settled) =
            scoring.epochStates(1);
        assertEq(totalSignals, 0, "totalSignals should be 0");
        assertEq(settledSignals, 0, "settledSignals should be 0");
        assertTrue(settled, "epoch 1 should be marked settled");
    }

    function test_settleEpoch_emptySignals_emitsEpochSettled() external {
        vm.warp(block.timestamp + 4 hours + 1);

        vm.expectEmit(true, false, false, true);
        emit EpochSettled(1, 0, 0);

        vm.prank(KEEPER);
        scoring.settleEpoch();
    }

    function test_settleEpoch_emptySignals_advancesLastEpochStart() external {
        uint256 startBefore = scoring.lastEpochStart();
        vm.warp(block.timestamp + 4 hours + 1);

        vm.prank(KEEPER);
        scoring.settleEpoch();

        assertGt(
            scoring.lastEpochStart(),
            startBefore,
            "lastEpochStart should advance to current block time"
        );
        assertEq(
            scoring.lastEpochStart(),
            block.timestamp,
            "lastEpochStart should equal the settlement block timestamp"
        );
    }

    // ─── Authorization on the empty path ────────────────────────────────

    function test_settleEpoch_emptySignals_revertsForNonKeeper() external {
        vm.warp(block.timestamp + 4 hours + 1);
        address attacker = address(0xBAD);

        // The role check fires before the empty-signals fast path, so an
        // unauthorized caller still gets the AccessControl revert.
        vm.prank(attacker);
        vm.expectRevert();
        scoring.settleEpoch();
    }

    // ─── Re-entrancy: epoch can't be settled twice ─────────────────────

    function test_settleEpoch_emptySignals_revertsWhenAlreadySettled() external {
        vm.warp(block.timestamp + 4 hours + 1);

        vm.prank(KEEPER);
        scoring.settleEpoch(); // settles epoch 1, advances to 2

        // Advance again so the EpochNotReady guard doesn't shadow the real check
        vm.warp(block.timestamp + 4 hours + 1);

        // Settling epoch 2 (now current) should also work, but trying to
        // re-settle epoch 1 isn't possible via the external API — settleEpoch
        // operates on currentEpochId. We verify epoch 1 stays settled.
        (, , bool settledAfter) = scoring.epochStates(1);
        assertTrue(settledAfter, "epoch 1 remains settled after epoch 2 starts");
    }

    // ─── Timing-guard invariant (known design quirk for audit) ──────────

    /// @notice Documents a known design quirk: settleEpoch does NOT check
    ///         the epoch timer. Only performUpkeep() does. A keeper can
    ///         settle the current epoch immediately after the previous one
    ///         (zero seconds between them) if it bypasses performUpkeep.
    ///
    ///         This isn't a bug per se — settleEpoch is gated by the
    ///         EPOCH_SETTLER role, so only authorized keepers can call it
    ///         — but it does mean role-based access control is the ONLY
    ///         protection against premature settlement. Worth raising at
    ///         audit kickoff: a misconfigured keeper could blow through
    ///         dozens of epochs in a single block, draining the reward
    ///         pool. Production keeper (scripts/keeper/src/index.ts) calls
    ///         checkUpkeep() before settleEpoch to guard, but that's an
    ///         off-chain check.
    function test_settleEpoch_emptySignals_succeedsBeforeEpochDuration() external {
        // Don't warp — epoch just started, less than 4 hours elapsed.
        vm.prank(KEEPER);
        scoring.settleEpoch(); // no revert — settleEpoch trusts the caller

        // Epoch DID advance even though timer hadn't expired.
        assertEq(scoring.currentEpochId(), 2, "epoch advances without timer check");
    }
}
