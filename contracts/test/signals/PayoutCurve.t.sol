// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {EpochScoring} from "../../src/signals/EpochScoring.sol";
import {SignalTypes} from "../../src/signals/SignalTypes.sol";

/// @notice Registry mock that hands back a signal owned by a fixed provider so
///         EpochScoring.applyPayout's getProviderStake lookup resolves to a
///         staked account. Only the methods on applyPayout's path are real.
contract MockRegistryWithProvider {
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

    // Stubs for the rest of the surface EpochScoring may touch.
    function getSignalCount() external pure returns (uint256) { return 0; }
    function advanceEpoch() external {}
    function getEpochSignalCount(uint256) external pure returns (uint256) { return 0; }
    function getEpochSignalProvider(uint256, uint256) external pure returns (address) { return address(0); }
    function getEpochSignalReturn(uint256, uint256) external pure returns (int256) { return 0; }
}

/// @notice Staking mock reporting a fixed stake (>= MIN_STAKE) for everyone.
///         slash/reward are no-ops — the tests read applyPayout's return value
///         directly, which is the realized payout BEFORE it hits the staking
///         contract, so the curve is observed independent of staking behavior.
contract MockStakingFixed {
    uint256 public stakeAmount;

    constructor(uint256 stakeAmount_) {
        stakeAmount = stakeAmount_;
    }

    function getProviderStake(address) external view returns (uint256) { return stakeAmount; }
    function getStakeAtEpoch(address, uint256) external pure returns (uint256) { return 0; }
    function slash(address, uint256) external {}
    function reward(address, uint256) external {}
}

/// @notice Pins the shape of the EpochScoring slash/reward curve.
///
///         Regression guard for the 2026-05-31 disclosure (A. Deev): the
///         payout curve was quadratic (symmetric about accuracy=5000) instead
///         of linear/monotonic, because rawPayout multiplied by `accuracyBps`
///         twice. The worst signal (accuracy=0) was penalized LESS than a
///         less-wrong one — payout(0)=0 > payout(2500)<0 — so spam/noise paid
///         no penalty, defeating the slashing half of the incentive design.
///
///         These tests assert the economic INVARIANT the whitepaper promises:
///         payout is non-decreasing in accuracy, negative below the 5000
///         break-even, positive above it. They are intentionally agnostic to
///         the payout MAGNITUDE / scale constant (the `* 3 / 1000` factor and
///         whether the MAX_PENALTY/MAX_REWARD clips bind) — that magnitude is a
///         separate economic-parameter decision. Monotonicity is the property
///         that makes the protocol's "honest, slashable track record" claim
///         true at all, so it is the one we lock here.
contract PayoutCurveTest is Test {
    EpochScoring scoring;
    MockRegistryWithProvider registry;
    MockStakingFixed staking;

    address constant PROVIDER = address(0x9A11);
    address constant ZENT_TOKEN = address(0x271c);
    address constant KEEPER = address(0x2251); // scoringOracle + EPOCH_SETTLER
    uint256 constant STAKE = 1000e18; // > MIN_STAKE (100e18)

    function setUp() public {
        registry = new MockRegistryWithProvider(PROVIDER);
        staking = new MockStakingFixed(STAKE);
        scoring = new EpochScoring(
            address(registry),
            address(staking),
            ZENT_TOKEN,
            KEEPER, // scoringOracle
            KEEPER // keeper (EPOCH_SETTLER)
        );
    }

    /// @dev Drive a single signal end-to-end: cache accuracy as the oracle,
    ///      then settle it as the EPOCH_SETTLER and return the realized payout.
    function _payoutAt(bytes32 id, uint256 accuracyBps) internal returns (int256) {
        vm.prank(KEEPER);
        scoring.setAccuracy(id, accuracyBps);
        vm.prank(KEEPER);
        return scoring.applyPayout(id);
    }

    // ─── The exact inversion from the disclosure PoC ────────────────────

    /// @notice The headline bug: accuracy=0 must NOT out-earn accuracy=2500.
    ///         Pre-fix: payout(0)=0 > payout(2500)<0 (worst signal punished
    ///         least). Post-fix: payout(0) <= payout(2500).
    function test_worstSignalIsNotRewardedOverLessBadSignal() external {
        int256 p0 = _payoutAt(bytes32(uint256(1)), 0);
        int256 p2500 = _payoutAt(bytes32(uint256(2)), 2500);

        assertLe(p0, p2500, "accuracy=0 must be penalized at least as much as accuracy=2500");
        assertLe(p0, 0, "accuracy=0 must be a slash or zero, never a reward");
    }

    // ─── Sign / break-even structure ────────────────────────────────────

    function test_breakEvenAtMidpointIsZero() external {
        assertEq(_payoutAt(bytes32(uint256(3)), 5000), 0, "accuracy=5000 is break-even");
    }

    function test_belowMidpointSlashesOrZero() external {
        assertLe(_payoutAt(bytes32(uint256(4)), 1000), 0, "below 5000 must not reward");
        assertLe(_payoutAt(bytes32(uint256(5)), 4999), 0, "just below 5000 must not reward");
    }

    function test_aboveMidpointRewardsOrZero() external {
        assertGe(_payoutAt(bytes32(uint256(6)), 5001), 0, "just above 5000 must not slash");
        assertGe(_payoutAt(bytes32(uint256(7)), 9000), 0, "above 5000 must not slash");
    }

    function test_perfectBeatsWorst() external {
        int256 worst = _payoutAt(bytes32(uint256(8)), 0);
        int256 best = _payoutAt(bytes32(uint256(9)), 10000);
        assertLt(worst, best, "perfect accuracy must out-earn worst accuracy");
    }

    // ─── Clip endpoints bind at the documented bounds (finding #2) ──────

    /// @notice With the corrected ×3/10 scale, the documented MAX_REWARD_BPS
    ///         (+5.0%) and MAX_PENALTY_BPS (−1.7%) clips must actually bind at
    ///         the accuracy extremes, matching the whitepaper. Under the
    ///         pre-fix ×3/1000 scale, realized payouts only spanned ±0.3% and
    ///         these clips were unreachable dead code.
    function test_clipsBind_atDocumentedBounds() external {
        // accuracy=0 -> payoutFactor=-10000 -> rawPayout=-3000 -> clipped to
        // -170 bps -> -1.7% of stake.
        int256 worst = _payoutAt(bytes32(uint256(20)), 0);
        assertEq(worst, -int256(STAKE * 170 / 10000), "worst signal slashes exactly -1.7% of stake");

        // accuracy=10000 -> payoutFactor=+10000 -> rawPayout=+3000 -> clipped to
        // +500 bps -> +5.0% of stake.
        int256 best = _payoutAt(bytes32(uint256(21)), 10000);
        assertEq(best, int256(STAKE * 500 / 10000), "perfect signal rewards exactly +5.0% of stake");
    }

    // ─── Monotonicity across a swept ladder ─────────────────────────────

    /// @notice Walk accuracy 0..10000 in steps of 250 and assert the payout
    ///         never decreases. This is the property that fails on the
    ///         quadratic curve and holds on the linear one.
    function test_payoutMonotonicNonDecreasing() external {
        int256 prev = type(int256).min;
        uint256 id = 100;
        for (uint256 acc = 0; acc <= 10000; acc += 250) {
            int256 p = _payoutAt(bytes32(id++), acc);
            assertGe(p, prev, "payout must be non-decreasing in accuracy");
            prev = p;
        }
    }

    // ─── Fuzz: any a1 <= a2 implies payout(a1) <= payout(a2) ────────────

    function testFuzz_payoutMonotonic(uint256 a1, uint256 a2) external {
        a1 = bound(a1, 0, 10000);
        a2 = bound(a2, 0, 10000);
        if (a1 > a2) (a1, a2) = (a2, a1);

        int256 p1 = _payoutAt(bytes32(uint256(0xA1)), a1);
        int256 p2 = _payoutAt(bytes32(uint256(0xA2)), a2);

        assertLe(p1, p2, "lower accuracy must never out-earn higher accuracy");
    }
}
