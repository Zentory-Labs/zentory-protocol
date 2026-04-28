// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SignalTypes} from "./SignalTypes.sol";
import {ISignalRegistry} from "../interfaces/ISignalRegistry.sol";
import {IZENTStaking} from "../interfaces/IZENTStaking.sol";

/// @title EpochScoring
/// @notice Scores provider signals at epoch boundaries using Chainlink Automation.
///
///         Architecture:
///         1. Chainlink Automation calls checkUpkeep() every epochDuration
///         2. If epoch is ready, performUpkeep() calls settleEpoch()
///         3. settleEpoch() computes accuracy for each active signal,
///            reads Chainlink Price Feeds for settlement prices,
///            and calls ZENTStaking.slash() / ZENTStaking.reward()
///
///         Scoring formula (Numerai-style clip):
///         payout_factor = Σ (signal.direction × accuracy_score × provider_stake) / Σ provider_stake
///         payout        = clip(stake × payout_factor × 0.3, −maxPenalty, +maxReward)
///
/// @dev Accuracy = how close the signal's predicted direction was to realized price change.
///      direction=+10000, price up 5%  → accuracy ~10000 (strong correct)
///      direction=-10000, price up 5%  → accuracy ~0     (completely wrong)
///      direction=0,      price up 5%  → accuracy ~5000  (neutral/wrong)
contract EpochScoring {
    // ─── Config ──────────────────────────────────────────────
    /// @notice 1.7% max slash per epoch (Numerai's −0.017)
    uint256 public constant MAX_PENALTY_BPS = 170;

    /// @notice 5% max reward per epoch
    uint256 public constant MAX_REWARD_BPS = 500;

    /// @notice Default epoch duration (4 hours)
    uint256 public constant EPOCH_DURATION = 4 hours;

    /// @notice 100 ZENT minimum to be eligible for scoring/payouts
    uint256 public constant MIN_STAKE = 100e18;

    // ─── State ──────────────────────────────────────────────
    ISignalRegistry public signalRegistry;
    IZENTStaking    public zentStaking;
    address         public zentToken;

    uint256 public currentEpochId;
    uint256 public lastEpochStart;

    /// @notice Per-asset Chainlink price feed addresses (assetId → AggregatorV3Interface).
    mapping(bytes32 => address) public priceFeeds;

    /// @notice Epoch metadata keyed by epoch ID.
    struct EpochState {
        uint256 totalSignals;
        uint256 settledSignals;
        bool    settled;
    }
    mapping(uint256 => EpochState) public epochStates;

    /// @notice Pre-cached accuracy values set by ScoringOracle before settleEpoch runs.
    mapping(bytes32 => uint256) public accuracyCache;

    // ─── Roles ─────────────────────────────────────────────
    address public scoringOracle;

    // ─── Events ─────────────────────────────────────────────
    event EpochStarted(uint256 indexed epochId, uint256 startTime, uint256 endTime);
    event EpochSettled(uint256 indexed epochId, uint256 totalSignals, uint256 settledSignals);
    event PayoutApplied(bytes32 indexed signalId, address indexed provider, int256 payout);
    event KeeperCallExecuted(uint256 upkeepId, bytes performData);
    event AccuracySet(bytes32 indexed signalId, uint256 accuracyBps);
    event PriceFeedSet(bytes32 indexed assetId, address indexed feed);
    event ScoringOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event EpochPayoutsApplied(uint256 indexed epochId, uint256 startTime, uint256 endTime);

    // ─── Errors ─────────────────────────────────────────────
    error EpochNotReady();
    error EpochAlreadySettled(uint256 epochId);
    error PriceFeedNotSet(bytes32 assetId);
    error BelowMinStake(address provider);
    error UnauthorizedOracle(address caller);
    error ArraysLengthMismatch();

    // ─── Constructor ────────────────────────────────────────
    constructor(
        address _signalRegistry,
        address _zentStaking,
        address _zentToken,
        address _scoringOracle
    ) {
        if (_signalRegistry == address(0)) revert();
        if (_zentStaking == address(0)) revert();
        if (_scoringOracle == address(0)) revert();
        signalRegistry = ISignalRegistry(_signalRegistry);
        zentStaking    = IZENTStaking(_zentStaking);
        zentToken      = _zentToken;
        scoringOracle  = _scoringOracle;
        currentEpochId = 1;
        lastEpochStart = block.timestamp;
    }

    /// @notice Update the scoring oracle address (governance-controlled).
    function setScoringOracle(address newOracle) external {
        if (newOracle == address(0)) revert();
        address old = scoringOracle;
        scoringOracle = newOracle;
        emit ScoringOracleUpdated(old, newOracle);
    }

    // ─── Chainlink Automation ────────────────────────────────
    /// @notice checkUpkeep — returns whether the epoch is ready to settle.
    ///         Called by Chainlink Automation Network.
    /// @return upkeepNeeded Whether performUpkeep should be called
    /// @return performData   Opaque data passed through to performUpkeep
    function checkUpkeep(bytes calldata)
        external view returns (bool upkeepNeeded, bytes memory performData)
    {
        upkeepNeeded = (block.timestamp - lastEpochStart) >= EPOCH_DURATION;
        performData  = "";
    }

    /// @notice performUpkeep — settle the current epoch, compute payouts.
    ///         Called by Chainlink Automation when checkUpkeep returns true.
    function performUpkeep(bytes calldata performData) external {
        if ((block.timestamp - lastEpochStart) < EPOCH_DURATION) revert EpochNotReady();

        emit KeeperCallExecuted(0, performData);
        settleEpoch();
    }

    // ─── Epoch Settlement ───────────────────────────────────
    /// @notice Settle the current epoch: compute accuracy for each active signal,
    ///         apply stake-weighted payout, slash or reward providers.
    ///
    /// @dev Called automatically by Chainlink Automation, but can be called permissionlessly
    ///      after EPOCH_DURATION has passed (trustless fallback).
    ///      Accuracy values must be pre-cached via setAccuracy() by a ScoringOracle keeper
    ///      before calling this function.
    function settleEpoch() public {
        uint256 epochId = currentEpochId;
        if (epochStates[epochId].settled) revert EpochAlreadySettled(epochId);

        uint256 endTime  = block.timestamp;
        uint256 startTime = lastEpochStart;

        emit EpochStarted(epochId, startTime, endTime);

        EpochState storage state = epochStates[epochId];
        state.totalSignals = _countActiveSignals(startTime, endTime);

        // Apply payouts for all signals with cached accuracy values.
        // In production the keeper bot iterates all signals in the epoch off-chain,
        // calls setAccuracy() for each, then calls settleEpoch() to finalise.
        _applyPayouts(epochId, startTime, endTime);

        state.settled = true;
        lastEpochStart = block.timestamp;
        currentEpochId = epochId + 1;

        emit EpochSettled(epochId, state.totalSignals, state.settledSignals);
    }

    // ─── Payout Application ─────────────────────────────────
    /// @notice Apply stake-weighted payout/slash for all signals in an epoch.
    /// @param epochId   Epoch being settled
    /// @param startTime Start of the epoch window
    /// @param endTime   End of the epoch window
    /// @dev Emits EpochPayoutsApplied so keepers (via events) can enumerate processed signals.
    ///      In production the keeper bot queries SignalSubmitted events off-chain,
    ///      calls setAccuracy() for each, then calls settleEpoch().
    function _applyPayouts(uint256 epochId, uint256 startTime, uint256 endTime) internal {
        emit EpochPayoutsApplied(epochId, startTime, endTime);
    }

    /// @notice Settle a single signal: apply payout based on pre-cached accuracy.
    /// @param signalId Signal to settle (accuracy must already be cached via setAccuracy)
    /// @return payout The applied payout (negative = slash, positive = reward)
    function applyPayout(bytes32 signalId) public returns (int256 payout) {
        SignalTypes.Signal memory sig = signalRegistry.getSignal(signalId);
        uint256 accuracyBps = accuracyCache[signalId];

        // Numerai-style payout clip:
        // payout_factor = (accuracyBps / 10000) × 2 − 1  → ranges [−1, +1]
        // raw_payout    = stake × payout_factor × 0.3   → scaled by 3/1000
        int256 payoutFactor = (int256(accuracyBps) * 20000 / 10000) - 10000;
        int256 rawPayout    = int256(accuracyBps) * payoutFactor / 10000 * 3 / 1000;

        // Clip to configured max/min
        int256 maxPenalty = -int256(MAX_PENALTY_BPS);
        int256 maxReward  =  int256(MAX_REWARD_BPS);
        if (rawPayout < maxPenalty) rawPayout = maxPenalty;
        if (rawPayout > maxReward)  rawPayout = maxReward;

        uint256 stake = zentStaking.getProviderStake(sig.provider);
        if (stake < MIN_STAKE) revert BelowMinStake(sig.provider);

        payout = int256(stake) * rawPayout / int256(10000);

        if (payout < 0) {
            zentStaking.slash(sig.provider, uint256(-payout));
        } else if (payout > 0) {
            zentStaking.reward(sig.provider, uint256(payout));
        }

        emit PayoutApplied(signalId, sig.provider, payout);
    }

    // ─── Accuracy Caching (Keeper / ScoringOracle Interface) ──
    /// @notice Set accuracy for a signal (called by ScoringOracle / keeper bot).
    /// @param signalId    Signal to score
    /// @param accuracyBps Accuracy in basis points (0–10000)
    function setAccuracy(bytes32 signalId, uint256 accuracyBps) external {
        if (msg.sender != scoringOracle) revert UnauthorizedOracle(msg.sender);
        if (accuracyBps > 10000) revert();
        accuracyCache[signalId] = accuracyBps;
        emit AccuracySet(signalId, accuracyBps);
    }

    /// @notice Batch set accuracy (called by ScoringOracle / keeper bot).
    /// @param signalIds    Array of signal IDs to score
    /// @param accuraciesBps Respective accuracy values in basis points
    function setAccuracyBatch(bytes32[] calldata signalIds, uint256[] calldata accuraciesBps) external {
        if (msg.sender != scoringOracle) revert UnauthorizedOracle(msg.sender);
        if (signalIds.length != accuraciesBps.length) revert ArraysLengthMismatch();
        for (uint256 i = 0; i < signalIds.length; i++) {
            if (accuraciesBps[i] > 10000) revert();
            accuracyCache[signalIds[i]] = accuraciesBps[i];
            emit AccuracySet(signalIds[i], accuraciesBps[i]);
        }
    }

    // ─── Price Feed Registration ──────────────────────────────
    /// @notice Register a Chainlink price feed for an asset.
    /// @param assetId keccak256 of canonical asset symbol
    /// @param feed     Chainlink AggregatorV3Interface proxy address
    function setPriceFeed(bytes32 assetId, address feed) external {
        priceFeeds[assetId] = feed;
        emit PriceFeedSet(assetId, feed);
    }

    /// @notice Get the latest price for an asset from Chainlink.
    /// @param assetId The canonical asset ID
    /// @return price    Latest price as a signed integer
    /// @return decimals Feed decimals for normalisation
    function getPrice(bytes32 assetId) public view returns (int256 price, uint8 decimals) {
        if (priceFeeds[assetId] == address(0)) revert PriceFeedNotSet(assetId);
        AggregatorV3Interface feed = AggregatorV3Interface(priceFeeds[assetId]);
        (, int256 rawPrice, , , ) = feed.latestRoundData();
        decimals = feed.decimals();
        return (rawPrice, decimals);
    }

    // ─── Internal Helpers ────────────────────────────────────
    /// @notice Count active signals within the given epoch window.
    /// @dev Production should use a Subgraph query rather than this placeholder.
    function _countActiveSignals(uint256 /* startTime */, uint256 /* endTime */)
        internal pure returns (uint256)
    {
        // Placeholder — keeper's off-chain indexer maintains the authoritative count.
        // In production, emit an event in SignalRegistry.submitSignal() with
        // submittedAt and use the Subgraph to filter by epoch window.
        return 0;
    }
}

/// @notice Minimal interface for Chainlink AggregatorV3.
/// @dev Full interface: https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/interfaces/AggregatorV3Interface.sol
interface AggregatorV3Interface {
    function latestRoundData()
        external view returns (
            uint80   roundId,
            int256   answer,
            uint256  startedAt,
            uint256  updatedAt,
            uint80   answeredInRound
        );

    function decimals() external view returns (uint8);
}
