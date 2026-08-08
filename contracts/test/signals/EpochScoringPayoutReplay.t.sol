// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {EpochScoring} from "../../src/signals/EpochScoring.sol";
import {SignalTypes} from "../../src/signals/SignalTypes.sol";

/// Registry mock: returns a signal owned by a fixed provider (mirrors PayoutCurve.t.sol).
contract ReplayMockRegistry {
    address public provider;

    constructor(address provider_) {
        provider = provider_;
    }

    function getSignal(bytes32 id) external view returns (SignalTypes.Signal memory s) {
        s.signalId = id;
        s.provider = provider;
        s.status = SignalTypes.SignalStatus.Active;
        return s;
    }

    function getSignalCount() external pure returns (uint256) { return 0; }
    function advanceEpoch() external {}
    function getEpochSignalCount(uint256) external pure returns (uint256) { return 0; }
    function getEpochSignalProvider(uint256, uint256) external pure returns (address) { return address(0); }
    function getEpochSignalReturn(uint256, uint256) external pure returns (int256) { return 0; }
}

/// Staking mock that RECORDS calls, so we can prove a replay would really have
/// slashed/rewarded twice (PayoutCurve's mock no-ops, which is why it never caught this).
contract RecordingStaking {
    uint256 public stakeAmount;
    uint256 public slashCalls;
    uint256 public rewardCalls;
    uint256 public totalSlashed;
    uint256 public totalRewarded;

    constructor(uint256 stakeAmount_) {
        stakeAmount = stakeAmount_;
    }

    function getProviderStake(address) external view returns (uint256) { return stakeAmount; }
    function getStakeAtEpoch(address, uint256) external pure returns (uint256) { return 0; }

    function slash(address, uint256 amt) external {
        slashCalls++;
        totalSlashed += amt;
    }

    function reward(address, uint256 amt) external {
        rewardCalls++;
        totalRewarded += amt;
    }
}

/// Regression guards for audit CRITICAL-2 and the related "unscored == max slash" HIGH
/// (2026-08-07).
///
/// CRITICAL-2: `applyPayout` recorded NOTHING about having run, so the EPOCH_SETTLER
/// could call it on the same signalId without limit — repeatedly slashing a provider's
/// bond, or repeatedly minting the reward. Nothing in the contract stopped it.
///
/// HIGH: `accuracyCache` defaults to 0, and 0 is the MAXIMUM-SLASH input, so a signal
/// the scoring oracle never scored was indistinguishable from a maximally-wrong one —
/// a stalled oracle silently burned every provider's stake.
contract EpochScoringPayoutReplayTest is Test {
    EpochScoring scoring;
    ReplayMockRegistry registry;
    RecordingStaking staking;

    address constant PROVIDER = address(0x9A11);
    address constant ZENT_TOKEN = address(0x271c);
    address constant KEEPER = address(0x2251); // scoringOracle + EPOCH_SETTLER
    uint256 constant STAKE = 1000e18;

    function setUp() public {
        registry = new ReplayMockRegistry(PROVIDER);
        staking = new RecordingStaking(STAKE);
        scoring = new EpochScoring(address(registry), address(staking), ZENT_TOKEN, KEEPER, KEEPER);
    }

    // ─── CRITICAL-2: payouts are one-shot ──────────────────────────────────

    function test_slashCannotBeReplayed() external {
        bytes32 id = bytes32(uint256(1));
        vm.prank(KEEPER);
        scoring.setAccuracy(id, 0); // maximally wrong -> slash

        vm.prank(KEEPER);
        scoring.applyPayout(id);
        assertEq(staking.slashCalls(), 1, "slashed once");
        uint256 slashedAfterFirst = staking.totalSlashed();

        // The replay: previously this slashed the same bond again, repeatable forever.
        vm.prank(KEEPER);
        vm.expectRevert(abi.encodeWithSelector(EpochScoring.PayoutAlreadyApplied.selector, id));
        scoring.applyPayout(id);

        assertEq(staking.slashCalls(), 1, "still only one slash");
        assertEq(staking.totalSlashed(), slashedAfterFirst, "no additional stake burned");
    }

    function test_rewardCannotBeReplayed() external {
        bytes32 id = bytes32(uint256(2));
        vm.prank(KEEPER);
        scoring.setAccuracy(id, 10000); // maximally right -> reward

        vm.prank(KEEPER);
        scoring.applyPayout(id);
        assertEq(staking.rewardCalls(), 1, "rewarded once");
        uint256 rewardedAfterFirst = staking.totalRewarded();

        // The replay: previously this minted the same reward again, unbounded.
        vm.prank(KEEPER);
        vm.expectRevert(abi.encodeWithSelector(EpochScoring.PayoutAlreadyApplied.selector, id));
        scoring.applyPayout(id);

        assertEq(staking.rewardCalls(), 1, "still only one reward");
        assertEq(staking.totalRewarded(), rewardedAfterFirst, "no extra ZENT emitted");
    }

    function test_payoutAppliedFlagIsPublic() external {
        bytes32 id = bytes32(uint256(3));
        assertFalse(scoring.payoutApplied(id), "unsettled");
        vm.prank(KEEPER);
        scoring.setAccuracy(id, 6000);
        vm.prank(KEEPER);
        scoring.applyPayout(id);
        assertTrue(scoring.payoutApplied(id), "settled flag observable off-chain");
    }

    /// Distinct signals must still settle independently — the guard is per-signal.
    function test_distinctSignalsStillSettle() external {
        for (uint256 i = 10; i < 14; i++) {
            bytes32 id = bytes32(i);
            vm.prank(KEEPER);
            scoring.setAccuracy(id, 10000);
            vm.prank(KEEPER);
            scoring.applyPayout(id);
        }
        assertEq(staking.rewardCalls(), 4, "each distinct signal settles once");
    }

    // ─── HIGH: an unscored signal must not be treated as maximally wrong ────

    function test_unscoredSignalIsNotSlashed() external {
        bytes32 id = bytes32(uint256(42)); // setAccuracy never called

        vm.prank(KEEPER);
        vm.expectRevert(abi.encodeWithSelector(EpochScoring.SignalNotScored.selector, id));
        scoring.applyPayout(id);

        assertEq(staking.slashCalls(), 0, "a stalled scoring oracle must burn nothing");
    }

    /// Accuracy legitimately set to 0 is still a real score and must still slash —
    /// the guard distinguishes "unscored" from "scored as wrong", not both.
    function test_explicitZeroAccuracyStillSlashes() external {
        bytes32 id = bytes32(uint256(43));
        vm.prank(KEEPER);
        scoring.setAccuracy(id, 0);
        assertTrue(scoring.accuracyScored(id), "explicitly scored");

        vm.prank(KEEPER);
        scoring.applyPayout(id);
        assertEq(staking.slashCalls(), 1, "a genuinely wrong signal is still slashed");
    }

    function test_batchAccuracyMarksScored() external {
        bytes32[] memory ids = new bytes32[](2);
        uint256[] memory accs = new uint256[](2);
        ids[0] = bytes32(uint256(50));
        ids[1] = bytes32(uint256(51));
        accs[0] = 7000;
        accs[1] = 3000;

        vm.prank(KEEPER);
        scoring.setAccuracyBatch(ids, accs);

        assertTrue(scoring.accuracyScored(ids[0]), "batch marks scored");
        assertTrue(scoring.accuracyScored(ids[1]), "batch marks scored");

        vm.prank(KEEPER);
        scoring.applyPayout(ids[0]);
        vm.prank(KEEPER);
        scoring.applyPayout(ids[1]);
    }
}
