// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
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
contract EpochScoring is AccessControl {
    // ─── Roles ─────────────────────────────────────────────
    bytes32 public constant EPOCH_SETTLER = keccak256("EPOCH_SETTLER");

    // ─── Config ──────────────────────────────────────────────
    /// @notice 1.7% max slash per epoch (Numerai's −0.017)
    uint256 public constant MAX_PENALTY_BPS = 170;

    /// @notice 5% max reward per epoch
    uint256 public constant MAX_REWARD_BPS = 500;

    /// @notice Default epoch duration (4 hours)
    uint256 public constant EPOCH_DURATION = 4 hours;

    /// @notice 100 ZENT minimum to be eligible for scoring/payouts
    uint256 public constant MIN_STAKE = 100e18;

    /// @notice Top N providers that receive rewards after each epoch is settled.
    uint256 public constant REWARD_CUTOFF = 10;

    /// @notice Reward amount distributed to each top-performing provider per epoch.
    uint256 public epochReward;

    /// @notice Cached total stake across all providers (used for stake-weight calculation).
    uint256 public totalStake;

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

    /// @notice In-memory scoring result for a single signal provider.
    struct ScoreResult {
        address provider;   /// @dev Provider address
        uint256 accuracy;  /// @dev Accuracy score in basis points (0-10000)
        uint256 finalScore; /// @dev Combined score (accuracy + recency + stake)
        uint256 rank;       /// @dev Provider rank (1 = best)
    }

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
    event SignalScored(address indexed provider, uint256 accuracy, uint256 finalScore, uint256 rank);

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
        address _scoringOracle,
        address _keeper
    ) {
        if (_signalRegistry == address(0)) revert();
        if (_zentStaking == address(0)) revert();
        if (_scoringOracle == address(0)) revert();
        if (_keeper == address(0)) revert();
        signalRegistry = ISignalRegistry(_signalRegistry);
        zentStaking    = IZENTStaking(_zentStaking);
        zentToken      = _zentToken;
        scoringOracle  = _scoringOracle;
        currentEpochId = 1;
        lastEpochStart = block.timestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EPOCH_SETTLER, _keeper);
    }

    /// @notice Update the scoring oracle address (governance-controlled).
    function setScoringOracle(address newOracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newOracle == address(0)) revert();
        address old = scoringOracle;
        scoringOracle = newOracle;
        emit ScoringOracleUpdated(old, newOracle);
    }

    /// @notice Set the epoch reward amount distributed to top providers per epoch.
    /// @param reward The reward amount in ZENT wei
    function setEpochReward(uint256 reward) external onlyRole(DEFAULT_ADMIN_ROLE) {
        epochReward = reward;
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
    function performUpkeep(bytes calldata performData) external onlyRole(EPOCH_SETTLER) {
        if ((block.timestamp - lastEpochStart) < EPOCH_DURATION) revert EpochNotReady();

        emit KeeperCallExecuted(0, performData);
        settleEpoch();
    }

    // ─── Epoch Settlement ───────────────────────────────────
    /// @notice Settle the current epoch: compute accuracy for each active signal,
    ///         apply stake-weighted payout, slash or reward providers.
    ///
    /// @dev Called by Chainlink Automation via performUpkeep() or directly by an EPOCH_SETTLER.
    ///      Accuracy values must be pre-cached via setAccuracy() by the ScoringOracle keeper
    ///      before calling this function.
    /// @return totalRewards The total ZENT rewards distributed to top-performing providers.
    function settleEpoch() public onlyRole(EPOCH_SETTLER) returns (uint256 totalRewards) {
        uint256 epochId = currentEpochId;
        if (epochStates[epochId].settled) revert EpochAlreadySettled(epochId);

        uint256 endTime   = block.timestamp;
        uint256 startTime = lastEpochStart;

        emit EpochStarted(epochId, startTime, endTime);

        EpochState storage state = epochStates[epochId];
        uint256 signalCount = ISignalRegistry(signalRegistry).getSignalCount();
        state.totalSignals = signalCount;

        // Compute total stake across all providers for stake-weight normalization.
        totalStake = 0;
        for (uint256 i = 0; i < signalCount; i++) {
            address provider = ISignalRegistry(signalRegistry).getSignalProvider(i);
            totalStake += IZENTStaking(zentStaking).getProviderStake(provider);
        }

        // Score each provider and build results array.
        ScoreResult[] memory results = new ScoreResult[](signalCount);
        for (uint256 i = 0; i < signalCount; i++) {
            address provider = ISignalRegistry(signalRegistry).getSignalProvider(i);
            (uint256 stake, uint256[] memory epochsActive) = _getProviderStakeInfo(provider);

            // Get actual vs. signal return for this epoch.
            int256 actualReturn = _getEpochPriceMovement(epochId);
            int256 signalReturn = ISignalRegistry(signalRegistry).getSignalReturn(provider, epochId);
            uint256 accuracy = _calculateAccuracy(actualReturn, signalReturn);

            // Combine: 50% accuracy, 30% recency, 20% stake weight.
            uint256 recencyBonus = _calculateRecencyBonus(provider, epochId, epochsActive);
            uint256 stakeScore = totalStake > 0 ? (stake * 100) / totalStake : 0;
            uint256 finalScore = (accuracy * 50 / 100) + (recencyBonus * 30 / 100) + (stakeScore * 20 / 100);

            results[i] = ScoreResult({
                provider: provider,
                accuracy: accuracy,
                finalScore: finalScore,
                rank: 0  // filled after sorting
            });
        }

        // Rank results by finalScore descending.
        _rankResults(results);

        // Calculate and apply rewards for top-performing providers.
        uint256 reward = epochReward / signalCount;
        for (uint256 i = 0; i < results.length; i++) {
            if (results[i].rank <= REWARD_CUTOFF) {
                totalRewards += reward;
                emit SignalScored(results[i].provider, results[i].accuracy, results[i].finalScore, results[i].rank);
                zentStaking.reward(results[i].provider, reward);
            }
        }

        // Apply payouts for all signals with cached accuracy values.
        _applyPayouts(epochId, startTime, endTime);

        state.settled = true;
        state.settledSignals = signalCount;
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
    function applyPayout(bytes32 signalId) external onlyRole(EPOCH_SETTLER) returns (int256 payout) {
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
    function setPriceFeed(bytes32 assetId, address feed) external onlyRole(DEFAULT_ADMIN_ROLE) {
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

    /// @notice Calculate accuracy score from actual vs. predicted price movement.
    /// @param actual  The realized price movement (in basis points)
    /// @param signal  The predicted price movement (in basis points)
    /// @return accuracy Accuracy score from 0 to 10000 (higher = more accurate)
    function _calculateAccuracy(int256 actual, int256 signal) internal pure returns (uint256) {
        if (actual == 0) return 0;
        int256 diff = actual > signal ? actual - signal : signal - actual;
        int256 absActual = actual > 0 ? actual : -actual;
        int256 accuracyRaw = 10000 - ((diff * 10000) / absActual);
        return accuracyRaw > 0 ? uint256(accuracyRaw) : 0;
    }

    /// @notice Calculate recency bonus for a provider based on recent signal submission history.
    /// @dev Providers who submitted signals in the last 3 epochs receive a higher bonus.
    /// @param provider    Address of the signal provider
    /// @param epochId     Current epoch being settled
    /// @param epochsActive Array of epoch IDs the provider was active in
    /// @return recencyBonus Score from 0 to 100 (higher = more recent)
    function _calculateRecencyBonus(
        address provider,
        uint256 epochId,
        uint256[] memory epochsActive
    ) internal pure returns (uint256) {
        uint256 recentCount = 0;
        for (uint256 i = 0; i < epochsActive.length; i++) {
            if (epochsActive[i] >= epochId - 3 && epochsActive[i] <= epochId) {
                recentCount++;
            }
        }
        return (recentCount * 100) / 3; // max 100 bonus
    }

    /// @notice Rank results by finalScore in descending order and assign ranks.
    /// @param results In-memory array of ScoreResult to rank
    function _rankResults(ScoreResult[] memory results) internal pure {
        // Bubble sort by finalScore descending.
        for (uint256 i = 0; i < results.length; i++) {
            for (uint256 j = i + 1; j < results.length; j++) {
                if (results[j].finalScore > results[i].finalScore) {
                    ScoreResult memory tmp = results[i];
                    results[i] = results[j];
                    results[j] = tmp;
                }
            }
        }
        // Assign ranks (1 = best).
        for (uint256 i = 0; i < results.length; i++) {
            results[i].rank = i + 1;
        }
    }

    /// @notice Retrieve stake info for a specific provider.
    /// @dev Queries ZENTStaking for the provider's current stake and recent epoch activity.
    /// @param provider Address of the signal provider
    /// @return stake Current total stake for the provider
    /// @return epochsActive Array of recent epoch IDs where provider had active stake
    function _getProviderStakeInfo(address provider)
        internal view returns (uint256 stake, uint256[] memory epochsActive)
    {
        stake = IZENTStaking(zentStaking).getProviderStake(provider);
        epochsActive = new uint256[](5);
        uint256 count = 0;
        for (uint256 i = 0; i < 5; i++) {
            uint256 checkEpoch = block.number - i;
            if (IZENTStaking(zentStaking).getStakeAtEpoch(provider, checkEpoch) > 0) {
                epochsActive[count++] = checkEpoch;
            }
        }
    }

    /// @notice Get the realized price movement for a given epoch.
    /// @dev Reads from Chainlink price feeds for the epoch's end timestamp.
    ///      Currently a stub that returns 0; production should query price oracle.
    /// @param epochId The epoch to get price movement for
    /// @return priceMovement Signed price movement in basis points
    function _getEpochPriceMovement(uint256 epochId) internal view returns (int256) {
        // Stub: returns 0 until a price oracle integration is implemented.
        // Production should read the settlement price from Chainlink at epoch end.
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
