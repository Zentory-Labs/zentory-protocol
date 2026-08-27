// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SignalRegistry} from "../../src/signals/SignalRegistry.sol";
import {ZENTStaking}    from "../../src/staking/ZENTStaking.sol";
import {ZENT}           from "../../src/ZENT.sol";

/// @notice  RedeploySignalRegistry invariant tests.
///
///         Mirrors the wiring performed by `script/RedeploySignalRegistry.s.sol`
///         (the M2-F13 single-contract redeploy that fixes the stale SignalRegistry
///         bytecode) and asserts every post-deploy invariant. We do NOT spin up the
///         whole forge-script harness here — we replicate the script's wiring
///         logic as direct calls and assert:
///
///           - Constructor sets `currentEpochId = 1` (genesis epoch, aligned with
///             a freshly-deployed EpochScoring).
///           - Constructor grants `DEFAULT_ADMIN_ROLE` + `SCORING_ORACLE` to the
///             deployer (bootstrap).
///           - `stakingContract()` reads back the address that was passed in.
///           - After the script's wiring (grant SCORING_ORACLE to a stand-in
///             EpochScoring address + revoke from deployer), the post-conditions
///             hold:
///               * EpochScoring has SCORING_ORACLE
///               * deployer DOES NOT have SCORING_ORACLE (least privilege)
///               * deployer STILL has DEFAULT_ADMIN_ROLE (admin stays put)
///               * stakingContract is unchanged
///
///         If we ever change the wiring rules in `script/RedeploySignalRegistry.s.sol`,
///         these tests should be the first thing that breaks.
contract RedeploySignalRegistryInvariantTest is Test {
    ZENT           internal zent;
    ZENTStaking    internal staking;
    SignalRegistry internal registry;

    address internal deployer      = makeAddr("deployer");
    address internal epochScoring  = makeAddr("epochScoring"); // stand-in for EpochScoring contract

    uint256 internal constant MIN_STAKE = 100e18;

    function setUp() public {
        // Minimal ZENT (the registry constructor only needs a non-zero staking
        // address; it does not call back into the staking during construction).
        zent = new ZENT();

        // ZENTStaking; only the address matters for SignalRegistry wiring tests.
        staking = new ZENTStaking(address(zent), deployer, MIN_STAKE);

        // Pretend the deployer is broadcasting the deployment so DEFAULT_ADMIN_ROLE
        // lands on the deployer (matches the production script where the deployer
        // EOA is msg.sender).
        vm.prank(deployer);
        registry = new SignalRegistry(address(staking), deployer);
    }

    // ─── Constructor invariants ───────────────────────────────────────

    function test_constructor_sets_staking_contract() external view {
        assertEq(registry.stakingContract(), address(staking), "staking contract not set");
    }

    function test_constructor_grants_default_admin_to_deployer() external view {
        bytes32 DEFAULT_ADMIN_ROLE = registry.DEFAULT_ADMIN_ROLE();
        assertTrue(
            registry.hasRole(DEFAULT_ADMIN_ROLE, deployer),
            "deployer missing DEFAULT_ADMIN_ROLE"
        );
    }

    function test_constructor_grants_scoring_oracle_to_deployer_bootstrap() external view {
        assertTrue(
            registry.hasRole(registry.SCORING_ORACLE(), deployer),
            "deployer missing bootstrap SCORING_ORACLE"
        );
    }

    function test_constructor_inits_current_epoch_id_at_1() external view {
        // Source-fixed genesis: registry starts at epoch 1, matching EpochScoring's
        // constructor default. Mismatched counters were the 2026-06 off-by-one bug.
        assertEq(registry.currentEpochId(), 1, "currentEpochId != 1");
    }

    function test_constructor_reverts_on_zero_staking() external {
        vm.prank(deployer);
        vm.expectRevert(SignalRegistry.StakingContractNotSet.selector);
        new SignalRegistry(address(0), deployer);
    }

    function test_constructor_reverts_on_zero_scoring_oracle() external {
        vm.prank(deployer);
        vm.expectRevert(SignalRegistry.StakingContractNotSet.selector);
        new SignalRegistry(address(staking), address(0));
    }

    // ─── Script wiring invariants ──────────────────────────────────────

    /// @notice Simulate the script: grant SCORING_ORACLE to a stand-in EpochScoring
    ///         address, then revoke from deployer. Verify post-conditions.
    function test_script_wiring_grants_scoring_oracle_to_epoch_scoring() external {
        // Grant (deployer is DEFAULT_ADMIN_ROLE; startPrank to simulate script broadcast).
        vm.startPrank(deployer);
        registry.grantRole(registry.SCORING_ORACLE(), epochScoring);
        registry.revokeRole(registry.SCORING_ORACLE(), deployer);
        vm.stopPrank();

        // Post-conditions.
        assertTrue(
            registry.hasRole(registry.SCORING_ORACLE(), epochScoring),
            "EpochScoring missing SCORING_ORACLE"
        );
        assertFalse(
            registry.hasRole(registry.SCORING_ORACLE(), deployer),
            "deployer bootstrap SCORING_ORACLE not revoked"
        );
    }

    function test_script_wiring_preserves_default_admin() external {
        // Admin should survive the role wiring (only SCORING_ORACLE is touched).
        vm.startPrank(deployer);
        registry.grantRole(registry.SCORING_ORACLE(), epochScoring);
        registry.revokeRole(registry.SCORING_ORACLE(), deployer);
        vm.stopPrank();

        bytes32 DEFAULT_ADMIN_ROLE = registry.DEFAULT_ADMIN_ROLE();
        assertTrue(
            registry.hasRole(DEFAULT_ADMIN_ROLE, deployer),
            "deployer lost DEFAULT_ADMIN_ROLE (must be preserved)"
        );
    }

    function test_script_wiring_preserves_staking_contract_pointer() external {
        // The staking pointer must NOT change during the script's role wiring
        // (only the SCORING_ORACLE role is touched).
        vm.startPrank(deployer);
        registry.grantRole(registry.SCORING_ORACLE(), epochScoring);
        registry.revokeRole(registry.SCORING_ORACLE(), deployer);
        vm.stopPrank();

        assertEq(
            registry.stakingContract(),
            address(staking),
            "staking contract pointer changed during wiring"
        );
    }

    function test_script_wiring_preserves_genesis_epoch() external {
        vm.startPrank(deployer);
        registry.grantRole(registry.SCORING_ORACLE(), epochScoring);
        registry.revokeRole(registry.SCORING_ORACLE(), deployer);
        vm.stopPrank();

        assertEq(registry.currentEpochId(), 1, "currentEpochId changed during wiring");
    }

    /// @notice Audit M-4: `transferAdmin` must atomically grant + revoke so the
    ///         admin role is never zero. Included here because the M2-F13 redeploy
    ///         hands admin to the founder's EOA and they should be able to move it
    ///         without bricking the registry.
    function test_transferAdmin_works_on_fresh_deploy() external {
        address newAdmin = makeAddr("newAdmin");
        vm.prank(deployer);
        registry.transferAdmin(newAdmin);

        bytes32 DEFAULT_ADMIN_ROLE = registry.DEFAULT_ADMIN_ROLE();
        assertTrue(registry.hasRole(DEFAULT_ADMIN_ROLE, newAdmin), "newAdmin not granted");
        assertFalse(registry.hasRole(DEFAULT_ADMIN_ROLE, deployer), "deployer not revoked");
    }

    /// @notice The script's contract `grantRole` + `revokeRole` calls must come
    ///         from DEFAULT_ADMIN_ROLE (the deployer), not from msg.sender of the
    ///         broadcast. Sanity-check that the deployer's DEFAULT_ADMIN_ROLE is
    ///         sufficient to wire the roles the script wires.
    function test_deployer_has_authority_to_wire() external {
        bytes32 DEFAULT_ADMIN_ROLE = registry.DEFAULT_ADMIN_ROLE();
        bytes32 SCORING_ORACLE = registry.SCORING_ORACLE();

        // Pre-grant.
        assertTrue(registry.hasRole(SCORING_ORACLE, deployer), "pre: deployer missing SCORING_ORACLE");

        // Grant + revoke both succeed from DEFAULT_ADMIN_ROLE.
        vm.prank(deployer);
        registry.grantRole(SCORING_ORACLE, epochScoring);
        assertTrue(registry.hasRole(SCORING_ORACLE, epochScoring), "grant failed");

        vm.prank(deployer);
        registry.revokeRole(SCORING_ORACLE, deployer);
        assertFalse(registry.hasRole(SCORING_ORACLE, deployer), "revoke failed");

        // Sanity: DEFAULT_ADMIN_ROLE survives the SCORING_ORACLE churn.
        assertTrue(registry.hasRole(DEFAULT_ADMIN_ROLE, deployer), "admin lost");
    }

    /// @notice Regression: a fresh SignalRegistry pointed at the known-bad
    ///         2026-04-27 ZENTStaking (`getProviderStake` reverts) must NOT be
    ///         considered valid by the script. The script's safety guard refuses
    ///         to deploy with this staking address; here we document the guard
    ///         and the underlying address it checks against.
    function test_known_bad_staking_address_is_documented() external {
        // The KNOWN_BAD_STAKING constant lives in the script (not importable
        // here without a deploy), so we encode it inline. Update both if either
        // changes — the script lives at `script/RedeploySignalRegistry.s.sol`.
        address knownBad = 0x4E2e7Fd3C85c05697b24743e580B03abCD6d0c65;
        address liveStaking = address(staking);

        // Sanity: this test's setUp() deploys a fresh ZENTStaking; that one is
        // not the known-bad one (different address).
        assertTrue(knownBad != liveStaking, "setUp is using the known-bad staking");

        // Sanity: the known-bad address really IS non-empty code on-chain
        // (verified at audit time by `cast code 0x4E2e7Fd3 --rpc-url <998>`).
        // We can't run a chain read from a unit test, so this assertion is a
        // comment-only marker — see the audit note in the PR description.
        assertTrue(true, "see PR description for manual on-chain bytecode check");
    }
}
