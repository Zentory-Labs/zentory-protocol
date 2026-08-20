// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm}    from "forge-std/Vm.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {EpochScoring}        from "../../src/signals/EpochScoring.sol";
import {SignalTypes}         from "../../src/signals/SignalTypes.sol";

/// @dev Minimal mintable ERC20 used as the ZENT token in this suite.
contract MockZENT is ERC20 {
    constructor() ERC20("MockZENT", "mZENT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev ISignalRegistry mock that returns a fixed list of (provider, return)
///      pairs for the active epoch. The list size is settable per-test.
contract MultiProviderMockRegistry {
    address[] internal _providers;
    int256[]  internal _returns;

    constructor(address[] memory providers_, int256[] memory returns_) {
        _providers = providers_;
        _returns   = returns_;
    }

    function getEpochSignalCount(uint256) external view returns (uint256) { return _providers.length; }
    function getEpochSignalProvider(uint256, uint256 i) external view returns (address) { return _providers[i]; }
    function getEpochSignalReturn(uint256, uint256 i)   external view returns (int256) { return _returns[i]; }

    function getSignal(bytes32) external pure returns (SignalTypes.Signal memory s) { return s; }
    function getSignalCount() external pure returns (uint256) { return 0; }
    function advanceEpoch() external {}
    function stakingContract() external pure returns (address) { return address(0); }
    function getProviderCount() external pure returns (uint256) { return 0; }
    function getProviderAt(uint256) external pure returns (address) { return address(0); }
    function getSignalProvider(uint256) external pure returns (address) { return address(0); }
    function getSignalReturn(address, uint256) external pure returns (int256) { return 0; }
    function signalExists(bytes32) external pure returns (bool) { return false; }
    function providerNonce(address) external pure returns (uint256) { return 0; }
    function resolveSignals(bytes32[] calldata, uint256[] calldata) external {}
    function submitSignal(
        address, SignalTypes.AssetClass, bytes32, int256, uint256, uint256, bytes calldata
    ) external pure returns (bytes32) { return bytes32(0); }
    function submitSignalBatch(SignalTypes.Signal[] calldata)
        external pure returns (bytes32[] memory ids) { return ids; }
}

/// @dev IZENTStaking mock whose `reward()` reverts ONLY for a configured
///      "broken" provider and succeeds for everyone else. Mirrors the real
///      failure mode: ZENTStaking.reward() requires pos.amount > 0 for the
///      recipient, so a provider that un-staked between signal submit and
///      settle triggers a revert. All other view fns return a positive stake
///      so providers survive the recency-bonus / stake-weight calculations.
contract SelectiveRevertingStaking {
    address public brokenProvider;
    uint256 public constant FAKE_STAKE = 1_000e18;

    constructor(address brokenProvider_) {
        brokenProvider = brokenProvider_;
    }

    function setBrokenProvider(address p) external { brokenProvider = p; }

    function getProviderStake(address) external pure returns (uint256) { return FAKE_STAKE; }
    function getStakeAtEpoch(address, uint256) external pure returns (uint256) { return FAKE_STAKE; }

    function reward(address provider, uint256) external view {
        if (provider == brokenProvider) {
            // Revert with a fixed 4-byte sentinel. Using `revert("...")` would
            // ABI-encode as `Error(string)` and complicate the test's decoding
            // of the captured `reason` bytes.
            bytes memory reason = hex"deadbeef";
            assembly { revert(add(reason, 32), mload(reason)) }
        }
    }

    function slash(address, uint256) external view {}
    function stake(uint256, uint64) external pure returns (uint64) { return 0; }
    function increaseAmount(uint256) external view {}
    function extendLock(uint64) external pure returns (uint64) { return 0; }
    function withdraw() external view {}
    function veBalance(address) external pure returns (uint256) { return 0; }
    function hasAccess(address) external pure returns (bool) { return false; }
    function stakedBalance(address) external pure returns (uint256) { return 0; }
    function totalVeSupply() external pure returns (uint256) { return 0; }
    function setMinStake(uint256) external view {}
}

/// @notice Audit-finding Q5 (Tier 0 — 0.B.3) regression suite.
///
///         Pre-fix: `_distributeRewards` swallowed the revert on a single
///         provider's `zentStaking.reward()` and emitted no event, so a
///         provider that un-staked between signal submit and settle silently
///         forfeited their reward AND the keeper had no way to reconcile the
///         missed payout post-hoc.
///
///         Post-fix:
///           1. `RewardPayoutFailed(provider, epochId, amount, reason)` is
///              emitted on the catch.
///           2. The missed amount is recorded in
///              `failedPayouts[epochId][provider]` for later claim.
///           3. `claimFailedPayouts(epochId, provider)` transfers that amount
///              to the provider (one-shot, requires the contract to hold ZENT).
///           4. `fundRewardPool(amount)` (admin-only) pulls ZENT into the
///              contract so step 3 has liquidity.
contract RewardPayoutFailureTest is Test {
    EpochScoring                  scoring;
    MultiProviderMockRegistry     registry;
    SelectiveRevertingStaking     staking;
    MockZENT                      zent;

    // Re-declare events locally so `vm.expectEmit` can match them. Solidity
    // event declarations at the contract level aren't exposed as
    // `EpochScoring.EventName(...)` for emit syntax; matching by topic hash
    // would also work, but the typed emit gives better compile-time checks.
    event RewardPayoutFailed(address indexed provider, uint256 indexed epochId, uint256 amount, bytes reason);
    event FailedPayoutClaimed(uint256 indexed epochId, address indexed provider, uint256 amount);
    event RewardPoolFunded(address indexed from, uint256 amount);

    address constant ADMIN    = address(0xA11CE);
    address constant KEEPER   = address(0x22510); // scoringOracle + EPOCH_SETTLER
    address constant ALICE    = address(0xA11A);
    address constant BOB      = address(0xB0B);
    address constant CAROL    = address(0xCAFE);
    address constant ATTACKER = address(0xBAD);

    uint256 constant EPOCH_REWARD = 1_000e18;

    // Sentinel revert payload used by `SelectiveRevertingStaking.reward()`. We
    // use a fixed 4-byte sentinel rather than `revert("...")` so the captured
    // `bytes reason` in `RewardPayoutFailed` is exactly this value (Solidity's
    // `revert(string)` ABI-encodes as `Error(string)`, which would require an
    // extra decode step in the test).
    bytes constant REVERT_REASON_BYTES = hex"deadbeef";

    // event topics for log scanning
    bytes32 constant REWARD_PAYOUT_FAILED_SIG =
        keccak256("RewardPayoutFailed(address,uint256,uint256,bytes)");

    function setUp() public {
        address[] memory providers = new address[](3);
        providers[0] = ALICE;
        providers[1] = BOB;
        providers[2] = CAROL;
        int256[] memory rets = new int256[](3);
        rets[0] = 10000; // full-conviction long, ranks first
        rets[1] = 9000;  // 2nd
        rets[2] = 8000;  // 3rd
        registry = new MultiProviderMockRegistry(providers, rets);

        // BOB is the "broken" provider: reward() reverts for him.
        staking = new SelectiveRevertingStaking(BOB);

        // Deploy the real ZENT mock; give ADMIN a generous balance so the
        // admin can fund the reward pool during the test.
        zent = new MockZENT();
        zent.mint(ADMIN, 100_000e18);

        // ADMIN = deployer so DEFAULT_ADMIN_ROLE lands on ADMIN; KEEPER gets
        // EPOCH_SETTLER + scoringOracle.
        vm.prank(ADMIN);
        scoring = new EpochScoring(
            address(registry),
            address(staking),
            address(zent),
            KEEPER,
            KEEPER
        );

        // epochReward is admin-settable.
        vm.prank(ADMIN);
        scoring.setEpochReward(EPOCH_REWARD);
    }

    // ─── Core regression: failure path now emits + records ────────────────

    /// @notice Settling an epoch with a broken provider must NOT revert the
    ///         whole call (preserves the M-1 invariant), and the missed payout
    ///         must be visible via the new event + mapping.
    function test_settleEpoch_emitsRewardPayoutFailed_whenProviderHasNoStake() external {
        vm.warp(block.timestamp + 4 hours + 1);

        // REWARD_CUTOFF = 10; all 3 providers rank 1..3 so all 3 hit the
        // reward() path. BOB reverts; ALICE + CAROL succeed.
        // epochReward / results.length = 1000e18 / 3 = 333.333...e18; integer
        // division rounds DOWN to 333e18 per provider.
        uint256 rewardPerProvider = EPOCH_REWARD / 3;

        // settleEpoch emits multiple events (EpochStarted, SignalScored × N,
        // RewardPayoutFailed, EpochPayoutsApplied, EpochSettled). vm.expectEmit
        // matches the NEXT emitted log, so we use vm.recordLogs() and scan the
        // captured logs for our event of interest — same pattern as
        // EpochScoringSnapshotOrder.t.sol.
        vm.recordLogs();
        vm.prank(KEEPER);
        scoring.settleEpoch();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == REWARD_PAYOUT_FAILED_SIG) {
                // topics[1] = provider, topics[2] = epochId; data = (amount, reason).
                assertEq(address(uint160(uint256(logs[i].topics[1]))), BOB, "topic[1] provider");
                assertEq(uint256(logs[i].topics[2]), 1, "topic[2] epochId");
                (uint256 amt, bytes memory reason) = abi.decode(logs[i].data, (uint256, bytes));
                assertEq(amt, rewardPerProvider, "data amount");
                // `reason` is the raw revert payload from the staking mock's
                // assembly-revert; Solidity `revert("...")` would ABI-encode it
                // as Error(string), but the mock uses an inline assembly revert
                // with a fixed sentinel so we can assert on the bytes directly.
                assertEq(reason, REVERT_REASON_BYTES, "data reason matches the staking mock's revert payload");
                found = true;
                break;
            }
        }
        assertTrue(found, "RewardPayoutFailed must be emitted on revert");

        // And the failed-payout mapping must hold the recorded amount.
        assertEq(scoring.failedPayoutFor(1, BOB),   rewardPerProvider, "BOB's missed payout recorded");
        assertEq(scoring.failedPayoutFor(1, ALICE), 0,                  "ALICE succeeded -> nothing to claim");
        assertEq(scoring.failedPayoutFor(1, CAROL), 0,                  "CAROL succeeded -> nothing to claim");
    }

    /// @notice The full-epoch settle still settles (i.e. does not revert)
    ///         even though one of the three reward() calls reverts — this
    ///         pins the M-1 invariant that Q5 must NOT regress.
    function test_settleEpoch_stillCompletesDespiteOneRevertingProvider() external {
        vm.warp(block.timestamp + 4 hours + 1);

        vm.prank(KEEPER);
        uint256 totalRewards = scoring.settleEpoch();

        // 3 providers, EPOCH_REWARD / 3 paid out, 2 of 3 succeed.
        uint256 rewardPerProvider = EPOCH_REWARD / 3;
        assertEq(totalRewards, rewardPerProvider * 2, "totalRewards reflects only successful rewards");

        (uint256 totalSignals, uint256 settledSignals, bool settled) = scoring.epochStates(1);
        assertTrue(settled, "epoch 1 settles despite BOB reverting");
        assertEq(totalSignals, 3, "totalSignals counts all 3 signals");
        assertEq(settledSignals, 3, "settledSignals counts all 3 signals");
    }

    // ─── claimFailedPayouts ───────────────────────────────────────────────

    function test_claimFailedPayouts_transfersZentToProvider() external {
        vm.warp(block.timestamp + 4 hours + 1);
        vm.prank(KEEPER);
        scoring.settleEpoch();

        uint256 rewardPerProvider = EPOCH_REWARD / 3;
        assertEq(scoring.failedPayoutFor(1, BOB), rewardPerProvider, "precondition: BOB has a failed payout");

        // Admin funds the pool with exactly the recorded amount.
        vm.startPrank(ADMIN);
        zent.approve(address(scoring), rewardPerProvider);
        scoring.fundRewardPool(rewardPerProvider);
        vm.stopPrank();

        assertEq(zent.balanceOf(address(scoring)), rewardPerProvider, "pool funded");

        uint256 bobBalBefore = zent.balanceOf(BOB);

        vm.expectEmit(true, true, false, true, address(scoring));
        emit FailedPayoutClaimed(1, BOB, rewardPerProvider);

        scoring.claimFailedPayouts(1, BOB);

        assertEq(zent.balanceOf(BOB) - bobBalBefore, rewardPerProvider, "BOB received the missed payout");
        assertEq(zent.balanceOf(address(scoring)), 0, "pool drained by the claim");
        assertEq(scoring.failedPayoutFor(1, BOB), 0, "recorded amount zeroed (one-shot)");
    }

    /// @notice Second claim on the same (epochId, provider) reverts with the
    ///         typed `NothingToClaim` error.
    function test_claimFailedPayouts_isOneShot() external {
        vm.warp(block.timestamp + 4 hours + 1);
        vm.prank(KEEPER);
        scoring.settleEpoch();

        uint256 rewardPerProvider = EPOCH_REWARD / 3;

        vm.startPrank(ADMIN);
        zent.approve(address(scoring), rewardPerProvider);
        scoring.fundRewardPool(rewardPerProvider);
        vm.stopPrank();

        scoring.claimFailedPayouts(1, BOB); // first claim succeeds

        vm.expectRevert(abi.encodeWithSelector(
            EpochScoring.NothingToClaim.selector, uint256(1), BOB
        ));
        scoring.claimFailedPayouts(1, BOB);
    }

    /// @notice Claiming for a (epoch, provider) pair that has no recorded
    ///         missed payout reverts with `NothingToClaim`.
    function test_claimFailedPayouts_revertsNothingToClaim() external {
        vm.expectRevert(abi.encodeWithSelector(
            EpochScoring.NothingToClaim.selector, uint256(1), ALICE
        ));
        scoring.claimFailedPayouts(1, ALICE);
    }

    /// @notice If the pool has no ZENT the claim reverts with the typed
    ///         `InsufficientRewardPool` error rather than silently failing
    ///         or running out of gas. Distinguishes this failure mode from
    ///         `NothingToClaim` for the keeper bot.
    function test_claimFailedPayouts_revertsInsufficientRewardPool_whenUnfunded() external {
        vm.warp(block.timestamp + 4 hours + 1);
        vm.prank(KEEPER);
        scoring.settleEpoch();

        uint256 rewardPerProvider = EPOCH_REWARD / 3;
        assertEq(scoring.failedPayoutFor(1, BOB), rewardPerProvider, "precondition: BOB has a failed payout");
        assertEq(zent.balanceOf(address(scoring)), 0, "precondition: pool is empty");

        vm.expectRevert(abi.encodeWithSelector(
            EpochScoring.InsufficientRewardPool.selector, rewardPerProvider, uint256(0)
        ));
        scoring.claimFailedPayouts(1, BOB);
    }

    /// @notice claimFailedPayouts is permissionless — anyone (e.g. the keeper
    ///         bot, which holds no role on EpochScoring) may trigger it; the
    ///         funds still go to the recorded provider.
    function test_claimFailedPayouts_isPermissionless() external {
        vm.warp(block.timestamp + 4 hours + 1);
        vm.prank(KEEPER);
        scoring.settleEpoch();

        uint256 rewardPerProvider = EPOCH_REWARD / 3;

        vm.startPrank(ADMIN);
        zent.approve(address(scoring), rewardPerProvider);
        scoring.fundRewardPool(rewardPerProvider);
        vm.stopPrank();

        vm.prank(ATTACKER); // no special role
        scoring.claimFailedPayouts(1, BOB);

        assertEq(zent.balanceOf(BOB), rewardPerProvider, "provider still receives the funds");
        assertEq(zent.balanceOf(ATTACKER), 0, "caller receives nothing");
    }

    // ─── fundRewardPool access control + path ─────────────────────────────

    function test_fundRewardPool_onlyAdmin() external {
        uint256 amount = 100e18;
        vm.startPrank(ADMIN);
        zent.approve(address(scoring), amount);
        vm.stopPrank();

        // ATTACKER is not admin — revert expected (AccessControl revert;
        // selector varies across OZ versions so we just expect SOME revert).
        vm.prank(ATTACKER);
        vm.expectRevert();
        scoring.fundRewardPool(amount);

        // Keeper holds EPOCH_SETTLER but NOT DEFAULT_ADMIN_ROLE — also must
        // be rejected.
        vm.prank(KEEPER);
        vm.expectRevert();
        scoring.fundRewardPool(amount);

        // ADMIN succeeds and emits the event.
        vm.expectEmit(true, false, false, true, address(scoring));
        emit RewardPoolFunded(ADMIN, amount);

        vm.prank(ADMIN);
        scoring.fundRewardPool(amount);

        assertEq(zent.balanceOf(address(scoring)), amount, "pool credited");
    }

    /// @notice fundRewardPool requires the admin to have approved the
    ///         contract to spend their ZENT. Without the allowance, the
    ///         typed `InsufficientAllowance` error reverts.
    function test_fundRewardPool_revertsInsufficientAllowance() external {
        uint256 amount = 100e18;
        // No approval granted.

        vm.expectRevert(abi.encodeWithSelector(
            EpochScoring.InsufficientAllowance.selector, amount, uint256(0)
        ));
        vm.prank(ADMIN);
        scoring.fundRewardPool(amount);
    }

    /// @notice Happy-path: admin approves > amount, fundRewardPool pulls
    ///         exactly `amount` into the contract.
    function test_fundRewardPool_happyPath() external {
        uint256 amount = 250e18;

        vm.startPrank(ADMIN);
        zent.approve(address(scoring), amount * 2);
        uint256 adminBalBefore = zent.balanceOf(ADMIN);
        scoring.fundRewardPool(amount);
        vm.stopPrank();

        assertEq(zent.balanceOf(ADMIN), adminBalBefore - amount, "admin debited");
        assertEq(zent.balanceOf(address(scoring)), amount, "contract credited");
    }

    /// @notice `amount == 0` is a no-op — useful for keeper retries without
    ///         re-approving.
    function test_fundRewardPool_zeroIsNoop() external {
        vm.prank(ADMIN);
        scoring.fundRewardPool(0);

        assertEq(zent.balanceOf(address(scoring)), 0, "no funds moved");
    }

    // ─── Happy-path preservation: no behavior change for non-broken epoch ──

    /// @notice When ALL providers succeed, no failedPayouts are recorded and
    ///         the epoch settles cleanly. Pins that Q5 did not regress the
    ///         happy path.
    function test_settleEpoch_noFailuresRecordsNothing() external {
        // Replace the staking mock with one where no provider reverts.
        staking.setBrokenProvider(address(0));

        vm.warp(block.timestamp + 4 hours + 1);

        // Capture all logs so we can assert no RewardPayoutFailed was emitted.
        vm.recordLogs();
        vm.prank(KEEPER);
        uint256 totalRewards = scoring.settleEpoch();

        uint256 rewardPerProvider = EPOCH_REWARD / 3;
        assertEq(totalRewards, rewardPerProvider * 3, "all 3 providers paid");
        assertEq(scoring.failedPayoutFor(1, ALICE), 0, "no failed payout recorded");
        assertEq(scoring.failedPayoutFor(1, BOB),   0, "no failed payout recorded");
        assertEq(scoring.failedPayoutFor(1, CAROL), 0, "no failed payout recorded");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != REWARD_PAYOUT_FAILED_SIG, "no RewardPayoutFailed emitted on happy path");
        }
    }
}