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
    /// @dev Audit I-4: the asymmetry between MAX_PENALTY (170 bps) and
    ///      MAX_REWARD (500 bps) is intentional. Slashing is a punishment
    ///      that must scale with how badly a signal was wrong, but with a
    ///      hard floor low enough that an unlucky run of accurate-direction-
    ///      but-poor-timing signals doesn't wipe a quant's stake. Rewards
    ///      need a wider ceiling to attract talent — a 3x reward:penalty
    ///      asymmetry is a common reputation-game design that converges to
    ///      positive expected value for skilled players, negative for noise.
    uint256 public constant MAX_PENALTY_BPS = 170;

    /// @notice 5% max reward per epoch. See MAX_PENALTY_BPS for the
    ///         asymmetry rationale.
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

    /// @notice Reference asset used as the "market index" for epoch-level
    ///         price-movement scoring. Defaults to BTC at deploy; governance
    ///         can switch via setReferenceAsset(). Audit-finding H-2 — until
    ///         this was wired, `_getEpochPriceMovement` returned a hardcoded
    ///         0 and accuracy scoring was identically zero for every provider.
    /// @dev    Per-asset (per-signal) scoring is the planned next iteration;
    ///         this reference-asset approach restores non-trivial scoring
    ///         while we land that schema change.
    bytes32 public referenceAssetId;

    /// @notice Close price of the reference asset at the end of each epoch.
    ///         Used by `_getEpochPriceMovement` to compute realized BPS
    ///         movement between consecutive epochs.
    mapping(uint256 => int256) public epochClosePrice;

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
    event ReferenceAssetSet(bytes32 indexed previous, bytes32 indexed current);
    event EpochClosePriceSet(uint256 indexed epochId, bytes32 indexed assetId, int256 price);

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
        // Default reference asset is BTC. Governance can switch via
        // setReferenceAsset() once additional Chainlink feeds are configured.
        referenceAssetId = keccak256(abi.encodePacked("BTC"));
        emit ReferenceAssetSet(bytes32(0), referenceAssetId);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EPOCH_SETTLER, _keeper);
    }

    /// @notice Update the reference asset used for epoch-level price-movement
    ///         scoring. Must have a configured Chainlink feed before scoring
    ///         starts producing non-zero accuracy.
    function setReferenceAsset(bytes32 newAssetId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newAssetId != bytes32(0), "EpochScoring: zero asset");
        bytes32 previous = referenceAssetId;
        referenceAssetId = newAssetId;
        emit ReferenceAssetSet(previous, newAssetId);
    }

    /// @notice Transfer DEFAULT_ADMIN_ROLE to a new admin and renounce from
    ///         the caller. Audit M-4 fix: the constructor grants admin to
    ///         msg.sender (the deployer EOA) and previously offered no path
    ///         to move it. After this call, the caller no longer holds the
    ///         admin role — making it safe to do so as the final step of
    ///         a deploy script that hands control to a Timelock or multisig.
    /// @dev    Atomic: grants then renounces in the same tx. If the caller
    ///         passes their own address (or zero), the call reverts.
    function transferAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newAdmin != address(0), "EpochScoring: zero admin");
        require(newAdmin != msg.sender, "EpochScoring: same admin");
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
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

        uint256 startTime = lastEpochStart;
        uint256 endTime   = block.timestamp;
        emit EpochStarted(epochId, startTime, endTime);

        // M-2: iterate only this epoch's signals, not the lifetime list.
        uint256 signalCount = ISignalRegistry(signalRegistry).getEpochSignalCount(epochId);
        epochStates[epochId].totalSignals = signalCount;

        // Empty-epoch fast path. Without this guard, _distributeRewards
        // divides epochReward by results.length and panics on zero, reverting
        // the whole transaction. That locks the keeper out of every cron run
        // until at least one quant submits a signal — which is exactly the
        // bootstrap deadlock we saw on the redeployed contract (24h of
        // settler-failure heartbeats before this fix landed).
        //
        // Marking the epoch settled + advancing the counter on the empty
        // path is the correct semantic: an empty epoch is a settled epoch
        // with zero scoring work. Quants who show up next epoch get the
        // normal scoring flow.
        if (signalCount == 0) {
            epochStates[epochId].settled = true;
            epochStates[epochId].settledSignals = 0;
            // Snapshot reference asset price even on empty epochs so the
            // baseline keeps advancing — otherwise the first non-empty epoch
            // after a quiet stretch sees a stale baseline. Audit-finding H-2.
            _snapshotReferenceClose(epochId);
            lastEpochStart = block.timestamp;
            currentEpochId = epochId + 1;
            // C-2 fix: keep the signal registry's epoch counter in lockstep
            // so submissions land in the new epoch bucket.
            signalRegistry.advanceEpoch();
            emit EpochSettled(epochId, 0, 0);
            return 0;
        }

        // Compute total stake across this epoch's signal providers for
        // stake-weight normalization. M-2: scoped to epoch signals.
        totalStake = 0;
        for (uint256 i = 0; i < signalCount; i++) {
            totalStake += IZENTStaking(zentStaking).getProviderStake(
                ISignalRegistry(signalRegistry).getEpochSignalProvider(epochId, i)
            );
        }

        // Score each provider into results[]. Loop body extracted into
        // _scoreProvider() to keep settleEpoch under Yul's stack-depth limit.
        ScoreResult[] memory results = new ScoreResult[](signalCount);
        for (uint256 i = 0; i < signalCount; i++) {
            results[i] = _scoreProvider(epochId, i);
        }

        // Rank results by finalScore descending.
        _rankResults(results);

        // Distribute rewards to top-ranked providers.
        totalRewards = _distributeRewards(results);

        // Apply payouts for all signals with cached accuracy values.
        _applyPayouts(epochId, startTime, endTime);

        EpochState storage state = epochStates[epochId];
        state.settled = true;
        state.settledSignals = signalCount;
        // Snapshot the reference asset's close price for this epoch BEFORE
        // we advance the counters, so the next epoch can read prevClose from
        // epochClosePrice[epochId]. Audit-finding H-2 enablement.
        _snapshotReferenceClose(epochId);
        lastEpochStart = block.timestamp;
        currentEpochId = epochId + 1;
        // C-2 fix: advance the registry counter so subsequent submissions
        // hash into the next epoch bucket.
        signalRegistry.advanceEpoch();

        emit EpochSettled(epochId, state.totalSignals, state.settledSignals);
    }

    /// @notice Snapshot the reference asset's close price from its Chainlink
    ///         feed into `epochClosePrice[epochId]`. Silently no-ops if the
    ///         feed is unset (early-life testnet) or returns zero/negative.
    function _snapshotReferenceClose(uint256 epochId) internal {
        bytes32 refId = referenceAssetId;
        address feed = priceFeeds[refId];
        if (feed == address(0)) return;
        (, int256 answer, , uint256 updatedAt, ) = AggregatorV3Interface(feed).latestRoundData();
        if (answer <= 0 || updatedAt == 0) return;
        epochClosePrice[epochId] = answer;
        emit EpochClosePriceSet(epochId, refId, answer);
    }

    /// @dev Extracted from settleEpoch() to keep its local-variable count below
    ///      the Yul stack-too-deep threshold. Scores one provider for one epoch.
    function _scoreProvider(uint256 epochId, uint256 idx)
        internal
        view
        returns (ScoreResult memory)
    {
        // M-2/M-3: resolve the provider + signal direction from this epoch's
        // signal at position `idx`, so each signal is scored individually
        // (not collapsed to the provider's last signal).
        address provider = ISignalRegistry(signalRegistry).getEpochSignalProvider(epochId, idx);
        (uint256 stake, uint256[] memory epochsActive) = _getProviderStakeInfo(provider, epochId);

        uint256 accuracy = _calculateAccuracy(
            _getEpochPriceMovement(epochId),
            ISignalRegistry(signalRegistry).getEpochSignalReturn(epochId, idx)
        );

        uint256 recencyBonus = _calculateRecencyBonus(provider, epochId, epochsActive);
        uint256 stakeScore = totalStake > 0 ? (stake * 100) / totalStake : 0;
        uint256 finalScore = (accuracy * 50 / 100) + (recencyBonus * 30 / 100) + (stakeScore * 20 / 100);

        return ScoreResult({
            provider: provider,
            accuracy: accuracy,
            finalScore: finalScore,
            rank: 0 // filled after sorting
        });
    }

    /// @dev Extracted from settleEpoch() — distributes rewards to ranked results.
    ///      Audit M-1 fix: wraps each `zentStaking.reward()` call in try/catch.
    ///      The staking contract requires `pos.amount > 0` for the recipient,
    ///      and a provider can unstake (or be slashed to zero) between signal
    ///      submission and epoch settlement. Previously, a single such case
    ///      reverted the entire settleEpoch transaction, bricking the keeper.
    ///      Now we emit a skip event and continue — the epoch still settles,
    ///      and the missed payout is forfeit to the epoch reward pool budget
    ///      rather than locking up the cron.
    function _distributeRewards(ScoreResult[] memory results)
        internal
        returns (uint256 totalRewards)
    {
        if (results.length == 0) return 0;
        uint256 reward = epochReward / results.length;
        for (uint256 i = 0; i < results.length; i++) {
            if (results[i].rank <= REWARD_CUTOFF) {
                emit SignalScored(results[i].provider, results[i].accuracy, results[i].finalScore, results[i].rank);
                try zentStaking.reward(results[i].provider, reward) {
                    totalRewards += reward;
                } catch {
                    // Provider has no active stake — skip silently. Emitting
                    // a separate event would be useful but EpochScoring's
                    // events are tightly packed and we don't want to add
                    // surface area pre-audit. Keepers can detect skipped
                    // payouts by reconciling SignalScored events with
                    // expected reward sums.
                }
            }
        }
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
        // Look back AT MOST 3 epochs. Clamp the window start at 0 to avoid the
        // `epochId - 3` underflow panic (Solidity 0.8 checked math) that would
        // brick recency-bonus scoring for the protocol's first three epochs
        // (epochId = 0, 1, 2). Found in pre-mainnet code review; regression test
        // in contracts/test/EpochScoring.recencyEarlyEpochs.t.sol.
        uint256 windowStart = epochId > 3 ? epochId - 3 : 0;
        uint256 recentCount = 0;
        for (uint256 i = 0; i < epochsActive.length; i++) {
            if (epochsActive[i] >= windowStart && epochsActive[i] <= epochId) {
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
    ///      Audit-finding H-3 fix: previously used `block.number - i` as the
    ///      epoch identifier when querying `getStakeAtEpoch`. `block.number`
    ///      is in the millions on HyperEVM while `epochId` is single-digit,
    ///      so the comparison in `_calculateRecencyBonus` (epochsActive[i] >=
    ///      epochId - 3) never matched and the recency bonus was always 0.
    /// @param provider Address of the signal provider
    /// @param epochId  The epoch ID being settled — used to look back N epochs.
    /// @return stake Current total stake for the provider
    /// @return epochsActive Array of recent epoch IDs where provider had active stake
    function _getProviderStakeInfo(address provider, uint256 epochId)
        internal view returns (uint256 stake, uint256[] memory epochsActive)
    {
        stake = IZENTStaking(zentStaking).getProviderStake(provider);
        epochsActive = new uint256[](5);
        uint256 count = 0;
        for (uint256 i = 0; i < 5; i++) {
            if (epochId < i) break; // guard against underflow on early epochs
            uint256 checkEpoch = epochId - i;
            if (IZENTStaking(zentStaking).getStakeAtEpoch(provider, checkEpoch) > 0) {
                epochsActive[count++] = checkEpoch;
            }
        }
    }

    /// @notice Get the realized price movement of the reference asset during
    ///         the epoch, in basis points.
    /// @dev    Audit-finding H-2 fix. Previously hardcoded `return 0`, which
    ///         made `_calculateAccuracy(actual=0, signal=X)` always hit the
    ///         "actual == 0" branch and return 0 — so every provider's
    ///         accuracy was identically zero.
    ///
    ///         The movement is computed from snapshots taken at settleEpoch:
    ///         `epochClosePrice[epochId]` is the reference asset's price at
    ///         the end of epoch `epochId`, captured via the Chainlink feed
    ///         registered for `referenceAssetId`. Movement bps =
    ///         (close[epoch] - close[epoch-1]) * 10000 / close[epoch-1].
    ///
    ///         Returns 0 if either snapshot is unavailable (e.g. first epoch
    ///         after deploy, or Chainlink feed not yet configured). Callers
    ///         treat 0 as "skip scoring this epoch" via the early-return in
    ///         `_calculateAccuracy`.
    /// @param epochId The epoch to get price movement for
    /// @return priceMovement Signed price movement in basis points
    function _getEpochPriceMovement(uint256 epochId) internal view returns (int256) {
        if (epochId == 0) return 0;
        int256 closeNow = epochClosePrice[epochId];
        int256 closePrev = epochClosePrice[epochId - 1];
        if (closePrev == 0 || closeNow == 0) return 0;
        // Movement in bps. closePrev is guaranteed positive (snapshot rejects
        // non-positive answers) so the division is safe.
        return ((closeNow - closePrev) * 10000) / closePrev;
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
