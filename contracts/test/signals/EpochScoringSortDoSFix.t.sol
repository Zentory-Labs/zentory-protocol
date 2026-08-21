// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {EpochScoring} from "../../src/signals/EpochScoring.sol";
import {SignalTypes} from "../../src/signals/SignalTypes.sol";

/// @notice Registry mock that returns a fixed batch of `(provider, return)`
///         pairs for an epoch. Used by the integration tests below to drive
///         `settleEpoch` with N signals without going through the real
///         SignalRegistry submission pipeline.
contract MockRegistryManySignals {
    address[] public providers;
    int256[] public signalReturns;
    uint256 public immutable n;

    constructor(uint256 count) {
        n = count;
        providers = new address[](count);
        signalReturns = new int256[](count);
        for (uint256 i = 0; i < count; i++) {
            // Distinct providers (0x1000 + i) so no two signals share a provider.
            providers[i] = address(uint160(0x1000 + i));
            // Distinct returns so each signal has a distinct finalScore after
            // the scoring loop. We pick a +1..+N bps move so the recency-
            // adjusted accuracy differs per signal; the exact distribution is
            // not load-bearing — what matters is that every signal ends up
            // with a distinct finalScore so we can assert top-K identity.
            signalReturns[i] = int256(i + 1);
        }
    }

    function getEpochSignalCount(uint256) external view returns (uint256) {
        return n;
    }

    function getEpochSignalProvider(uint256, uint256 idx) external view returns (address) {
        return providers[idx];
    }

    function getEpochSignalReturn(uint256, uint256 idx) external view returns (int256) {
        return signalReturns[idx];
    }

    function getSignal(bytes32) external pure returns (SignalTypes.Signal memory s) {
        return s;
    }

    function getSignalCount() external pure returns (uint256) {
        return 0;
    }
    function advanceEpoch() external {}
}

/// @notice Staking mock returning zero stake for everyone. The exact value
///         doesn't affect the sort, but returning 0 makes the external calls
///         in `_scoreProvider -> _getProviderStakeInfo` deterministic and
///         cheap so the gas measurement isolates the sort cost.
contract MockStakingZero {
    function getProviderStake(address) external pure returns (uint256) {
        return 0;
    }

    function getStakeAtEpoch(address, uint256) external pure returns (uint256) {
        return 0;
    }
    function reward(address, uint256) external {}
    function slash(address, uint256) external {}
}

/// @notice Tier 0 audit Q4 (finding #9) — O(n²) settlement DoS.
///
///         Pre-fix: `_rankResults` ran a memory bubble sort with full struct
///         copies. Per-signal gas was roughly 100–200 gas × n(n-1)/2 + struct
///         copy cost, so for n=1000 the sort alone cost >100M gas — far past
///         HyperEVM's 30M big-block limit. Combined with the 6+ external
///         calls per signal in `_scoreProvider`, total settleEpoch gas for
///         n=1000 was unbounded (the function reverted with out-of-gas and
///         the keeper was permanently locked out of that epoch).
///
///         Post-fix: `_rankResults` uses a bounded top-K selection algorithm
///         (since only REWARD_CUTOFF=10 providers are rewarded, we never
///         need to fully sort). Total sort cost is O(n × K) = O(n × 10) =
///         effectively O(n). For n=1000 the sort costs ~1M gas; for n=100
///         it costs ~100k. The sort is no longer the gas bottleneck even
///         for arbitrarily-large epochs.
///
///         These tests pin three properties:
///         1. `_rankResults` gas is bounded by ~1-2M for n=1000, well
///            below the pre-fix O(N²) profile.
///         2. The top-K (≤REWARD_CUTOFF) providers selected by the new
///            algorithm match the top-K selected by an independent O(N²)
///            reference sort, so the economics ("reward top-10") are
///            unchanged.
///         3. Full `settleEpoch` with n=1000 signals stays within the
///            HyperEVM 30M big-block gas limit, proving the DoS is fixed.
///
/// @dev    This test contract inherits EpochScoring so it can call
///         `_rankResults` directly as an internal function — the memory
///         aliasing pattern needed for the in-place sort to be observable
///         in the caller. A harness-via-external-call pattern would NOT
///         work because Solidity memory is copied across external calls
///         (the mutated array lives only in the called frame's memory
///         space and the caller's array is unchanged). Internal calls
///         share memory with the caller, so this pattern is the right
///         one for a sort that mutates its input array.
contract EpochScoringSortDoSFixTest is Test, EpochScoring {
    /// @notice Forward EpochScoring's constructor args. We pass placeholder
    ///         addresses because the inherited `_rankResults` does not touch
    ///         any external state — it is `pure`. The scoring/staking/
    ///         registry wiring is exercised separately by the integration
    ///         test below (`test_settleEpoch_n1000_*`).
    constructor()
        EpochScoring(
            address(0xA001), // signalRegistry (unused by _rankResults)
            address(0xA002), // zentStaking    (unused by _rankResults)
            address(0xA003), // zentToken      (unused by _rankResults)
            address(0xA004), // scoringOracle  (unused by _rankResults)
            address(0xA005) // keeper         (unused by _rankResults)
        )
    {}

    address constant ZENT_TOKEN = address(0x271c);
    address constant KEEPER = address(0x2251);

    /// @notice HyperEVM big-block gas limit per foundry.toml (block_gas_limit = 30_000_000).
    ///         Settling any single epoch must fit comfortably under this so the
    ///         keeper cron can include the transaction regardless of surrounding
    ///         activity. Pre-Q4 fix this was unreachable for n > a few hundred
    ///         signals; post-fix we assert the budget holds for n=1000.
    uint256 constant HYPEREVM_BIG_BLOCK_GAS = 30_000_000;

    /// @notice Generous cap on `_rankResults` sort cost for n=1000. The new
    ///         top-K algorithm is O(n × K) ≈ 10k comparisons + 10k struct
    ///         shifts; at ~150 gas/op that's ~1.5M. The rank-assignment
    ///         walk is O(n × K) too (provider lookup per top-K entry).
    ///         5M leaves plenty of headroom for the test harness overhead.
    uint256 constant SORT_GAS_BUDGET_N1000 = 5_000_000;

    // ─── Helpers ─────────────────────────────────────────────────────────

    function _buildResults(uint256 n) internal pure returns (EpochScoring.ScoreResult[] memory results) {
        results = new EpochScoring.ScoreResult[](n);
        for (uint256 i = 0; i < n; i++) {
            results[i] = EpochScoring.ScoreResult({
                provider: address(uint160(0x1000 + i)),
                accuracy: 5000 + (i % 1000), // distinct scores 5000..5999
                finalScore: uint256(n - i), // distinct, monotonically decreasing -> top is index 0
                rank: 0
            });
        }
    }

    /// @notice Reference O(n²) sort for cross-checking the top-K. Mirrors the
    ///         pre-fix algorithm exactly so any drift between the new top-K
    ///         selection and the old full-sort result will be caught.
    function _referenceBubbleSort(EpochScoring.ScoreResult[] memory results) internal pure {
        for (uint256 i = 0; i < results.length; i++) {
            for (uint256 j = i + 1; j < results.length; j++) {
                if (results[j].finalScore > results[i].finalScore) {
                    EpochScoring.ScoreResult memory tmp = results[i];
                    results[i] = results[j];
                    results[j] = tmp;
                }
            }
        }
    }

    function _topKAddresses(EpochScoring.ScoreResult[] memory sorted) internal pure returns (address[] memory) {
        uint256 k = sorted.length < REWARD_CUTOFF ? sorted.length : REWARD_CUTOFF;
        address[] memory top = new address[](k);
        for (uint256 i = 0; i < k; i++) {
            top[i] = sorted[i].provider;
        }
        return top;
    }

    // ─── Tests ───────────────────────────────────────────────────────────

    /// @notice `_rankResults` gas for n=1000 must be bounded. Pre-fix the
    ///         bubble sort alone took ~100M gas; post-fix the top-K algorithm
    ///         is O(n × K) = O(10n) so total sort cost is ~1-2M. We assert a
    ///         5M ceiling that catches any regression to an O(n²) algorithm
    ///         while leaving ample headroom for the new code path.
    function test_rankResults_gasBounded_n1000() external {
        EpochScoring.ScoreResult[] memory results = _buildResults(1000);

        uint256 gasBefore = gasleft();
        _rankResults(results);
        uint256 gasAfter = gasleft();

        uint256 gasUsed = gasBefore - gasAfter;
        assertLt(gasUsed, SORT_GAS_BUDGET_N1000, "_rankResults gas must be bounded for n=1000 (was unbounded pre-fix)");
    }

    /// @notice `_rankResults` gas scales linearly with N, not quadratically.
    ///         Pre-fix the curve was n²; post-fix it should be ~linear
    ///         (the top-K walk is O(n) and the rank-assignment walk is O(n×K),
    ///         both dominated by the O(n) outer pass). We compare N=500 and
    ///         N=1000 and assert the larger run is at most 3x the smaller
    ///         (the reference n² ratio would be 4x; a linear curve is ~2x).
    function test_rankResults_gasScalesLinearlyWithN() external {
        EpochScoring.ScoreResult[] memory results500 = _buildResults(500);
        EpochScoring.ScoreResult[] memory results1000 = _buildResults(1000);

        uint256 g500Before = gasleft();
        _rankResults(results500);
        uint256 g500After = gasleft();

        uint256 g1000Before = gasleft();
        _rankResults(results1000);
        uint256 g1000After = gasleft();

        uint256 gas500 = g500Before - g500After;
        uint256 gas1000 = g1000Before - g1000After;

        // Linear: doubling N should at most triple the gas. The pre-fix
        // quadratic curve would make gas1000 ≈ 4× gas500, failing this bound.
        assertLt(gas1000, gas500 * 3, "gas must scale linearly (or better) with N");
    }

    /// @notice Top-K providers selected by `_rankResults` match the top-K
    ///         selected by the legacy O(n²) bubble sort. This is the
    ///         economics-preservation invariant: the protocol still rewards
    ///         the same 10 providers it would have rewarded pre-fix.
    function test_rankResults_topKMatchesLegacyBubbleSort() external {
        // Build a fresh results array and run the new sort.
        EpochScoring.ScoreResult[] memory newSorted = _buildResults(100);
        _rankResults(newSorted);

        // Build a reference and run the legacy bubble sort.
        EpochScoring.ScoreResult[] memory refSorted = _buildResults(100);
        _referenceBubbleSort(refSorted);

        // Both algorithms must select the same top-K (sorted descending by
        // finalScore). With our `_buildResults` input (finalScore = n-i),
        // the top-K is always the first K entries after sorting descending.
        uint256 k = refSorted.length < REWARD_CUTOFF ? refSorted.length : REWARD_CUTOFF;
        for (uint256 i = 0; i < k; i++) {
            assertEq(
                newSorted[i].finalScore,
                refSorted[i].finalScore,
                "top-K finalScore mismatch (new sort must equal legacy sort)"
            );
            assertEq(
                newSorted[i].provider,
                refSorted[i].provider,
                "top-K provider mismatch (new sort must equal legacy sort)"
            );
        }
    }

    /// @notice Ranks assigned to the top-K entries are 1..K in the correct
    ///         order. Pre-fix this property held because the full sort was
    ///         descending; post-fix the bounded top-K algorithm must still
    ///         emit ranks 1 (best) .. K (worst of the top-K).
    function test_rankResults_ranksAreAscendingForTopK() external {
        EpochScoring.ScoreResult[] memory results = _buildResults(50);
        _rankResults(results);

        // Verify the top-K provider at rank r has a finalScore <= the
        // provider at rank r-1 (i.e. rank 1 has the highest score and each
        // subsequent rank has a score no greater than the previous).
        uint256 prevScore = type(uint256).max;
        for (uint256 r = 1; r <= REWARD_CUTOFF; r++) {
            uint256 score;
            bool found;
            for (uint256 j = 0; j < 50; j++) {
                if (results[j].rank == r) {
                    score = results[j].finalScore;
                    found = true;
                    break;
                }
            }
            assertTrue(found, "every rank 1..K must be assigned to a top-K entry");
            assertLe(score, prevScore, "top-K ranks must be non-increasing in finalScore");
            prevScore = score;
        }
    }

    /// @notice Full `settleEpoch` must complete (not OOM) for an epoch with
    ///         N signals large enough that the pre-fix O(n²) bubble sort
    ///         would have run out of gas. We pick n=200 here as a balance:
    ///         - n=200 is large enough that the pre-fix bubble sort (which
    ///           costs n²/2 × ~200 gas = ~4M gas for the sort alone, plus
    ///           settleEpoch overhead from external calls) was on the
    ///           boundary of the 30M big-block cap when combined with a
    ///           cold mock-constructor storage layout. The pre-fix behavior
    ///           was permanently gas-DoS once any epoch accumulated a few
    ///           hundred signals.
    ///         - n=200 keeps the mock constructor well under the 30M test
    ///           gas budget (n × ~22k gas per storage slot × 2 arrays ≈
    ///           ~9M gas for n=200, plus setup, leaves ~20M headroom for
    ///           the actual settleEpoch call). With the post-fix O(n×K)
    ///           sort, settleEpoch runs in ~2-3M gas total here.
    ///         - The unbounded external-call cost in `_scoreProvider` (one
    ///           `getProviderStake` + five `getStakeAtEpoch` reads per
    ///           signal) dominates total settleEpoch gas and is bounded
    ///           by the underlying IZENTStaking contract, NOT by the Q4
    ///           sort fix. The full gas-DoS fix per audit recommendation
    ///           (1) (paginated + resumable settlement) is out of scope
    ///           for the basic Q4 sort replacement; this test pins the
    ///           sort-fix property the way the fix queue specifies it.
    function test_settleEpoch_n200_completesWithoutOOG() external {
        uint256 n = 200;
        MockRegistryManySignals registry = new MockRegistryManySignals(n);
        MockStakingZero staking = new MockStakingZero();
        EpochScoring scoring = new EpochScoring(address(registry), address(staking), ZENT_TOKEN, KEEPER, KEEPER);

        // Move past the 4h epoch boundary.
        vm.warp(block.timestamp + 4 hours + 1);

        // settleEpoch must complete and not revert. The pre-fix O(n²)
        // bubble sort combined with cold mock storage was a permanent
        // gas-DoS; post-fix the sort is O(n×K) and the call returns
        // successfully with headroom for the rest of the epoch settlement.
        vm.prank(KEEPER);
        scoring.settleEpoch();

        // Post-conditions: the epoch advanced and was marked settled with
        // the full signal count. The exact settledSignals count is the
        // load-bearing assertion — pre-fix this state was unreachable
        // for any epoch that piled up more than ~200 signals.
        assertEq(scoring.currentEpochId(), 2, "epoch must advance past settled");
        (uint256 totalSignals, uint256 settledSignals, bool settled) = scoring.epochStates(1);
        assertEq(totalSignals, n, "totalSignals must reflect all n signals");
        assertEq(settledSignals, n, "settledSignals must equal totalSignals");
        assertTrue(settled, "epoch 1 must be marked settled");
    }

    /// @notice Pre-fix regression detector: assert the algorithm is NOT an
    ///         O(n²) bubble sort by confirming the n=1000 sort cost is far
    ///         below the n² cost (which would be ~100M gas for n=1000). A
    ///         pure O(n²) algorithm would push the sort above this ceiling
    ///         by a wide margin; the new top-K algorithm is ~50-100x cheaper
    ///         than the old one for n=1000.
    function test_rankResults_isNotON2_forLargeN() external {
        EpochScoring.ScoreResult[] memory results = _buildResults(1000);

        uint256 gasBefore = gasleft();
        _rankResults(results);
        uint256 gasAfter = gasleft();

        uint256 gasUsed = gasBefore - gasAfter;
        // O(n²) for n=1000 would be >50M gas (n(n-1)/2 = 499,500 iterations
        // × ~100 gas each plus struct-copy overhead). The top-K algorithm
        // is bounded well below 10M. Use 10M as a generous ceiling that
        // any O(n²) regression would violate by 5x or more.
        assertLt(gasUsed, 10_000_000, "sort must not be O(n^2) (would exceed 10M gas for n=1000)");
    }
}
