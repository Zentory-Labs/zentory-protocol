// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {EpochScoring} from "../../src/signals/EpochScoring.sol";
import {SignalTypes} from "../../src/signals/SignalTypes.sol";

/// @notice Minimal ISignalRegistry mock — only the methods touched by
///         setAccuracy / setAccuracyBatch tests are stubbed (none, in
///         practice — both are pure mapping writes). The mock exists so
///         EpochScoring can be constructed without depending on the full
///         SignalRegistry surface.
contract AccessMockRegistry {
    function getSignal(bytes32) external pure returns (SignalTypes.Signal memory) {
        return SignalTypes.Signal({
            signalId: bytes32(0),
            provider: address(0),
            assetClass: SignalTypes.AssetClass.CRYPTO_SPOT,
            assetId: bytes32(0),
            direction: 0,
            confidence: 0,
            submittedAt: 0,
            expiresAt: 0,
            signature: new bytes(0),
            status: SignalTypes.SignalStatus.Active
        });
    }

    function getSignalCount() external pure returns (uint256) {
        return 0;
    }
    function advanceEpoch() external {}

    function getEpochSignalCount(uint256) external pure returns (uint256) {
        return 0;
    }

    function getEpochSignalProvider(uint256, uint256) external pure returns (address) {
        return address(0);
    }

    function getEpochSignalReturn(uint256, uint256) external pure returns (int256) {
        return 0;
    }

    function submitSignal(address, SignalTypes.AssetClass, bytes32, int256, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes32)
    {
        return bytes32(0);
    }

    function submitSignalBatch(SignalTypes.Signal[] calldata) external pure returns (bytes32[] memory ids) {
        return ids;
    }

    function stakingContract() external pure returns (address) {
        return address(0);
    }

    function getProviderCount() external pure returns (uint256) {
        return 0;
    }

    function getProviderAt(uint256) external pure returns (address) {
        return address(0);
    }

    function signalExists(bytes32) external pure returns (bool) {
        return false;
    }

    function providerNonce(address) external pure returns (uint256) {
        return 0;
    }
    function resolveSignals(bytes32[] calldata, uint256[] calldata) external {}

    function getSignalProvider(uint256) external pure returns (address) {
        return address(0);
    }

    function getSignalReturn(address, uint256) external pure returns (int256) {
        return 0;
    }
}

/// @notice Minimal IZENTStaking mock — also not exercised by setAccuracy
///         paths, but EpochScoring's constructor wires it in.
contract AccessMockStaking {
    function getProviderStake(address) external pure returns (uint256) {
        return 0;
    }

    function getStakeAtEpoch(address, uint256) external pure returns (uint256) {
        return 0;
    }
    function slash(address, uint256) external {}
    function reward(address, uint256) external {}

    function stake(uint256, uint64) external pure returns (uint64) {
        return 0;
    }
    function increaseAmount(uint256) external {}

    function extendLock(uint64) external pure returns (uint64) {
        return 0;
    }
    function withdraw() external {}

    function veBalance(address) external pure returns (uint256) {
        return 0;
    }

    function hasAccess(address) external pure returns (bool) {
        return false;
    }

    function stakedBalance(address) external pure returns (uint256) {
        return 0;
    }

    function totalVeSupply() external pure returns (uint256) {
        return 0;
    }
    function setMinStake(uint256) external {}
}

/// @title SetAccuracyRoleGatedTest
/// @notice Regression guard for Tier 0 audit Q3 ("Single hot-key accuracy setter").
///
///         Pre-fix: `setAccuracy` and `setAccuracyBatch` were gated by a plain
///         `if (msg.sender != scoringOracle) revert UnauthorizedOracle(...)`
///         check against a single address. The scoring oracle EOA could be
///         rotated through `setScoringOracle()` only via the admin role, but
///         once set the address had unrestricted write access to accuracy
///         values driving real slashing / reward payouts.
///
///         Post-fix: the gate is now `onlyRole(SCORING_ORACLE_ROLE)` from
///         OpenZeppelin's AccessControl, so the role can be held by a Safe
///         multisig, an EOA, or a contract — and rotated by the admin role
///         without redeploying EpochScoring.
///
///         This file pins the post-fix invariants so Q3 cannot regress:
///         (1) the oracle address initially granted in the constructor holds
///             SCORING_ORACLE_ROLE and can call setAccuracy / setAccuracyBatch,
///         (2) a non-role caller reverts with the standard OZ
///             AccessControlUnauthorizedAccount(account, role) custom error,
///         (3) the admin can rotate the role via setScoringOracle (granting
///             the new address and revoking the old) — i.e. multisig rotation
///             works as the fix promises,
///         (4) the accuracy cache is populated on a successful call,
///         (5) batch writes still mark every signal as `accuracyScored`.
contract SetAccuracyRoleGatedTest is Test {
    EpochScoring scoring;
    AccessMockRegistry registry;
    AccessMockStaking staking;

    address constant ADMIN = address(0xA11CE); // placeholder; real admin is address(this) at runtime
    address constant ORACLE = address(0x2251); // scoringOracle at deploy (also EPOCH_SETTLER)
    address constant KEEPER = address(0x2251); // same as ORACLE here
    address constant ZENT_TOKEN = address(0x271c);
    address constant ATTACKER = address(0xBAD0);
    address constant NEW_ORACLE = address(0xC0FFEE);

    bytes32 constant SCORING_ORACLE_ROLE = keccak256("SCORING_ORACLE_ROLE");

    /// @dev The test contract's runtime address — used to assert admin-only
    ///         access patterns. We can't use `address(this)` in a constant,
    ///         so we record it at deploy time and use the captured value
    ///         in admin-only assertions.
    address admin;

    function setUp() public {
        registry = new AccessMockRegistry();
        staking = new AccessMockStaking();
        scoring = new EpochScoring(
            address(registry),
            address(staking),
            ZENT_TOKEN,
            ORACLE, // _scoringOracle at deploy
            KEEPER // _keeper (EPOCH_SETTLER)
        );
        admin = address(this);
        // Sanity: the constructor grants DEFAULT_ADMIN_ROLE to msg.sender, which
        // is the test contract. This assertion guards against the test
        // contract address changing shape in a future foundry-std release.
        assertTrue(scoring.hasRole(scoring.DEFAULT_ADMIN_ROLE(), admin), "admin role granted at deploy");
    }

    // ─── Happy path: role-holder writes succeed ───────────────────────────

    /// @notice The address passed as the constructor oracle is granted the
    ///         role and can call setAccuracy. This is the post-fix default.
    function test_roleHolderCanSetAccuracy() external {
        bytes32 id = bytes32(uint256(1));
        vm.prank(ORACLE);
        scoring.setAccuracy(id, 7000);
        assertEq(scoring.accuracyCache(id), 7000, "accuracy written to cache");
        assertTrue(scoring.accuracyScored(id), "scored flag set");
    }

    function test_roleHolderCanSetAccuracyBatch() external {
        bytes32[] memory ids = new bytes32[](2);
        uint256[] memory accs = new uint256[](2);
        ids[0] = bytes32(uint256(10));
        ids[1] = bytes32(uint256(11));
        accs[0] = 8000;
        accs[1] = 2000;

        vm.prank(ORACLE);
        scoring.setAccuracyBatch(ids, accs);

        assertEq(scoring.accuracyCache(ids[0]), 8000);
        assertEq(scoring.accuracyCache(ids[1]), 2000);
        assertTrue(scoring.accuracyScored(ids[0]), "batch[0] scored");
        assertTrue(scoring.accuracyScored(ids[1]), "batch[1] scored");
    }

    // ─── Negative path: non-role callers revert with OZ custom error ──────

    /// @notice Pre-fix: revert was `UnauthorizedOracle(msg.sender)`.
    ///         Post-fix: revert is the standard OZ AccessControl custom error
    ///         carrying (account, role). This is the assertion the validator
    ///         contract depends on.
    function test_nonRoleHolderRevertsOnSetAccuracy() external {
        bytes32 id = bytes32(uint256(2));
        vm.prank(ATTACKER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, ATTACKER, SCORING_ORACLE_ROLE
            )
        );
        scoring.setAccuracy(id, 9000);
        // Cache must remain unset — attacker cannot poison a signal's accuracy.
        assertEq(scoring.accuracyCache(id), 0, "no partial write");
        assertFalse(scoring.accuracyScored(id), "scored flag not flipped by attacker");
    }

    function test_nonRoleHolderRevertsOnSetAccuracyBatch() external {
        bytes32[] memory ids = new bytes32[](1);
        uint256[] memory accs = new uint256[](1);
        ids[0] = bytes32(uint256(20));
        accs[0] = 9000;

        vm.prank(ATTACKER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, ATTACKER, SCORING_ORACLE_ROLE
            )
        );
        scoring.setAccuracyBatch(ids, accs);
        assertEq(scoring.accuracyCache(ids[0]), 0, "no partial batch write");
    }

    /// @notice The Admin role alone (DEFAULT_ADMIN_ROLE) is NOT sufficient —
    ///         admin can grant the role, but the role itself is what the
    ///         gate checks. This prevents a holder of admin from accidentally
    ///         writing accuracy without explicit role grant (least privilege).
    function test_adminAloneCannotSetAccuracy() external {
        // The test contract is the admin (constructor grants DEFAULT_ADMIN_ROLE
        // to msg.sender, which is the test contract during setUp).
        bytes32 id = bytes32(uint256(3));
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, SCORING_ORACLE_ROLE)
        );
        scoring.setAccuracy(id, 5000);
    }

    /// @notice A random EOA (no role at all) reverts with the OZ error
    ///         carrying its own address — the error message identifies the
    ///         actual caller, which is exactly what an auditor needs to
    ///         triage an on-chain abuse attempt.
    function test_zeroAddressAsCallerReverts() external {
        bytes32 id = bytes32(uint256(4));
        vm.prank(address(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(0), SCORING_ORACLE_ROLE
            )
        );
        scoring.setAccuracy(id, 1000);
    }

    // ─── Role rotation: the multisig-friendly path the audit demanded ────

    /// @notice Admin rotates the scoring oracle by calling setScoringOracle.
    ///         Post-fix the rotation is implemented as `_grantRole` for the
    ///         new address and `_revokeRole` for the old, so the gate stays
    ///         consistent across the rotation. This is the headliner benefit
    ///         of the Q3 fix vs the pre-fix plain-equality gate: a Safe
    ///         multisig can now hold the role and rotate EOAs without
    ///         redeploying EpochScoring.
    function test_adminCanRotateScoringOracleRole() external {
        // Sanity: ORACLE can write before rotation.
        bytes32 id1 = bytes32(uint256(100));
        vm.prank(ORACLE);
        scoring.setAccuracy(id1, 6000);
        assertEq(scoring.accuracyCache(id1), 6000, "pre-rotation oracle can write");

        // Rotate.
        scoring.setScoringOracle(NEW_ORACLE);
        assertEq(scoring.scoringOracle(), NEW_ORACLE, "scoringOracle storage updated");

        // Old oracle no longer has the role — writes revert.
        bytes32 id2 = bytes32(uint256(101));
        vm.prank(ORACLE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, ORACLE, SCORING_ORACLE_ROLE
            )
        );
        scoring.setAccuracy(id2, 5000);

        // New oracle can write.
        vm.prank(NEW_ORACLE);
        scoring.setAccuracy(id2, 7000);
        assertEq(scoring.accuracyCache(id2), 7000, "post-rotation oracle can write");
    }

    /// @notice `hasRole` reflects the live rotation so off-chain monitors
    ///         (event-monitor, auditor dashboards) can read the role
    ///         membership without needing to inspect the legacy `scoringOracle`
    ///         storage variable.
    function test_hasRoleReflectsRotation() external {
        assertTrue(scoring.hasRole(SCORING_ORACLE_ROLE, ORACLE), "ORACLE has role initially");
        assertFalse(scoring.hasRole(SCORING_ORACLE_ROLE, NEW_ORACLE), "NEW_ORACLE has no role yet");

        scoring.setScoringOracle(NEW_ORACLE);
        assertFalse(scoring.hasRole(SCORING_ORACLE_ROLE, ORACLE), "ORACLE lost role after rotation");
        assertTrue(scoring.hasRole(SCORING_ORACLE_ROLE, NEW_ORACLE), "NEW_ORACLE gained role after rotation");
    }

    /// @notice The SCORING_ORACLE_ROLE constant is public on the contract so
    ///         off-chain tooling (subgraph, monitor) can resolve the role
    ///         identifier without re-deriving the keccak256.
    function test_scoringOracleRoleIsExposed() external view {
        assertEq(
            scoring.SCORING_ORACLE_ROLE(),
            SCORING_ORACLE_ROLE,
            "public constant matches the keccak256(\"SCORING_ORACLE_ROLE\") derivation"
        );
    }

    // ─── Existing safety checks still bind ────────────────────────────────

    /// @notice The pre-existing `accuracyBps > 10000` bound is still enforced
    ///         on the role-gated path. Rotating the gate must not have
    ///         removed the bounds check.
    function test_accuracyAbove10000StillReverts() external {
        vm.prank(ORACLE);
        vm.expectRevert(); // generic revert; the historical error was an unnamed revert
        scoring.setAccuracy(bytes32(uint256(200)), 10001);
    }

    /// @notice The pre-existing array-length-mismatch check on the batch
    ///         path is still enforced.
    function test_batchLengthMismatchStillReverts() external {
        bytes32[] memory ids = new bytes32[](2);
        uint256[] memory accs = new uint256[](1);
        ids[0] = bytes32(uint256(300));
        ids[1] = bytes32(uint256(301));
        accs[0] = 5000;

        vm.prank(ORACLE);
        vm.expectRevert(abi.encodeWithSelector(EpochScoring.ArraysLengthMismatch.selector));
        scoring.setAccuracyBatch(ids, accs);
    }
}
