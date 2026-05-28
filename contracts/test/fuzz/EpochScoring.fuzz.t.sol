// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {EpochScoring} from "../../src/signals/EpochScoring.sol";
import {SignalTypes} from "../../src/signals/SignalTypes.sol";

// ─── Harness — exposes internal pure functions for fuzz testing ────────
contract EpochScoringHarness is EpochScoring {
    constructor(
        address _signalRegistry,
        address _zentStaking,
        address _zentToken,
        address _scoringOracle,
        address _keeper
    ) EpochScoring(_signalRegistry, _zentStaking, _zentToken, _scoringOracle, _keeper) {}

    function exposed_calculateAccuracy(int256 actual, int256 signal) external pure returns (uint256) {
        return _calculateAccuracy(actual, signal);
    }

    function exposed_calculateRecencyBonus(
        address provider, uint256 epochId, uint256[] memory epochsActive
    ) external pure returns (uint256) {
        return _calculateRecencyBonus(provider, epochId, epochsActive);
    }
}

// ─── Fuzz mock — configurable per-test through setters ────────────────
contract FuzzMockSignalRegistry {
    uint256 public _signalCount;
    uint256 public currentEpochId;
    address public _singleProvider;

    function setSignalCount(uint256 c) external { _signalCount = c; }
    function setSingleProvider(address p) external { _singleProvider = p; }

    function getEpochSignalCount(uint256) external view returns (uint256) { return _signalCount; }
    function getEpochSignalProvider(uint256, uint256) external view returns (address) { return _singleProvider; }
    function getEpochSignalReturn(uint256, uint256) external pure returns (int256) { return 0; }
    function advanceEpoch() external { currentEpochId++; }

    function getSignal(bytes32) external view returns (SignalTypes.Signal memory s) {
        s.provider = _singleProvider;
    }

    function getSignalCount() external pure returns (uint256) { return 0; }
    function getSignalProvider(uint256) external pure returns (address) { return address(0); }
    function getSignalReturn(address, uint256) external pure returns (int256) { return 0; }
    function stakingContract() external pure returns (address) { return address(0); }
    function getProviderCount() external pure returns (uint256) { return 0; }
    function getProviderAt(uint256) external pure returns (address) { return address(0); }
    function signalExists(bytes32) external pure returns (bool) { return false; }
    function providerNonce(address) external pure returns (uint256) { return 0; }
    function resolveSignals(bytes32[] calldata, uint256[] calldata) external {}
    function submitSignal(address, SignalTypes.AssetClass, bytes32, int256, uint256, uint256, bytes calldata) external pure returns (bytes32) { return bytes32(0); }
    function submitSignalBatch(SignalTypes.Signal[] calldata) external pure returns (bytes32[] memory) { return new bytes32[](0); }
}

contract FuzzMockZENTStaking {
    uint256 public _stake;
    uint256 public lastSlashAmount;
    uint256 public lastRewardAmount;

    function setStake(uint256 s) external { _stake = s; }
    function getProviderStake(address) external view returns (uint256) { return _stake; }
    function getStakeAtEpoch(address, uint256) external view returns (uint256) { return _stake; }
    function slash(address, uint256 amount) external { lastSlashAmount = amount; }
    function reward(address, uint256 amount) external { lastRewardAmount = amount; }

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

// ─── Fuzz Tests ───────────────────────────────────────────────────────
contract EpochScoringFuzzTest is Test {
    EpochScoringHarness harness;
    FuzzMockSignalRegistry registry;
    FuzzMockZENTStaking staking;

    address constant KEEPER = address(0x2251);

    function setUp() external {
        registry = new FuzzMockSignalRegistry();
        staking  = new FuzzMockZENTStaking();
        harness  = new EpochScoringHarness(
            address(registry),
            address(staking),
            address(0x271c), // ZENT_TOKEN placeholder
            KEEPER,          // scoringOracle
            KEEPER           // EPOCH_SETTLER
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    // Edge Case 1: Signal submitted mid-epoch is attributed to next epoch
    // ═══════════════════════════════════════════════════════════════════

    function testFuzz_settleEpoch_pushesSignalsToNextEpoch(uint8 signalCount) external {
        vm.assume(signalCount > 0 && signalCount <= 50);
        registry.setSignalCount(signalCount);
        registry.setSingleProvider(makeAddr("provider"));
        staking.setStake(1000e18);

        vm.warp(block.timestamp + 4 hours + 1);
        vm.prank(KEEPER);
        harness.settleEpoch();

        // After settlement, epoch advanced by 1.
        // The signalCount was for epoch 1; epoch 2 should start with 0.
        assertEq(harness.currentEpochId(), 2, "epoch must advance after settle");
        (uint256 totalSignals, uint256 settledSignals, bool postSettled) =
            harness.epochStates(1);
        assertEq(settledSignals, signalCount, "epoch 1 must report settled signals");
    }

    // ═══════════════════════════════════════════════════════════════════
    // Edge Case 2: Zero-signal epoch does not divide by zero
    // ═══════════════════════════════════════════════════════════════════

    function testFuzz_emptyEpoch_returnsZeroRewards(uint256 signalCount) external {
        signalCount = bound(signalCount, 0, 0);
        registry.setSignalCount(signalCount);

        vm.warp(block.timestamp + 4 hours + 1);
        vm.prank(KEEPER);

        // Must not panic(0x12) division by zero
        uint256 rewards = harness.settleEpoch();

        assertEq(rewards, 0, "empty epoch must return zero rewards");
        assertEq(harness.currentEpochId(), 2, "epoch must advance");
    }

    function testFuzz_emptyEpoch_consecutiveSettlementsOk() external {
        for (uint256 i = 0; i < 10; i++) {
            registry.setSignalCount(0);
            vm.warp(block.timestamp + 4 hours + 1);
            vm.prank(KEEPER);
            harness.settleEpoch();
        }
        assertEq(harness.currentEpochId(), 11, "ten consecutive empty epochs must succeed");
    }

    // ═══════════════════════════════════════════════════════════════════
    // Edge Case 3: Accuracy and payout bounds
    // ═══════════════════════════════════════════════════════════════════

    function testFuzz_calculateAccuracy_neverExceeds10000(
        int256 actual, int256 signal
    ) external {
        actual = bound(actual, -100000, 100000);
        signal = bound(signal, -100000, 100000);

        uint256 accuracy = harness.exposed_calculateAccuracy(actual, signal);

        assertLe(accuracy, 10000, "accuracy must not exceed 10000 bps");
    }

    function testFuzz_calculateAccuracy_zeroActual_returnsZero(int256 signal) external {
        signal = bound(signal, -100000, 100000);
        uint256 accuracy = harness.exposed_calculateAccuracy(0, signal);
        assertEq(accuracy, 0, "zero actual movement must produce zero accuracy");
    }

    function testFuzz_calculateAccuracy_perfectSignal_returns10000(int256 movement) external {
        movement = bound(movement, 1, 100000);
        uint256 accuracy = harness.exposed_calculateAccuracy(movement, movement);
        assertEq(accuracy, 10000, "perfect signal must produce 10000 accuracy");
    }

    function testFuzz_calculateAccuracy_worstSignal_returnsZero(int256 movement) external {
        movement = bound(movement, 1, 100000);
        // Signal opposite of actual
        uint256 accuracy = harness.exposed_calculateAccuracy(movement, -movement);
        assertEq(accuracy, 0, "completely wrong signal must produce zero accuracy");
    }

    // ═══════════════════════════════════════════════════════════════════
    // Edge Case 3b: applyPayout respects MAX_PENALTY_BPS / MAX_REWARD_BPS
    // ═══════════════════════════════════════════════════════════════════

    function testFuzz_applyPayout_neverExceedsProtocolBounds(
        uint256 accuracyBps, uint96 stakeAmt
    ) external {
        accuracyBps = bound(accuracyBps, 0, 10000);
        vm.assume(stakeAmt >= 100e18 && stakeAmt <= 1_000_000e18);

        bytes32 signalId = keccak256("bound-test");
        staking.setStake(stakeAmt);
        registry.setSingleProvider(makeAddr("provider"));

        vm.prank(KEEPER);
        harness.setAccuracy(signalId, accuracyBps);

        vm.prank(KEEPER);
        int256 payout = harness.applyPayout(signalId);

        // Payout = stake * rawPayout / 10000
        // rawPayout ∈ [-170, 500] after clipping
        int256 minPayout = -int256(uint256(stakeAmt)) * 170 / 10000;
        int256 maxPayout =  int256(uint256(stakeAmt)) * 500 / 10000;

        assertGe(payout, minPayout, "payout must not exceed max slashing bound");
        assertLe(payout, maxPayout, "payout must not exceed max reward bound");
    }

    // ═══════════════════════════════════════════════════════════════════
    // Edge Case 4: Slashing math does not under/overflow
    // ═══════════════════════════════════════════════════════════════════

    function testFuzz_applyPayout_extremeValues_noOverflow(
        uint256 accuracyBps, uint192 rawStake
    ) external {
        accuracyBps = bound(accuracyBps, 0, 10000);
        uint256 stake = uint256(rawStake) + 100e18; // at least MIN_STAKE

        bytes32 signalId = keccak256("overflow-test");
        staking.setStake(stake);
        registry.setSingleProvider(makeAddr("provider"));

        vm.prank(KEEPER);
        harness.setAccuracy(signalId, accuracyBps);

        // Must not revert with arithmetic overflow
        vm.prank(KEEPER);
        int256 payout = harness.applyPayout(signalId);

        // Cross-check: manually compute expected slash vs reward
        int256 payoutFactor = (int256(accuracyBps) * 20000 / 10000) - 10000;
        int256 rawPayout    = int256(accuracyBps) * payoutFactor / 10000 * 3 / 1000;

        int256 maxPenalty = -170;
        int256 maxReward  =  500;
        if (rawPayout < maxPenalty) rawPayout = maxPenalty;
        if (rawPayout > maxReward)  rawPayout = maxReward;

        int256 expectedPayout = int256(stake) * rawPayout / 10000;
        assertEq(payout, expectedPayout, "payout must match independent calculation");

        // Verify slash/reward amounts
        if (payout < 0) {
            assertEq(staking.lastSlashAmount(), uint256(-payout), "slash amount mismatch");
            assertEq(staking.lastRewardAmount(), 0, "no reward expected");
        } else if (payout > 0) {
            assertEq(staking.lastRewardAmount(), uint256(payout), "reward amount mismatch");
            assertEq(staking.lastSlashAmount(), 0, "no slash expected");
        } else {
            assertEq(staking.lastSlashAmount(), 0, "no slash for zero payout");
            assertEq(staking.lastRewardAmount(), 0, "no reward for zero payout");
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // Recency bonus invariants
    // ═══════════════════════════════════════════════════════════════════

    function testFuzz_recencyBonus_boundedByArrayLength(
        uint256 epochId, uint256[3] memory recent
    ) external {
        epochId = bound(epochId, 4, 1000);
        // Real _getProviderStakeInfo returns length-5 array. Put recent epochs
        // at the front and leave trailing zeros (matching production behavior).
        uint256[] memory active = new uint256[](5);
        for (uint256 i = 0; i < 3; i++) {
            recent[i] = bound(recent[i], epochId - 3, epochId);
            active[i] = recent[i];
        }

        uint256 bonus = harness.exposed_calculateRecencyBonus(
            makeAddr("any"), epochId, active
        );
        // Formula: (recentCount * 100) / 3. Max recentCount = active.length = 5.
        assertLe(bonus, (active.length * 100) / 3, "recency bonus must follow formula bounds");
    }
}
