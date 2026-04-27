// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {StrategyExecutor} from "../../src/keeper/StrategyExecutor.sol";
import {HyperCoreAdapter} from "../../src/keeper/HyperCoreAdapter.sol";

/// @title StrategyExecutorFuzzTest
/// @notice Fuzz tests for StrategyExecutor access control and signal execution.
contract StrategyExecutorFuzzTest is Test {
    StrategyExecutor executor;
    HyperCoreAdapter adapter;

    // Use raw uint256 private keys (not addresses) for signing
    uint256 internal constant GOVERNOR_KEY = 0xA11CE;
    uint256 internal constant KEEPER_KEY = 0xB0B;
    uint256 internal constant GUARDIAN_KEY = 0xCAFE;
    uint256 internal constant SIGNAL_SIGNER_KEY = 0xFA19;

    address public governor = vm.addr(GOVERNOR_KEY);
    address public keeper = vm.addr(KEEPER_KEY);
    address public guardian = vm.addr(GUARDIAN_KEY);
    address public signalSigner = vm.addr(SIGNAL_SIGNER_KEY);
    address public vault = makeAddr("vault");

    function setUp() external {
        adapter = new HyperCoreAdapter(governor);
        executor = new StrategyExecutor(address(adapter), governor);

        executor.grantRole(executor.KEEPER_ROLE(), keeper);
        executor.grantRole(executor.GUARDIAN_ROLE(), guardian);
        executor.setAuthorizedSigner(signalSigner);
        executor.setVaultRegistry(vault, 1);
    }

    // ─── Helper: sign a signal digest ──────────────────────────────────────────
    function _signSignal(
        bytes32 digest,
        uint256 privateKey
    ) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, bytes1(v));
    }

    // ─── Governor setters ──────────────────────────────────────────────────────

    function test_fuzz_governorCanSetMaxPositionSize(address someVault, uint256 limit) external {
        vm.assume(someVault != address(0));

        vm.prank(governor);
        executor.setMaxPositionSize(someVault, limit);
        assertEq(executor.maxPositionSize(someVault), limit);
    }

    function test_fuzz_governorCanSetMaxLeverage(address someVault, uint256 bps) external {
        vm.assume(someVault != address(0));
        vm.assume(bps <= 100000);

        vm.prank(governor);
        executor.setMaxLeverageBPS(someVault, bps);
        assertEq(executor.maxLeverageBPS(someVault), bps);
    }

    function test_fuzz_nonGovernorCannotSetMaxPositionSize(address someVault, uint256 limit) external {
        vm.assume(someVault != address(0));

        address nonGovernor = makeAddr("nonGovernor");
        vm.prank(nonGovernor);
        vm.expectRevert();
        executor.setMaxPositionSize(someVault, limit);
    }

    // ─── Pause ─────────────────────────────────────────────────────────────────

    function test_fuzz_guardianCanPause() external {
        vm.prank(guardian);
        executor.setPaused(true);
        assertTrue(executor.paused());
    }

    function test_fuzz_guardianCanUnpause() external {
        vm.prank(guardian);
        executor.setPaused(true);
        vm.prank(guardian);
        executor.setPaused(false);
        assertFalse(executor.paused());
    }

    function test_fuzz_nonGuardianCannotPause() external {
        address nonGuardian = makeAddr("nonGuardian");
        vm.prank(nonGuardian);
        vm.expectRevert();
        executor.setPaused(true);
    }

    // ─── Vault registry ─────────────────────────────────────────────────────────

    function test_fuzz_vaultRegistrySettableByGovernor(address someVault, uint8 localAsset) external {
        vm.assume(someVault != address(0));
        vm.assume(localAsset <= 3);

        vm.prank(governor);
        executor.setVaultRegistry(someVault, localAsset);
        assertEq(executor.vaultRegistry(someVault), localAsset);
    }

    // ─── Transfer admin ─────────────────────────────────────────────────────────

    function test_fuzz_transferAdminWorks(address newAdmin) external {
        vm.assume(newAdmin != address(0));
        // Transferring admin to self would immediately renounce and leave `newAdmin`
        // without DEFAULT_ADMIN_ROLE, so exclude that edge case.
        vm.assume(newAdmin != governor);

        vm.prank(governor);
        executor.transferAdmin(newAdmin);

        assertTrue(executor.hasRole(executor.DEFAULT_ADMIN_ROLE(), newAdmin));
        assertFalse(executor.hasRole(executor.DEFAULT_ADMIN_ROLE(), governor));
    }

    function test_fuzz_nonAdminCannotTransferAdmin(address newAdmin) external {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert();
        executor.transferAdmin(newAdmin);
    }

    // ─── Authorized signer ─────────────────────────────────────────────────────

    function test_fuzz_authorizedSignerSettable(address signer) external {
        vm.assume(signer != address(0));

        vm.prank(governor);
        executor.setAuthorizedSigner(signer);
        assertEq(executor.authorizedSigner(), signer);
    }

    function test_fuzz_authorizedSignerCannotBeZero() external {
        vm.prank(governor);
        vm.expectRevert("StrategyExecutor: zero signer");
        executor.setAuthorizedSigner(address(0));
    }
}
