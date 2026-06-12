// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {EpochScoring} from "../../src/signals/EpochScoring.sol";

/// @notice Exposes the internal capture-accuracy formula for direct unit tests.
contract AccuracyHarness is EpochScoring {
    constructor(address registry, address staking, address zent, address oracle, address keeper)
        EpochScoring(registry, staking, zent, oracle, keeper)
    {}

    function calc(int256 actual, int256 signal) external pure returns (uint256) {
        return _calculateAccuracy(actual, signal);
    }
}

/// @notice Scoring methodology #68
///         (docs/decisions/2026-06-12-068-scoring-methodology.md):
///         accuracy = 5000 + clamp(conviction x actualMoveBps / 10000 x 10, +-5000).
///         5000 is neutral and matches the payout curve's documented break-even
///         (see PayoutCurve.t.sol: accuracy=5000 pays exactly 0). The previous
///         closeness formula compared a 0..10000 conviction against a bps move
///         and returned ~0 for every realistic epoch — accuracy was
///         structurally unearnable.
contract EpochScoringCaptureAccuracyTest is Test {
    AccuracyHarness harness;

    function setUp() public {
        // Constructor args are unused by the pure formula; any non-zero
        // addresses satisfy the constructor's wiring requirements.
        harness = new AccuracyHarness(address(1), address(2), address(3), address(4), address(5));
    }

    function test_zeroMoveIsNeutral() external view {
        assertEq(harness.calc(0, 10000), 5000, "zero move -> nothing to capture -> neutral");
        assertEq(harness.calc(0, 0), 5000, "zero move, flat -> neutral");
    }

    function test_flatConvictionIsNeutralRegardlessOfMove() external view {
        assertEq(harness.calc(250, 0), 5000, "flat captures nothing in a rally");
        assertEq(harness.calc(-250, 0), 5000, "flat loses nothing in a selloff");
    }

    function test_fullConvictionCapturesTheMove() external view {
        assertEq(harness.calc(100, 10000), 6000, "+100 bps at full conviction -> 6000");
        assertEq(harness.calc(-100, 10000), 4000, "-100 bps at full conviction -> 4000");
    }

    function test_partialConvictionScalesLinearly() external view {
        // 50% conviction on a +200 bps move captures +100 bps -> 6000.
        assertEq(harness.calc(200, 5000), 6000, "half conviction on +200 bps -> 6000");
        // 10% conviction on a +100 bps move captures +10 bps -> 5100.
        assertEq(harness.calc(100, 1000), 5100, "10% conviction on +100 bps -> 5100");
    }

    function test_saturatesAtPlusMinus500BpsCaptured() external view {
        assertEq(harness.calc(500, 10000), 10000, "+500 bps captured saturates high");
        assertEq(harness.calc(2000, 10000), 10000, "beyond saturation stays capped");
        assertEq(harness.calc(-500, 10000), 0, "-500 bps captured saturates low");
        assertEq(harness.calc(-2000, 10000), 0, "beyond saturation stays floored");
    }

    function test_outOfRangeConvictionIsClamped() external view {
        // Defensive clamps: scoring never reverts on out-of-range data.
        assertEq(harness.calc(100, 20000), 6000, "conviction clamps to 10000");
        assertEq(harness.calc(100, -5), 5000, "negative conviction clamps to 0 -> neutral");
    }

    function test_monotoneInMoveAtFixedConviction() external view {
        uint256 prev = 0;
        for (int256 move = -600; move <= 600; move += 50) {
            uint256 acc = harness.calc(move, 10000);
            assertGe(acc, prev, "accuracy must be non-decreasing in the captured move");
            prev = acc;
        }
    }
}
