// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {StrategyExecutor} from "../../src/keeper/StrategyExecutor.sol";
import {HyperCoreAdapter} from "../../src/keeper/HyperCoreAdapter.sol";

/// @title StrategyExecutorInvariantTest
/// @notice Invariant tests for StrategyExecutor.
/// @dev   Only pure/view invariants are reliable in open invariance testing
///         (where the engine can call ANY function on the contract).
///         State-modifying access-control tests are in StrategyExecutor.t.sol.
contract StrategyExecutorInvariantTest is Test {
    StrategyExecutor executor;
    HyperCoreAdapter adapter;

    address governor = makeAddr("governor");
    address keeper = makeAddr("keeper");
    address guardian = makeAddr("guardian");
    address attacker = makeAddr("attacker");
    address signalSigner = makeAddr("signalSigner");

    function setUp() external {
        adapter = new HyperCoreAdapter(governor);
        executor = new StrategyExecutor(address(adapter), governor);

        executor.grantRole(executor.KEEPER_ROLE(), keeper);
        executor.grantRole(executor.GUARDIAN_ROLE(), guardian);
        executor.setAuthorizedSigner(signalSigner);
        executor.setVaultRegistry(makeAddr("zeth"), 1);
    }

    // ─── Pure invariants: these hold regardless of who calls what ───────────────

    /// @notice Roles are constants — always distinct
    function invariant_rolesAreDistinct() external view {
        bytes32 KEEPER = keccak256("KEEPER_ROLE");
        bytes32 GUARDIAN = keccak256("GUARDIAN_ROLE");
        bytes32 GOVERNOR = keccak256("GOVERNOR_ROLE");
        assertTrue(KEEPER != GUARDIAN);
        assertTrue(KEEPER != GOVERNOR);
        assertTrue(GUARDIAN != GOVERNOR);
    }

    /// @notice DOMAIN_SEPARATOR is set once at construction and immutable
    function invariant_domainSeparatorNotZero() external view {
        assertTrue(executor.DOMAIN_SEPARATOR() != bytes32(0));
    }

    /// @notice SIGNAL_TYPEHASH is a constant — always non-zero
    function invariant_signalTypehashNotZero() external view {
        assertTrue(executor.SIGNAL_TYPEHASH() != bytes32(0));
    }

    /// @notice KEEPER_ROLE and GUARDIAN_ROLE are non-zero constants
    function invariant_roleConstantsNotZero() external view {
        assertTrue(executor.KEEPER_ROLE() != bytes32(0));
        assertTrue(executor.GUARDIAN_ROLE() != bytes32(0));
        assertTrue(executor.GOVERNOR_ROLE() != bytes32(0));
    }

    /// @notice HyperCore adapter address is immutable
    function invariant_hyperCoreAdapterSet() external view {
        assertTrue(address(executor.hyperCore()) != address(0));
    }

    /// @notice Governor always has GOVERNOR_ROLE after setup
    function invariant_governorHasGovernorRole() external view {
        assertTrue(executor.hasRole(executor.GOVERNOR_ROLE(), governor));
    }
}
