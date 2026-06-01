// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {EpochScoring} from "../../src/signals/EpochScoring.sol";

/// @notice Registry mock that always reports exactly one signal in the epoch,
///         owned by `provider`, predicting `signalReturn` (bps). Only the
///         methods on settleEpoch's non-empty path are implemented.
contract MockRegistryOneSignal {
    address public provider;
    int256 public signalReturn;
    uint256 public currentEpochId;

    constructor(address provider_, int256 signalReturn_) {
        provider = provider_;
        signalReturn = signalReturn_;
    }

    function getEpochSignalCount(uint256) external pure returns (uint256) { return 1; }
    function getEpochSignalProvider(uint256, uint256) external view returns (address) { return provider; }
    function getEpochSignalReturn(uint256, uint256) external view returns (int256) { return signalReturn; }
    function getSignalCount() external pure returns (uint256) { return 1; }
    function advanceEpoch() external { currentEpochId += 1; }
}

/// @notice Staking mock: the provider is always actively staked.
contract MockStakingActive {
    function getProviderStake(address) external pure returns (uint256) { return 1_000e18; }
    function getStakeAtEpoch(address, uint256) external pure returns (uint256) { return 1_000e18; }
    function reward(address, uint256) external {}
    function slash(address, uint256) external {}
}

/// @notice Minimal Chainlink AggregatorV3 mock with a settable price.
contract MockAggregator {
    int256 public price;
    function setPrice(int256 p) external { price = p; }
    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, price, block.timestamp, block.timestamp, 1);
    }
}

/// @notice Spec-conformance audit, finding #3 (High): the reference-close
///         snapshot must be written BEFORE the scoring loop reads it.
///
///         Pre-fix, _snapshotReferenceClose(epochId) ran AFTER the
///         _scoreProvider loop, so _getEpochPriceMovement(epochId) read a zero
///         epochClosePrice[epochId] and accuracy was identically 0 for every
///         provider every epoch — a silent re-introduction of the H-2 no-op.
///
///         This test settles two consecutive epochs with a moving price feed
///         and asserts that, by the second epoch (when a prior close exists),
///         the scoring loop observes a non-zero price movement and emits a
///         non-zero accuracy. On the pre-fix ordering this accuracy is 0.
contract EpochScoringSnapshotOrderTest is Test {
    EpochScoring scoring;
    MockRegistryOneSignal registry;
    MockStakingActive staking;
    MockAggregator feed;

    address constant PROVIDER = address(0x5161);
    address constant ZENT_TOKEN = address(0x271c);

    bytes32 constant SIGNAL_SCORED_SIG =
        keccak256("SignalScored(address,uint256,uint256,uint256)");

    function setUp() public {
        vm.warp(1_000_000); // ensure feed updatedAt > 0
        // Signal predicts +100 bps; we will move the price +100 bps so a correct
        // ordering yields perfect accuracy (10000).
        registry = new MockRegistryOneSignal(PROVIDER, int256(100));
        staking = new MockStakingActive();
        // scoringOracle + keeper (EPOCH_SETTLER) = this test contract; DEFAULT_ADMIN
        // is also granted to msg.sender, so we can register the price feed.
        scoring = new EpochScoring(
            address(registry), address(staking), ZENT_TOKEN, address(this), address(this)
        );
        feed = new MockAggregator();
        scoring.setPriceFeed(scoring.referenceAssetId(), address(feed));
    }

    function _settleAndReadAccuracy() internal returns (uint256 accuracy, bool found) {
        vm.recordLogs();
        scoring.settleEpoch();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == SIGNAL_SCORED_SIG) {
                (uint256 acc, , ) = abi.decode(logs[i].data, (uint256, uint256, uint256));
                return (acc, true);
            }
        }
        return (0, false);
    }

    function test_scoringObservesPriceMovement_afterSnapshotReorder() external {
        // Epoch 1: price 60000. Snapshots close[1]; movement(1)=0 (no close[0]),
        // so epoch-1 accuracy is legitimately 0 (no prior baseline).
        feed.setPrice(60_000e8);
        (uint256 acc1, bool found1) = _settleAndReadAccuracy();
        assertTrue(found1, "epoch 1 should emit SignalScored");
        assertEq(acc1, 0, "epoch 1 has no prior close -> movement 0 -> accuracy 0");

        // Epoch 2: price +1% to 60600. With the snapshot taken BEFORE scoring,
        // _getEpochPriceMovement(2) = (60600-60000)*10000/60000 = +100 bps. The
        // signal predicted +100, so accuracy = 10000 (perfect). Pre-fix the
        // close[2] read during scoring was 0 -> accuracy 0.
        feed.setPrice(60_600e8);
        (uint256 acc2, bool found2) = _settleAndReadAccuracy();
        assertTrue(found2, "epoch 2 should emit SignalScored");
        assertGt(acc2, 0, "post-fix: scoring must observe the price move (pre-fix this is 0)");
        assertEq(acc2, 10000, "+100 bps move vs +100 bps signal -> perfect accuracy");

        // And the close was actually recorded for epoch 2.
        assertGt(scoring.epochClosePrice(2), 0, "epoch 2 close must be snapshotted");
    }
}
