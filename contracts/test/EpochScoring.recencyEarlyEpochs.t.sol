// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {EpochScoring} from "../src/signals/EpochScoring.sol";

/// @dev Harness to expose the internal pure `_calculateRecencyBonus` for testing.
contract RecencyHarness is EpochScoring {
    constructor(address a, address b, address c, address d, address e) EpochScoring(a, b, c, d, e) {}

    function exposed_calculateRecencyBonus(
        address provider,
        uint256 epochId,
        uint256[] memory epochsActive
    ) external pure returns (uint256) {
        return _calculateRecencyBonus(provider, epochId, epochsActive);
    }
}

/// @notice Regression: _calculateRecencyBonus must NOT revert for the protocol's
/// first three epochs (epochId = 0, 1, 2). Previously `epochId - 3` underflowed
/// the unsigned subtraction (Solidity 0.8 checked math), panicking the function
/// the moment a real signal flowed before epoch 3 and bricking recency scoring
/// at the most critical time. Caught pre-mainnet.
contract EpochScoringRecencyEarlyEpochsTest is Test {
    RecencyHarness harness;
    address constant PROVIDER = address(0xBEEF);

    function setUp() public {
        // Constructor requires non-zero addresses; values are irrelevant for a
        // pure function under test, so this contract stands in for everything.
        harness = new RecencyHarness(address(this), address(this), address(0), address(this), address(this));
    }

    function _empty() internal pure returns (uint256[] memory) {
        return new uint256[](0);
    }

    /// Epoch 0 with no history must return 0 cleanly (not panic).
    function test_epochZero_noActive_returnsZero() public view {
        assertEq(harness.exposed_calculateRecencyBonus(PROVIDER, 0, _empty()), 0);
    }

    /// Epoch 1 with no history must return 0 cleanly (not panic).
    function test_epochOne_noActive_returnsZero() public view {
        assertEq(harness.exposed_calculateRecencyBonus(PROVIDER, 1, _empty()), 0);
    }

    /// Epoch 2 with no history must return 0 cleanly (not panic).
    function test_epochTwo_noActive_returnsZero() public view {
        assertEq(harness.exposed_calculateRecencyBonus(PROVIDER, 2, _empty()), 0);
    }

    /// Epoch 1, active in epoch 0 -> counts as recent (windowStart = 0).
    function test_epochOne_activeInZero_countsRecent() public view {
        uint256[] memory active = new uint256[](1);
        active[0] = 0;
        // recentCount = 1; bonus = 1 * 100 / 3 = 33.
        assertEq(harness.exposed_calculateRecencyBonus(PROVIDER, 1, active), 33);
    }

    /// Epoch 5 with the same window math (epochId > 3 branch) -- regression
    /// guard for the non-edge case so the underflow fix didn't break it.
    function test_epochFive_normalWindow() public view {
        uint256[] memory active = new uint256[](3);
        active[0] = 2; active[1] = 3; active[2] = 4;
        // windowStart = 2; all three active in [2,5] -> recentCount = 3 -> bonus = 100.
        assertEq(harness.exposed_calculateRecencyBonus(PROVIDER, 5, active), 100);
    }

    /// Out-of-window epochs are excluded (epoch 1 too old when epochId = 5).
    function test_epochFive_excludesOutOfWindow() public view {
        uint256[] memory active = new uint256[](2);
        active[0] = 1; active[1] = 4;
        // windowStart = 2; only epoch 4 counts -> recentCount = 1 -> bonus = 33.
        assertEq(harness.exposed_calculateRecencyBonus(PROVIDER, 5, active), 33);
    }
}
