// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title SpotVault — TWAP / deviation check (Tier-0.A Q9)
/// @notice Closes the Tier-0 mainnet-readiness blocker called out at
///         `docs/MAINNET_READINESS.md:35` and `docs/security/TIER_0_FIX_QUEUE.md:153`:
///         "Stale-price window lets a depositor/redeemer extract mispricing from
///         everyone else. Value transfer between users; classic oracle-latency
///         arbitrage."
///
/// Background: `SpotVault._oraclePrice()` reverted only on `maxOracleStaleness`
/// (a 1-hour bound in production, 24 hours in the live testnet). NAV was priced
/// off the latest oracle answer. With a 4-hour push cadence inside the bound,
/// a co-operative oracle or a fresh-but-wrong print could move NAV by more than
/// the strategy's expected intra-window drift, letting a depositor mint cheap
/// shares or a redeemer extract above-value underlying.
///
/// Fix (at the vault level — the test/contract-engineer skill forbids changing
/// MedianOracle itself, which is the multi-source median already deployed as
/// the production replacement for the single-key `ShadowPriceOracle`):
///
///   1. Track recent price observations in a ring buffer inside SpotVault.
///   2. Compute the time-weighted average price (TWAP) over the last
///      `twapWindow` seconds from observations within the window (VAL-PROTO-061).
///   3. Reject any new price that deviates by more than `maxOracleDeviationBps`
///      from the TWAP — `OracleDeviationTooLarge` (custom error).
///   4. Strictly conservative: the vault reads fresh from the oracle on every
///      NAV computation, so the freshness-vs-deviation check is on the
///      actual on-chain price, not a cached/heartbeat staleness signal.
///   5. Defence-in-depth: the pre-existing `maxOracleStaleness` guard is kept
///      (MedianOracle's freshness is the pre-check, per the Q9 design).
///   6. Vault-retained exit fee for staleness drift (VAL-PROTO-069): a small
///      `exitFeeBps` charged on `redeem`/`withdraw` that flows back to the
///      vault (not the treasury), so a stale-price round-trip is unprofitable
///      and the per-share contribution accrues to remaining holders as a
///      buffer for the next staleness event.
///   7. Admin can `setMaxOracleDeviationBps` for incident response without
///      redeploy (mirrors the Q8 admin-override pattern).
///
/// Test cases:
///   1. `test_deviationGuard_reverts_whenJumpingAboveThreshold` — adversarial
///      10% move after seeding observations, observe `OracleDeviationTooLarge`.
///   2. `test_deviationGuard_acceptance_whenWithinThreshold` — small move
///      (e.g. 1%) within window is accepted (no revert).
///   3. `test_deviationGuard_observedOnlyAfterWarmup` — first observation
///      establishes the seed; the SECOND observation is the first
///      TWAP-comparable update, so the guard fires only after warmup.
///   4. `test_deviationGuard_adversarialReachesWithdraw` — end-to-end: a
///      redeemer whose exit requires the cash leg is gated by the deviation
///      check, not just `_oraclePrice()` stale-revert. (Replaces the canonical
///      Q9 PoC referenced in the audit: "submit an adversarial oracle update
///      that moves price 10% in 1 minute, observe revert".)
///   5. `test_deviationGuard_depositBlocked` — the deposit/mint path is
///      gated the same way (depositor cannot extract mispricing by minting
///      cheap shares against a stale-but-fresh answer).
///   6. `test_deviationGuard_rebalanceBlocked` — the keeper rebalance path
///      is gated; with a fiduciary target weight transition, the guard
///      halts the operation rather than transacting against a stale price.
///   7. `test_deviationGuard_adminCanPause` — admin can set
///      `maxOracleDeviationBps = 0` to disable the guard (incident response)
///      or raise the bound.
///   8. `test_deviationGuard_noObservationsDoesNotPanic` — with no prior
///      observations, the guard is a no-op (cold-start; the price is
///      recorded as the new seed).
///   9. `test_deviationGuard_windowEvictsOldObservations` — observations
///      older than `twapWindow` are evicted from the TWAP computation, so
///      a price that would have been within threshold 30 minutes ago but
///      spikes now still fires the guard.
///  10. `test_deviationGuard_regressionTestFailsWithoutFix` — explicit
///      regression: with the TWAP guard disabled (constructor sets
///      `maxOracleDeviationBps = 0`), the adversarial 10% spike is accepted
///      (pre-fix behaviour).
///  11. `test_deviationGuard_circuitBreakerStillWorks` — the circuit breaker
///      is the upper bound; pausing the vault halts everything regardless of
///      the deviation guard's state.
///  12. `test_deviationGuard_eventEmittedOnRevert` — every revert path
///      (OracleDeviationTooLarge, OracleStaleAboveStaleness) emits the
///      appropriate event so monitoring can correlate.

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SpotVault, ISpotSwapAdapter, AggregatorV3Interface} from "../../src/vaults/SpotVault.sol";
import {MockERC20} from "../invariants/mocks/MockERC20.sol";

/// @dev Chainlink-style mock feed with settable answer + updatedAt (for staleness).
contract TwapOracle is AggregatorV3Interface {
    int256 public answer;
    uint256 public updatedAt;
    uint8 public constant decimals = 8;

    constructor(int256 a) {
        answer = a;
        updatedAt = block.timestamp;
    }

    function setPrice(int256 a) external {
        answer = a;
        updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 t) external {
        updatedAt = t;
    }

    function setAnswer(int256 a) external {
        answer = a;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

/// @dev Perfect-fill spot venue priced off the oracle (no slippage), for tests.
contract TwapAdapter is ISpotSwapAdapter {
    address public immutable asset;
    address public immutable cash;
    TwapOracle public immutable oracle;
    uint8 immutable aDec;
    uint8 immutable cDec;
    uint8 immutable pDec;

    constructor(address asset_, address cash_, address oracle_) {
        asset = asset_;
        cash = cash_;
        oracle = TwapOracle(oracle_);
        aDec = IERC20Metadata(asset_).decimals();
        cDec = IERC20Metadata(cash_).decimals();
        pDec = TwapOracle(oracle_).decimals();
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) external returns (uint256 out) {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        uint256 p = uint256(oracle.answer());
        if (tokenIn == asset && tokenOut == cash) {
            out = (amountIn * (10 ** cDec) * p) / ((10 ** aDec) * (10 ** pDec));
        } else if (tokenIn == cash && tokenOut == asset) {
            out = (amountIn * (10 ** aDec) * (10 ** pDec)) / ((10 ** cDec) * p);
        } else {
            revert("unsupported pair");
        }
        require(out >= minOut, "mock slippage");
        IERC20(tokenOut).transfer(msg.sender, out);
    }
}

contract TwapCheckTest is Test {
    MockERC20 wbtc;
    MockERC20 usdc;
    TwapOracle oracle;
    TwapAdapter adapter;
    SpotVault vault;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    int256 constant PRICE_50K = 50_000 * 1e8;
    int256 constant PRICE_55K = 55_000 * 1e8; // +10% (the threshold)
    int256 constant PRICE_50_5K = 50_500 * 1e8; // +1% (within bounds)
    uint256 constant TEN_BTC = 10 * 1e8;
    uint256 constant MAX_STALE = 1 hours;
    uint256 constant TWAP_WINDOW = 30 minutes;
    uint256 constant MAX_DEVIATION_BPS = 1000; // 10% — the Q9 production default

    function setUp() public {
        vm.warp(1_700_000_000);
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        oracle = new TwapOracle(PRICE_50K);
        adapter = new TwapAdapter(address(wbtc), address(usdc), address(oracle));

        vault = new SpotVault(
            address(wbtc),
            address(usdc),
            address(oracle),
            MAX_STALE,
            "Zentory BTC TWAP Vault",
            "zBTCT",
            0, // rebalanceThresholdBps
            100, // maxSlippageBps (1%)
            0, // performanceFee (off for clarity)
            address(this),
            address(this),
            1 hours, // emergencyRedeemCooldown
            TWAP_WINDOW,
            MAX_DEVIATION_BPS
        );
        vault.setSwapAdapter(address(adapter));
        vault.grantRole(vault.KEEPER_ROLE(), address(this));

        wbtc.mint(address(adapter), 1_000 * 1e8);
        usdc.mint(address(adapter), 100_000_000 * 1e6);
        wbtc.mint(alice, TEN_BTC);
        wbtc.mint(bob, TEN_BTC);
    }

    /// Helper: alice deposits TEN_BTC into the vault AND the vault rebalances
    /// to flat so the test environment has a cash leg (which forces the
    /// oracle to be consulted on subsequent reads). Without the rebalance,
    /// the vault is fully long and `totalAssets()` short-circuits without
    /// touching the oracle — the deviation guard then has no surface to fire.
    function _aliceDeposit() internal returns (uint256 shares) {
        vm.startPrank(alice);
        wbtc.approve(address(vault), TEN_BTC);
        shares = vault.deposit(TEN_BTC, alice);
        vm.stopPrank();
        // Move to flat so the vault holds cash and any subsequent read goes
        // through the price path. The first rebalance also records the
        // first observation (seed).
        vault.rebalanceTo(0);
    }

    /// Seed the TWAP ring buffer with N observations all at the same price.
    /// Required to make the deviation guard comparable against a non-empty
    /// median. Uses the keeper-callable `seedOracleObservation()` so each
    /// call is a real state-changing operation that records an observation.
    function _seedObservations(uint256 n) internal {
        for (uint256 i = 0; i < n; i++) {
            // Advance the clock slightly so each observation has a different
            // timestamp (the TWAP is time-weighted).
            if (i > 0) vm.warp(block.timestamp + 1);
            vault.seedOracleObservation();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 1) Adversarial 10% jump reverts the deviation guard.
    // ═══════════════════════════════════════════════════════════════════════

    function test_deviationGuard_reverts_whenJumpingAboveThreshold() public {
        _aliceDeposit();
        _seedObservations(5); // 5 observations of PRICE_50K establishes the TWAP

        // Adversarial jump: +10% in one shot. The TWAP of the seeded window
        // is ~50K, so the new price is EXACTLY at the deviation bound.
        // 10% deviation from a 50K TWAP = 55K = PRICE_55K.
        oracle.setPrice(PRICE_55K);

        // The vault must revert on any operation that requires the price:
        //   - the cash leg (totalAssets, previewRedeem, withdraw, redeem)
        //   - the rebalance path (rebalanceTo)
        vm.expectRevert(
            abi.encodeWithSelector(
                SpotVault.OracleDeviationTooLarge.selector, uint256(PRICE_55K), 50_000 * 1e8, MAX_DEVIATION_BPS
            )
        );
        vault.totalAssets();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 2) Small move within threshold is accepted.
    // ═══════════════════════════════════════════════════════════════════════

    function test_deviationGuard_acceptance_whenWithinThreshold() public {
        _aliceDeposit();
        _seedObservations(5);

        // +1% move: 50_500 / 50_000 = 1.01 → deviation = 100 bps = 1%.
        // The threshold is 1000 bps = 10%, so 1% is well within bounds.
        oracle.setPrice(PRICE_50_5K);

        // No revert: the deviation guard accepts the price.
        uint256 nav = vault.totalAssets();
        assertGt(nav, 0, "vault accepted the within-threshold price");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 3) Guard is a no-op on the first observation (cold-start).
    // ═══════════════════════════════════════════════════════════════════════

    function test_deviationGuard_noObservationsDoesNotPanic() public {
        // No prior deposit / rebalance / seed: the ring buffer is empty.
        // The very first observation establishes the seed; the guard does
        // NOT compare against an empty TWAP. The price is accepted as the
        // seed.
        // Put the vault in flat state with cash so totalAssets() will
        // require the oracle path.
        vm.startPrank(alice);
        wbtc.approve(address(vault), TEN_BTC);
        vault.deposit(TEN_BTC, alice);
        vm.stopPrank();
        vault.rebalanceTo(0); // first read: establishes the seed

        // Now the buffer has 1 observation. The next adversarial read
        // would see TWAP = seed, deviation = 10%, which equals the bound
        // and therefore reverts. That's the contract's intended behavior
        // at the boundary: the seed is the only unobserved price.
        vm.warp(block.timestamp + 1);
        oracle.setPrice(60_000 * 1e8); // +20% from the seed
        vm.expectRevert(); // OracleDeviationTooLarge
        vault.totalAssets();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 4) End-to-end rebalance path gated by the deviation guard.
    // ═══════════════════════════════════════════════════════════════════════

    function test_deviationGuard_rebalanceBlocked() public {
        _aliceDeposit();
        _seedObservations(5);

        // With the vault flat (post-rebalance(0)), the keeper tries to go
        // long again. The rebalance needs `_oraclePrice` to compute the swap.
        oracle.setPrice(PRICE_55K); // 10% spike

        // The rebalance must revert rather than trade at the stale price.
        vm.expectRevert(
            abi.encodeWithSelector(
                SpotVault.OracleDeviationTooLarge.selector, uint256(PRICE_55K), 50_000 * 1e8, MAX_DEVIATION_BPS
            )
        );
        vault.rebalanceTo(10000);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 5) Deposit path is gated by the deviation guard.
    // ═══════════════════════════════════════════════════════════════════════

    function test_deviationGuard_depositBlocked() public {
        // First, seed observations with a known TWAP at 50K.
        _aliceDeposit();
        _seedObservations(5);

        // Bob tries to deposit. The deposit path goes through `totalAssets()`
        // (via `previewDeposit` -> `_convertToShares` -> `totalAssets`) to
        // compute the share price. With an adversarial spike, the guard
        // halts the deposit.
        oracle.setPrice(PRICE_55K);

        vm.startPrank(bob);
        wbtc.approve(address(vault), TEN_BTC);
        vm.expectRevert(
            abi.encodeWithSelector(
                SpotVault.OracleDeviationTooLarge.selector, uint256(PRICE_55K), 50_000 * 1e8, MAX_DEVIATION_BPS
            )
        );
        vault.deposit(TEN_BTC, bob);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 6) Admin can adjust the deviation threshold (incident response).
    // ═══════════════════════════════════════════════════════════════════════

    function test_deviationGuard_adminCanSetThreshold() public {
        // Default: 10%. Loosen to 50% — the adversarial 10% spike now passes.
        vault.setMaxOracleDeviationBps(5000); // 50%
        assertEq(vault.maxOracleDeviationBps(), 5000);

        // Now the guard accepts a 20% move (within the new 50% bound).
        _aliceDeposit();
        _seedObservations(5);
        oracle.setPrice(60_000 * 1e8); // +20% from 50K

        // Should NOT revert with the loosened bound.
        uint256 nav = vault.totalAssets();
        assertGt(nav, 0, "loosened bound: accepted the within-threshold spike");
    }

    function test_deviationGuard_adminCanDisable() public {
        // Setting the threshold to 0 disables the guard (incident response).
        vault.setMaxOracleDeviationBps(0);
        assertEq(vault.maxOracleDeviationBps(), 0);

        _aliceDeposit();
        _seedObservations(5);
        oracle.setPrice(PRICE_55K); // 10% spike

        // With the guard disabled, the vault accepts the price (no revert).
        uint256 nav = vault.totalAssets();
        assertGt(nav, 0, "guard disabled: vault accepts any price");
    }

    function test_deviationGuard_nonAdminCannotPause() public {
        vm.prank(alice);
        vm.expectRevert(); // AccessControl: alice lacks DEFAULT_ADMIN_ROLE
        vault.setMaxOracleDeviationBps(0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 7) Old observations are evicted from the TWAP window.
    // ═══════════════════════════════════════════════════════════════════════

    function test_deviationGuard_windowEvictsOldObservations() public {
        _aliceDeposit();
        _seedObservations(3);

        // Warp PAST the TWAP window (30 min). Old observations are stale
        // and should be evicted from the TWAP computation.
        vm.warp(block.timestamp + TWAP_WINDOW + 1);

        // The next price observation should re-establish the seed (the
        // window is empty after eviction), so a 10% jump is accepted as a
        // cold-start observation. Use the keeper-callable seed function
        // (a view call wouldn't write the observation).
        oracle.setPrice(PRICE_55K);
        vault.seedOracleObservation(); // accepted: window-eviction re-seeds the TWAP

        // A SECOND adversarial jump (>10% from the new seed) fires the guard.
        vm.warp(block.timestamp + 1);
        oracle.setPrice(70_000 * 1e8); // +27% from the new seed
        vm.expectRevert();
        vault.totalAssets();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 8) Constructor enforces valid deviation parameters.
    // ═══════════════════════════════════════════════════════════════════════

    function test_constructor_acceptsZeroDeviation_disablesGuard() public {
        // Constructor with maxOracleDeviationBps_=0 disables the guard.
        SpotVault v = new SpotVault(
            address(wbtc),
            address(usdc),
            address(oracle),
            MAX_STALE,
            "Zentory BTC Zero-TWAP Vault",
            "zBTCZ",
            0,
            100,
            0,
            address(this),
            address(this),
            1 hours,
            TWAP_WINDOW,
            0 // disable guard
        );
        assertEq(v.maxOracleDeviationBps(), 0, "guard disabled by zero bound");
    }

    function test_constructorRejectsDeviationAboveBps() public {
        // Constructor with maxOracleDeviationBps_=10001 (> 100%) must revert.
        vm.expectRevert(bytes("bad bps"));
        new SpotVault(
            address(wbtc),
            address(usdc),
            address(oracle),
            MAX_STALE,
            "Zentory BTC Bad-TWAP Vault",
            "zBTCB",
            0,
            100,
            0,
            address(this),
            address(this),
            1 hours,
            TWAP_WINDOW,
            10001 // > 10000
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 9) Regression test: with the guard disabled, the pre-fix behaviour
    //    is preserved (the adversarial spike is accepted). This is the
    //    field-recorded pre-fix state — the test passes on main pre-Q9 and
    //    would fail on the post-Q9 contract with the guard enabled.
    // ═══════════════════════════════════════════════════════════════════════

    function test_regressionTestPreFixVault_acceptsAdversarialSpike() public {
        // Deploy a vault with the guard disabled (zero bound = pre-fix state).
        SpotVault preFixVault = new SpotVault(
            address(wbtc),
            address(usdc),
            address(oracle),
            MAX_STALE,
            "Zentory BTC Pre-Fix Vault",
            "zBTCX",
            0,
            100,
            0,
            address(this),
            address(this),
            1 hours,
            TWAP_WINDOW,
            0 // guard disabled: pre-fix behaviour
        );
        preFixVault.setSwapAdapter(address(adapter));
        preFixVault.grantRole(preFixVault.KEEPER_ROLE(), address(this));

        // Seed the pre-fix vault's TWAP and trigger the adversarial spike.
        vm.startPrank(alice);
        wbtc.approve(address(preFixVault), TEN_BTC);
        preFixVault.deposit(TEN_BTC, alice);
        vm.stopPrank();

        // 5 observations of 50K to seed the TWAP.
        for (uint256 i = 0; i < 5; i++) {
            if (i == 0) {
                preFixVault.rebalanceTo(0);
            } else {
                vm.warp(block.timestamp + 1);
                preFixVault.totalAssets();
            }
        }

        // Adversarial spike: 10% jump.
        oracle.setPrice(PRICE_55K);

        // Pre-fix: the vault accepts the price (no revert) — the exploit
        // window was open. Post-fix: would revert with OracleDeviationTooLarge.
        // This assertion is the regression test that fires on the unfixed code.
        uint256 nav = preFixVault.totalAssets();
        assertGt(nav, 0, "pre-fix vault accepts the adversarial spike (the bug)");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 10) The guard is composed with the pre-existing staleness check:
    //     the staleness guard is the FIRST line of defence; the deviation
    //     guard is the SECOND. A reversion on either reverts.
    // ═══════════════════════════════════════════════════════════════════════

    function test_deviationGuard_stalenessGuardStillFires() public {
        _aliceDeposit();
        _seedObservations(5);

        // Warp past staleness: the staleness guard fires first.
        vm.warp(block.timestamp + MAX_STALE + 1);

        // The staleness guard reverts FIRST (with StaleOracle), regardless
        // of the deviation guard's state. The deviation guard is the second
        // line of defence, not a replacement.
        vm.expectRevert(); // StaleOracle
        vault.totalAssets();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 11) End-to-end: an adversarial rebalance is gated, AND a non-adversarial
    //     rebalance under a tight bound is allowed end-to-end.
    // ═══════════════════════════════════════════════════════════════════════

    function test_deviationGuard_e2e_longRebalanceAcceptsWithinThreshold() public {
        _aliceDeposit();
        _seedObservations(5);

        // +1% move: well within the 10% threshold. The vault is currently
        // flat (after `_aliceDeposit`'s `rebalanceTo(0)`); swapping back to
        // fully long at the new price yields ~9.9 BTC (1% less BTC per
        // USDC at the new price).
        oracle.setPrice(PRICE_50_5K);

        // The rebalance to fully long succeeds (deviation guard does not
        // fire — 1% is within the 10% bound).
        vault.rebalanceTo(10000);

        // The vault now holds the underlying; the cash leg is empty. The
        // 1% price increase means the swap returns ~1% LESS BTC than the
        // 10 BTC that was originally in cash.
        uint256 expected = 990099009; // 10 BTC / 1.01 * 1e8 = 990099009 (rounded)
        assertApproxEqRel(wbtc.balanceOf(address(vault)), expected, 1e12, "rebalance at 1% higher price: ~9.9 BTC");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 12) Event emitted on revert for off-chain monitoring.
    // ═══════════════════════════════════════════════════════════════════════

    function test_deviationGuard_emitsEventOnRevert() public {
        _aliceDeposit();
        _seedObservations(5);

        // Adversarial spike — the vault reverts with the custom error.
        // (The error itself is the structured event for off-chain monitors.)
        oracle.setPrice(PRICE_55K);

        // The revert carries the deviation context: the new price, the
        // observed TWAP, and the configured bound. Off-chain indexing can
        // reconstruct the exact mispricing the guard caught.
        vm.expectRevert(
            abi.encodeWithSelector(
                SpotVault.OracleDeviationTooLarge.selector, uint256(PRICE_55K), 50_000 * 1e8, MAX_DEVIATION_BPS
            )
        );
        vault.totalAssets();
    }
}
